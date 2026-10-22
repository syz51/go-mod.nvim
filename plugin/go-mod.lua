if vim.g.loaded_gomod_nvim == 1 then
	return
end
vim.g.loaded_gomod_nvim = 1

local existing = package.loaded["go-mod"]
if existing and existing.is_setup() then
	return
end

local function bootstrap()
	local ok, module = pcall(require, "go-mod")
	if ok and not module.is_setup() then
		ok, module = pcall(module.setup)
	end
	if not ok then
		vim.notify("go-mod.nvim could not initialize: " .. tostring(module), vim.log.levels.ERROR)
		return
	end
	return require("go-mod")
end

local group = vim.api.nvim_create_augroup("GoModPlugin", { clear = true })
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
	pattern = "go.mod",
	group = group,
	callback = bootstrap,
})
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "gomod", "go.mod" },
	group = group,
	callback = bootstrap,
})

-- Commands are available before the first go.mod is opened.
vim.api.nvim_create_user_command("GoModSetup", bootstrap, { desc = "Initialize go-mod.nvim" })
for _, item in ipairs({
	{ "GoModCheck", "check_dependencies" },
	{ "GoModToggle", "toggle" },
	{ "GoModLog", "log" },
	{ "GoModUpdate", "update" },
}) do
	local name, action = item[1], item[2]
	vim.api.nvim_create_user_command(name, function(args)
		local module = bootstrap()
		if not module then
			return
		end
		if action == "log" then
			require("go-mod.log").open()
		elseif action == "update" then
			local updater = require("go-mod.updater")
			if args.args ~= "" then
				updater.update_module(args.args)
			else
				updater.update_selection_window()
			end
		else
			module[action]()
		end
	end, {
		nargs = action == "update" and "?" or 0,
		desc = "Load go-mod.nvim and run " .. name,
	})
end
