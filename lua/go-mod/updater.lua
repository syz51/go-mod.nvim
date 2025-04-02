-- Module update functionality for go-mod.nvim
local M = {}

-- Import required modules
local api = vim.api
local plenary_job = require("plenary.job")
local core = require("go-mod.core")
local ui = require("go-mod.ui")
local log = require("go-mod.log")

-- Update a single module to its latest version
function M.update_module(module_name)
	local bufnr = api.nvim_get_current_buf()

	-- Validate buffer exists and is a go.mod file
	if
		not api.nvim_buf_is_valid(bufnr) or (vim.bo[bufnr].filetype ~= "gomod" and vim.bo[bufnr].filetype ~= "go.mod")
	then
		log.error("Not a valid go.mod buffer")
		return
	end

	-- Check if module exists in current buffer
	local buffer_data = core.get_buffer_info(bufnr)
	if not buffer_data or not buffer_data.modules or not buffer_data.modules[module_name] then
		log.error("Module not found: " .. module_name)
		vim.notify("Module not found: " .. module_name, vim.log.levels.ERROR)
		return
	end

	local module_info = buffer_data.modules[module_name]

	-- Only update if module is outdated
	if module_info.status ~= "outdated" then
		log.info("Module " .. module_name .. " is not outdated, skipping update")
		vim.notify("Module " .. module_name .. " is already up to date", vim.log.levels.INFO)
		return
	end

	-- Get the current directory (assuming it's the Go module root)
	local cwd = vim.fn.getcwd()

	-- Show notification that update is starting
	vim.notify(
		"Updating " .. module_name .. " from " .. module_info.current .. " to " .. module_info.latest .. "...",
		vim.log.levels.INFO
	)

	-- Run go get to update the module
	plenary_job
		:new({
			command = "go",
			args = { "get", module_name .. "@" .. module_info.latest },
			cwd = cwd,
			on_exit = function(j, return_val)
				if return_val == 0 then
					vim.schedule(function()
						vim.notify(
							"Successfully updated " .. module_name .. " to " .. module_info.latest,
							vim.log.levels.INFO
						)

						-- Re-check dependencies after update
						core.check_dependencies()
					end)
				else
					local stderr = table.concat(j:stderr_result(), "\n")
					log.error("Failed to update " .. module_name .. ": " .. stderr)
					vim.schedule(function()
						vim.notify("Failed to update " .. module_name .. ". See log for details.", vim.log.levels.ERROR)
					end)
				end
			end,
		})
		:start()
end

-- Update all outdated modules
function M.update_all_modules()
	local bufnr = api.nvim_get_current_buf()

	-- Validate buffer exists and is a go.mod file
	if
		not api.nvim_buf_is_valid(bufnr) or (vim.bo[bufnr].filetype ~= "gomod" and vim.bo[bufnr].filetype ~= "go.mod")
	then
		log.error("Not a valid go.mod buffer")
		return
	end

	-- Check if we have any modules to update
	local buffer_data = core.get_buffer_info(bufnr)
	if not buffer_data or not buffer_data.modules then
		log.error("No module information available")
		vim.notify("No module information available. Run check first.", vim.log.levels.ERROR)
		return
	end

	-- Find outdated modules
	local outdated_modules = {}
	for module_name, info in pairs(buffer_data.modules) do
		if info.status == "outdated" then
			table.insert(outdated_modules, {
				name = module_name,
				current = info.current,
				latest = info.latest,
			})
		end
	end

	-- Check if there are any outdated modules
	if #outdated_modules == 0 then
		vim.notify("No outdated modules found", vim.log.levels.INFO)
		return
	end

	-- Sort modules by name
	table.sort(outdated_modules, function(a, b)
		return a.name < b.name
	end)

	-- Ask for confirmation before updating all modules
	local total = #outdated_modules
	local confirm_msg = string.format("Update all %d outdated modules?", total)

	vim.ui.select({ "Yes", "No" }, {
		prompt = confirm_msg,
	}, function(choice)
		if choice == "Yes" then
			-- Update all outdated modules one by one
			vim.notify(string.format("Updating %d modules...", total), vim.log.levels.INFO)

			-- Update modules one by one to avoid conflicts
			local function update_next(index)
				if index <= #outdated_modules then
					local module = outdated_modules[index]
					M.update_module(module.name)

					-- Schedule next update with a slight delay
					vim.defer_fn(function()
						update_next(index + 1)
					end, 1000) -- 1 second delay between updates
				else
					vim.notify("All modules updated successfully", vim.log.levels.INFO)
				end
			end

			update_next(1)
		end
	end)
end

-- Get list of outdated modules (for command completion)
function M.get_outdated_modules()
	local bufnr = api.nvim_get_current_buf()

	if not api.nvim_buf_is_valid(bufnr) then
		return {}
	end

	local buffer_data = core.get_buffer_info(bufnr)
	if buffer_data and buffer_data.modules then
		local completions = {}
		for module_name, info in pairs(buffer_data.modules) do
			if info.status == "outdated" then
				table.insert(completions, module_name)
			end
		end
		return completions
	end

	return {}
end

-- Show a window with all outdated modules and allow selection
function M.update_selection_window()
	local bufnr = api.nvim_get_current_buf()

	-- Validate buffer exists and is a go.mod file
	if
		not api.nvim_buf_is_valid(bufnr) or (vim.bo[bufnr].filetype ~= "gomod" and vim.bo[bufnr].filetype ~= "go.mod")
	then
		log.error("Not a valid go.mod buffer")
		return
	end

	-- Check if we have any modules to update
	local buffer_data = core.get_buffer_info(bufnr)
	if not buffer_data or not buffer_data.modules then
		log.error("No module information available")
		vim.notify("No module information available. Run check first.", vim.log.levels.ERROR)
		return
	end

	-- Find outdated modules
	local outdated_modules = {}
	for module_name, info in pairs(buffer_data.modules) do
		if info.status == "outdated" then
			table.insert(outdated_modules, {
				name = module_name,
				current = info.current,
				latest = info.latest,
			})
		end
	end

	-- Check if there are any outdated modules
	if #outdated_modules == 0 then
		vim.notify("No outdated modules found", vim.log.levels.INFO)
		return
	end

	-- Sort modules by name
	table.sort(outdated_modules, function(a, b)
		return a.name < b.name
	end)

	-- Show the UI for selecting modules to update
	ui.show_update_window(outdated_modules, M.update_module)
end

-- Return the module
return M
