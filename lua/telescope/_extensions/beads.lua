local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("beads.nvim telescope extension requires nvim-telescope/telescope.nvim")
end

return telescope.register_extension({
  -- `extensions = { beads = {...} }` in telescope's setup merges into the
  -- beads config without resetting it, so it composes with an explicit
  -- require("beads").setup() regardless of call order. Note: `keymaps`
  -- (global leader maps) is only bound by require("beads").setup().
  setup = function(ext_config)
    if ext_config and not vim.tbl_isempty(ext_config) then
      require("beads.config").merge(ext_config)
    end
  end,
  exports = {
    beads = function(opts)
      require("beads.picker").open(opts)
    end,
    ready = function(opts)
      require("beads.picker").open(vim.tbl_extend("force", opts or {}, { source = "ready" }))
    end,
    search = function(opts)
      require("beads.picker").search(opts)
    end,
    memories = function()
      require("beads.memories").open()
    end,
  },
})
