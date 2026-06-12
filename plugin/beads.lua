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

cmd("BeadsMemories", function()
  require("beads.memories").open()
end, { desc = "Beads: browse memories" })

cmd("BeadsDashboard", function()
  require("beads.dashboard").open()
end, { desc = "Beads: home dashboard" })

cmd("BeadsBoard", function()
  require("beads.board").open()
end, { desc = "Beads: kanban board" })

cmd("BeadsSearch", function(o)
  require("beads.picker").search({ default_text = o.args ~= "" and o.args or nil })
end, { nargs = "?", desc = "Beads: live search (bd search)" })

cmd("BeadsGraph", function(o)
  local issues = require("beads.issues")
  local id = o.args ~= "" and o.args or issues.match_issue_id(vim.fn.expand("<cWORD>"))
  if id then
    require("beads.graphview").open(id)
  else
    vim.notify("BeadsGraph: no issue id given or under cursor", vim.log.levels.WARN)
  end
end, { nargs = "?", desc = "Beads: dependency graph" })
