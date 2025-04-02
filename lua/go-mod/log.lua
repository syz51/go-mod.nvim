local M = {}

-- Default config
local config = {
	log_level = "info",
	log_file = "",
}

-- Log levels
local levels = {
	trace = 1,
	debug = 2,
	info = 3,
	warn = 4,
	error = 5,
}

-- Setup logger
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, {
		log_level = opts.log_level,
		log_file = opts.log_file,
	})

	-- Create log file if it doesn't exist and path is specified
	if config.log_file ~= "" then
		local Path = require("plenary.path")
		local log_dir = Path:new(config.log_file):parent()

		if not log_dir:exists() then
			log_dir:mkdir({ parents = true })
		end

		-- Test if we can write to the log file
		local file = io.open(config.log_file, "a")
		if file then
			file:write("--- Log initialized at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
			file:close()
		else
			vim.notify("Failed to open log file: " .. config.log_file, vim.log.levels.ERROR)
			config.log_file = ""
		end
	end

	M.info("Logger initialized with level: " .. config.log_level)
end

-- Get log level as number
local function get_level_number(level)
	return levels[level] or levels.info
end

-- Internal logging function
local function log(level, msg)
	if get_level_number(level) >= get_level_number(config.log_level) then
		-- Format the log message
		local log_msg = string.format("[%s] [%s] %s", os.date("%H:%M:%S"), level:upper(), msg)

		-- Log to Neovim (only for warn and error by default)
		if level == "warn" or level == "error" or config.log_level == "debug" or config.log_level == "trace" then
			local log_level = vim.log.levels[level:upper()] or vim.log.levels.INFO
			vim.notify(log_msg, log_level)
		end

		-- Log to file if configured
		if config.log_file ~= "" then
			local file = io.open(config.log_file, "a")
			if file then
				file:write(os.date("%Y-%m-%d ") .. log_msg .. "\n")
				file:close()
			end
		end
	end
end

-- Public logging functions
function M.trace(msg)
	log("trace", msg)
end
function M.debug(msg)
	log("debug", msg)
end
function M.info(msg)
	log("info", msg)
end
function M.warn(msg)
	log("warn", msg)
end
function M.error(msg)
	log("error", msg)
end

-- Open the log file in a new buffer
function M.open()
	if config.log_file ~= "" then
		-- Check if file exists
		local file = io.open(config.log_file, "r")
		if file then
			file:close()
			vim.cmd("edit " .. config.log_file)

			-- Set up buffer for log viewing
			local bufnr = vim.api.nvim_get_current_buf()

			-- Set buffer options
			vim.bo[bufnr].modifiable = false
			vim.bo[bufnr].buftype = "nofile"
			vim.bo[bufnr].filetype = "log"

			-- Add autocmd to reload log when buffer is shown
			local group = vim.api.nvim_create_augroup("GoModLogView", { clear = true })
			vim.api.nvim_create_autocmd({ "BufEnter" }, {
				pattern = config.log_file,
				group = group,
				callback = function()
					local current_bufnr = vim.api.nvim_get_current_buf()
					vim.bo[current_bufnr].modifiable = true
					vim.cmd("silent! %delete_")
					vim.cmd("silent! read " .. config.log_file)
					vim.cmd("silent! 1delete_")
					vim.bo[current_bufnr].modifiable = false
					vim.bo[current_bufnr].modified = false
					vim.cmd("normal! G")
				end,
			})
		else
			vim.notify("Log file does not exist: " .. config.log_file, vim.log.levels.WARN)
		end
	else
		vim.notify("No log file configured", vim.log.levels.WARN)
	end
end

return M
