-- Core functionality for go-mod.nvim
local M = {}

-- Import required modules
local api = vim.api
local plenary_job = require("plenary.job")
local config = require("go-mod.config")
local semver = require("go-mod.semver")
local log = require("go-mod.log")

-- Namespace for virtual text
local ns_id = api.nvim_create_namespace("go_mod")

-- Store buffer information
local buffer_info = {}

-- Parse go.mod file and extract dependencies
local function parse_gomod(content)
	local modules = {}
	local in_require_block = false

	-- Handle empty content
	if not content or content == "" then
		log.warn("Empty go.mod content")
		return modules
	end

	for _, line in ipairs(vim.split(content, "\n")) do
		-- Check for require block
		if line:match("^require%s+%(") then
			in_require_block = true
		elseif in_require_block and line:match("^%)") then
			in_require_block = false
		end

		-- Extract module information
		local module_pattern = in_require_block and "^%s*([%w%.%-%_/]+)%s+([%w%.%+%-%~]+)"
			or "^require%s+([%w%.%-%_/]+)%s+([%w%.%+%-%~]+)"

		local module_name, version = line:match(module_pattern)
		if module_name and version then
			log.debug("Found module: " .. module_name .. " @ " .. version)
			modules[module_name] = {
				current = version,
				latest = nil,
				status = "unknown",
				line = nil,
			}
		end
	end

	return modules
end

-- Find line numbers for each module
local function find_module_lines(bufnr, modules)
	-- Validate buffer exists
	if not api.nvim_buf_is_valid(bufnr) then
		log.error("Invalid buffer: " .. bufnr)
		return modules
	end

	local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local in_require_block = false

	for i, line in ipairs(lines) do
		-- Check for require block
		if line:match("^require%s+%(") then
			in_require_block = true
		elseif in_require_block and line:match("^%)") then
			in_require_block = false
		end

		-- Match module in line
		local module_pattern = in_require_block and "^%s*([%w%.%-%_/]+)%s+([%w%.%+%-%~]+)"
			or "^require%s+([%w%.%-%_/]+)%s+([%w%.%+%-%~]+)"

		local found_module_name = line:match(module_pattern)
		if found_module_name and modules[found_module_name] then
			modules[found_module_name].line = i - 1 -- 0-indexed
		end
	end

	return modules
end

-- Display module information in the buffer
local function display_module_info(bufnr, modules)
	-- Validate buffer exists
	if not api.nvim_buf_is_valid(bufnr) then
		log.error("Invalid buffer: " .. bufnr)
		return
	end

	-- Clear existing virtual text
	api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

	-- Count modules by status
	local status_count = {
		outdated = 0,
		up_to_date = 0,
		unpublished = 0,
		error = 0,
		unknown = 0,
	}

	for _, info in pairs(modules) do
		if info.line ~= nil then
			local text = ""
			local hl_group = config.options.highlights.up_to_date

			if info.status == "outdated" then
				text = config.options.icons.outdated .. info.current .. " → " .. info.latest
				hl_group = config.options.highlights.outdated
				status_count.outdated = status_count.outdated + 1
			elseif info.status == "up_to_date" then
				text = config.options.icons.up_to_date .. "Up to date"
				hl_group = config.options.highlights.up_to_date
				status_count.up_to_date = status_count.up_to_date + 1
			elseif info.status == "unpublished" then
				text = config.options.icons.unpublished .. "Newer than latest"
				hl_group = config.options.highlights.unpublished
				status_count.unpublished = status_count.unpublished + 1
			elseif info.status == "error" then
				text = config.options.icons.error .. "Error checking"
				hl_group = config.options.highlights.error
				status_count.error = status_count.error + 1
			else
				status_count.unknown = status_count.unknown + 1
			end

			if text ~= "" then
				api.nvim_buf_set_extmark(bufnr, ns_id, info.line, 0, {
					virt_text = { { text, hl_group } },
					virt_text_pos = "eol",
					hl_mode = "combine",
				})
			end
		end
	end

	-- Store module info for this buffer
	buffer_info[bufnr] = {
		modules = modules,
		last_check = os.time(),
		visible = true,
	}

	-- Log summary
	log.info(
		string.format(
			"Dependency check complete: %d outdated, %d up-to-date, %d newer, %d error, %d unknown",
			status_count.outdated,
			status_count.up_to_date,
			status_count.unpublished,
			status_count.error,
			status_count.unknown
		)
	)
end

