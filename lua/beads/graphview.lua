-- Dependency graph float: `bd graph <id> --compact` rendered read-only,
-- with ids link-styled and gd-jumpable into the detail view.

local cli = require("beads.cli")
local float = require("beads.float")
local helpbar = require("beads.helpbar")
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

    local ns = vim.api.nvim_create_namespace("beads_graph")
    for _, h in ipairs(render.link_spans(lines)) do
      vim.api.nvim_buf_set_extmark(buf, ns, h.lnum, h.col_start, {
        end_col = h.col_end,
        hl_group = h.hl_group,
      })
    end

    local function geometry()
      return float.center(110, #lines + 1)
    end
    local win = vim.api.nvim_open_win(
      buf,
      true,
      vim.tbl_extend("force", geometry(), {
        border = "rounded",
        title = " graph " .. id .. " ",
        title_pos = "center",
        footer = helpbar.footer("graph"),
        footer_pos = "center",
        style = "minimal",
      })
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

    local function bmap(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = "Beads: " .. desc })
    end
    bmap("q", close, "close graph")
    bmap("<Esc>", close, "close graph")
    bmap("gd", jump, "open issue under cursor")
    bmap("<CR>", jump, "open issue under cursor")
  end)
end

return M
