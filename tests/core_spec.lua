vim.opt.runtimepath:append(vim.fn.getcwd())
local api = vim.api
local original_system = vim.system
local artifacts = vim.env.GO_MOD_TEST_TMPDIR or vim.fn.tempname()
local owns_artifacts = not vim.env.GO_MOD_TEST_TMPDIR
vim.fn.mkdir(artifacts, "p")
artifacts = assert(vim.uv.fs_realpath(artifacts))
local jobs, messages, live, peak = {}, {}, 0, 0
local fail_start
package.loaded["go-mod.log"] = {
	setup = function() end,
	info = function() end,
	open = function() end,
	error = function(message)
		assert(not vim.in_fast_event(), "logging from fast event")
		messages[#messages + 1] = message
	end,
}
vim.system = function(argv, options, callback)
	assert(not vim.in_fast_event(), "system launched from fast event")
	if fail_start then
		error(fail_start)
	end
	assert(argv[1] == "go" and argv[2] == "list" and #argv == 5)
	assert(options.env == nil, "process must inherit environment")
	assert(options.text and options.timeout)
	local job = { argv = argv, options = options, callback = callback }
	function job:kill(signal)
		assert(signal == 15)
		self.killed = true
	end
	function job:complete(result)
		if not self.finished then
			live = live - 1
		end
		self.finished = true
		self.callback(result or { code = 0, stdout = '{"Version":"v1.2.0"}', stderr = "" })
	end
	jobs[#jobs + 1] = job
	live, peak = live + 1, math.max(peak, live + 1)
	return job
end
local config = require("go-mod.config")
config.options.max_concurrent_jobs = 2
config.options.timeout = 15
config.options.virtual_text = { prefix = "TEST", spacing = 2 }
local core = require("go-mod.core")
local ns = api.nvim_create_namespace("go_mod")
local buffers = {}
local function buffer(label, lines)
	local buf = api.nvim_create_buf(true, false)
	local directory = artifacts .. "/" .. label
	vim.fn.mkdir(directory, "p")
	api.nvim_buf_set_name(buf, directory .. "/go.mod")
	vim.bo[buf].filetype = "gomod"
	api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "require example.com/a v1.0.0" })
	buffers[#buffers + 1] = buf
	return buf
end
local function flush()
	vim.wait(20, function()
		return false
	end, 1)
end
local function marks(buf)
	return api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end
local function reset()
	core.shutdown()
	for _, job in ipairs(jobs) do
		if not job.finished then
			job:complete()
		end
	end
	flush()
	assert(live == 0, "leaked jobs")
	jobs, live, peak, messages, fail_start = {}, 0, 0, {}, nil
end
local ok, err = xpcall(function()
	-- Completion metadata and configured rendering are tied to the requested buffer.
	local buf = buffer("basic")
	core.check_dependencies(buf)
	assert(#jobs == 1)
	assert(jobs[1].options.cwd == artifacts .. "/basic")
	assert(jobs[1].argv[5] == "example.com/a@latest")
	local exit_timer = assert(vim.uv.new_timer())
	exit_timer:start(0, 0, function()
		exit_timer:close()
		jobs[1]:complete()
	end)
	flush()
	local info = assert(core.get_buffer_info(buf))
	assert(info.modules["example.com/a"].status == "outdated")
	assert(info.root == artifacts .. "/basic" and info.visible and info.last_check)
	assert(info.changedtick == api.nvim_buf_get_changedtick(buf))
	assert(marks(buf)[1][4].virt_text[1][1]:match("^  TEST "))
	core.toggle(buf)
	assert(not info.visible and #marks(buf) == 0)
	core.toggle(buf)
	assert(info.visible and #marks(buf) == 1 and #jobs == 1)
	reset()

	-- Hiding an in-flight request persists through completion and invalidation.
	core.check_dependencies(buf)
	core.toggle(buf)
	jobs[1]:complete()
	flush()
	assert(not core.get_buffer_info(buf).visible and #marks(buf) == 0)
	core.invalidate_buffer(buf)
	assert(core.get_buffer_info(buf) == nil and #marks(buf) == 0)
	core.check_dependencies(buf)
	jobs[2]:complete()
	flush()
	assert(not core.get_buffer_info(buf).visible and #marks(buf) == 0)
	reset()

	-- Superseded and cancelled jobs cannot publish results.
	core.check_dependencies(buf)
	local old = jobs[1]
	core.check_dependencies(buf)
	assert(old.killed)
	old:complete()
	flush()
	assert(core.get_buffer_info(buf) == nil)
	jobs[2]:complete()
	flush()
	assert(core.get_buffer_info(buf))
	core.check_dependencies(buf)
	core.invalidate_buffer(buf)
	assert(jobs[3].killed and core.get_buffer_info(buf) == nil and #marks(buf) == 0)
	jobs[3]:complete()
	flush()
	assert(core.get_buffer_info(buf) == nil)
	reset()

	-- Edits, deletion, and rename invalidate late responses.
	core.check_dependencies(buf)
	api.nvim_buf_set_lines(buf, 0, -1, false, { "require example.com/b v1.0.0" })
	jobs[1]:complete()
	flush()
	assert(core.get_buffer_info(buf) == nil and #marks(buf) == 0)
	core.check_dependencies(buf)
	api.nvim_buf_set_name(buf, artifacts .. "/renamed.mod")
	jobs[2]:complete()
	flush()
	assert(core.get_buffer_info(buf) == nil and #marks(buf) == 0)
	local deleted = buffer("deleted")
	core.check_dependencies(deleted)
	api.nvim_buf_delete(deleted, { force = true })
	jobs[3]:complete()
	flush()
	assert(core.get_buffer_info(deleted) == nil)
	reset()

	-- Queue admission is global across buffers; cleanup never starts queued jobs for that buffer.
	local many = buffer("many", {
		"require (",
		"example.com/a v1.0.0",
		"example.com/b v1.0.0",
		"example.com/c v1.0.0",
		"example.com/d v1.0.0",
		")",
	})
	local second = buffer("second")
	core.check_dependencies(many)
	core.check_dependencies(second)
	assert(#jobs == 2 and peak == 2)
	jobs[1]:complete()
	flush()
	assert(#jobs == 3 and peak == 2)
	core.cleanup_buffer(many)
	assert(#jobs == 3 and live == 2)
	jobs[2]:complete()
	flush()
	assert(#jobs == 4 and jobs[4].options.cwd == artifacts .. "/second")
	jobs[3]:complete()
	jobs[4]:complete()
	flush()
	assert(core.get_buffer_info(many) == nil and core.get_buffer_info(second))
	assert(peak <= 2)
	reset()

	-- SIGTERM does not release capacity, even across repeated checks and setup.
	local plugin = require("go-mod")
	local saved_options = vim.deepcopy(config.options)
	local options = { auto_check = false, check_interval = 0, max_concurrent_jobs = 1, timeout = 15 }
	plugin.setup(options)
	core.check_dependencies(second)
	local lingering = jobs[1]
	for _ = 1, 4 do
		core.check_dependencies(second)
	end
	assert(lingering.killed and not lingering.finished and live == 1 and #jobs == 1)
	for _ = 1, 2 do
		plugin.setup(options)
		core.check_dependencies(second)
		assert(#jobs == 1 and live == 1 and core.get_buffer_info(second) == nil)
	end
	lingering:complete()
	flush()
	assert(#jobs == 2 and live == 1 and core.get_buffer_info(second) == nil)
	local waiting = buffer("waiting")
	core.check_dependencies(waiting)
	-- A repeated terminal callback must not decrement capacity a second time.
	lingering:complete()
	flush()
	assert(#jobs == 2 and live == 1)
	jobs[2]:complete()
	flush()
	assert(core.get_buffer_info(second) and #jobs == 3 and live == 1)
	jobs[3]:complete()
	flush()
	assert(core.get_buffer_info(waiting) and peak == 1 and live == 0)
	plugin.teardown()
	config.options = saved_options
	reset()

	-- Out-of-order failures still drain the queue and finish the entire aggregate.
	core.check_dependencies(many)
	jobs[2]:complete({ code = 124 })
	flush()
	assert(#jobs == 3 and core.get_buffer_info(many) == nil)
	jobs[1]:complete({ code = 1, stderr = "unavailable" })
	flush()
	assert(#jobs == 4 and core.get_buffer_info(many) == nil)
	jobs[4]:complete({ code = 0, stdout = "malformed JSON" })
	jobs[3]:complete()
	flush()
	local completed = assert(core.get_buffer_info(many))
	local errors = 0
	for _, module in pairs(completed.modules) do
		if module.status == "error" then
			errors = errors + 1
		end
	end
	assert(errors == 3 and peak == 2 and live == 0)
	reset()

	-- Empty files, invalid versions, spawn failures, malformed output, exits, and timeouts finish.
	local empty = buffer("empty", { "module example.com/empty" })
	core.check_dependencies(empty)
	assert(core.get_buffer_info(empty) and #jobs == 0)
	local invalid = buffer("invalid", { "require example.com/a nonsense" })
	core.check_dependencies(invalid)
	assert(core.get_buffer_info(invalid).modules["example.com/a"].status == "error" and #jobs == 0)
	for _, failure in ipairs({ "ENOENT: executable not found", "spawn failed" }) do
		fail_start = failure
		core.check_dependencies(second)
		local module = assert(core.get_buffer_info(second)).modules["example.com/a"]
		assert(module.status == "error" and module.error:find(failure, 1, true))
	end
	fail_start = nil
	for _, result in ipairs({
		{ code = 1, stderr = "network unavailable" },
		{ code = 124 },
		{ code = 0, stdout = "not json" },
		{ code = 0, stdout = "{}" },
		{ code = 0, stdout = '{"Version":"invalid"}' },
	}) do
		core.check_dependencies(second)
		jobs[#jobs]:complete(result)
		flush()
		local module = assert(core.get_buffer_info(second)).modules["example.com/a"]
		assert(module.status == "error" and #module.error > 0)
	end
	assert(#messages >= 8)
	reset()

	-- Explicit/default buffer arguments and interval validation.
	local target = buffer("periodic")
	api.nvim_set_current_buf(target)
	core.check_dependencies()
	jobs[1]:complete()
	flush()
	core.check_periodic(0)
	assert(#jobs == 1)
	core.get_buffer_info(target).last_check = 0
	core.check_periodic(target)
	assert(#jobs == 2)
	core.shutdown()
	jobs[2]:complete()
	flush()
	assert(core.get_buffer_info(target) == nil)
	local wrong = buffer("wrong")
	vim.bo[wrong].filetype = "go"
	core.check_dependencies(wrong)
	assert(#jobs == 2)
	vim.bo[wrong].filetype = "gomod"
	api.nvim_buf_set_name(wrong, artifacts .. "/not-go.mod")
	core.check_dependencies(wrong)
	assert(#jobs == 2)
	reset()
end, debug.traceback)
core.shutdown()
vim.system = original_system
for _, buf in ipairs(buffers) do
	if api.nvim_buf_is_valid(buf) then
		api.nvim_buf_delete(buf, { force = true })
	end
end
if owns_artifacts then
	vim.fn.delete(artifacts, "rf")
end
assert(ok, err)
print("core_spec: passed")
