-- Luacheck config for a Neovim plugin + plenary/busted test suite.
std = "lua51"
cache = true
codes = true

-- Neovim injects `vim` globally. The base table is read-only; the option/
-- variable/env namespaces the plugin legitimately assigns through are
-- declared writable so W122 only fires on genuinely suspicious writes
-- (e.g. clobbering vim.api or a typo'd namespace).
read_globals = { "vim" }
globals = {
  "vim.g",
  "vim.b",
  "vim.w",
  "vim.o",
  "vim.bo",
  "vim.wo",
  "vim.opt",
  "vim.env",
}

-- plenary's busted port exposes these in spec files; specs also stub the
-- vim.ui prompts and vim.notify, so those fields are writable there only.
files["tests/"] = {
  read_globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "setup",
    "teardown",
    "pending",
    "assert",
  },
  globals = {
    "vim.g",
    "vim.b",
    "vim.w",
    "vim.o",
    "vim.bo",
    "vim.wo",
    "vim.opt",
    "vim.env",
    "vim.ui",
    "vim.notify",
  },
}

exclude_files = {
  ".deps/",
  "doc/",
}

-- Line length is enforced by stylua (column_width), not luacheck.
max_line_length = false
