-- Description editing: acwrite scratch buffer whose :w round-trips through
-- `bd update <id> --body-file -`.

local cli = require("beads.cli")

local M = {}

-- The detail view is a float, and floats cannot be split — the edit buffer
-- opens in its own centered float instead.
local function open_float(buf, id)
  local width = math.min(90, vim.o.columns - 10)
  local height = math.min(20, vim.o.lines - 8)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = (" edit %s — :w saves, :q closes "):format(id),
    title_pos = "center",
  })
  vim.wo[win].wrap = true
  return win
end

--- Open a float with the issue description; :w persists via bd update.
---@param issue table normalized issue (needs id + description)
function M.open_description(issue)
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
