local M = {}

local defaults = {
	icons = { outdated = "󰚰 ", up_to_date = "󰄬 ", unpublished = "󰚯 ", error = "󰅚 " },
	virtual_text = { prefix = "●", spacing = 4 },
	highlights = {
		outdated = "DiagnosticWarn",
		up_to_date = "DiagnosticHint",
		unpublished = "DiagnosticInfo",
		error = "DiagnosticError",
	},
	auto_check = true,
	check_interval = 60,
	max_concurrent_jobs = 4,
	timeout = 30000,
	log_level = "info",
	log_file = vim.fn.stdpath("cache") .. "/go-mod.log",
}
M.options = vim.deepcopy(defaults)

local function expect(ok, name, description)
	if not ok then
		error("go-mod: " .. name .. " must be " .. description, 3)
	end
end

local function number(value, minimum, integer)
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= minimum
		and (not integer or value % 1 == 0)
end

function M.setup(opts)
	if opts == nil then
		opts = {}
	end
	expect(type(opts) == "table", "options", "a table")
	for key in pairs(opts) do
		expect(defaults[key] ~= nil, "option " .. tostring(key), "a recognized configuration option")
	end
	for _, key in ipairs({ "icons", "highlights", "virtual_text" }) do
		expect(opts[key] == nil or type(opts[key]) == "table", key, "a table")
	end
	local options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
	expect(type(options.auto_check) == "boolean", "auto_check", "a boolean")
	expect(number(options.check_interval, 0), "check_interval", "a finite number >= 0 (minutes)")
	expect(number(options.max_concurrent_jobs, 1, true), "max_concurrent_jobs", "an integer >= 1")
	expect(number(options.timeout, 1, true), "timeout", "an integer >= 1 (milliseconds)")
	expect(type(options.log_file) == "string", "log_file", "a string")
	expect(
		vim.tbl_contains({ "trace", "debug", "info", "warn", "error" }, options.log_level),
		"log_level",
		"trace, debug, info, warn, or error"
	)
	for _, key in ipairs({ "icons", "highlights", "virtual_text" }) do
		for field, value in pairs(options[key]) do
			expect(defaults[key][field] ~= nil, key .. "." .. tostring(field), "a recognized option")
			if key == "virtual_text" and field == "spacing" then
				expect(number(value, 0, true), key .. "." .. field, "an integer >= 0")
			else
				expect(type(value) == "string", key .. "." .. field, "a string")
			end
		end
	end
	M.options = options
	return options
end

return M
