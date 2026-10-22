local M = {}

function M.check()
	local health = vim.health
	local start, ok, warn, err = health.start, health.ok, health.warn, health.error
	start("go-mod.nvim")
	if vim.fn.has("nvim-0.12") == 1 then
		ok("Neovim 0.12 or newer")
	else
		err("Neovim 0.12 or newer is required")
	end
	if vim.fn.executable("go") == 1 then
		local version = vim.fn.system({ "go", "version" })
		if vim.v.shell_error == 0 then
			version = vim.trim(version)
			local major, minor = version:match("^go version go(%d+)%.(%d+)")
			major, minor = tonumber(major), tonumber(minor)
			if not major then
				warn("Unable to determine Go version: " .. version, { "Verify Go 1.16 or newer is installed" })
			elseif major > 1 or (major == 1 and minor >= 16) then
				ok(version)
			else
				err("Go 1.16 or newer is required; found " .. version, { "Upgrade Go, then restart Neovim" })
			end
		else
			err("go is executable but 'go version' failed: " .. version)
		end
	else
		err("Go is missing from PATH", { "Install Go 1.16 or newer, then restart Neovim" })
	end
	local options = require("go-mod.config").options
	if options.log_file == "" then
		ok("File logging is disabled")
	else
		local parent = vim.fn.fnamemodify(options.log_file, ":h")
		local writable = vim.fn.filereadable(options.log_file) == 1 and vim.fn.filewritable(options.log_file) == 1
		if writable or vim.fn.filewritable(parent) == 2 then
			ok("Log path: " .. options.log_file)
		else
			warn(
				"Log path may not be writable: " .. options.log_file,
				{ "Choose a writable log_file or set it to an empty string" }
			)
		end
	end
end

return M
