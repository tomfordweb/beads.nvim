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
      "Install beads: https://github.com/steveyegge/beads",
      "Or point config.bd_bin at the binary",
    })
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
