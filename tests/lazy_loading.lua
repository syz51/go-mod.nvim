-- Real lazy.nvim import, installation and events; no plugin preload or custom config.
assert(vim.fn.has("nvim-0.12") == 1, "Neovim >=0.12 is required")
local api = vim.api
local scratch = assert(vim.env.GO_MOD_TEST_TMPDIR, "run with scripts/test-lazy.sh")
local mode = assert(vim.env.GO_MOD_TEST_LAZY_MODE)
assert(mode == "ft" or mode == "cmd", "unknown lazy loading mode")
local root = assert(vim.env.GO_MOD_TEST_ROOT)
local config_root = vim.fn.stdpath("config")
local case_root = scratch .. "/" .. mode
vim.o.shadafile = "NONE"
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
vim.o.loadplugins = true -- -u NONE disables this; ordinary user init enables it.
vim.opt.runtimepath:prepend(config_root)
vim.opt.runtimepath:prepend(assert(vim.env.GO_MOD_TEST_LAZY_PATH))
vim.cmd("filetype plugin indent on")

local remote = vim.env.GO_MOD_TEST_PLUGIN_URL
local version = vim.env.GO_MOD_TEST_PLUGIN_VERSION or "*"
local spec = {
	remote or "syz51/go-mod.nvim",
	name = "go-mod.nvim",
	version = version,
	opts = { auto_check = true, check_interval = 0, log_file = "", timeout = 1234 },
}
if not remote then
	spec.dir = root
end
if mode == "ft" then
	spec.ft = "gomod"
else
	spec.cmd = { "GoModCheck", "GoModToggle", "GoModUpdate", "GoModLog", "GoModSetup" }
end
vim.fn.mkdir(config_root .. "/lua/plugins", "p")
vim.fn.writefile(vim.split("return { " .. vim.inspect(spec) .. " }", "\n"), config_root .. "/lua/plugins/go-mod.lua")

