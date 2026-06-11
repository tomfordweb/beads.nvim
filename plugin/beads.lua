if vim.g.loaded_beads then
  return
end
vim.g.loaded_beads = true

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

cmd("Beads", function()
  require("beads.picker").open()
end, { desc = "Beads: browse issues" })

cmd("BeadsReady", function()
  require("beads.picker").open({ source = "ready" })
end, { desc = "Beads: ready (unblocked) work" })

cmd("BeadsShow", function(o)
  require("beads.view").open(o.args)
end, { nargs = 1, desc = "Beads: show issue detail" })

cmd("BeadsCreate", function()
  require("beads.create").open_form()
end, { desc = "Beads: create issue" })

cmd("BeadsQuick", function(o)
  require("beads.create").quick(o.args ~= "" and o.args or nil)
end, { nargs = "?", desc = "Beads: quick capture" })

cmd("BeadsPalette", function()
  require("beads.palette").open()
end, { desc = "Beads: command palette" })
