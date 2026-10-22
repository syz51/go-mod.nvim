local M = {}
local config = require("go-mod.config")
local log = require("go-mod.log")
local core, updater
local initialized = false
local timer
local scheduled = {}

local function stop_timer()
	if timer then
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
		timer = nil
	end
end

local function eligible(bufnr)
	return vim.api.nvim_buf_is_valid(bufnr)
		and vim.api.nvim_buf_is_loaded(bufnr)
		and (vim.bo[bufnr].filetype == "gomod" or vim.bo[bufnr].filetype == "go.mod")
end

local function queue_check(bufnr)
	if scheduled[bufnr] then
		return
	end
	local ticket = {}
	scheduled[bufnr] = ticket
	vim.schedule(function()
		if scheduled[bufnr] ~= ticket then
			return
		end
		scheduled[bufnr] = nil
		if initialized and eligible(bufnr) then
			core.check_dependencies(bufnr)
		end
	end)
end

function M.is_setup()
	return initialized
end

function M.teardown()
	initialized = false
	stop_timer()
	scheduled = {}
	if core and core.shutdown then
		core.shutdown()
	end
	pcall(vim.api.nvim_del_augroup_by_name, "GoMod")
end

function M.setup(opts)
	if vim.fn.has("nvim-0.12") ~= 1 then
		error("go-mod.nvim requires Neovim 0.12 or newer")
	end
	local options = config.setup(opts)
	M.teardown()
	core = require("go-mod.core")
	updater = require("go-mod.updater")
	log.setup(options)
	initialized = true
	vim.g.gomod_nvim_loaded = 1

	local api = vim.api
	local group = api.nvim_create_augroup("GoMod", { clear = true })
	if options.auto_check then
		api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePost" }, {
			pattern = "go.mod",
			group = group,
			callback = function(args)
				queue_check(args.buf)
			end,
		})
		api.nvim_create_autocmd("FileType", {
			pattern = { "gomod", "go.mod" },
			group = group,
			callback = function(args)
				queue_check(args.buf)
			end,
		})
	end

	if options.check_interval > 0 then
		api.nvim_create_autocmd("BufEnter", {
			pattern = "go.mod",
			group = group,
			callback = function(args)
				if eligible(args.buf) then
					core.check_periodic(args.buf)
				end
			end,
		})
		local interval = math.max(1, math.floor(options.check_interval * 60000))
		timer = vim.uv.new_timer()
		timer:start(
			interval,
			interval,
			vim.schedule_wrap(function()
				if not initialized then
					return
				end
				for _, bufnr in ipairs(api.nvim_list_bufs()) do
					if eligible(bufnr) then
						core.check_periodic(bufnr)
					end
				end
			end)
		)
	end

	api.nvim_create_autocmd({ "BufDelete", "BufWipeout", "BufUnload" }, {
		group = group,
		callback = function(args)
			scheduled[args.buf] = nil
			core.cleanup_buffer(args.buf)
		end,
	})
	api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.teardown })

	api.nvim_create_user_command("GoModCheck", function()
		M.check_dependencies()
	end, { desc = "Check Go module dependencies for updates", force = true })
	api.nvim_create_user_command("GoModToggle", function()
		M.toggle()
	end, { desc = "Toggle Go module dependency information", force = true })
	api.nvim_create_user_command("GoModLog", log.open, { desc = "Open the go-mod log file", force = true })
	api.nvim_create_user_command("GoModSetup", function()
		M.setup()
	end, { desc = "Initialize go-mod.nvim with default settings", force = true })
	api.nvim_create_user_command("GoModUpdate", function(args)
		if args.args ~= "" then
			updater.update_module(args.args)
		else
			updater.update_selection_window()
		end
	end, {
		desc = "Select and update Go module dependencies",
		nargs = "?",
		force = true,
		complete = function()
			return updater.get_outdated_modules()
		end,
	})

	if options.auto_check then
		for _, bufnr in ipairs(api.nvim_list_bufs()) do
			if eligible(bufnr) then
				queue_check(bufnr)
			end
		end
	end
	log.info("go-mod initialized")
	return M
end

local function ensure_setup()
	if not initialized then
		M.setup()
	end
end

function M.check_dependencies(bufnr)
	ensure_setup()
	return core.check_dependencies(bufnr)
end

function M.toggle(bufnr)
	ensure_setup()
	return core.toggle(bufnr)
end

function M.update_module(module_name, bufnr)
	ensure_setup()
	return updater.update_module(module_name, bufnr)
end

function M.update_all_modules(bufnr)
	ensure_setup()
	return updater.update_all_modules(bufnr)
end

return M
