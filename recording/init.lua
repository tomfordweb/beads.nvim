-- Clean Neovim config for recording the README demo GIF inside the VHS
-- container (E9). Loads ONLY beads.nvim + its runtime deps and sets minimal
-- chrome so the floats are the whole story on camera. Container paths are
-- fixed by recording/Dockerfile (/deps/*) and record.sh (/work = repo).
--
--   nvim -u /work/recording/init.lua        (cwd = the seeded demo dir)
--
-- Mirrors tests/minimal_init.lua's rtp wiring; deliberately separate from the
-- gitignored notes/scripts/capture-init.lua (that drives the interactive
-- tmux+asciinema harness — this one is the committed, headless path).

vim.opt.rtp:prepend("/work")
vim.opt.rtp:prepend("/deps/plenary.nvim")
vim.opt.rtp:prepend("/deps/telescope.nvim")
vim.cmd("runtime! plugin/plenary.vim")

-- Minimal, legible chrome so the floats fill the frame.
vim.opt.termguicolors = true
vim.opt.laststatus = 0
vim.opt.ruler = false
vim.opt.showmode = false
vim.opt.number = false
vim.opt.signcolumn = "no"
vim.opt.cmdheight = 1
vim.opt.fillchars = { eob = " " }
vim.opt.guicursor = "n-v-c:block-blinkon0"
pcall(vim.cmd.colorscheme, "habamax")

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

-- Blank scratch buffer behind the floats — no file name / path on screen.
vim.opt.buftype = "nofile"
