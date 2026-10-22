vim.opt.runtimepath:prepend(vim.fn.getcwd())
local config = require("go-mod.config")
local options = config.setup({ timeout = 100, icons = { outdated = "!" } })
assert(options.timeout == 100 and options.icons.outdated == "!")
options = config.setup({})
assert(options.timeout == 30000, "setup must start from defaults")
for _, bad in ipairs({
	false,
	{ auto_check = "yes" },
	{ check_interval = -1 },
	{ timeout = 0 },
	{ timeout = 1.5 },
	{ timeout = math.huge },
	{ max_concurrent_jobs = 0 },
	{ log_level = "verbose" },
	{ icons = false },
	{ icons = { unknown = "?" } },
	{ virtual_text = { spacing = -1 } },
	{ virtual_text = { prefix = false } },
	{ typo = true },
}) do
	assert(not pcall(config.setup, bad), "invalid configuration must fail clearly: " .. vim.inspect(bad))
end

local log = require("go-mod.log")
local messages, fast_notifications = {}, 0
vim.notify = function(message)
	if vim.in_fast_event() then
		fast_notifications = fast_notifications + 1
	end
	messages[#messages + 1] = message
end
log.setup({ log_level = "debug", log_file = "" })
local timer = vim.uv.new_timer()
timer:start(0, 0, function()
	log.debug("debug from fast event")
	log.error("error from fast event")
	timer:close()
end)
assert(vim.wait(500, function()
	return #messages == 2
end))
assert(fast_notifications == 0, "notifications must run on the main loop")
assert(messages[1]:find("[DEBUG]", 1, true) and messages[2]:find("[ERROR]", 1, true))

local scratch = assert(vim.env.GO_MOD_TEST_TMPDIR, "run with scripts/test.sh")
local path = scratch .. "/logs with spaces/module | log.txt"
log.setup({ log_level = "info", log_file = path })
log.info("first entry")
log.open()
local buf = vim.api.nvim_get_current_buf()
assert(not vim.bo[buf].modifiable and vim.bo[buf].buftype == "nofile")
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("first entry", 1, true))
log.info("second entry")
log.open()
assert(vim.api.nvim_get_current_buf() == buf, "reopening the log must reuse its view")
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("second entry", 1, true))
assert(vim.fn.filereadable(path) == 1, "viewing logs must leave the real file intact")
print("configuration and logging regressions passed")
