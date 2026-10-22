-- Keyboard-accessible, scrollable module update picker.
local M = {}
local api = vim.api

-- The callback receives one list; the updater owns serialization.
function M.show_update_window(modules, update_callback)
	if #modules == 0 then
		return
	end
	local origin = api.nvim_get_current_win()
	local width = math.max(1, math.min(80, vim.o.columns - 4))
	local height = 1
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	local win = api.nvim_open_win(buf, true, {
		style = "minimal",
		relative = "editor",
		width = width,
		height = height,
		row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
		col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
		border = "rounded",
	})
	vim.wo[win].winblend = 10
	vim.wo[win].cursorline = true
	vim.wo[win].wrap = true
	local selected = {}
	local selected_row = #modules + 4
	local all_row = selected_row + 1
	local cancel_row = all_row + 1
	local function render()
		local lines = { "Go Module Updates", string.rep("─", width) }
		for i, module in ipairs(modules) do
			table.insert(
				lines,
				string.format(
					"[%s] %s (%s → %s)",
					selected[i] and "x" or " ",
					module.name,
					module.current,
					module.latest
				)
			)
		end
		table.insert(lines, string.rep("─", width))
		table.insert(lines, "[Update Selected] (u)")
		table.insert(lines, "[Update All] (U)")
		table.insert(lines, "[Cancel] (q/Esc)")
		vim.bo[buf].modifiable = true
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
	end
	local function layout()
		if not api.nvim_win_is_valid(win) then
			return
		end
		width = math.max(1, math.min(80, vim.o.columns - 4))
		api.nvim_win_set_config(win, { width = width })
		render()
		-- Measure screen rows at the final width, including wrapped paths and versions.
		height = math.max(1, math.min(api.nvim_win_text_height(win, {}).all, vim.o.lines - 4))
		api.nvim_win_set_config(win, {
			relative = "editor",
			height = height,
			row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
			col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
		})
	end
	local function close()
		if api.nvim_win_is_valid(win) then
			api.nvim_win_close(win, true)
		end
		if api.nvim_win_is_valid(origin) then
			api.nvim_set_current_win(origin)
		end
	end
	local function submit(all)
		local names = {}
		for i, module in ipairs(modules) do
			if all or selected[i] then
				table.insert(names, module.name)
			end
		end
		if #names == 0 then
			vim.notify("No modules selected for update. Use Space to select a module.", vim.log.levels.WARN)
			return
		end
		close()
		update_callback(names)
	end
	local function toggle()
		local index = api.nvim_win_get_cursor(win)[1] - 2
		if index >= 1 and index <= #modules then
			selected[index] = not selected[index]
			render()
		end
	end
	local function tab(direction)
		local row = api.nvim_win_get_cursor(win)[1]
		local actions = { selected_row, all_row, cancel_row }
		local target = direction == 1 and selected_row or cancel_row
		for i, action in ipairs(actions) do
			if row == action then
				target = actions[(i - 1 + direction) % #actions + 1]
				break
			end
		end
		api.nvim_win_set_cursor(win, { target, 0 })
	end
	local mappings = {
		["<Space>"] = toggle,
		["<CR>"] = function()
			local row = api.nvim_win_get_cursor(win)[1]
			if row == selected_row then
				submit(false)
			elseif row == all_row then
				submit(true)
			elseif row == cancel_row then
				close()
			else
				toggle()
			end
		end,
		["a"] = function()
			local all = true
			for i = 1, #modules do
				if not selected[i] then
					all = false
					break
				end
			end
			for i = 1, #modules do
				selected[i] = not all
			end
			render()
		end,
		["u"] = function()
			submit(false)
		end,
		["U"] = function()
			submit(true)
		end,
		["<Tab>"] = function()
			tab(1)
		end,
		["<S-Tab>"] = function()
			tab(-1)
		end,
		["q"] = close,
		["c"] = close,
		["<Esc>"] = close,
	}
	for key, callback in pairs(mappings) do
		api.nvim_buf_set_keymap(buf, "n", key, "", { noremap = true, silent = true, callback = callback })
	end
	layout()
	local resize = api.nvim_create_autocmd("VimResized", { callback = layout })
	api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			api.nvim_del_autocmd(resize)
		end,
	})
	vim.bo[buf].filetype = "go-mod-updates"
	api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)
	api.nvim_win_set_cursor(win, { 3, 0 })
end

return M
