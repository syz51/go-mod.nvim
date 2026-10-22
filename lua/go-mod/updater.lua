-- Completion-driven go get batches, serialized per module root.
local M = {}
local api = vim.api
local uv = vim.uv
local core = require("go-mod.core")
local config = require("go-mod.config")
local ui = require("go-mod.ui")
local log = require("go-mod.log")
local parser = require("go-mod.parser")
local batches = {}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.WARN)
end

local function unchanged(source)
	return api.nvim_buf_is_valid(source.bufnr)
		and api.nvim_buf_is_loaded(source.bufnr)
		and api.nvim_buf_get_name(source.bufnr) == source.name
		and not vim.bo[source.bufnr].modified
		and api.nvim_buf_get_changedtick(source.bufnr) == source.tick
		and uv.fs_realpath(source.name) == source.path
end

local function disk_contents(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content
end

local function saved_contents(bufnr)
	local separator = vim.bo[bufnr].fileformat == "dos" and "\r\n" or "\n"
	local content = table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), separator)
	if vim.bo[bufnr].endofline then
		content = content .. separator
	end
	return (vim.bo[bufnr].bomb and "\239\187\191" or "") .. content
end

-- Check both the file identity and bytes: changedtick cannot detect external writes.
local function snapshot_unchanged(source)
	local stat = uv.fs_stat(source.path)
	return unchanged(source)
		and stat
		and stat.dev == source.dev
		and stat.ino == source.ino
		and disk_contents(source.path) == source.content
		and saved_contents(source.bufnr) == source.content
end

local function capture(bufnr)
	bufnr = (not bufnr or bufnr == 0) and api.nvim_get_current_buf() or bufnr
	if not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr) then
		notify("Open a saved go.mod buffer and run a dependency check first.")
		return
	end
	local name = api.nvim_buf_get_name(bufnr)
	local path = uv.fs_realpath(name)
	if vim.fn.fnamemodify(name, ":t") ~= "go.mod" or not path then
		notify("Save this buffer as go.mod and run a dependency check first.")
		return
	end
	if vim.bo[bufnr].modified then
		notify("Save go.mod and run a dependency check before updating.")
		return
	end
	local root = vim.fn.fnamemodify(path, ":h")
	local tick = api.nvim_buf_get_changedtick(bufnr)
	local data = core.get_buffer_info(bufnr)
	if
		not data
		or not data.last_check
		or not data.modules
		or data.changedtick ~= tick
		or not data.root
		or uv.fs_realpath(data.root) ~= root
	then
		notify("Run a dependency check for this saved go.mod before updating.")
		return
	end
	local content, stat = disk_contents(path), uv.fs_stat(path)
	if not content or not stat or content ~= saved_contents(bufnr) then
		notify("go.mod changed on disk. Reload it and run a dependency check before updating.")
		return
	end
	return {
		bufnr = bufnr,
		name = name,
		path = path,
		root = root,
		tick = tick,
		content = content,
		dev = stat.dev,
		ino = stat.ino,
		modules = vim.deepcopy(data.modules),
	}
end

local function outdated(source)
	local names = {}
	for name, info in pairs(source.modules) do
		if info.status == "outdated" and type(info.latest) == "string" and info.latest ~= "" then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

-- Reload only the captured, unchanged buffer. Preserve views in all its windows.
local function synchronize(source)
	if not unchanged(source) then
		return false
	end
	local views = {}
	for _, win in ipairs(api.nvim_list_wins()) do
		if api.nvim_win_get_buf(win) == source.bufnr then
			api.nvim_win_call(win, function()
				views[win] = vim.fn.winsaveview()
			end)
		end
	end
	local ok = pcall(api.nvim_buf_call, source.bufnr, function()
		if not unchanged(source) then
			error("go.mod changed")
		end
		vim.cmd("silent noautocmd keepalt edit!")
	end)
	for win, view in pairs(views) do
		if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == source.bufnr then
			api.nvim_win_call(win, function()
				vim.fn.winrestview(view)
			end)
		end
	end
	return ok
		and api.nvim_buf_is_valid(source.bufnr)
		and api.nvim_buf_get_name(source.bufnr) == source.name
		and not vim.bo[source.bufnr].modified
end

