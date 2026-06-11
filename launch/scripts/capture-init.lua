-- Clean Neovim config for recording launch assets. Loads ONLY beads.nvim +
-- its runtime deps (telescope, plenary) and optionally dressing.nvim for tidy
-- vim.ui.select/input floats. Mirrors tests/minimal_init.lua's rtp wiring.
--
-- Launch (cwd must be the seeded demo dir so the plugin finds its .beads):
--   nvim -u launch/scripts/capture-init.lua
-- Env: PLENARY_DIR, TELESCOPE_DIR, DRESSING_DIR override the default lazy paths.

local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>:p"), ":h:h:h") -- launch/scripts -> repo root
vim.opt.rtp:prepend(root)

local function add(dir)
  if dir ~= "" and vim.fn.isdirectory(dir) == 1 then
    vim.opt.rtp:prepend(dir)
    return true
  end
  return false
end

add(os.getenv("PLENARY_DIR") or vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"))
add(os.getenv("TELESCOPE_DIR") or vim.fn.expand("~/.local/share/nvim/lazy/telescope.nvim"))
local has_dressing =
  add(os.getenv("DRESSING_DIR") or vim.fn.expand("~/.local/share/nvim/lazy/dressing.nvim"))

vim.cmd("runtime! plugin/plenary.vim")

-- Minimal, legible chrome so the floats are the whole story on camera.
vim.opt.termguicolors = true
vim.opt.laststatus = 0 -- no status line
vim.opt.ruler = false
vim.opt.showmode = false
vim.opt.number = false
vim.opt.signcolumn = "no"
vim.opt.cmdheight = 1
vim.opt.fillchars = { eob = " " } -- hide ~ on empty lines
vim.opt.guicursor = "n-v-c:block-blinkon0" -- steady cursor, no blink jitter in the cast
pcall(vim.cmd.colorscheme, "habamax") -- ships with nvim, good contrast on dark

if has_dressing then
  require("dressing").setup({
    input = { border = "rounded", relative = "editor" },
    select = { backend = { "builtin" }, builtin = { border = "rounded" } },
  })
end

-- Slightly fuller floats than the defaults so they fill the recording frame.
require("beads").setup({
  keymaps = true,
  float = {
    view = { width = 0.9, height = 0.9 },
    palette = { width = 0.8 },
    graph = { width = 0.85 },
  },
})
pcall(function()
  require("telescope").load_extension("beads")
end)

-- A blank scratch buffer behind the floats (no file name / path on screen).
vim.opt.buftype = "nofile"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
