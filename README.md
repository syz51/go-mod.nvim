# go-mod.nvim

A Neovim plugin for checking and updating Go module dependencies directly in your editor.

## Features

- Shows dependency status with virtual text in go.mod files
- Highlights outdated, up-to-date, and unpublished dependencies
- Allows updating dependencies to their latest versions
- Provides a UI for selecting which dependencies to update
- Automatic checking on file open and periodic rechecking

## Screenshots

Screenshots to be added

## Requirements

- Neovim 0.7+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Go 1.16+ installed and in your PATH
- Nerd font for symbols

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'syz51/go-mod.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = true,
  ft = 'gomod', -- Optional: only load for go.mod files
}
```

## Configuration

The plugin comes with sensible defaults, but you can customize it by passing options to the `setup` function:

```lua
require('go-mod').setup({
  -- Icons for the signs
  icons = {
    outdated = "󰚰 ",
    up_to_date = "󰄬 ",
    unpublished = "󰚯 ",
    error = "󰅚 ",
  },

  -- Highlight groups
  highlights = {
    outdated = "DiagnosticWarn",
    up_to_date = "DiagnosticOk",
    unpublished = "DiagnosticInfo",
    error = "DiagnosticError",
  },

  -- Auto check on file open
  auto_check = true,

  -- Check interval in minutes (0 to disable)
  check_interval = 60,

  -- Log level: "trace", "debug", "info", "warn", "error"
  log_level = "info",

  -- Log file path (empty for no file logging)
  log_file = vim.fn.stdpath("cache") .. "/go-mod.log",
})
```

## Usage

### Commands

- `:GoModCheck` - Check dependencies in the current buffer
- `:GoModToggle` - Toggle visibility of the dependency information
- `:GoModLog` - Open the log file
- `:GoModUpdate` - Open a UI to select and update modules
- `:GoModUpdate module-name` - Update a specific module

### Key Mappings

The plugin doesn't set any key mappings by default. Here are some suggestions:

```lua
-- Add to your init.lua or config
vim.api.nvim_create_autocmd("FileType", {
  pattern = {"gomod", "go.mod"},
  callback = function()
    local opts = { noremap = true, silent = true, buffer = true }
    vim.keymap.set('n', '<leader>mc', '<cmd>GoModCheck<CR>', opts)
    vim.keymap.set('n', '<leader>mt', '<cmd>GoModToggle<CR>', opts)
    vim.keymap.set('n', '<leader>mu', '<cmd>GoModUpdate<CR>', opts)
  end
})
```

### Update Window Controls

In the update selection window:

- `Space` or `Enter` - Toggle selection of a module
- `a` - Toggle selection of all modules
- `u` - Update selected modules
- `U` - Update all modules
- `Esc`, `q`, or `c` - Cancel and close the window

## License

MIT

## Credits

- [syz51](https://github.com/syz51)
