# go-mod.nvim

Check Go module dependencies and update them from a `go.mod` buffer in Neovim.
Dependency status appears as virtual text, and a floating picker lets you choose
which outdated modules to update.

## Requirements

- Neovim **0.12 or newer**
- Go **1.16 or newer**, available as `go` in Neovim's `PATH`
- A Nerd Font for the default icons, or your own text icons

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "syz51/go-mod.nvim",
  ft = "gomod",
  opts = {},
}
```

With another plugin manager, install `syz51/go-mod.nvim` on your runtime path. The plugin initializes automatically on the first
`go.mod` file. Explicit setup is optional; use it to customize defaults:

```lua
require("go-mod").setup({
  check_interval = 30, -- minutes
})
```

A file already open when setup runs is also eligible for automatic checking.

## Usage

1. Open a `go.mod` file. With `auto_check = true`, the plugin checks its required
   module paths for available versions.
2. Run `:GoModCheck` to check manually. After editing, **save the file, then run
   `:GoModCheck`** before updating.
3. Run `:GoModUpdate` to open the picker, or `:GoModUpdate example.com/module`
   to update one outdated module. Command completion lists outdated module paths.
4. Review the resulting `go.mod` and `go.sum` changes and run your project's tests.

| Command | Action |
| --- | --- |
| `:GoModCheck` | Check the current `go.mod` buffer |
| `:GoModToggle` | Toggle dependency virtual text |
| `:GoModUpdate [module]` | Pick updates, or update the named outdated module |
| `:GoModLog` | Open the configured log file |
| `:GoModSetup` | Initialize with defaults; optional when using automatic loading |
| `:checkhealth go-mod` | Check prerequisites and configuration |

In the picker, move with normal Neovim motions and use:

| Key | Action |
| --- | --- |
| `Space`, `Enter` on a module row | Toggle that module |
| `a` | Toggle all selections |
| `u` | Update selected modules |
| `U` | Update all listed modules |
| `Tab`, `Shift-Tab` | Move between footer actions; press Enter to activate |
| `Esc`, `q`, `c` | Close the picker |

No global key mappings are installed. For example, add a buffer-local mapping
from your own `FileType` autocmd:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "gomod",
  callback = function(args)
    vim.keymap.set("n", "<leader>mc", "<cmd>GoModCheck<CR>", {
      buffer = args.buf,
      silent = true,
    })
  end,
})
```

Checks and updates run in the directory of the original `go.mod`, even if you
change buffers or Neovim's working directory. Updates reject unsaved buffers or
files changed since the check, including changes on disk. Selected versions are
passed together to one `go get` command so Go resolves their constraints as a
group. Conflicting selections fail; results are refreshed afterward.
Avoid concurrent external edits while Go is running. Edits made in the buffer
during an update are preserved and require a reload and a fresh check.
With a positive `check_interval`, loaded `go.mod` buffers receive periodic
refreshes even without leaving and re-entering the buffer.

## Configuration

All options are optional. Defaults:

```lua
require("go-mod").setup({
  icons = {
    outdated = "󰚰 ",
    up_to_date = "󰄬 ",
    unpublished = "󰚯 ",
    error = "󰅚 ",
  },
  virtual_text = {
    prefix = "●",
    spacing = 4,
  },
  highlights = {
    outdated = "DiagnosticWarn",
    up_to_date = "DiagnosticHint",
    unpublished = "DiagnosticInfo",
    error = "DiagnosticError",
  },
  auto_check = true,
  check_interval = 60, -- minutes; 0 disables timer and re-entry refreshes
  log_level = "info", -- trace, debug, info, warn, error
  log_file = vim.fn.stdpath("cache") .. "/go-mod.log", -- "" disables file logging
  max_concurrent_jobs = 4, -- concurrent version lookups
  timeout = 30000, -- milliseconds per Go process
})
```

`virtual_text.prefix` is displayed before each status and `spacing` controls its
separation from the source line. Set `auto_check = false` and
`check_interval = 0` for manual checking only.
An interval of `0` keeps the initial automatic check but disables periodic and
re-entry refreshes. `unpublished` means the current version compares newer than
the returned latest version; it does not establish that a version was never
published.

## Go behavior and limits

- Version checks query the original required module path upstream. They do not
  check a local replacement's contents or treat its version as the upstream
  version. Private or offline lookups can fail.
- Go handles updates and respects applicable `replace` directives. The plugin
  does not rewrite replacements or migrate imports and module paths across
  major-version boundaries such as `example.com/lib` to `example.com/lib/v2`.
- `go get` can change transitive dependencies and `go.sum`, and, depending on your
  Go version and project, Go or toolchain directives. Review its changes.
- Go uses the process and project environment, including `GOPROXY`, `GOPRIVATE`,
  credentials, workspace settings, and applicable Go configuration. The plugin
  does not configure private registry access for you.
- Updates reject an effective `GOFLAGS=-modfile=...` setting, including one
  saved with `go env -w`, because it redirects writes away from the open
  `go.mod`. Remove that setting before updating with this plugin.

See the [Go modules reference](https://go.dev/ref/mod) for Go's resolution and
versioning rules.

## Troubleshooting

Run `:checkhealth go-mod` and confirm `:echo executable('go')` returns `1`.
Use `:set filetype?` to check that the buffer is `gomod`. Save changes, then run
`:GoModCheck`. For lookup failures, run `go list -m -json module/path@latest`
in the directory containing that `go.mod`, using the same environment as
Neovim. Check `:GoModLog` for details; logging must have a nonempty `log_file`.
Use `log_level = "debug"` temporarily when investigating, and remove private
paths, module names, and credentials before sharing logs.

See `:help go-mod` for commands and Lua APIs. Development and local checks are
covered in [CONTRIBUTING.md](CONTRIBUTING.md).

Tagged versions are available on the [releases page](https://github.com/syz51/go-mod.nvim/releases).
To pin a release with lazy.nvim, add `tag = "v0.1.0"` to the installation spec.

## License

[MIT](LICENSE), copyright (c) 2025 Roy Sun.
