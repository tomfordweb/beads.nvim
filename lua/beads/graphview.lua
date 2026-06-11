-- Dependency graph float: `bd graph <id> --compact` rendered read-only,
-- with ids link-styled and gd-jumpable into the detail view.

local cli = require("beads.cli")
local config = require("beads.config")
local float = require("beads.float")
local issues = require("beads.issues")
local render = require("beads.render")

local M = {}

--- Show the dependency graph for an issue id.
---@param id string
function M.open(id)
  render.define_highlights()
  cli.run_plain({ "graph", id, "--compact" }, function(ok, stdout)
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
      return float.center(float.dims("graph").width or 110, #lines + 1)
    end
    local win = vim.api.nvim_open_win(
      buf,
      true,
      float.decorate(
        geometry(),
        { title = " graph " .. id .. " ", pane = "graph", style = "minimal" }
      )
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
  end)
end

return M
