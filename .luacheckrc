-- Luacheck config for a Neovim plugin + plenary/busted test suite.
std = "lua51"
cache = true
codes = true

-- Neovim injects `vim` globally.
read_globals = { "vim" }

-- plenary's busted port exposes these in spec files.
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
}

exclude_files = {
  ".deps/",
  "doc/",
}

-- Line length is enforced by stylua (column_width), not luacheck.
max_line_length = false
