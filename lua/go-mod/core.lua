local M = {}
local api = vim.api
local config = require("go-mod.config")
local semver = require("go-mod.semver")
local parser = require("go-mod.parser")
local log = require("go-mod.log")
local ns = api.nvim_create_namespace("go_mod")
local buffers, queue = {}, {}
local active, pumping = 0, false
local pump, finish, cancel

local function resolve(bufnr)
	if not bufnr or bufnr == 0 then
		return api.nvim_get_current_buf()
	end
	return bufnr
end

local function valid(bufnr)
	if not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr) then
		return false
	end
	local ft = vim.bo[bufnr].filetype
	return (ft == "gomod" or ft == "go.mod") and vim.fs.basename(api.nvim_buf_get_name(bufnr)) == "go.mod"
end

local function clear(bufnr)
	if api.nvim_buf_is_valid(bufnr) then
		api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	end
end

local function current(request)
	local state = buffers[request.bufnr]
	return not request.cancelled
		and state == request.state
		and state.request == request
		and state.generation == request.generation
		and valid(request.bufnr)
		and api.nvim_buf_get_name(request.bufnr) == request.name
		and api.nvim_buf_get_changedtick(request.bufnr) == request.changedtick
end

local function render(bufnr, info)
	clear(bufnr)
	if not info.visible then
		return
	end
	local options = config.options
	for _, module in pairs(info.modules) do
		local text
		if module.status == "outdated" then
			text = module.current .. " → " .. module.latest
		elseif module.status == "up_to_date" then
			text = "Up to date"
		elseif module.status == "unpublished" then
			text = "Newer than latest"
		elseif module.status == "error" then
			text = "Error: " .. (module.error or "Unable to check version")
		end
		if text then
			local vt = options.virtual_text or {}
			text = string.rep(" ", vt.spacing or 4)
				.. (vt.prefix or "●")
				.. " "
				.. ((options.icons or {})[module.status] or "")
				.. text
			api.nvim_buf_set_extmark(bufnr, ns, module.line, 0, {
				virt_text = { { text, (options.highlights or {})[module.status] or "DiagnosticInfo" } },
				virt_text_pos = "eol",
				hl_mode = "combine",
			})
		end
	end
end

local function stop_job(task)
	if task.job then
		pcall(task.job.kill, task.job, 15)
	end
end

cancel = function(request)
	if not request or request.cancelled then
		return
	end
	request.cancelled = true
	if request.state.request == request then
		request.state.request = nil
	end
	for _, task in ipairs(request.tasks) do
		if not task.done then
			if task.started then
				-- Killing is asynchronous: retain the slot until the terminal callback.
				stop_job(task)
			else
				finish(task)
			end
		end
	end
end

finish = function(task, err)
	if task.done then
		return
	end
	task.done = true
	if task.started then
		active = active - 1
	end
	local request = task.request
	request.pending = request.pending - 1
	if err then
		task.info.status, task.info.error = "error", err
		log.error(task.name .. ": " .. err)
	end
	if request.pending == 0 and current(request) then
		local state = request.state
		state.info = {
			modules = request.modules,
			last_check = os.time(),
			visible = state.visible,
			changedtick = request.changedtick,
			root = request.root,
		}
		state.name = request.name
		state.request = nil
		render(request.bufnr, state.info)
	end
end

local function response(task, result)
	if task.done then
		return
	end
	if not current(task.request) then
		cancel(task.request)
		finish(task)
		pump()
		return
	end
	local ok, err = pcall(function()
		if result.code == 124 then
			error("go list timed out after " .. (config.options.timeout or 30000) .. " ms", 0)
		elseif result.code ~= 0 then
			error("go list failed (exit " .. tostring(result.code) .. "): " .. (result.stderr or ""), 0)
		end
		local decoded = vim.json.decode(result.stdout or "")
		if type(decoded) ~= "table" or type(decoded.Version) ~= "string" then
			error("go list returned no version", 0)
		end
		local latest, version_error = semver.parse(decoded.Version)
		if not latest then
			error(version_error, 0)
		end
		local comparison = semver.compare(task.version, latest)
		task.info.latest = decoded.Version
		task.info.status = comparison < 0 and "outdated" or (comparison > 0 and "unpublished" or "up_to_date")
	end)
	finish(task, not ok and tostring(err) or nil)
	pump()
end

