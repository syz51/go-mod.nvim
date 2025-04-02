# go-mod.nvim

A Neovim plugin that checks Go module dependencies in go.mod files for updates,
similar to package-info.nvim for JavaScript/TypeScript.

![Go Mod Demo](https://github.com/username/go-mod.nvim/assets/demo.gif)

## Features

- ✅ Shows which dependencies are out of date with visual indicators
- 🔄 Provides latest available versions for each dependency
- 🔍 Semantic version comparison to accurately identify outdated packages
- 🔄 Automatic checking when opening go.mod files
- ⏱️ Configurable periodic checking
- 📝 Comprehensive logging system
- 🎨 Fully customizable appearance

## Screenshots

### Outdated Dependencies

![Outdated Dependencies](https://github.com/username/go-mod.nvim/assets/outdated.png)

### Up-to-date Dependencies

![Up-to-date Dependencies](https://github.com/username/go-mod.nvim/assets/uptodate.png)

## Requirements

- Neovim >= 0.7.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Go installed and in your PATH

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "username/go-mod.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  ft = "gomod",
  opts = {
    -- your configuration here (see Configuration section)
  },
}
```

### Using vim-plug

## How It Works

1. The plugin parses your go.mod file to extract all dependencies and their
   current versions.
2. It uses `go list -m -json module@latest` to check for the latest available
   version of each dependency.
3. It compares the current version with the latest version using semantic
   versioning rules.
4. It displays the status of each dependency using virtual text at the end of
   each line.

## Troubleshooting

### Common Issues

#### Plugin Not Working

- Make sure Go is installed and in your PATH
- Check the log file with `:GoModLog` for any errors
- Try running with `log_level = "debug"` for more detailed logs

#### Dependencies Not Showing as Outdated

- Make sure you have internet connectivity
- Check if the Go modules proxy is accessible
- Try manually running `go list -m -json module@latest` to see if it works

#### Visual Indicators Not Showing

- Make sure your terminal supports the icons or customize them
- Check if the highlight groups are defined in your colorscheme