local function start_batch(source, names)
	if not snapshot_unchanged(source) then
		notify("go.mod changed. Save it and run a dependency check before updating.")
		return
	end
	if batches[source.root] then
		notify("An update is already running for " .. source.root .. ". Wait for it to finish.")
		return
	end
	local queue, seen = {}, {}
	for _, name in ipairs(names) do
		local info = source.modules[name]
		if not info or info.status ~= "outdated" or type(info.latest) ~= "string" or info.latest == "" then
			notify("No checked update available for " .. tostring(name) .. ". Run a dependency check first.")
			return
		end
		if not seen[name] then
			seen[name] = true
			table.insert(queue, { name = name, latest = info.latest })
		end
	end
	if #queue == 0 then
		notify("No outdated modules found", vim.log.levels.INFO)
		return
	end
	batches[source.root] = source
	local started, finished = false, false
	local function finish(reason)
		if finished then
			return
		end
		finished = true
		local completed = 0
		if started then
			local content = disk_contents(source.path)
			local actual = content and uv.fs_realpath(source.name) == source.path and parser.parse(content)
			for _, item in ipairs(queue) do
				if actual and actual[item.name] and actual[item.name].current == item.latest then
					completed = completed + 1
				end
			end
			if not reason and completed ~= #queue then
				reason = "Final go.mod requirements differ from the selected versions. Inspect go.mod and check again."
			end
		end
		-- Keep the root locked through synchronization and the final notification.
		local synced = started and synchronize(source)
		if reason then
			notify(
				string.format("Verified %d/%d selected versions. %s", completed, #queue, reason),
				vim.log.levels.ERROR
			)
		else
			notify(string.format("Successfully updated %d modules", completed), vim.log.levels.INFO)
		end
		if started and not synced then
			notify(
				"go.mod changed during the update; your edits were preserved. Reload when ready, save, and run a dependency check."
			)
		end
		batches[source.root] = nil
		if synced then
			core.check_dependencies(source.bufnr)
		end
	end
	local function run(argv, callback)
		local settled = false
		local ok, err = pcall(
			vim.system,
			argv,
			{
				cwd = source.root,
				text = true,
				timeout = config.options.timeout or 30000,
			},
			vim.schedule_wrap(function(result)
				if settled or finished then
					return
				end
				settled = true
				if result.code ~= 0 or (result.signal and result.signal ~= 0) then
					local reason = result.code == 124 and "timed out" or ("exited with code " .. tostring(result.code))
					log.error("go " .. argv[2] .. " " .. reason .. "\n" .. (result.stderr or ""))
					local context = argv[2] == "get" and "Failed to update selected modules: " or ""
					finish(context .. "go " .. argv[2] .. " " .. reason .. ". See log for details.")
				else
					callback(result)
				end
			end)
		)
		if not ok then
			settled = true
			if argv[2] == "get" then
				started = false
			end
			log.error("Failed to start go " .. argv[2] .. ": " .. tostring(err))
			finish("Failed to start go " .. argv[2] .. ". See log for details.")
		end
	end
	-- Go resolves process GOFLAGS and persistent `go env -w GOFLAGS` itself.
	-- Query it asynchronously under the same lock before any mutating command.
	run({ "go", "env", "GOFLAGS" }, function(result)
		if (result.stdout or ""):find("-modfile", 1, true) then
			finish(
				"Effective GOFLAGS contains -modfile. Remove it from the environment or go env -w GOFLAGS, then retry."
			)
			return
		end
		if not snapshot_unchanged(source) then
			finish("go.mod changed before the update. Reload or save it and run a dependency check again.")
			return
		end
		local argv = { "go", "get" }
		for _, item in ipairs(queue) do
			argv[#argv + 1] = item.name .. "@" .. item.latest
		end
		core.invalidate_buffer(source.bufnr)
		notify(string.format("Updating %d modules...", #queue), vim.log.levels.INFO)
		started = true
		run(argv, function()
			finish()
		end)
	end)
end

function M.update_modules(module_names, bufnr)
	local source = capture(bufnr)
	if source then
		start_batch(source, module_names)
	end
end

function M.update_module(module_name, bufnr)
	M.update_modules({ module_name }, bufnr)
end

function M.update_all_modules(bufnr)
	local source = capture(bufnr)
	if not source then
		return
	end
	local names = outdated(source)
	if #names == 0 then
		notify("No outdated modules found", vim.log.levels.INFO)
		return
	end
	vim.ui.select(
		{ "Yes", "No" },
		{ prompt = string.format("Update all %d outdated modules?", #names) },
		function(choice)
			if choice == "Yes" then
				start_batch(source, names)
			end
		end
	)
end

function M.get_outdated_modules()
	local data = core.get_buffer_info(api.nvim_get_current_buf())
	return data and data.modules and outdated(data) or {}
end

function M.update_selection_window(bufnr)
	local source = capture(bufnr)
	if not source then
		return
	end
	local modules = {}
	for _, name in ipairs(outdated(source)) do
		local info = source.modules[name]
		table.insert(modules, { name = name, current = info.current, latest = info.latest })
	end
	if #modules == 0 then
		notify("No outdated modules found", vim.log.levels.INFO)
		return
	end
	ui.show_update_window(modules, function(names)
		start_batch(source, names)
	end)
end

return M