-- Observe actual setup calls without loading, wrapping, or replacing plugin code.
local setup_calls, load_events = 0, 0
debug.sethook(function(event)
	if event == "call" then
		local info = debug.getinfo(2, "nS")
		if info.name == "setup" and info.source:match("/lua/go%-mod/init%.lua$") then
			setup_calls = setup_calls + 1
		end
	end
end, "c")
api.nvim_create_autocmd("User", {
	pattern = "LazyLoad",
	callback = function(event)
		if event.data == "go-mod.nvim" then
			load_events = load_events + 1
		end
	end,
})
local errors, fetch_notices = {}, {}
vim.notify = function(message, level, opts)
	if level == vim.log.levels.ERROR then
		errors[#errors + 1] = tostring(message)
	end
	if tostring(message):find("Fetching dependency versions for go.mod…", 1, true) then
		assert(level == vim.log.levels.INFO and opts.title == "go-mod.nvim")
		fetch_notices[#fetch_notices + 1] = message
	end
end

-- Only go list is simulated; lazy.nvim's Git installation remains real.
local real_system = vim.system
local lookups = {}
vim.system = function(argv, opts, callback)
	if argv[1] == "go" and argv[2] == "list" then
		assert(#fetch_notices == 1, "first-fetch notice must precede the first Go lookup and never repeat")
		assert(fetch_notices[1] == "Fetching dependency versions for go.mod…", "notification must stay concise")
		assert(vim.deep_equal(argv, { "go", "list", "-m", "-json", "example.test/dep@latest" }))
		assert(opts.timeout == 1234, "lazy opts must reach the first lookup")
		local job = { cwd = opts.cwd, callback = callback }
		lookups[#lookups + 1] = job
		return { kill = function() end }
	end
	assert(argv[1] ~= "go", "unexpected Go invocation: " .. vim.inspect(argv))
	return real_system(argv, opts, callback)
end
-- No go.mod network requests can escape even if lookup code changes.
vim.env.GOPROXY, vim.env.GOSUMDB, vim.env.GOTOOLCHAIN = "off", "off", "local"

require("lazy").setup({
	spec = { { import = "plugins" } },
	defaults = { lazy = false, version = false }, -- LazyVim defaults
	lockfile = case_root .. "/lazy-lock.json",
	install = { missing = true },
	checker = { enabled = false },
	change_detection = { enabled = false, notify = false },
	rocks = { enabled = false },
	headless = { process = false, log = false, task = false, colors = false },
})
local plugin =
	assert(require("lazy.core.config").plugins["go-mod.nvim"], "imported spec missing: " .. table.concat(errors, "\n"))
assert(plugin.lazy == true, "ft/cmd must override LazyVim's lazy=false default")
assert(plugin.version == version, "explicit version must override version=false default")
local function unloaded()
	assert(not plugin._.loaded, "go-mod.nvim loaded before its trigger")
	assert(not package.loaded["go-mod"] and not package.loaded["go-mod.init"], "plugin was preloaded")
	assert(vim.g.loaded_gomod_nvim == nil, "plugin runtime script ran prematurely")
	assert(setup_calls == 0 and load_events == 0, "premature setup/load event")
end
unloaded()
vim.fn.writefile({ "ordinary text" }, case_root .. "/notes.txt")
vim.cmd.edit(vim.fn.fnameescape(case_root .. "/notes.txt"))
unloaded()

if remote then
	assert(not plugin.dir:find(root, 1, true), "remote test must not use the checkout dir")
	local function git(args)
		local result = real_system(vim.list_extend({ "git", "-C", plugin.dir }, args), { text = true }):wait()
		assert(result.code == 0, result.stderr)
		return vim.trim(result.stdout)
	end
	local lock = vim.json.decode(table.concat(vim.fn.readfile(case_root .. "/lazy-lock.json"), "\n"))
	local head = git({ "rev-parse", "HEAD" })
	assert(head == lock["go-mod.nvim"].commit, "installed HEAD must match lazy lock")
	local tag = git({ "describe", "--tags", "--exact-match", "HEAD" })
	if version == "*" then
		local semver = require("lazy.manage.semver")
		local versions = {}
		for name in git({ "tag", "--list" }):gmatch("[^\n]+") do
			local parsed = semver.version(name)
			if parsed and semver.range("*"):matches(parsed) then
				versions[#versions + 1] = parsed
			end
		end
		local selected = semver.last(versions)
		assert(selected, "remote repository has no stable semver tag")
		assert(head == git({ "rev-parse", selected.input .. "^{commit}" }), "HEAD must be the latest stable tag")
	else
		assert(head == git({ "rev-parse", version .. "^{commit}" }), "HEAD must match requested tag")
	end
	print("remote install: " .. tag .. " at " .. head)
end

local module_root = case_root .. "/project with spaces"
vim.fn.mkdir(module_root, "p")
vim.fn.writefile(
	{ "module example.test/app", "", "go 1.16", "", "require example.test/dep v1.0.0" },
	module_root .. "/go.mod"
)
vim.cmd.edit(vim.fn.fnameescape(module_root .. "/go.mod"))
local original = api.nvim_get_current_buf()
assert(vim.bo[original].filetype == "gomod", "native filetype detection must recognize go.mod")
if mode == "cmd" then
	unloaded()
	vim.cmd.GoModCheck()
end
assert(plugin._.loaded, "ordinary trigger did not load the plugin")
assert(setup_calls == 1, "lazy opts must call setup exactly once, got " .. setup_calls)
assert(require("go-mod").is_setup(), "lazy setup did not initialize the plugin")
local options = require("go-mod.config").options
local function configured()
	assert(options == require("go-mod.config").options, "a later bootstrap replaced the options table")
	assert(options.auto_check and options.check_interval == 0 and options.log_file == "" and options.timeout == 1234)
	assert(setup_calls == 1, "later bootstrap reset setup/options")
end
configured()

-- Switch before scheduled checks and lookup completions run.
local other = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(other)
assert(
	vim.wait(3000, function()
		return #lookups > 0 and load_events > 0
	end),
	"first-file automatic check or LazyLoad event missing: " .. table.concat(errors, "\n")
)
assert(load_events == 1, "expected exactly one LazyLoad event")
assert(#fetch_notices == 1, "lazy first-file check must notify exactly once")
for _, job in ipairs(lookups) do
	assert(
		vim.uv.fs_realpath(job.cwd) == vim.uv.fs_realpath(module_root),
		"deferred lookup followed the current buffer"
	)
	job.callback({ code = 0, signal = 0, stdout = '{"Version":"v1.1.0"}', stderr = "" })
end
local core = require("go-mod.core")
assert(
	vim.wait(3000, function()
		return core.get_buffer_info(original) ~= nil
	end),
	"first-file check did not complete"
)
assert(core.get_buffer_info(original).modules["example.test/dep"].status == "outdated")
assert(core.get_buffer_info(other) == nil, "check polluted the unrelated buffer")
assert(api.nvim_get_current_buf() == other, "check changed the current buffer")
local marks = api.nvim_buf_get_extmarks(original, api.nvim_get_namespaces().go_mod, 0, -1, { details = true })
assert(#marks == 1 and marks[1][4].virt_text[1][1]:find("v1.0.0 → v1.1.0", 1, true), "virtual text missing")
assert(#api.nvim_buf_get_extmarks(other, api.nvim_get_namespaces().go_mod, 0, -1, {}) == 0)
configured()

api.nvim_set_current_buf(original)
local commands = api.nvim_get_commands({})
for _, name in ipairs({ "GoModCheck", "GoModToggle", "GoModUpdate", "GoModLog", "GoModSetup" }) do
	assert(commands[name], "command missing: " .. name)
end
assert(commands.GoModUpdate.complete, "update command lost completion")
assert(vim.deep_equal(vim.fn.getcompletion("GoModUpdate ", "cmdline"), { "example.test/dep" }), "incorrect completion")
local origin_win = api.nvim_get_current_win()
vim.cmd.GoModUpdate()
local picker_win, picker_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
assert(picker_win ~= origin_win and vim.bo[picker_buf].filetype == "go-mod-updates", "picker did not open")
assert(table.concat(api.nvim_buf_get_lines(picker_buf, 0, -1, false), "\n"):find("example.test/dep", 1, true))
local closed = false
for _, map in ipairs(api.nvim_buf_get_keymap(picker_buf, "n")) do
	if map.lhs == "q" then
		map.callback()
		closed = true
		break
	end
end
assert(closed and not api.nvim_win_is_valid(picker_win), "picker did not close")
assert(api.nvim_get_current_win() == origin_win and api.nvim_get_current_buf() == original, "picker lost source buffer")
configured()
assert(#errors == 0, table.concat(errors, "\n"))
debug.sethook()
vim.system = real_system
require("go-mod").teardown()
print("lazy loading passed (" .. mode .. ", setup calls=" .. setup_calls .. ", LazyLoad events=" .. load_events .. ")")
