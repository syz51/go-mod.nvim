-- Configuration module for go-mod.nvim
local M = {}

-- Default configuration
M.options = {
	-- Icons for the signs
	icons = {
		outdated = "󰚰 ",
		up_to_date = "󰄬 ",
		unpublished = "󰚯 ",
		error = "󰅚 ",
	},
	-- Virtual text options
	virtual_text = {
		prefix = "●",
		spacing = 4,
	},
	-- Highlight groups
	highlights = {
		outdated = "DiagnosticWarn",
		up_to_date = "DiagnosticOk",
		unpublished = "DiagnosticInfo",
		error = "DiagnosticError",
	},
	-- Auto check on file open
	auto_check = true,
	-- Check interval in minutes (0 to disable)
	check_interval = 60,
	-- Log level: "trace", "debug", "info", "warn", "error"
	log_level = "info",
	-- Log file path (empty for no file logging)
	log_file = vim.fn.stdpath("cache") .. "/go-mod.log",
}

-- Setup function
function M.setup(opts)
	-- Merge user config with defaults
	M.options = vim.tbl_deep_extend("force", M.options, opts or {})

	-- Create log directory if needed
	if M.options.log_file ~= "" then
		local Path = require("plenary.path")
		local log_dir = Path:new(M.options.log_file):parent()

		if not log_dir:exists() then
			log_dir:mkdir({ parents = true })
		end
	end
end

-- Return the module
return M
