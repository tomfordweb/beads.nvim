-- Command palette for repo-level bd commands; output shown in a scratch float.

local cli = require("beads.cli")
local config = require("beads.config")
local float = require("beads.float")
local render = require("beads.render")

local M = {}

---@class BeadsPaletteCommand
---@field label string shown in the selector
---@field args string[] bd argv tail
---@field confirm boolean|nil ask before running

---@type BeadsPaletteCommand[]
M.commands = {
  { label = "status — database overview and statistics", args = { "status" } },
  { label = "epic status — completion per epic", args = { "epic", "status" } },
  {
    label = "epic close-eligible — close epics whose children are all done",
    args = { "epic", "close-eligible" },
    confirm = true,
  },
  { label = "ready — unblocked open issues", args = { "ready" } },
  { label = "stale — issues not updated recently", args = { "stale" } },
  { label = "lint — check issues for missing sections", args = { "lint" } },
  { label = "dep cycles — detect dependency cycles", args = { "dep", "cycles" } },
  { label = "count — count open issues", args = { "count" } },
  { label = "init — create .beads db in project dir", args = { "init" }, confirm = true },
}

---@param text string
---@param title string
local function show_output(text, title)
  render.define_highlights()
  local lines = vim.split(render.strip_ansi(text), "\n", { plain = true })
  -- trim trailing blank lines
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  if #lines == 0 then
    lines = { "(no output)" }
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local function geometry()
    return float.center(float.dims("palette").width or 100, #lines + 1)
  end
  local win = vim.api.nvim_open_win(
    buf,
    true,
    float.decorate(
      geometry(),
      { title = " bd " .. title .. " ", pane = "palette_output", style = "minimal" }
    )
  )
  vim.wo[win].wrap = false
  float.auto_resize(win, geometry)

  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, silent = true, nowait = true })
  end
end

---@param cmd BeadsPaletteCommand
local function run_command(cmd)
  if cmd.confirm then
    local dir = cli.resolve_cwd()
    local choice = vim.fn.confirm(
      ("Run `bd %s` in %s?"):format(table.concat(cmd.args, " "), dir),
      "&Yes\n&No",
      2
    )
    if choice ~= 1 then
      return
    end
  end
  cli.run_plain(cmd.args, function(ok, stdout)
    if ok then
      show_output(stdout or "", table.concat(cmd.args, " "))
    end
  end)
end

--- Open the bd command palette (vim.ui.select — telescope dropdown when
--- telescope-ui-select is installed).
function M.open()
  local items = vim.list_extend(vim.deepcopy(M.commands), config.get().palette.extra or {})
  vim.ui.select(items, {
    prompt = "bd",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      run_command(choice)
    end
  end)
end

return M
