-- Real lifecycle events and offline jobs exercise first-fetch notifications.
local api = vim.api
local scratch = assert(vim.env.GO_MOD_TEST_TMPDIR, "run with scripts/test.sh") .. "/notifications"
local real_system, real_notify = vim.system, vim.notify
local notices, jobs = {}, {}
local fail_start = false
local message = "Fetching dependency versions for go.mod…"
vim.notify = function(text, level, opts)
	assert(not vim.in_fast_event(), "notification must run on the main loop")
	if text:find(message, 1, true) then
		assert(text == message, "notification must stay on one short line")
		assert(level == vim.log.levels.INFO and opts.title == "go-mod.nvim")
		notices[#notices + 1] = text
	end
end
vim.system = function(argv, opts, callback)
	assert(argv[1] == "go" and argv[2] == "list", "only fake Go lookups are allowed")
	if require("go-mod.config").options.notify_on_load then
		local found = false
		for _, text in ipairs(notices) do
			found = found or text == message
		end
		assert(found, "notification must precede the process attempt")
	end
	if fail_start then
		error("fake spawn failure")
	end
	local job = { callback = callback, cwd = opts.cwd }
	function job:kill()
		self.killed = true
	end
	function job:complete()
		self.callback({ code = 0, stdout = '{"Version":"v1.1.0"}', stderr = "" })
	end
	jobs[#jobs + 1] = job
	return job
end
local function flush()
	vim.wait(20, function()
		return false
	end, 1)
end
local function file(label, lines)
	local directory = scratch .. "/" .. label
	vim.fn.mkdir(directory, "p")
	local path = directory .. "/go.mod"
	vim.fn.writefile(lines or { "module example.test/app", "require example.test/dep v1.0.0" }, path)
	return path
end
local function load(path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	vim.bo[buf].filetype = "gomod"
	return buf
end
local plugin = require("go-mod")
local core = require("go-mod.core")
plugin.setup({ log_level = "error", log_file = "", check_interval = 0, max_concurrent_jobs = 1 })
vim.cmd("filetype on")

-- The real first-file automatic path notifies even with logging set to ERROR.
local path = file("first project with spaces")
vim.cmd.edit(vim.fn.fnameescape(path))
local first = api.nvim_get_current_buf()
assert(
	vim.wait(500, function()
		return #jobs == 1
	end),
	"first-file automatic lookup did not start"
)
assert(#notices == 1)

-- A superseding check waits for cancellation, without a repeated notification.
core.check_dependencies(first)
assert(jobs[1].killed and #jobs == 1 and #notices == 1)
jobs[1]:complete()
flush()
assert(#jobs == 2 and #notices == 1)
jobs[2]:complete()
flush()

-- Saves, explicit checks, periodic refreshes, and multiple tasks share the flag.
vim.cmd.write()
flush()
assert(#jobs == 3 and #notices == 1)
jobs[3]:complete()
flush()
core.check_dependencies(first)
jobs[4]:complete()
flush()
require("go-mod.config").options.check_interval = 1
core.get_buffer_info(first).last_check = 0
core.check_periodic(first)
jobs[5]:complete()
flush()
assert(#notices == 1)

-- Empty/invalid buffers stay quiet until a valid lookup actually starts.
local empty = load(file("empty", { "module example.test/empty" }))
local invalid = load(file("invalid", { "require example.test/dep invalid" }))
flush()
assert(#jobs == 5 and #notices == 1)
assert(core.get_buffer_info(empty) and core.get_buffer_info(invalid))
api.nvim_buf_set_lines(empty, 0, -1, false, {
	"require (",
	"example.test/dep v1.0.0",
	"example.test/second v1.0.0",
	")",
})
core.check_dependencies(empty)
assert(#jobs == 6 and #notices == 2)

-- A queued buffer that unloads must never notify or launch its cancelled work.
local queued = load(file("queued"))
flush()
assert(#jobs == 6 and #notices == 2)
api.nvim_buf_delete(queued, { unload = true })
jobs[6]:complete()
flush()
assert(#jobs == 7 and #notices == 2)
jobs[7]:complete()
flush()
assert(#jobs == 7 and #notices == 2)
vim.fn.bufload(queued)
flush()
assert(#jobs == 8 and #notices == 3, "reloaded cancelled buffer must notify when it finally starts")
jobs[8]:complete()
flush()

-- Actual unload/reload retains the buffer number but resets first-fetch state.
api.nvim_set_current_buf(api.nvim_create_buf(true, false))
api.nvim_buf_delete(first, { unload = true })
assert(not api.nvim_buf_is_loaded(first))
vim.fn.bufload(first)
flush()
assert(#jobs == 9 and #notices == 4, "unloading must reset the notification state")
jobs[9]:complete()
flush()

-- A failed spawn still counts as the first actual attempt.
local failed = load(file("failed", { "module example.test/failed" }))
flush()
api.nvim_buf_set_lines(failed, 0, -1, false, { "require example.test/dep v1.0.0" })
fail_start = true
core.check_dependencies(failed)
assert(#notices == 5 and core.get_buffer_info(failed))
core.check_dependencies(failed)
assert(#notices == 5, "spawn failures must not repeat the first-fetch notice")
fail_start = false

-- Disabling the option suppresses notices without disabling actual lookups.
plugin.setup({ auto_check = false, notify_on_load = false, log_level = "debug", log_file = "", check_interval = 0 })
local silent = load(file("silent"))
flush()
local before = #jobs
core.check_dependencies(silent)
assert(#jobs == before + 1 and #notices == 5)
plugin.teardown()
for _, job in ipairs(jobs) do
	job:complete()
end
flush()
vim.system, vim.notify = real_system, real_notify
print("first-fetch notification regressions passed")
