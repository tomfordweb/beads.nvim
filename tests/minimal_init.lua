-- Minimal init for headless plenary test runs:
--   nvim --headless --noplugin -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>:p"), ":h:h")
vim.opt.rtp:prepend(root)

local plenary = os.getenv("PLENARY_DIR")
  or vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
vim.opt.rtp:prepend(plenary)
vim.cmd("runtime! plugin/plenary.vim")