local function start(task)
	local ok, err = pcall(function()
		task.job = vim.system(
			{ "go", "list", "-m", "-json", task.name .. "@latest" },
			{
				cwd = task.request.root,
				text = true,
				timeout = config.options.timeout or 30000,
			},
			vim.schedule_wrap(function(result)
				response(task, result)
			end)
		)
		if task.done or not current(task.request) then
			cancel(task.request)
			stop_job(task)
		end
	end)
	if not ok then
		finish(task, "Unable to start go list: " .. tostring(err))
		stop_job(task)
	end
end

pump = function()
	if pumping then
		return
	end
	pumping = true
	local limit = math.max(1, math.floor(config.options.max_concurrent_jobs or 4))
	while active < limit and #queue > 0 do
		local task = table.remove(queue, 1)
		if not task.done then
			if current(task.request) then
				task.started, active = true, active + 1
				start(task)
			else
				cancel(task.request)
			end
		end
	end
	pumping = false
end

function M.invalidate_buffer(bufnr)
	bufnr = resolve(bufnr)
	local state = buffers[bufnr]
	if state then
		state.generation = state.generation + 1
		cancel(state.request)
		state.info = nil
	end
	clear(bufnr)
	pump()
end

function M.check_dependencies(bufnr)
	bufnr = resolve(bufnr)
	if not valid(bufnr) then
		M.invalidate_buffer(bufnr)
		return
	end
	M.invalidate_buffer(bufnr)
	local state = buffers[bufnr] or { generation = 0, visible = true }
	buffers[bufnr] = state
	local name = api.nvim_buf_get_name(bufnr)
	local request = {
		bufnr = bufnr,
		state = state,
		generation = state.generation,
		name = name,
		root = vim.fs.dirname(name),
		changedtick = api.nvim_buf_get_changedtick(bufnr),
		modules = parser.parse(api.nvim_buf_get_lines(bufnr, 0, -1, false)),
		tasks = {},
		pending = 0,
	}
	state.request = request
	for module_name, info in pairs(request.modules) do
		local version, err = semver.parse(info.current)
		if not version then
			info.status, info.error = "error", err
			log.error(module_name .. ": " .. err)
		else
			local task = { request = request, name = module_name, info = info, version = version }
			request.tasks[#request.tasks + 1] = task
			request.pending = request.pending + 1
		end
	end
	if request.pending == 0 then
		-- Use the same completion path for empty or entirely invalid files.
		request.pending = 1
		finish({ request = request })
	else
		for _, task in ipairs(request.tasks) do
			queue[#queue + 1] = task
		end
		pump()
	end
end

function M.get_buffer_info(bufnr)
	bufnr = resolve(bufnr)
	local state = buffers[bufnr]
	if not state then
		return nil
	end
	if
		state.info
		and (
			not valid(bufnr)
			or state.name ~= api.nvim_buf_get_name(bufnr)
			or state.info.changedtick ~= api.nvim_buf_get_changedtick(bufnr)
		)
	then
		M.invalidate_buffer(bufnr)
	end
	return state.info
end

function M.check_periodic(bufnr)
	bufnr = resolve(bufnr)
	local interval = config.options.check_interval or 60
	if interval <= 0 or not valid(bufnr) then
		return
	end
	local info = M.get_buffer_info(bufnr)
	local state = buffers[bufnr]
	if not (state and state.request) and (not info or os.time() - info.last_check >= interval * 60) then
		M.check_dependencies(bufnr)
	end
end

function M.toggle(bufnr)
	bufnr = resolve(bufnr)
	if not valid(bufnr) then
		return
	end
	local state = buffers[bufnr] or { generation = 0, visible = false }
	buffers[bufnr] = state
	state.visible = not state.visible
	local info = M.get_buffer_info(bufnr)
	if info then
		info.visible = state.visible
	end
	if not state.visible then
		clear(bufnr)
	elseif info then
		render(bufnr, info)
	elseif not state.request then
		M.check_dependencies(bufnr)
	end
end

function M.cleanup_buffer(bufnr)
	bufnr = resolve(bufnr)
	local state = buffers[bufnr]
	if state then
		cancel(state.request)
	end
	buffers[bufnr] = nil
	clear(bufnr)
	pump()
end

function M.shutdown()
	-- Cancel every request before pumping so cleanup cannot start queued jobs.
	for _, state in pairs(buffers) do
		cancel(state.request)
	end
	for bufnr in pairs(buffers) do
		clear(bufnr)
	end
	buffers, queue = {}, {}
end

return M
