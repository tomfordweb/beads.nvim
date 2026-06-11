-- Small shared helpers: config-aware notifications and User autocmd events.

local M = {}

--- INFO-level success notification; silenced by `notify = false`.
--- Errors should keep going through vim.notify directly — they are never
--- suppressed.
---@param msg string
function M.info(msg)
  if require("beads.config").get().notify then
    vim.notify(msg, vim.log.levels.INFO)
  end
end

--- Fire a `User` autocmd so other plugins/config can react to bd mutations
--- (e.g. refresh a statusline component on BeadsIssueUpdated).
---@param pattern string e.g. "BeadsIssueUpdated", "BeadsMemoryUpdated"
---@param data table|nil passed through as the autocmd's `data`
function M.emit(pattern, data)
  vim.api.nvim_exec_autocmds("User", { pattern = pattern, data = data or {}, modeline = false })
end

return M
