---@class BeadsKeymaps
---@field base string prefix prepended to every menu key (e.g. "<leader>b")
---@field menus table<string, string|fun()|{ desc: string|nil, fn: fun() }|false>
--- menu values: builtin action name (see beads.actions), a function, a
--- { desc, fn } table, or false to disable a default entry

---@alias BeadsLhs string|string[]|false a key, a list of equivalent keys, or false to disable

---@class BeadsMappings
---@field picker table<string, BeadsLhs>
---@field view table<string, BeadsLhs>
---@field memories table<string, BeadsLhs>
---@field graph table<string, BeadsLhs>

---@class BeadsConfig
---@field bd_bin string
---@field cwd string|nil
---@field list_limit integer
---@field default_filters { status: string|nil, priority: integer|nil, type: string|nil, all: boolean }
---@field picker { theme: string|false, theme_opts: table, telescope: table }
---@field keymaps boolean|BeadsKeymaps
---@field mappings BeadsMappings
---@field icons { status: table<string, string>, deps_down: string, deps_up: string }
---@field graph { scope: "issue"|"all" }
---@field float { border: string|table, view: table, edit: table, palette: table, graph: table }
---@field edit { inline: boolean, discard_on_quit: boolean, autosave: boolean, autosave_debounce_ms: integer, persistent_undo: boolean, undodir: string|nil, guard_keys: string[], osc52: boolean }
---@field sidebar { enabled: boolean, width: integer, position: "left"|"right", sections: string[], history_limit: integer }
---@field helpbar boolean
---@field notify boolean
---@field refresh_on_focus boolean
---@field debug boolean
---@field palette { extra: table[] }
---@field runner fun(argv: string[], opts: table, on_exit: fun(out: table))|nil

local M = {}

