-- Plugin registration for go-mod.nvim
-- This file is optional for lazy loading support

-- Check if the plugin has already been loaded
if vim.g.loaded_gomod_nvim == 1 then
	return
end
vim.g.loaded_gomod_nvim = 1

-- Create autocommand group for the plugin
local gomod_group = vim.api.nvim_create_augroup("GoModPlugin", { clear = true })

-- Define auto-commands for lazy loading
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = "go.mod",
	group = gomod_group,
	callback = function()
		-- Only load the plugin once for go.mod files
		if vim.g.gomod_nvim_loaded ~= 1 then
			vim.g.gomod_nvim_loaded = 1

			-- Require and initialize the plugin with default settings
			-- This is for users who want automatic loading without explicit setup() call
			local ok, gomod = pcall(require, "go-mod")
			if ok then
				gomod.setup({})
			end
		end
	end,
})

-- Define vim commands for the plugin
vim.api.nvim_create_user_command("GoModSetup", function()
	local ok, gomod = pcall(require, "go-mod")
	if ok then
		gomod.setup({})
		vim.notify("go-mod.nvim initialized with default settings", vim.log.levels.INFO)
	else
		vim.notify("Failed to load go-mod.nvim", vim.log.levels.ERROR)
	end
end, {
	desc = "Initialize go-mod.nvim with default settings",
})
