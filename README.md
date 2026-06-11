# beads.nvim

Neovim UI for [beads](https://github.com/gastownhall/beads) (`bd`) — the issue
tracker with first-class dependency support. Browse and filter issues in
Telescope, view and edit them in a floating detail view, and navigate
dependency chains without leaving the editor.

Tested against bd 1.0.4. This project tracks its own issues with beads.

## Features

- **Issue browser** — Telescope picker over `bd list` with live filter
  cycling (status / priority / type / label / include-closed) and a rendered
  issue preview. No subprocess per keystroke: one fetch, client-side
  filtering. `<C-f>` defers/undefers the selected issue.
- **Ready view** — `bd ready` (open issues with no active blockers).
- **Detail view** — floating window with full fields and dependencies.
  Change status/priority, assign (`A`), labels (`L`), defer/undefer (`f`),
  close/reopen, and jump through dependency ids (`gd` / `<CR>`) with `<BS>`
  history.
- **Labels** — `L` in the detail view adds or removes labels (pick an
  existing one or type a new); `<C-l>` filters the browser by label.
- **Epic children** — epics render a `Children` section in the detail body
  (completion count, every child id jumpable); `:BeadsPalette` → `epic
  status` shows completion per epic.
- **Change history** — `H` in the detail view shows the issue's tracked-field
  transitions (status/priority/assignee/title/type/description) in a float.
- **Links sidebar** — companion pane beside the detail view: overview
  (status/priority/assignee/labels/dates) plus parent, children, depends-on
  and blocks sections, every id jumpable. `<Tab>` switches panes, `gs`
  toggles it.
- **Description editing** — `e` opens the description in a markdown buffer;
  `:w` persists via `bd update --body-file -`.
- **Create** — `:BeadsCreate` interactive form (title/type/priority/deps) or
  `:BeadsQuick` quick capture wrapping `bd q`.
- **Command palette** — `:BeadsPalette` runs repo-level commands
  (`status`, `epic status`, `ready`, `blocked`, `stale`, `lint`, `preflight`,
  `doctor`, `find-duplicates`, `orphans`, `dep cycles`, `diff`, `init`, …)
  with output in a float.
- **Help bar** — every pane shows its keybinds: floats render them in the
  window footer, the picker in its prompt title.
- **Resize-aware floats** — view/edit/palette floats re-center when the
  terminal size changes (tmux pane resize or zoom).
- **Link styling** — jumpable dependency ids render underlined
  (`BeadsLink`, default-linked to `Underlined`).
- **Comments** — issue comments render in the detail view; `a` adds one
  (`bd comment --stdin`).
- **Dependency graph** — `D` in the detail view (or `:BeadsGraph [id]`)
  shows `bd graph --compact` in a float; ids are links, `gd` opens them.
- **Live search** — `:BeadsSearch` re-queries `bd search` per keystroke,
  covering description text the cached picker can't; `<C-a>` includes
  closed issues.
- **Memories** — `:BeadsMemories` browses the bd memory store; `<CR>` edits
  in a float (`:w` → `bd remember`), `<C-n>` creates, `<C-d>` forgets.

## Requirements

- Neovim ≥ 0.10 (`vim.system`)
- [beads](https://github.com/gastownhall/beads) (`bd`) on `$PATH`
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

All keys optional; shown with defaults. Tables deep-merge, so override only
what you need.

```lua
require("beads").setup({
  bd_bin = "bd",            -- path to the bd binary
  cwd = nil,                -- nil: walk up from current buffer for .beads/
  list_limit = 200,         -- bd list -n
  default_filters = { status = nil, priority = nil, type = nil, all = false },

  picker = {
    theme = "ivy",          -- "ivy" | "dropdown" | "cursor" | false (your telescope defaults)
    theme_opts = {},        -- passed to the theme builder (e.g. { layout_config = { height = 0.4 } })
    telescope = {},         -- raw telescope picker opts, merged last
  },

  keymaps = true,           -- false (default), true, or { base, menus } — global leader maps

  -- in-pane mappings, keyed action -> key. A value may be a string, a list
  -- of equivalent keys, or false to disable. Partial overrides merge; an
  -- overridden value replaces the default wholesale.
  mappings = {
    picker   = { open = "<CR>", status = "<C-s>", priority = "<C-y>", type = "<C-t>", label = "<C-l>",
                 defer = "<C-f>", closed = "<C-a>", refetch = "<C-r>" },
    view     = { edit = "e", status = "s", priority = "p", comment = "a", labels = "L", assign = "A",
                 defer = "f", close = "c", reopen = "o", graph = "D", history = "H",
                 jump = { "gd", "<CR>" }, back = "<BS>", refresh = "R", quit = { "q", "<Esc>" },
                 sidebar = "<Tab>", sidebar_toggle = "gs" },
    sidebar  = { jump = { "gd", "<CR>" }, focus_view = "<Tab>", back = "<BS>", quit = { "q", "<Esc>" } },
    memories = { edit = "<CR>", new = "<C-n>", forget = "<C-d>", refetch = "<C-r>" },
    graph    = { jump = { "gd", "<CR>" }, quit = { "q", "<Esc>" } },
  },

  icons = {
    status = { open = "○", in_progress = "◐", blocked = "⊘", deferred = "❄", closed = "●" },
    deps_down = "↓",        -- "blocks N" column arrow
    deps_up = "↑",          -- "blocked by N" column arrow
  },

  float = {
    border = "rounded",     -- any nvim_open_win border
    view = { width = 96 },  -- heights are content-sized
    edit = { width = 90, height = 20 },  -- also the memory edit float
    palette = { width = 100 },
    graph = { width = 110 },
  },

  -- linked-issues sidebar next to the detail view
  sidebar = {
    enabled = true,         -- false: hidden until summoned with gs / <Tab>
    width = 34,
    position = "right",     -- "left"
    -- section order; remove entries to hide them
    sections = { "overview", "parent", "children", "depends_on", "blocks" },
  },

  helpbar = true,           -- false: no keybind footers / prompt-title help
  notify = true,            -- false: silence success messages (errors always shown)
  palette = { extra = {} }, -- extra palette entries { label=..., args={...} }
})
```

#### Customizing the sidebar

- `sidebar.enabled = false` makes it on-demand: `gs` (or `<Tab>`) in the
  detail view summons it; the visibility choice then sticks while you jump
  around, until the view closes.
- Reorder or drop `sections` — e.g. `{ "children", "depends_on", "blocks" }`
  skips the overview block entirely.
- `width`/`position` resize and flip it; on narrow terminals the sidebar
  shrinks before the detail view does.
- Remap pane keys via `mappings.view.sidebar` / `mappings.view.sidebar_toggle`
  / `mappings.sidebar` (set a value to `false` to disable that key).
- It reuses `BeadsLink`, `BeadsSection`, `BeadsMeta` and the status highlight
  groups, so colorscheme overrides apply automatically.

The same table can be passed through telescope instead (merges with
`setup()`, either order):

```lua
require("telescope").setup({
  extensions = { beads = { picker = { theme = "dropdown" } } },
})
```

### Highlight groups

All groups are `default`-linked — override with `vim.api.nvim_set_hl` or your
colorscheme: `BeadsTitle` (→Title), `BeadsMeta` (→Comment), `BeadsSection`
(→Function), `BeadsLink` (→Underlined), `BeadsHelp` (→NonText), `BeadsHelpKey`
(→Special), `BeadsStatusOpen` (→DiagnosticInfo), `BeadsStatusInProgress`
(→DiagnosticWarn), `BeadsStatusBlocked` (→DiagnosticError), `BeadsStatusClosed`
(→Comment), `BeadsStatusDeferred` (→NonText).

### Events

`User` autocmds fire after successful mutations, for statusline refreshes etc.:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "BeadsIssueUpdated", -- data = { id, action = "create"|"status"|"priority"|"close"|"reopen"|"comment"|"update" }
  callback = function(ev) ... end,
})
-- also: BeadsMemoryUpdated — data = { key, action = "remember"|"forget" }
```

### Statuses and types

Filter cycles and select prompts use `bd statuses` / `bd types` (fetched once
per session), so custom types configured in bd appear automatically.

Run `:checkhealth beads` to verify the install.

### Keymaps

Keymaps are a prefix (`base`) plus single-key `menus`. `keymaps = true` is
shorthand for:

```lua
keymaps = {
  base = "<leader>bd",
  menus = {
    l = "browse",      -- all non-closed issues
    a = "all",         -- every issue, closed included
    o = "open",        -- status:open only
    i = "in_progress", -- status:in_progress
    b = "blocked",     -- status:blocked
    d = "closed",      -- status:closed ("done")
    r = "ready",       -- unblocked work
    c = "create",      -- interactive create form
    q = "quick",       -- quick capture (bd q)
    p = "palette",     -- command palette
    m = "memories",    -- memory browser
    s = "search",      -- live bd search
    g = "graph",       -- dependency graph (id under cursor, else prompts)
  },
}
```

Menu values are builtin action names, a function, or `{ desc, fn }`:

```lua
keymaps = {
  base = "<leader>b",
  menus = {
    i = "all",          -- every issue, closed included
    o = "open",
    w = "in_progress",
    x = { desc = "show epic", fn = function() require("beads.view").open("myproj-x9s") end },
  },
}
```

Builtin actions: `browse`, `all`, `open`, `in_progress`, `blocked`,
`closed`, `ready`, `create`, `quick`, `palette`, `memories`, `search`,
`graph`.

## Usage

Commands: `:Beads`, `:BeadsReady`, `:BeadsShow <id>`, `:BeadsCreate`,
`:BeadsQuick [title]`, `:BeadsPalette`, `:BeadsMemories`,
`:BeadsSearch [text]`, `:BeadsGraph [id]`. Also `:Telescope beads
beads|ready|search|memories`.

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
| `a` | add a comment |
| `c` / `o` | close / reopen |
| `D` | dependency graph float |
| `gd` or `<CR>` | jump to dependency under cursor |
| `<Tab>` | focus the links sidebar (opens it if hidden) |
| `gs` | toggle the links sidebar |
| `<BS>` | back through jump history, then back to the picker |
| `R` | refresh |
| `q` / `<Esc>` | close (returns to the picker when opened from it) |

### Sidebar mappings

| Key | Action |
|-----|--------|
| `gd` or `<CR>` | open the issue under cursor in the detail view |
| `<Tab>` | focus back to the detail view |
| `<BS>` | back through jump history |
| `q` / `<Esc>` | close the detail view (sidebar included) |

### Memories picker mappings

| Key | Action |
|-----|--------|
| `<CR>` | edit memory in a float (`:w` → `bd remember`) |
| `<C-n>` | new memory (prompts for key) |
| `<C-d>` | forget memory (confirms) |
| `<C-r>` | refetch |

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
