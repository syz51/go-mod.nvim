-- Main entry point for the go-mod.nvim plugin
local M = {}

-- Initialize the modules
local config = require("go-mod.config")
local core = require("go-mod.core")
local updater = require("go-mod.updater")
local log = require("go-mod.log")

-- Setup function
function M.setup(opts)
	-- Initialize configuration
	config.setup(opts or {})

	-- Initialize logger
	log.setup(config.options)

	-- Create autocommands
	local api = vim.api
	local group = api.nvim_create_augroup("GoMod", { clear = true })

	-- Auto check on file open
	if config.options.auto_check then
		api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
			pattern = "go.mod",
			group = group,
			callback = function()
				-- Delay check to ensure buffer is fully loaded
				vim.schedule(function()
					vim.defer_fn(M.check_dependencies, 100)
				end)
			end,
		})
	end

	-- Set up periodic checking if interval > 0
	if config.options.check_interval > 0 then
		api.nvim_create_autocmd({ "BufEnter" }, {
			pattern = "go.mod",
			group = group,
			callback = function()
				core.check_periodic()
			end,
		})
	end

	-- Clean up when buffer is deleted
	api.nvim_create_autocmd({ "BufDelete" }, {
		pattern = "*",
		group = group,
		callback = function(args)
			core.cleanup_buffer(args.buf)
		end,
	})

	-- Create user commands
	api.nvim_create_user_command("GoModCheck", M.check_dependencies, {
		desc = "Check Go module dependencies for updates",
	})

	api.nvim_create_user_command("GoModToggle", M.toggle, {
		desc = "Toggle display of Go module dependency information",
	})

	api.nvim_create_user_command("GoModLog", function()
		log.open()
	end, {
		desc = "Open the go-mod log file",
	})

	api.nvim_create_user_command("GoModUpdate", function(args)
		if args.args ~= "" then
			updater.update_module(args.args)
		else
			updater.update_selection_window()
		end
	end, {
		desc = "Update Go module dependencies",
		nargs = "?",
		complete = function()
			return updater.get_outdated_modules()
		end,
	})

	log.info("go-mod initialized")
end

-- Public API functions
function M.check_dependencies()
	core.check_dependencies()
end

function M.toggle()
	core.toggle()
end

function M.update_module(module_name)
	updater.update_module(module_name)
end

function M.update_all_modules()
	updater.update_all_modules()
end

-- Return the module
return M