local defaults = {
  bd_bin = "bd",
  cwd = nil,
  list_limit = 200,
  default_filters = { status = nil, priority = nil, type = nil, all = false },
  -- theme: "ivy" | "dropdown" | "cursor" | false (use your telescope defaults);
  -- theme_opts feeds the theme builder, telescope is merged last into the
  -- picker opts (layout_config, borders, …)
  picker = { theme = "ivy", theme_opts = {}, telescope = {} },
  keymaps = false,
  -- buffer-local/picker mappings, keyed action -> lhs. An lhs may be a
  -- string, a list of equivalent keys, or false to disable the action's key.
  -- A user value replaces the default wholesale (no list merging).
  mappings = {
    picker = {
      open = "<CR>",
      status = "<C-s>",
      priority = "<C-y>",
      type = "<C-t>",
      label = "<C-l>",
      defer = "<C-f>",
      closed = "<C-a>",
      refetch = "<C-r>",
    },
    view = {
      edit = "e",
      status = "s",
      priority = "p",
      comment = "a",
      labels = "L",
      assign = "A",
      defer = "f",
      close = "c",
      reopen = "o",
      graph = "D",
      history = "H",
      jump = { "gd", "<CR>" },
      back = "<BS>",
      refresh = "R",
      quit = { "q", "<Esc>" },
      sidebar = "<Tab>",
      sidebar_toggle = "gs",
    },
    sidebar = {
      jump = { "gd", "<CR>" },
      focus_view = "<Tab>",
      back = "<BS>",
      quit = { "q", "<Esc>" },
    },
    memories = {
      edit = "<CR>",
      new = "<C-n>",
      forget = "<C-d>",
      refetch = "<C-r>",
    },
    graph = {
      jump = { "gd", "<CR>" },
      scope = "a",
      quit = { "q", "<Esc>" },
    },
  },
  icons = {
    status = {
      open = "○",
      in_progress = "◐",
      blocked = "⊘",
      deferred = "❄",
      closed = "●",
    },
    deps_down = "↓",
    deps_up = "↑",
  },
  -- Dependency-graph float scope (distinct from float.graph sizing below).
  -- "issue" graphs a single id (`bd graph <id> --compact`); "all" graphs every
  -- open issue (`bd graph --all --compact`). Toggle in-place with the `scope`
  -- key. M.open's scope arg overrides this default per-open.
  graph = { scope = "issue" },
  -- Float sizes. width/height accept a fraction (0–1 = % of the editor), a
  -- "<n>%" string, or an absolute cell count (>1). Heights left unset stay
  -- content-sized. Percentage defaults keep the floats a sensible, consistent
  -- size across terminal dimensions.
  float = {
    border = "rounded",
    view = { width = 0.8, height = 0.8 },
    edit = { width = 0.7, height = 0.6 }, -- also used by the memory edit float
    palette = { width = 0.7 }, -- content-sized height
    graph = { width = 0.8 }, -- content-sized height
  },
  -- Inline description editing (the `e` key in the detail view). When
  -- inline=true the description is edited in-place inside the detail float;
  -- inline=false falls back to the separate edit float (beads.edit).
  edit = {
    inline = true,
    discard_on_quit = false, -- :q saves before returning to the detail view
    autosave = false, -- debounced save while typing
    autosave_debounce_ms = 800,
    persistent_undo = false, -- keep undo history across edit sessions
    undodir = nil, -- defaults to stdpath("state")/beads/undo
    -- opt-in: over SSH/tmux with no clipboard provider, route "+/"* through
    -- Neovim 0.10's built-in OSC52 so yanks reach the local clipboard. No-op
    -- when a clipboard already works or the session is local.
    osc52 = false,
    -- normal-mode keys to neutralize inside the edit buffer only, so a global
    -- map (e.g. oil.nvim's "-") can't fire mid-edit. Insert mode is untouched.
    guard_keys = {},
  },
  -- linked-issues sidebar next to the detail view
  sidebar = {
    enabled = true, -- open automatically with the detail view
    width = 34,
    position = "right", -- "left"
    -- section order; remove entries to hide them. "history" surfaces the last
    -- `history_limit` change rows inline (full log still on `H`).
    sections = { "overview", "parent", "children", "depends_on", "blocks", "history" },
    history_limit = 3,
  },
  helpbar = true,
  notify = true,
  -- Re-center/resize open floats on terminal focus-resume as well as resize.
  -- tmux reattach and pane-zoom often fire FocusGained/VimResume instead of
  -- VimResized; set false to only track VimResized. Requires tmux
  -- `set -g focus-events on` for the focus events to reach nvim.
  refresh_on_focus = true,
  debug = false, -- log float resize/focus events via vim.notify(DEBUG)
  palette = { extra = {} },
  runner = nil,
}

local default_keymaps = {
  base = "<leader>bd",
  menus = {
    l = "browse",
    a = "all",
    o = "open",
    i = "in_progress",
    b = "blocked",
    d = "closed",
    r = "ready",
    c = "create",
    q = "quick",
    p = "palette",
    m = "memories",
    s = "search",
    g = "graph",
  },
}

local options = vim.deepcopy(defaults)

--- Mapping lhs values replace wholesale: tbl_deep_extend would merge a user
--- list { "x" } into the default { "gd", "<CR>" } by index, which surprises.
local function merge_mappings(base, user)
  local out = vim.deepcopy(base)
  for pane, acts in pairs(user or {}) do
    if type(acts) == "table" then
      out[pane] = out[pane] or {}
      for action, lhs in pairs(acts) do
        out[pane][action] = vim.deepcopy(lhs)
      end
    end
  end
  return out
end

local function normalize_keymaps(keymaps)
  if keymaps == true then
    return vim.deepcopy(default_keymaps)
  end
  if type(keymaps) == "table" then
    return {
      base = keymaps.base or default_keymaps.base,
      -- user menus replace the defaults wholesale when given; mixing
      -- defaults into custom single-letter menus surprises more than helps
      menus = keymaps.menus or vim.deepcopy(default_keymaps.menus),
    }
  end
  return keymaps
end

---@param base table current effective options
---@param opts table|nil
---@return table
local function apply(base, opts)
  opts = opts or {}
  local user_mappings = opts.mappings
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(base), opts)
  merged.mappings = merge_mappings(base.mappings, user_mappings)
  merged.keymaps = normalize_keymaps(merged.keymaps)
  return merged
end

--- Reset to defaults, then apply opts.
---@param opts table|nil
function M.setup(opts)
  options = apply(vim.deepcopy(defaults), opts)
end

--- Merge opts into the current effective options (no reset). Used by the
--- telescope extension's setup so `extensions = { beads = {...} }` composes
--- with an explicit require("beads").setup() call regardless of order.
---@param opts table|nil
function M.merge(opts)
  options = apply(options, opts)
end

---@return BeadsConfig
function M.get()
  return options
end

--- Normalize a mapping value to a list of lhs strings ({} when disabled).
---@param value BeadsLhs|nil
---@return string[]
function M.lhs(value)
  if type(value) == "string" then
    return { value }
  end
  if type(value) == "table" then
    return value
  end
  return {}
end

M.default_keymaps = default_keymaps
M.defaults = defaults

return M
