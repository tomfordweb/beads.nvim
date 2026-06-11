# beads.nvim

Neovim UI for [beads](https://github.com/steveyegge/beads) (`bd`) — the issue
tracker with first-class dependency support. Browse and filter issues in
Telescope, view and edit them in a floating detail view, and navigate
dependency chains without leaving the editor.

Tested against bd 1.0.4. This project tracks its own issues with bd.

## Features

- **Issue browser** — Telescope picker over `bd list` with live filter
  cycling (status / priority / type / include-closed) and a rendered issue
  preview. No subprocess per keystroke: one fetch, client-side filtering.
- **Ready view** — `bd ready` (open issues with no active blockers).
- **Detail view** — floating window with full fields and dependencies.
  Change status/priority, close/reopen, and jump through dependency ids
  (`gd` / `<CR>`) with `<BS>` history.
- **Description editing** — `e` opens the description in a markdown buffer;
  `:w` persists via `bd update --body-file -`.
- **Create** — `:BeadsCreate` interactive form (title/type/priority/deps) or
  `:BeadsQuick` quick capture wrapping `bd q`.
- **Command palette** — `:BeadsPalette` runs repo-level commands
  (`status`, `ready`, `stale`, `lint`, `dep cycles`, `init`, …) with output
  in a float.
- **Help bar** — every pane shows its keybinds: floats render them in the
  window footer, the picker in its prompt title.

## Requirements

- Neovim ≥ 0.10 (`vim.system`)
- [bd](https://github.com/steveyegge/beads) on `$PATH`
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
  (+ plenary)

## Installation (lazy.nvim)

```lua
{
  "tomfordweb/beads.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("beads").setup({ keymaps = true })
    require("telescope").load_extension("beads")
  end,
}
```

## Configuration

```lua
require("beads").setup({
  bd_bin = "bd",            -- path to the bd binary
  cwd = nil,                -- nil: walk up from current buffer for .beads/
  list_limit = 200,         -- bd list -n
  default_filters = { status = nil, priority = nil, type = nil, all = false },
  picker = { theme = "ivy" },
  keymaps = true,           -- false (default), true, or a table of overrides
  palette = { extra = {} }, -- extra palette entries { label=..., args={...} }
})
```

Default keymaps (when `keymaps = true`):

| Map | Action |
|-----|--------|
| `<leader>bdl` | browse issues |
| `<leader>bdr` | ready work |
| `<leader>bdc` | create issue |
| `<leader>bdq` | quick capture |
| `<leader>bdp` | command palette |

## Usage

Commands: `:Beads`, `:BeadsReady`, `:BeadsShow <id>`, `:BeadsCreate`,
`:BeadsQuick [title]`, `:BeadsPalette`. Also `:Telescope beads beads` /
`:Telescope beads ready`.

### Picker mappings

| Key | Action |
|-----|--------|
| `<CR>` | open detail view |
| `<C-s>` | cycle status filter |
| `<C-y>` | cycle priority filter |
| `<C-t>` | cycle type filter |
| `<C-a>` | toggle closed issues |
| `<C-r>` | refetch from bd |

### Detail view mappings

| Key | Action |
|-----|--------|
| `e` | edit description (`:w` saves) |
| `s` / `p` | set status / priority |
| `c` / `o` | close / reopen |
| `gd` or `<CR>` | jump to dependency under cursor |
| `<BS>` | back through jump history |
| `R` | refresh |
| `q` / `<Esc>` | close |

## Tests

```sh
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

Unit suites run without bd; the integration suite exercises a real bd binary
against a throwaway database in a tmpdir and is skipped when bd is absent.
Set `PLENARY_DIR` if plenary.nvim is not at the default lazy.nvim path.

## License

MIT
