-- Description editing: acwrite scratch buffer whose :w round-trips through
-- `bd update <id> --body-file -`.

local cli = require("beads.cli")
local float = require("beads.float")
local helpbar = require("beads.helpbar")

local M = {}

-- The detail view is a float, and floats cannot be split — the edit buffer
-- opens in its own centered float instead.
local function open_float(buf, id)
  local win = vim.api.nvim_open_win(
    buf,
    true,
    vim.tbl_extend("force", float.center(90, 20), {
      border = "rounded",
      title = (" edit %s "):format(id),
      title_pos = "center",
      footer = helpbar.footer("edit"),
      footer_pos = "center",
    })
  )
  vim.wo[win].wrap = true
  float.auto_resize(win, function()
    return float.center(90, 20)
  end)
  return win
end

--- Open a float with the issue description; :w persists via bd update.
---@param issue table normalized issue (needs id + description)
function M.open_description(issue)
  require("beads.render").define_highlights()
  local name = ("beads://%s/description"):format(issue.id)

  -- Reuse an existing edit buffer for this issue if one is already open.
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 then
    open_float(existing, issue.id)
    return
  end

  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(issue.description or "", "\n", { plain = true }))
  vim.bo[buf].modified = false

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      cli.run_stdin({ "update", issue.id, "--body-file", "-" }, body, function(ok)
        if not ok then
          return
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].modified = false
        end
        vim.notify("bd: updated description of " .. issue.id, vim.log.levels.INFO)
        require("beads.view").refresh()
      end)
    end,
  })

  open_float(buf, issue.id)
end

return M
