vim.opt.runtimepath:prepend(vim.fn.getcwd())
local scratch = assert(vim.env.GO_MOD_TEST_TMPDIR, "run with scripts/test.sh")
local api = vim.api
local checks, periodic, cleaned = {}, {}, {}
local spy = {
	check_dependencies = function(buf)
		checks[#checks + 1] = buf
	end,
	check_periodic = function(buf)
		periodic[#periodic + 1] = buf
	end,
	cleanup_buffer = function(buf)
		cleaned[#cleaned + 1] = buf
	end,
	shutdown = function() end,
	toggle = function() end,
}
package.loaded["go-mod.core"] = spy
package.loaded["go-mod.updater"] = {
	update_module = function() end,
	update_selection_window = function() end,
	get_outdated_modules = function()
		return {}
	end,
}
package.loaded["go-mod.log"] = { setup = function() end, info = function() end, open = function() end }
local config = require("go-mod.config")
local directory = scratch .. "/lifecycle"
vim.fn.mkdir(directory, "p")
vim.fn.writefile({ "module example.com/lifecycle" }, directory .. "/go.mod")
vim.cmd("filetype on")
dofile("plugin/go-mod.lua")
vim.cmd.edit(vim.fn.fnameescape(directory .. "/go.mod"))
local original = api.nvim_get_current_buf()
local module = require("go-mod")
assert(
	vim.wait(500, function()
		return #checks > 0
	end),
	"automatic bootstrap must check the first file"
)
assert(checks[1] == original, "bootstrap must target the opened buffer")

module.setup({ auto_check = true, check_interval = 0, log_file = "" })
checks = {}
api.nvim_exec_autocmds("BufReadPost", { buffer = original })
local other = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(other)
assert(vim.wait(500, function()
	return #checks > 0
end))
assert(checks[1] == original, "deferred checks must not follow the current buffer")

module.setup({ auto_check = false, check_interval = 0.0005, log_file = "" })
assert(
	vim.wait(500, function()
		return vim.tbl_contains(periodic, original)
	end),
	"periodic timer must check loaded go.mod buffers without buffer switching"
)
module.setup({ auto_check = false, check_interval = 0, log_file = "", timeout = 1234 })
local old_periodic_count = #periodic
vim.wait(80, function()
	return false
end)
assert(#periodic == old_periodic_count, "repeated setup must close the previous timer")
checks = {}
api.nvim_exec_autocmds("BufReadPost", { buffer = original })
vim.wait(20, function()
	return false
end)
assert(#checks == 0, "auto_check=false must not check files on open")

vim.g.loaded_gomod_nvim = nil
dofile("plugin/go-mod.lua")
assert(config.options.timeout == 1234, "plugin registration must preserve explicit setup")
local commands = api.nvim_get_commands({})
assert(commands.GoModUpdate.complete, "plugin registration must preserve completion")
api.nvim_buf_delete(original, { force = true })
assert(vim.tbl_contains(cleaned, original), "buffer deletion must clean up its checks")
module.teardown()
print("lifecycle regressions passed")
