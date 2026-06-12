-- Minimal init for headless plenary test runs:
--   nvim --headless --noplugin -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>:p"), ":h:h")
vim.opt.rtp:prepend(root)

local plenary = os.getenv("PLENARY_DIR") or vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
vim.opt.rtp:prepend(plenary)

-- telescope is a runtime dep of the picker; wire it when present so picker
-- specs (and CI) can load it. TELESCOPE_DIR is set by the CI checkout.
local telescope = os.getenv("TELESCOPE_DIR")
  or vim.fn.expand("~/.local/share/nvim/lazy/telescope.nvim")
if vim.fn.isdirectory(telescope) == 1 then
  vim.opt.rtp:prepend(telescope)
end

vim.cmd("runtime! plugin/plenary.vim")
