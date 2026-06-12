-- Home dashboard (F1): a small centered float summarizing the project from
-- `bd stats --json` — status counts, ready, total — with one-key jumps into the
-- matching picker filter. Read-only; reuses float + render like the other panes.

local cli = require("beads.cli")
local float = require("beads.float")
local render = require("beads.render")

local M = {}

-- key -> picker filter for the status-jump bindings.
local STATUS_JUMP = {
  o = { status = "open" },
  i = { status = "in_progress" },
  b = { status = "blocked" },
  d = { status = "closed" },
}

--- Open the dashboard float.
function M.open()
  render.define_highlights()
  cli.run_json({ "stats" }, function(ok, result)
    local summary = (ok and type(result) == "table" and result.summary) or {}
    local lines, hls = render.dashboard_lines(summary)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    float.apply_highlights(buf, "beads_dashboard", hls)
    vim.bo[buf].modifiable = false

    local function geometry()
      return float.center(float.width("dashboard", 34), float.height("dashboard", #lines + 1))
    end
    local win = vim.api.nvim_open_win(
      buf,
      true,
      float.decorate(geometry(), { title = " beads ", pane = "dashboard", style = "minimal" })
    )
    float.auto_resize(win, geometry)

    local function close()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    local function jump(filters)
      close()
      require("beads.picker").open({ filters = filters })
    end

    local maps = {
      q = close,
      ["<Esc>"] = close,
      r = function()
        close()
        require("beads.picker").open({ source = "ready" })
      end,
    }
    for key, filters in pairs(STATUS_JUMP) do
      maps[key] = function()
        jump(filters)
      end
    end
    for lhs, fn in pairs(maps) do
      vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true })
    end
  end)
end

return M
