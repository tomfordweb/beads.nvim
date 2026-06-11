-- Pure helpers for the per-pane keybind help bar. Floats render it as a
-- window footer (nvim >= 0.10); the telescope picker embeds it in the
-- prompt title since telescope draws its own borders.

local M = {}

--- Ordered { key, action } pairs per pane.
---@type table<string, string[][]>
M.PANES = {
  picker = {
    { "<CR>", "open" },
    { "<C-s>", "status" },
    { "<C-y>", "prio" },
    { "<C-t>", "type" },
    { "<C-a>", "closed" },
    { "<C-r>", "refetch" },
  },
  picker_ready = {
    { "<CR>", "open" },
    { "<C-y>", "prio" },
    { "<C-t>", "type" },
    { "<C-r>", "refetch" },
  },
  view = {
    { "e", "edit" },
    { "s", "status" },
    { "p", "prio" },
    { "c", "close" },
    { "o", "reopen" },
    { "gd", "dep-jump" },
    { "<BS>", "back" },
    { "R", "refresh" },
    { "q", "quit" },
  },
  edit = {
    { ":w", "save" },
    { ":q", "close" },
  },
  palette_output = {
    { "q", "close" },
  },
}

--- Plain one-line help string ("<CR> open  <C-s> status  …").
---@param pane string
---@return string
function M.line(pane)
  local parts = {}
  for _, item in ipairs(M.PANES[pane] or {}) do
    table.insert(parts, item[1] .. " " .. item[2])
  end
  return table.concat(parts, "  ")
end

--- Highlighted chunk list for nvim_open_win's `footer` option.
---@param pane string
---@return string[][] [text, hl_group] chunks
function M.footer(pane)
  local items = M.PANES[pane] or {}
  local chunks = {}
  for i, item in ipairs(items) do
    table.insert(chunks, { (i == 1 and " " or "  ") .. item[1], "BeadsHelpKey" })
    table.insert(chunks, { " " .. item[2], "BeadsHelp" })
  end
  if #chunks > 0 then
    table.insert(chunks, { " ", "BeadsHelp" })
  end
  return chunks
end

return M
