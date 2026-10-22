local M = {}
local config = { log_level = "info", log_file = "" }
local levels = { trace = 1, debug = 2, info = 3, warn = 4, error = 5 }

local function notify(message, level)
	local function show()
		vim.notify(message, level, { title = "go-mod.nvim" })
	end
	if vim.in_fast_event() then
		vim.schedule(show)
	else
		show()
	end
end

function M.setup(opts)
	config = { log_level = opts.log_level or "info", log_file = opts.log_file or "" }
	if config.log_file ~= "" then
		local parent = vim.fn.fnamemodify(config.log_file, ":h")
		local ok = pcall(vim.fn.mkdir, parent, "p")
		local file = ok and io.open(config.log_file, "a")
		if file then
			file:write("--- Log initialized at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
			file:close()
		else
			notify("Cannot write log file: " .. config.log_file .. ". File logging disabled.", vim.log.levels.WARN)
			config.log_file = ""
		end
	end
end

local function log(level, message)
	if levels[level] < (levels[config.log_level] or levels.info) then
		return
	end
	local formatted = string.format("[%s] [%s] %s", os.date("%H:%M:%S"), level:upper(), tostring(message))
	if level == "warn" or level == "error" or (levels[config.log_level] or levels.info) <= levels.debug then
		notify(formatted, vim.log.levels[level:upper()] or vim.log.levels.INFO)
	end
	if config.log_file ~= "" then
		local file = io.open(config.log_file, "a")
		if file then
			file:write(os.date("%Y-%m-%d ") .. formatted .. "\n")
			file:close()
		end
	end
end

for name in pairs(levels) do
	M[name] = function(message)
		log(name, message)
	end
end

function M.open()
	if config.log_file == "" then
		notify("No log file configured. Set log_file in setup() to enable file logging.", vim.log.levels.WARN)
		return
	end
	local path = config.log_file
	if vim.fn.filereadable(path) ~= 1 then
		notify("Log file does not exist: " .. path, vim.log.levels.WARN)
		return
	end
	local existing = vim.fn.bufnr("go-mod-log://" .. path)
	if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
		vim.api.nvim_set_current_buf(existing)
		vim.api.nvim_exec_autocmds("BufEnter", { buffer = existing })
		return
	end
	-- A scratch view avoids Ex filename parsing and leaves the real file untouched.
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "go-mod-log://" .. path)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "log"
	local function refresh()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		local ok, lines = pcall(vim.fn.readfile, path)
		if ok then
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.bo[buf].modifiable = false
			vim.bo[buf].modified = false
		end
	end
	refresh()
	vim.api.nvim_create_autocmd("BufEnter", { buffer = buf, callback = refresh })
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_win_set_cursor(0, { math.max(1, vim.api.nvim_buf_line_count(buf)), 0 })
end

return M
