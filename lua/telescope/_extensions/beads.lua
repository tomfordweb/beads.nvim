local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("beads.nvim telescope extension requires nvim-telescope/telescope.nvim")
end

return telescope.register_extension({
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
