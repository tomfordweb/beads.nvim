-- Wisps browser (:BeadsWisps): list ephemeral agent-runtime issues (the
-- dolt_ignored wisps table) grouped by type, and promote one to a permanent
-- bead with `bd promote`. Niche — most users never touch wisps — but surfaced
-- so the rare promote-worthy wisp is reachable from the editor.

local cli = require("beads.cli")
local config = require("beads.config")
local float = require("beads.float")
local issues = require("beads.issues")
local render = require("beads.render")
local util = require("beads.util")

local M = {}

-- bd's fixed wisp-type set (`bd list --wisp-type <t>`); there is no "all wisps"
-- flag, so the browser fans out one list call per type and tags the results.
M.WISP_TYPES = { "heartbeat", "ping", "patrol", "gc_report", "recovery", "error", "escalation" }

local state = { win = nil, buf = nil, rows = {} }

local function is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

local function close()
  if is_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win, state.buf, state.rows = nil, nil, {}
end

-- Fan out `bd list --wisp-type <t>` across every type, tag each result with the
-- type it came from, and hand the flattened list to cb once all calls return.
---@param cb fun(list: table[])
function M._fetch(cb)
  local results = {}
  local pending = #M.WISP_TYPES
  if pending == 0 then
    cb(results)
    return
  end
  for _, t in ipairs(M.WISP_TYPES) do
    cli.run_json({ "list", "--wisp-type", t }, function(ok, raw)
      if ok and type(raw) == "table" then
        for _, r in ipairs(raw) do
          local n = issues.normalize(r)
          n.wisp_type = t
          table.insert(results, n)
        end
      end
      pending = pending - 1
      if pending == 0 then
        cb(results)
      end
    end, { quiet = true })
  end
end

-- Id under the cursor in the wisps float, or nil on a header/blank row.
local function cursor_id()
  if not is_open() then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.rows[lnum]
end

-- Promote the carded wisp to a permanent bead (optionally with a reason), then
-- refresh so it drops out of the list.
local function promote()
  local id = cursor_id()
  if not id then
    return
  end
  vim.ui.input({ prompt = ("Promote %s — reason (optional): "):format(id) }, function(reason)
    if reason == nil then
      return
    end
    local args = { "promote", id }
    reason = vim.trim(reason)
    if reason ~= "" then
      table.insert(args, "--reason")
      table.insert(args, reason)
    end
    cli.run_plain(args, function(ok)
      if ok then
        util.info("bd: promoted " .. id)
        util.emit("BeadsIssueUpdated", { id = id, action = "promote" })
        M.refresh()
      end
    end)
  end)
end

local function render_into(list)
  if not is_open() then
    return
  end
  local width = vim.api.nvim_win_get_width(state.win)
  local lines, hls, rows = render.wisp_lines(list, M.WISP_TYPES, width)
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  float.apply_highlights(state.buf, "beads_wisps", hls)
  state.rows = rows
end

--- Refetch and re-render the wisp list in place. No-op when closed.
function M.refresh()
  if not is_open() then
    return
  end
  M._fetch(function(list)
    render_into(list)
  end)
end

local function setup_keymaps(buf)
  local m = config.get().mappings.wisps or {}
  local binds = {
    { m.promote, promote },
    { m.refetch, M.refresh },
    { m.quit, close },
  }
  for _, bind in ipairs(binds) do
    for _, lhs in ipairs(config.lhs(bind[1])) do
      vim.keymap.set("n", lhs, bind[2], { buffer = buf, silent = true, nowait = true })
    end
  end
end

--- Open the wisps browser.
function M.open()
  render.define_highlights()
  M._fetch(function(list)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"

    local function geometry()
      return float.center(float.width("palette", 80), float.height("palette", 24))
    end
    local win = vim.api.nvim_open_win(
      buf,
      true,
      float.decorate(geometry(), { title = " wisps ", pane = "wisps", style = "minimal" })
    )
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    float.auto_resize(win, geometry)

    state.win, state.buf = win, buf
    setup_keymaps(buf)
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        state.win, state.buf, state.rows = nil, nil, {}
      end,
    })
    render_into(list)
  end)
end

return M
