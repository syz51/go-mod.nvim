-- Default options and real events: the first check starts each lookup once.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local scratch = assert(vim.env.GO_MOD_TEST_TMPDIR, "run with scripts/test.sh") .. "/first-check"
local real_system, real_notify = vim.system, vim.notify
local jobs, kills = {}, 0
vim.notify = function() end
vim.system = function(argv, _, callback)
	assert(argv[1] == "go" and argv[2] == "list", "only fake Go lookups are allowed")
	local job = { callback = callback }
	function job:kill()
		kills = kills + 1
	end
	jobs[#jobs + 1] = job
	return job
end
local function settle()
	local index = 0
	assert(vim.wait(1000, function()
		while index < #jobs do
			index = index + 1
			jobs[index].callback({ code = 0, stdout = '{"Version":"v1.1.0"}', stderr = "" })
		end
		local info = require("go-mod.core").get_buffer_info()
		return index > 0 and info ~= nil and info.last_check ~= nil
	end, 1))
end
local function file(label)
	local directory = scratch .. "/" .. label
	vim.fn.mkdir(directory, "p")
	local lines = { "module example.test/app", "", "require (" }
	for i = 1, 6 do
		lines[#lines + 1] = string.format("\texample.test/dep%d v1.0.0", i)
	end
	lines[#lines + 1] = ")"
	vim.fn.writefile(lines, directory .. "/go.mod")
	return directory .. "/go.mod"
end
vim.cmd("filetype on")
dofile(vim.fn.getcwd() .. "/plugin/go-mod.lua")

-- BufReadPost, FileType and BufEnter all fire for one :edit.
vim.cmd.edit(vim.fn.fnameescape(file("open")))
local buf = api.nvim_get_current_buf()
settle()
assert(#jobs == 6 and kills == 0, string.format("first open: %d lookups, %d kills", #jobs, kills))

-- A write after the check starts a new check.
jobs = {}
vim.cmd("silent write")
settle()
assert(#jobs == 6 and kills == 0, string.format("write: %d lookups, %d kills", #jobs, kills))

-- A write during a check restarts it, also when the text is the same: the
-- file on disk may have changed.
jobs = {}
require("go-mod.core").check_dependencies(buf)
vim.cmd("silent write")
settle()
assert(#jobs == 10 and kills == 4, string.format("write in check: %d lookups, %d kills", #jobs, kills))

-- The first command after a teardown runs setup and then one check.
jobs, kills = {}, 0
require("go-mod").teardown()
vim.cmd("GoModCheck")
settle()
assert(#jobs == 6 and kills == 0, string.format("first command: %d lookups, %d kills", #jobs, kills))
kills = 0

-- An explicit check still replaces a running one.
jobs = {}
local core = require("go-mod.core")
core.check_dependencies(buf)
assert(core.is_checking(buf) and #jobs == 4)
core.check_dependencies(buf)
assert(kills == 4 and core.is_checking(buf))
settle()
assert(not core.is_checking(buf))

-- A check that the edit made stale does not block the queued check.
jobs, kills = {}, 0
core.check_dependencies(buf)
api.nvim_buf_set_lines(buf, 1, 1, false, { "// edited" })
assert(not core.is_checking(buf))
vim.cmd("silent write")
settle()
assert(#jobs == 10 and kills == 4, string.format("stale: %d lookups, %d kills", #jobs, kills))
assert(not core.is_checking(api.nvim_create_buf(false, true)))

vim.system, vim.notify = real_system, real_notify
print("first-check regressions passed")
