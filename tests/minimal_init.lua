-- Load repository code without user configuration or external dependencies.
assert(vim.fn.has("nvim-0.12") == 1, "Neovim >=0.12 is required")
local root = assert(vim.env.GO_MOD_TEST_ROOT, "GO_MOD_TEST_ROOT is required")
vim.opt.runtimepath:prepend(root)
vim.o.shadafile = "NONE"
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
