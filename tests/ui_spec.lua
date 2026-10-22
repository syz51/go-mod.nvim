local api = vim.api
vim.opt.runtimepath:append(vim.fn.getcwd())
local ui = require("go-mod.ui")
local origin = api.nvim_get_current_win()
local modules = {
	{ name = "example.test/first", current = "v1.0.0", latest = "v1.1.0" },
	{ name = "example.test/second", current = "v2.0.0", latest = "v2.1.0" },
	{ name = "example.test/last", current = "v3.0.0", latest = "v3.1.0" },
}
local win, buf, received, calls
local function open(list)
	received, calls = nil, 0
	ui.show_update_window(list or modules, function(names)
		assert(api.nvim_get_current_win() == origin, "source focus must be restored before update")
		received, calls = names, calls + 1
	end)
	win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
end
local function press(key)
	for _, map in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
		if map.lhs == key or (key == "<Space>" and map.lhs == " ") or (key == "<Tab>" and map.lhs == "<Tab>") then
			map.callback()
			return
		end
	end
	error("mapping not found: " .. key)
end
local function row(n)
	api.nvim_win_set_cursor(win, { n, 0 })
end
local function line(n)
	return api.nvim_buf_get_lines(buf, n - 1, n, false)[1]
end
open()
row(3)
press("<Space>")
assert(line(3):match("^%[x%] example.test/first"))
assert(line(4):match("^%[ %] example.test/second"))
row(5)
press("<CR>")
assert(line(5):match("^%[x%] example.test/last"))
press("u")
assert(calls == 1 and vim.deep_equal(received, { modules[1].name, modules[3].name }))
assert(not api.nvim_win_is_valid(win))
open()
row(4)
press("<CR>")
press("u")
assert(vim.deep_equal(received, { modules[2].name }))
open()
press("a")
for i = 3, 5 do
	assert(line(i):match("^%[x%]"))
end
press("a")
for i = 3, 5 do
	assert(line(i):match("^%[ %]"))
end
press("a")
press("u")
assert(calls == 1 and #received == 3)
open()
press("U")
assert(calls == 1 and vim.deep_equal(received, { modules[1].name, modules[2].name, modules[3].name }))
-- Tab reaches each footer action independently, even in a narrow terminal.
open()
row(3)
press("<Space>")
press("<Tab>")
assert(api.nvim_win_get_cursor(win)[1] == 7)
press("<CR>")
assert(vim.deep_equal(received, { modules[1].name }))
open()
press("<Tab>")
press("<Tab>")
press("<CR>")
assert(calls == 1 and #received == 3)
open()
press("<S-Tab>")
press("<CR>")
assert(calls == 0 and api.nvim_get_current_win() == origin)
for _, key in ipairs({ "q", "c", "<Esc>" }) do
	open()
	press(key)
	assert(calls == 0 and api.nvim_get_current_win() == origin)
end
local notice
vim.notify = function(message)
	notice = message
end
open()
press("u")
assert(notice:find("No modules selected", 1, true) and api.nvim_win_is_valid(win))
press("q")
local long_modules = {
	{
		name = "example.test/organization/very-long-module-path/with-several-components",
		current = "v0.0.0-20260101123456-123456789abc",
		latest = "v0.0.0-20261022123456-abcdef123456",
	},
	modules[2],
}
vim.o.columns = 110
vim.o.lines = 30
open(long_modules)
local wrapped_height = api.nvim_win_text_height(win, {}).all
assert(wrapped_height > #long_modules + 6, "fixture must wrap at the picker width")
assert(api.nvim_win_get_height(win) == wrapped_height, "ample space must show every wrapped row and footer")
assert(line(3):find(long_modules[1].name, 1, true))
assert(line(3):find(long_modules[1].latest, 1, true))
-- Resizing the same picker remeasures wraps and clamps to the new viewport.
vim.o.columns = 38
vim.o.lines = 14
api.nvim_exec_autocmds("VimResized", {})
local resized = api.nvim_win_get_config(win)
assert(resized.width == 34 and resized.height == 10)
assert(api.nvim_win_text_height(win, {}).all > resized.height)
press("<Space>")
press("<Tab>")
assert(api.nvim_win_get_cursor(win)[1] == 6)
press("<CR>")
assert(calls == 1 and vim.deep_equal(received, { long_modules[1].name }))
open(long_modules)
press("<Tab>")
press("<Tab>")
assert(api.nvim_win_get_cursor(win)[1] == 7)
press("<CR>")
assert(calls == 1 and vim.deep_equal(received, { long_modules[1].name, long_modules[2].name }))
open(long_modules)
press("<S-Tab>")
assert(api.nvim_win_get_cursor(win)[1] == 8)
press("<Tab>")
assert(api.nvim_win_get_cursor(win)[1] == 6)
press("<S-Tab>")
press("<CR>")
assert(calls == 0 and api.nvim_get_current_win() == origin)
-- Closed pickers must release their resize handlers.
api.nvim_exec_autocmds("VimResized", {})
vim.o.columns = 28
vim.o.lines = 10
local many = {}
for i = 1, 40 do
	many[i] = { name = "example.test/" .. i, current = "v1.0.0", latest = "v1.1.0" }
end
open(many)
local dimensions = api.nvim_win_get_config(win)
assert(dimensions.width <= 24 and dimensions.height <= 6)
assert(api.nvim_buf_line_count(buf) == 46)
row(42)
press("<Space>")
press("u")
assert(vim.deep_equal(received, { "example.test/40" }))
print("ui_spec: passed")
