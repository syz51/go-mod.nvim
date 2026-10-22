local api = vim.api
vim.opt.runtimepath:append(vim.fn.getcwd())
local scratch = (vim.env.GO_MOD_TEST_TMPDIR and (vim.env.GO_MOD_TEST_TMPDIR .. "/updater-spec") or vim.fn.tempname())
vim.fn.mkdir(scratch .. "/project", "p")
local root = vim.uv.fs_realpath(scratch .. "/project")
local path = root .. "/go.mod"
local notices, jobs, checked, invalidated, cache = {}, {}, {}, {}, {}
local spawn_error = false
local effective_flags = ""
local picker_callback, confirm_callback
vim.notify = function(message)
	assert(not vim.in_fast_event())
	table.insert(notices, message)
end
package.loaded["go-mod.log"] = {
	error = function()
		assert(not vim.in_fast_event())
	end,
}
package.loaded["go-mod.config"] = { options = { timeout = 5000 } }
package.loaded["go-mod.core"] = {
	get_buffer_info = function(buf)
		return cache[buf]
	end,
	invalidate_buffer = function(buf)
		invalidated[#invalidated + 1] = buf
		cache[buf] = nil
	end,
	check_dependencies = function(buf)
		assert(not vim.in_fast_event())
		checked[#checked + 1] = { buf = buf, content = api.nvim_buf_get_lines(buf, 0, -1, false) }
	end,
}
package.loaded["go-mod.ui"] = {
	show_update_window = function(_, callback)
		picker_callback = callback
	end,
}
vim.system = function(argv, opts, callback)
	if spawn_error then
		error("spawn failed")
	end
	local job = { argv = argv, opts = opts, callback = callback }
	table.insert(jobs, job)
	return job
end
vim.ui.select = function(_, _, callback)
	confirm_callback = callback
end
local updater = require("go-mod.updater")
local function drain()
	assert(vim.wait(1000, function()
		return true
	end, 1))
	vim.wait(10, function()
		return false
	end, 1)
end
local function complete(job, code, stdout)
	local timer = vim.uv.new_timer()
	timer:start(0, 0, function()
		timer:stop()
		timer:close()
		job.callback({
			code = code,
			signal = 0,
			stdout = stdout or (job.argv[2] == "env" and effective_flags or ""),
			stderr = "failure detail",
		})
	end)
	drain()
end
local function contains(fragment)
	for _, message in ipairs(notices) do
		if message:find(fragment, 1, true) then
			return true
		end
	end
	return false
end
local function fresh()
	vim.fn.writefile(
		{ "module example.test/project", "", "require example.test/a v1.0.0", "require example.test/b v1.0.0" },
		path
	)
	vim.cmd("edit! " .. vim.fn.fnameescape(path))
	vim.bo.filetype = "gomod"
	local buf = api.nvim_get_current_buf()
	cache[buf] = {
		last_check = 1,
		root = root,
		changedtick = api.nvim_buf_get_changedtick(buf),
		modules = {
			["example.test/a"] = { current = "v1.0.0", latest = "v1.1.0", status = "outdated" },
			["example.test/b"] = { current = "v1.0.0", latest = "v1.2.0", status = "outdated" },
		},
	}
	notices, jobs, checked, invalidated = {}, {}, {}, {}
	return buf
end

local function write_versions(a, b)
	vim.fn.writefile({
		"module example.test/project",
		"require example.test/a " .. (a or "v1.1.0"),
		"require example.test/b " .. (b or "v1.2.0"),
	}, path)
end
local function preflight()
	assert(jobs[1].argv[2] == "env" and jobs[1].argv[3] == "GOFLAGS")
	complete(jobs[1], 0)
	assert(#jobs == 2 and jobs[2].argv[2] == "get")
end

local buf = fresh()
-- One graph resolution, independent of editor cwd and current buffer.
vim.cmd("cd " .. vim.fn.fnameescape(scratch))
updater.update_modules({ "example.test/a", "example.test/b", "example.test/a" })
assert(#jobs == 1 and #invalidated == 0 and jobs[1].opts.cwd == root)
-- Lock includes read-only preflight, before invalidating the cached check.
updater.update_module("example.test/a", buf)
assert(#jobs == 1 and contains("already running"))
preflight()
assert(#invalidated == 1 and invalidated[1] == buf)
assert(vim.deep_equal(jobs[2].argv, { "go", "get", "example.test/a@v1.1.0", "example.test/b@v1.2.0" }))
assert(not contains("Successfully") and #checked == 0)
vim.cmd("enew")
local unrelated = api.nvim_get_current_buf()
write_versions()
complete(jobs[2], 0)
assert(#checked == 1 and checked[1].buf == buf)
assert(checked[1].content[2] == "require example.test/a v1.1.0")
assert(api.nvim_get_current_buf() == unrelated and contains("Successfully updated 2"))
complete(jobs[1], 0)
complete(jobs[2], 0)
assert(#checked == 1 and #jobs == 2)

-- Effective GOFLAGS covers both process environment and persistent Go settings,
-- including relative and absolute alternate modfiles. Unrelated flags survive.
local original_flags = vim.env.GOFLAGS
for _, flags in ipairs({ "-modfile=other.mod", "-modfile=" .. root .. "/other.mod" }) do
	for _, process in ipairs({ true, false }) do
		buf = fresh()
		vim.env.GOFLAGS = process and flags or nil
		effective_flags = flags -- go env returns the effective value in both cases.
		updater.update_module("example.test/a")
		complete(jobs[1], 0)
		assert(#jobs == 1 and #invalidated == 0 and #checked == 0)
		assert(contains("Effective GOFLAGS contains -modfile") and not contains("Successfully"))
	end
end
vim.env.GOFLAGS = original_flags
effective_flags = "-tags=example -mod=mod"
buf = fresh()
updater.update_module("example.test/a")
preflight()
assert(jobs[2].opts.env == nil) -- Never silently replace user flags.
write_versions()
complete(jobs[2], 0)
assert(contains("Successfully updated 1"))
effective_flags = ""

-- External changes with no buffer changedtick change must stop before any write.
buf = fresh()
write_versions("v9.0.0")
updater.update_module("example.test/a")
assert(#jobs == 0 and contains("changed on disk"))
buf = fresh()
updater.update_module("example.test/a")
write_versions("v9.0.0")
complete(jobs[1], 0)
assert(#jobs == 1 and #checked == 0 and #invalidated == 0 and contains("changed before"))
-- Replacing the file with identical bytes still changes its identity.
buf = fresh()
updater.update_module("example.test/a")
local moved = root .. "/old.mod"
assert(vim.uv.fs_rename(path, moved))
vim.fn.writefile(vim.fn.readfile(moved), path)
complete(jobs[1], 0)
assert(#jobs == 1 and contains("changed before"))
vim.fn.delete(moved)

-- A zero exit is insufficient: verify every selected on-disk requirement.
buf = fresh()
updater.update_modules({ "example.test/a", "example.test/b" })
preflight()
write_versions("v1.1.0", "v1.3.0-pre.1")
complete(jobs[2], 0)
assert(contains("Verified 1/2") and contains("requirements differ") and not contains("Successfully"))
buf = fresh()
updater.update_module("example.test/a")
preflight()
vim.fn.delete(path)
complete(jobs[2], 0)
assert(contains("Verified 0/1") and not contains("Successfully") and #checked == 0)

-- Failed get can partially change disk; report verified versions and the failure.
buf = fresh()
updater.update_modules({ "example.test/a", "example.test/b" })
preflight()
write_versions("v1.1.0", "v1.0.0")
complete(jobs[2], 1)
assert(#jobs == 2 and not contains("Successfully") and contains("Verified 1/2") and contains("exited with code 1"))
assert(#checked == 1 and checked[1].buf == buf)
-- Preflight failures and spawn exceptions release the root lock.
buf = fresh()
updater.update_module("example.test/a")
complete(jobs[1], 1)
assert(#jobs == 1 and #checked == 0 and contains("go env exited"))
buf = fresh()
spawn_error = true
updater.update_module("example.test/a")
assert(#jobs == 0 and contains("Failed to start") and #checked == 0)
spawn_error = false
buf = fresh()
updater.update_module("example.test/a")
preflight()
write_versions()
complete(jobs[2], 0)
assert(contains("Successfully updated 1"))

buf = fresh()
api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved work" })
updater.update_module("example.test/a")
assert(#jobs == 0 and contains("Save go.mod"))
for _, bad in ipairs({ "changedtick", "root", "last_check", "cache" }) do
	buf = fresh()
	if bad == "changedtick" then
		cache[buf].changedtick = -1
	elseif bad == "root" then
		cache[buf].root = scratch
	elseif bad == "last_check" then
		cache[buf].last_check = nil
	else
		cache[buf] = nil
	end
	updater.update_module("example.test/a")
	assert(#jobs == 0 and contains("dependency check"))
end

-- Buffer edits, deletion and rename during preflight must prevent writes.
for _, change in ipairs({ "edit", "tick", "delete", "rename" }) do
	buf = fresh()
	updater.update_module("example.test/a")
	if change == "delete" then
		api.nvim_buf_delete(buf, { force = true })
	elseif change == "rename" then
		api.nvim_buf_set_name(buf, root .. "/renamed-preflight.mod")
	else
		api.nvim_buf_set_lines(buf, 0, -1, false, { "my new edits" })
		if change == "tick" then
			vim.bo[buf].modified = false
		end
	end
	complete(jobs[1], 0)
	assert(#jobs == 1 and #checked == 0 and contains("changed before"))
end
-- Edits during the actual get are preserved; final disk requirements are verified.
for _, change in ipairs({ "edit", "tick", "delete", "rename" }) do
	buf = fresh()
	updater.update_module("example.test/a")
	preflight()
	if change == "delete" then
		api.nvim_buf_delete(buf, { force = true })
	elseif change == "rename" then
		api.nvim_buf_set_name(buf, root .. "/renamed-get.mod")
	else
		api.nvim_buf_set_lines(buf, 0, -1, false, { "last-process edits" })
		if change == "tick" then
			vim.bo[buf].modified = false
		end
	end
	write_versions()
	complete(jobs[2], 0)
	assert(#checked == 0 and contains("your edits were preserved"))
	if change == "edit" or change == "tick" then
		assert(api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "last-process edits")
	end
end

-- Deferred choices retain the originating buffer, versions, and disk snapshot.
buf = fresh()
updater.update_all_modules()
vim.cmd("enew")
confirm_callback("Yes")
preflight()
write_versions()
complete(jobs[2], 0)
assert(checked[1].buf == buf)
buf = fresh()
updater.update_selection_window()
cache[buf].modules["example.test/b"].latest = "v99.0.0"
vim.cmd("enew")
picker_callback({ "example.test/b", "example.test/a" })
preflight()
assert(jobs[2].argv[3] == "example.test/b@v1.2.0")
write_versions()
complete(jobs[2], 0)
assert(checked[1].buf == buf)
for _, external in ipairs({ true, false }) do
	buf = fresh()
	updater.update_selection_window()
	if external then
		write_versions("v9.0.0")
	else
		api.nvim_buf_set_lines(buf, 0, -1, false, { "edited while choosing" })
	end
	picker_callback({ "example.test/a" })
	assert(#jobs == 0 and contains("go.mod changed"))
end

-- Native timeout applies to both preflight and get; each releases the lock.
package.loaded["go-mod.config"].options.timeout = 17
for _, phase in ipairs({ "env", "get" }) do
	buf = fresh()
	updater.update_modules({ "example.test/a", "example.test/b" })
	if phase == "get" then
		preflight()
	end
	local job = jobs[#jobs]
	assert(job.opts.timeout == 17 and job.opts.text == true)
	assert(#checked == 0 and not contains("Successfully"))
	complete(job, 124)
	assert(contains("timed out") and not contains("Successfully"))
end

vim.cmd("cd " .. vim.fn.fnameescape(vim.fn.fnamemodify(vim.fn.getcwd(), ":h")))
vim.fn.delete(scratch, "rf")
print("updater_spec: passed")
