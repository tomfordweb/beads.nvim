-- Issue creation: quick capture (bd q) and a flat sequential form chain.

local cli = require("beads.cli")
local issues = require("beads.issues")
local util = require("beads.util")

local M = {}

--- Quick capture via `bd q <title>`; prompts when no title given.
---@param title string|nil
function M.quick(title)
  if title and title ~= "" then
    return M._quick_run(title)
  end
  vim.ui.input({ prompt = "bd q: " }, function(input)
    if input and input ~= "" then
      M._quick_run(input)
    end
  end)
end

---@param title string
function M._quick_run(title)
  cli.run_plain({ "q", title }, function(ok, stdout)
    if not ok then
      return
    end
    local id = vim.trim(stdout or "")
    util.info("bd: created " .. id)
    util.emit("BeadsIssueUpdated", { id = id, action = "create" })
  end)
end

-- The form is a flat chain of named steps to avoid callback pyramids.
-- Each step fills `form` and calls the next.

local function submit(form)
  cli.run_json(issues.build_create_args(form), function(ok, result)
    if not ok then
      return
    end
    local created = result and (result.id and result or result[1])
    local id = created and created.id
    util.emit("BeadsIssueUpdated", { id = id, action = "create" })
    if not id then
      util.info("bd: issue created")
      return
    end
    util.info("bd: created " .. id)
    require("beads.view").open(id)
  end)
end

local function step_deps(form)
  vim.ui.input({ prompt = "Deps (e.g. blocks:bd-15,bd-20 — empty to skip): " }, function(input)
    form.deps = input -- nil on abort is fine; build_create_args skips empty
    submit(form)
  end)
end

local function step_priority(form)
  local labels = { "P0 critical", "P1 high", "P2 normal", "P3 low", "P4 backlog" }
  vim.ui.select(labels, { prompt = "Priority" }, function(choice, idx)
    if not choice then
      return
    end
    form.priority = idx - 1
    step_deps(form)
  end)
end

local function step_type(form)
  vim.ui.select(issues.types(), { prompt = "Type" }, function(choice)
    if not choice then
      return
    end
    form.type = choice
    step_priority(form)
  end)
end

--- Interactive create form: title -> type -> priority -> deps -> bd create.
function M.open_form()
  vim.ui.input({ prompt = "Title: " }, function(title)
    if not title or title == "" then
      return
    end
    step_type({ title = title })
  end)
end

return M
