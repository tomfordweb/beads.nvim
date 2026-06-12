-- Dependency graph float. Scope "issue" renders `bd graph <id> --compact`
-- for one issue; scope "all" renders `bd graph --all --compact` for every
-- open issue. The `scope` key flips between them and re-renders in place.
-- Output is read-only with ids link-styled and gd-jumpable into the detail view.

local cli = require("beads.cli")
local config = require("beads.config")
local float = require("beads.float")
local issues = require("beads.issues")
local render = require("beads.render")

local M = {}

--- bd argv for a graph at the given scope. "all" ignores id and graphs every
--- open issue; "issue" graphs the single id.
---@param id string|nil
---@param scope "issue"|"all"
---@return string[]
function M.argv(id, scope)
  -- "all" (or a missing id, defensively) graphs everything; a nil id must
  -- never reach the argv as a hole between "graph" and "--compact".
  if scope == "all" or not id then
    return { "graph", "--all", "--compact" }
  end
  return { "graph", id, "--compact" }
end

--- Float title for a graph at the given scope.
---@param id string|nil
---@param scope "issue"|"all"
---@return string
function M.title(id, scope)
  if scope == "all" then
    return " graph (all) "
  end
  return " graph " .. (id or "") .. " "
end

--- Show the dependency graph. With scope "all" no id is needed.
---@param id string|nil
---@param scope "issue"|"all"|nil defaults to config.graph.scope
function M.open(id, scope)
  scope = scope or config.get().graph.scope
  render.define_highlights()

  cli.run_plain(M.argv(id, scope), function(ok, stdout)
    if not ok then
      return
    end
    local lines = vim.split(render.strip_ansi(stdout or ""), "\n", { plain = true })
    while #lines > 0 and vim.trim(lines[#lines]) == "" do
      table.remove(lines)
    end
    if #lines == 0 then
      lines = { "(no graph)" }
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    float.apply_highlights(buf, "beads_graph", render.link_spans(lines))

    local function geometry()
      return float.center(float.width("graph", 110), float.height("graph", #lines + 1))
    end
    local win = vim.api.nvim_open_win(
      buf,
      true,
      float.decorate(geometry(), { title = M.title(id, scope), pane = "graph", style = "minimal" })
    )
    vim.wo[win].wrap = false
    float.auto_resize(win, geometry)

    local function close()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    local function jump()
      local target = issues.match_issue_id(vim.fn.expand("<cWORD>"))
      if target then
        close()
        require("beads.view").open(target)
      end
    end
    -- Flip issue<->all and re-render in place (closing this float first).
    -- Switching to single-issue scope needs an id; when there is none (the
    -- all-graph opened from the menu) the toggle is a no-op.
    local function toggle_scope()
      local next_scope = scope == "all" and "issue" or "all"
      if next_scope == "issue" and not id then
        return
      end
      close()
      M.open(id, next_scope)
    end

    local m = config.get().mappings.graph
    local function bmap(lhs_value, rhs, desc)
      for _, lhs in ipairs(config.lhs(lhs_value)) do
        vim.keymap.set(
          "n",
          lhs,
          rhs,
          { buffer = buf, silent = true, nowait = true, desc = "Beads: " .. desc }
        )
      end
    end
    bmap(m.quit, close, "close graph")
    bmap(m.jump, jump, "open issue under cursor")
    bmap(m.scope, toggle_scope, "toggle graph scope (issue/all)")
  end)
end

return M