-- Check for latest versions of modules
local function check_latest_versions(modules, callback)
	local pending = 0
	local completed = 0

	-- If no modules to check, call callback immediately
	if vim.tbl_count(modules) == 0 then
		vim.schedule(function()
			callback(modules)
		end)
		return
	end

	for module_name, info in pairs(modules) do
		pending = pending + 1

		-- Log the command being executed
		local cmd = "go list -m -json " .. module_name .. "@latest"
		log.debug("Executing: " .. cmd)

		-- Use 'go list -m -json' to get module info
		plenary_job
			:new({
				command = "go",
				args = { "list", "-m", "-json", module_name .. "@latest" },
				cwd = vim.fn.getcwd(), -- Add current working directory
				env = vim.fn.environ(), -- Add environment variables
				on_stdout = function(_, data)
					if data and data ~= "" then
						log.debug("stdout for " .. module_name .. ": " .. data)
					end
				end,
				on_stderr = function(_, data)
					if data and data ~= "" then
						log.warn("stderr for " .. module_name .. ": " .. data)
					end
				end,
				on_exit = function(j, return_val)
					completed = completed + 1

					if return_val == 0 then
						local result = table.concat(j:result(), "\n")
						log.debug("Result for " .. module_name .. ": " .. result)

						local success, data = pcall(vim.json.decode, result)
						if success and data and data.Version then
							info.latest = data.Version
							log.info(
								"Latest version of "
									.. module_name
									.. ": "
									.. data.Version
									.. " (Current: "
									.. info.current
									.. ")"
							)

							-- Parse versions
							local current_version = semver.parse(info.current)
							local latest_version = semver.parse(info.latest)

							log.debug(
								string.format(
									"Comparing versions - Current: %s (%d.%d.%d%s), Latest: %s (%d.%d.%d%s)",
									info.current,
									current_version.major,
									current_version.minor,
									current_version.patch,
									current_version.prerelease,
									info.latest,
									latest_version.major,
									latest_version.minor,
									latest_version.patch,
									latest_version.prerelease
								)
							)

							local comparison = semver.compare(current_version, latest_version)

							if comparison < 0 then
								info.status = "outdated"
								log.info(module_name .. " is outdated: " .. info.current .. " → " .. info.latest)
							elseif comparison > 0 then
								info.status = "unpublished"
								log.info(
									module_name .. " is newer than latest: " .. info.current .. " > " .. info.latest
								)
							else
								info.status = "up_to_date"
								log.info(module_name .. " is up to date: " .. info.current)
							end
						else
							info.status = "error"
							log.error("Failed to parse JSON for module: " .. module_name)
							if not success then
								log.error("JSON parse error: " .. tostring(data))
							end
						end
					else
						info.status = "error"
						log.error("Failed to check module: " .. module_name .. ", exit code: " .. return_val)
					end

					-- Call callback when all jobs are done
					if completed == pending then
						-- Schedule the callback to run in the main event loop
						vim.schedule(function()
							callback(modules)
						end)
					end
				end,
			})
			:start()
	end
end

-- Check dependencies in the current buffer
function M.check_dependencies()
	local bufnr = api.nvim_get_current_buf()

	-- Validate buffer exists
	if not api.nvim_buf_is_valid(bufnr) then
		log.error("Invalid buffer: " .. bufnr)
		return
	end

	local filetype = vim.bo[bufnr].filetype

	-- Handle Go files with both gomod and go filetypes
	if filetype ~= "gomod" and filetype ~= "go.mod" then
		log.debug("Not a go.mod file, skipping")
		return
	end

	log.info("Checking dependencies in buffer " .. bufnr)

	-- Get buffer content
	local content = table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

	-- Parse go.mod file
	local modules = parse_gomod(content)

	-- Find line numbers for modules
	modules = find_module_lines(bufnr, modules)

	-- Check latest versions
	check_latest_versions(modules, function(updated_modules)
		display_module_info(bufnr, updated_modules)
	end)
end

-- Check periodically based on interval
function M.check_periodic()
	local bufnr = api.nvim_get_current_buf()

	-- Check if we need to refresh
	if buffer_info[bufnr] and buffer_info[bufnr].last_check then
		local elapsed = os.time() - buffer_info[bufnr].last_check
		if elapsed > (config.options.check_interval * 60) then
			M.check_dependencies()
		end
	end
end

-- Toggle virtual text display
function M.toggle()
	local bufnr = api.nvim_get_current_buf()

	-- Validate buffer exists
	if not api.nvim_buf_is_valid(bufnr) then
		log.error("Invalid buffer: " .. bufnr)
		return
	end

	if not buffer_info[bufnr] or not buffer_info[bufnr].visible then
		M.check_dependencies()
	else
		api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
		if buffer_info[bufnr] then
			buffer_info[bufnr].visible = false
		end
		log.info("Disabled go-mod for buffer " .. bufnr)
	end
end

-- Clean up resources for a buffer
function M.cleanup_buffer(bufnr)
	if buffer_info[bufnr] then
		buffer_info[bufnr] = nil
		log.debug("Cleaned up resources for buffer " .. bufnr)
	end
end

-- Get buffer information (for use by other modules)
function M.get_buffer_info(bufnr)
	return buffer_info[bufnr]
end

-- Return the module
return M
