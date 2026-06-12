-- Install / load-contract tests.
--
-- Every package manager in the README (lazy.nvim, packer.nvim, vim-plug,
-- mini.deps) does the same three things: put the plugin + its telescope/plenary
-- deps on the runtimepath, call require("beads").setup(), and load the Telescope
-- extension. The managers differ only in HOW they wire the runtimepath — the
-- plugin's behaviour afterwards is identical. So rather than install four real
-- managers in CI (which would test the managers, not this plugin), these specs
-- assert the contract every one of them relies on, against the same rtp wiring
-- tests/minimal_init.lua already sets up.

-- Locate plugin/beads.lua on the runtimepath — exactly where every package
-- manager puts it. (Headless runs use --noplugin, so it isn't auto-sourced.)
local function plugin_file()
  local found = vim.api.nvim_get_runtime_file("plugin/beads.lua", false)[1]
  assert.is_truthy(found, "plugin/beads.lua not found on runtimepath")
  return found
end

-- The user commands plugin/beads.lua registers when the plugin is sourced from
-- the runtimepath (which is what every manager arranges).
local EXPECTED_COMMANDS = {
  "Beads",
  "BeadsReady",
  "BeadsShow",
  "BeadsCreate",
  "BeadsQuick",
  "BeadsPalette",
  "BeadsMemories",
  "BeadsDashboard",
  "BeadsSearch",
  "BeadsGraph",
}

describe("install contract", function()
  it("registers every :Beads* command when plugin/beads.lua is sourced", function()
    -- Headless runs use --noplugin, so source the plugin file the way a real
    -- runtimepath load would. Reset the guard so it runs even if a prior spec
    -- already sourced it.
    vim.g.loaded_beads = nil
    vim.cmd("source " .. plugin_file())

    local commands = vim.api.nvim_get_commands({})
    for _, name in ipairs(EXPECTED_COMMANDS) do
      assert.is_truthy(commands[name], "missing user command :" .. name)
    end
  end)

  it("sourcing the plugin twice is a no-op (load guard holds)", function()
    vim.g.loaded_beads = nil
    vim.cmd("source " .. plugin_file())
    -- Second source returns early on vim.g.loaded_beads; must not error.
    assert.has_no.errors(function()
      vim.cmd("source " .. plugin_file())
    end)
    assert.is_truthy(vim.g.loaded_beads)
  end)

  it("require('beads').setup() applies config without error and is idempotent", function()
    assert.has_no.errors(function()
      require("beads").setup({ keymaps = true })
      require("beads").setup({ keymaps = false })
    end)
  end)

  it("loads the Telescope extension exposing the documented pickers", function()
    local has_telescope = pcall(require, "telescope")
    if not has_telescope then
      pending("telescope.nvim not found on rtp — skipping extension load", function() end)
      return
    end

    assert.has_no.errors(function()
      require("telescope").load_extension("beads")
    end)

    local ext = require("telescope").extensions.beads
    assert.is_truthy(ext, "telescope.extensions.beads not registered")
    for _, picker in ipairs({ "beads", "ready", "search", "memories" }) do
      assert.are.equal("function", type(ext[picker]), "missing telescope picker: " .. picker)
    end
  end)
end)
