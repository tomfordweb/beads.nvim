-- :checkhealth beads

local M = {}

function M.check()
  local health = vim.health
  health.start("beads.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10")
  else
    health.error("Neovim 0.10+ required (vim.system, float footer)")
  end

  if pcall(require, "telescope") then
    health.ok("telescope.nvim found")
  else
    health.error("telescope.nvim not found", { "Install nvim-telescope/telescope.nvim" })
  end

  if pcall(require, "plenary") then
    health.ok("plenary.nvim found")
  else
    health.error("plenary.nvim not found", { "Install nvim-lua/plenary.nvim" })
  end

  local bd_bin = require("beads.config").get().bd_bin
  if vim.fn.executable(bd_bin) == 1 then
    local out = vim.system({ bd_bin, "--version" }, { text = true }):wait()
    local version = vim.trim(out.stdout or "")
    if out.code == 0 and version ~= "" then
      health.ok(version)
    else
      health.warn(("`%s --version` failed (exit %d)"):format(bd_bin, out.code))
    end
  else
    health.error(("bd binary %q not executable"):format(bd_bin), {
      "Install beads: https://github.com/gastownhall/beads",
      "Or point config.bd_bin at the binary",
    })
  end

  -- Clipboard / OSC52 advisory (M8): clipboard is global, so only warn when a
  -- remote session likely can't reach the system clipboard.
  local clip = require("beads.clipboard")
  if clip.has_provider() then
    health.ok("clipboard provider available")
  elseif clip.is_remote() then
    health.warn(
      "remote session (SSH/tmux) with no clipboard provider — yanks won't reach your local clipboard",
      {
        "Neovim 0.10 ships OSC52: set `edit.osc52 = true`, or point vim.g.clipboard at vim.ui.clipboard.osc52",
        "Then `set clipboard=unnamedplus` to route yanks through it",
        "tmux: `set -g set-clipboard on`",
      }
    )
  else
    health.info("no clipboard provider; yanks stay in Neovim registers")
  end

  local root = require("beads.config").get().cwd or vim.fs.root(0, ".beads")
  if root then
    health.ok("beads database root: " .. root)
  else
    health.warn("no .beads directory found upward from the current buffer", {
      "Run `bd init` in your project, or set config.cwd",
    })
  end
end

return M
