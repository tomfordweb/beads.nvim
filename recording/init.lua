-- Clean Neovim config for recording the README demo GIF inside the VHS
-- container (E9). Loads ONLY beads.nvim + its runtime deps and sets minimal
-- chrome so the floats are the whole story on camera. Container paths are
-- fixed by recording/Dockerfile (/deps/*) and record.sh (/work = repo).
--
--   nvim -u /work/recording/init.lua        (cwd = the seeded demo dir)
--
-- Mirrors tests/minimal_init.lua's rtp wiring; deliberately separate from the
-- gitignored docs-internal/notes/scripts/capture-init.lua (that drives the interactive
-- tmux+asciinema harness — this one is the committed, headless path).

vim.opt.rtp:prepend("/work")
vim.opt.rtp:prepend("/deps/plenary.nvim")
vim.opt.rtp:prepend("/deps/telescope.nvim")
vim.opt.rtp:prepend("/deps/dressing.nvim")
vim.opt.rtp:prepend("/deps/nvim-notify")
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

-- Optional UI enhancers, recorded so the README GIFs show the recommended
-- experience. Documented as optional in the README; never runtime deps.
--   dressing.nvim  — bordered modal vim.ui.select / vim.ui.input
--   nvim-notify    — toast notifications for vim.notify
--   nvim-treesitter — markdown highlighting in the detail / edit buffers
pcall(function()
  require("dressing").setup({
    input = { border = "rounded" },
    select = { backend = { "telescope", "builtin" }, builtin = { border = "rounded" } },
  })
end)
pcall(function()
  local notify = require("notify")
  notify.setup({
    background_colour = "#000000",
    stages = "fade_in_slide_out",
    timeout = 2500,
    render = "default",
  })
  vim.notify = notify
end)
pcall(function()
  require("nvim-treesitter.configs").setup({
    highlight = { enable = true },
  })
end)

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
