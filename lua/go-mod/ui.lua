-- UI functionality for go-mod.nvim
local M = {}

-- Import required modules
local api = vim.api

-- Show a window with outdated modules for selection and updating
function M.show_update_window(outdated_modules, update_callback)
	-- Create a new floating window
	local width = 80
	local height = #outdated_modules + 4 -- modules + header + footer + buttons

	-- Calculate position
	local win_height = vim.o.lines
	local win_width = vim.o.columns
	local row = math.floor((win_height - height) / 2)
	local col = math.floor((win_width - width) / 2)

	-- Create buffer for floating window
	local float_bufnr = api.nvim_create_buf(false, true)
	vim.bo[float_bufnr].bufhidden = "wipe"

	-- Window options
	local opts = {
		style = "minimal",
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = "rounded",
	}

	-- Create window
	local win_id = api.nvim_open_win(float_bufnr, true, opts)

	-- Set window options
	vim.wo[win_id].winblend = 10
	vim.wo[win_id].cursorline = true

	-- Prepare buffer content
	local lines = {
		"Go Module Updates",
		string.rep("─", width - 2),
	}

	-- Track selected modules
	local selected = {}
	for i, module in ipairs(outdated_modules) do
		selected[i] = false
		local line = string.format("[ ] %s (%s → %s)", module.name, module.current, module.latest)
		table.insert(lines, line)
	end

	-- Add footer
	table.insert(lines, string.rep("─", width - 2))
	table.insert(lines, "[Update Selected] [Update All] [Cancel]")

	-- Set buffer content
	api.nvim_buf_set_lines(float_bufnr, 0, -1, false, lines)

	-- Set buffer as non-modifiable
	vim.bo[float_bufnr].modifiable = false

	-- Add syntax highlighting
	vim.bo[float_bufnr].filetype = "go-mod-updates"
	vim.cmd([[
        syntax match GoModUpdateTitle /^Go Module Updates$/
        syntax match GoModUpdateSeparator /^─\+$/
        syntax match GoModUpdateCheckbox /\[ \]/
        syntax match GoModUpdateSelectedCheckbox /\[x\]/
        syntax match GoModUpdateModule /\(\[ \]\\|\[x\]\) \zs.\+\ze (\S\+ → \S\+)/
        syntax match GoModUpdateVersion /(\S\+ → \S\+)/
        syntax match GoModUpdateButton /\[\w\+ \?\w*\]/
        
        highlight default link GoModUpdateTitle Title
        highlight default link GoModUpdateSeparator Comment
        highlight default link GoModUpdateCheckbox Question
        highlight default link GoModUpdateSelectedCheckbox String
        highlight default link GoModUpdateModule Normal
        highlight default link GoModUpdateVersion Special
        highlight default link GoModUpdateButton Statement
    ]])

	-- Helper function to toggle selection
	local function toggle_selection(idx)
		if idx < 3 or idx >= #lines - 1 then
			return
		end

		local mod_idx = idx - 2
		selected[mod_idx] = not selected[mod_idx]

		vim.bo[float_bufnr].modifiable = true
		local line = api.nvim_buf_get_lines(float_bufnr, idx, idx + 1, false)[1]
		local new_line
		if selected[mod_idx] then
			new_line = line:gsub("%[ %]", "[x]", 1)
		else
			new_line = line:gsub("%[x%]", "[ ]", 1)
		end
		api.nvim_buf_set_lines(float_bufnr, idx, idx + 1, false, { new_line })
		vim.bo[float_bufnr].modifiable = false
	end

	-- Helper function to update selected modules
	local function update_selected()
		local to_update = {}
		for i, is_selected in ipairs(selected) do
			if is_selected then
				table.insert(to_update, outdated_modules[i].name)
			end
		end

		if #to_update == 0 then
			vim.notify("No modules selected for update", vim.log.levels.WARN)
			return
		end

		-- Close the window
		api.nvim_win_close(win_id, true)

		-- Update each selected module
		for _, module_name in ipairs(to_update) do
			update_callback(module_name)
		end
	end

	-- Helper function to update all modules
	local function update_all()
		-- Close the window
		api.nvim_win_close(win_id, true)

		-- Update all outdated modules one by one
		for _, module in ipairs(outdated_modules) do
			update_callback(module.name)
		end
	end

	-- Set up key mappings
	local function set_mappings()
		local mappings = {
			["<CR>"] = function()
				local cur_line = api.nvim_win_get_cursor(win_id)[1]
				if cur_line >= 3 and cur_line < #lines - 1 then
					toggle_selection(cur_line - 1)
				elseif cur_line == #lines then
					-- Check which button was clicked
					col = api.nvim_win_get_cursor(win_id)[2]
					if col < 17 then -- [Update Selected]
						update_selected()
					elseif col < 31 then -- [Update All]
						update_all()
					else -- [Cancel]
						api.nvim_win_close(win_id, true)
					end
				end
			end,
			["<Esc>"] = function()
				api.nvim_win_close(win_id, true)
			end,
			["q"] = function()
				api.nvim_win_close(win_id, true)
			end,
			["<Space>"] = function()
				local cur_line = api.nvim_win_get_cursor(win_id)[1]
				if cur_line >= 3 and cur_line < #lines - 1 then
					toggle_selection(cur_line - 1)
				end
			end,
			["a"] = function()
				-- Toggle all
				local all_selected = true
				for _, is_selected in ipairs(selected) do
					if not is_selected then
						all_selected = false
						break
					end
				end

				-- Toggle based on current state
				for i = 1, #outdated_modules do
					selected[i] = not all_selected

					vim.bo[float_bufnr].modifiable = true
					local line = api.nvim_buf_get_lines(float_bufnr, i + 2, i + 3, false)[1]
					local new_line
					if selected[i] then
						new_line = line:gsub("%[ %]", "[x]", 1)
					else
						new_line = line:gsub("%[x%]", "[ ]", 1)
					end
					api.nvim_buf_set_lines(float_bufnr, i + 2, i + 3, false, { new_line })
					vim.bo[float_bufnr].modifiable = false
				end
			end,
			["u"] = update_selected,
			["U"] = update_all,
			["c"] = function()
				api.nvim_win_close(win_id, true)
			end,
		}

		for k, v in pairs(mappings) do
			api.nvim_buf_set_keymap(float_bufnr, "n", k, "", {
				noremap = true,
				silent = true,
				callback = v,
			})
		end
	end

	-- Set mappings
	set_mappings()

	-- Set cursor at first line with a module
	api.nvim_win_set_cursor(win_id, { 3, 0 })
end

-- Return the module
return M
