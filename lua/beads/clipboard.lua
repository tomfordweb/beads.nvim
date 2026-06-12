-- OSC52 clipboard helpers (M8). The clipboard is a global Neovim concern, so
-- this stays light: detect a remote session without a working provider (for the
-- :checkhealth advisory) and, opt-in via edit.osc52, wire Neovim 0.10's
-- built-in OSC52 provider so yanks to "+ reach the local clipboard over
-- SSH/tmux. It never clobbers an already-working clipboard.

local M = {}

--- True inside an SSH session or a tmux/screen multiplexer, where the system
--- clipboard usually isn't directly reachable.
---@return boolean
function M.is_remote()
  return (vim.env.SSH_TTY or vim.env.SSH_CONNECTION or vim.env.TMUX) ~= nil
end

--- True when Neovim already has a usable clipboard provider (an explicit
--- vim.g.clipboard or a detected backend like xclip/wl-copy/pbcopy).
---@return boolean
function M.has_provider()
  if vim.g.clipboard ~= nil then
    return true
  end
  return vim.fn.has("clipboard_working") == 1
end

--- Opt-in (edit.osc52): when remote with no configured provider, install
--- Neovim's built-in OSC52 clipboard for "+/"*. No-op (returns false) when the
--- option is off, a provider already works, the session is local, or the
--- built-in module is unavailable — so it can be called unconditionally.
---@return boolean enabled
function M.maybe_enable()
  if not require("beads.config").get().edit.osc52 then
    return false
  end
  if M.has_provider() or not M.is_remote() then
    return false
  end
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if not ok then
    return false
  end
  vim.g.clipboard = {
    name = "osc52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
  }
  return true
end

return M
