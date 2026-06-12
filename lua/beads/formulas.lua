-- Formula / molecule browser (:BeadsFormulas): list bd's workflow formulas and
-- act on one — show its structure (`bd formula show`) or pour it into a
-- persistent molecule (`bd mol pour`, with optional --var substitutions).
--
-- Formulas are an agent-workflow feature; a dev repo with none returns null, so
-- the list shape is normalized defensively (string entries or name/description
-- tables) and an empty result shows the search paths bd looked in.

local cli = require("beads.cli")
local util = require("beads.util")

local M = {}

--- Normalize `bd formula list --json` into a name-sorted list of
--- { name, description }. The JSON shape is unverified upstream, so accept a
--- bare-string array, a name->description map, or a list/map of tables carrying
--- a name (name/id/formula) and an optional description (description/summary/
--- phase). Anything without a usable name is skipped. Pure.
---@param raw any decoded bd formula list --json (may be nil)
---@return { name: string, description: string }[]
function M.normalize(raw)
  local out = {}
  if type(raw) ~= "table" then
    return out
  end
  for k, v in pairs(raw) do
    if type(v) == "string" then
      if type(k) == "number" then
        table.insert(out, { name = v, description = "" })
      else
        table.insert(out, { name = k, description = v })
      end
    elseif type(v) == "table" then
      local name = v.name or v.id or v.formula or (type(k) == "string" and k or nil)
      if type(name) == "string" then
        table.insert(out, {
          name = name,
          description = v.description or v.summary or v.phase or "",
        })
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

--- Build argv for `bd mol pour <name>` with repeated `--var key=value`. Pure.
---@param name string formula/proto name
---@param vars string[]|nil "key=value" substitutions
---@return string[]
function M.pour_args(name, vars)
  local args = { "mol", "pour", name }
  for _, kv in ipairs(vars or {}) do
    table.insert(args, "--var")
    table.insert(args, kv)
  end
  return args
end

-- Gather "key=value" var substitutions one at a time (empty answer finishes),
-- then pour the formula into a persistent molecule.
---@param name string
local function pour(name)
  local vars = {}
  local function ask()
    vim.ui.input({
      prompt = ("pour %s — var key=value (empty to finish): "):format(name),
    }, function(value)
      value = value and vim.trim(value)
      if value and value ~= "" then
        table.insert(vars, value)
        ask()
        return
      end
      cli.run_plain(M.pour_args(name, vars), function(ok, stdout)
        if ok then
          util.info("bd: poured " .. name)
          util.emit("BeadsIssueUpdated", { id = name, action = "pour" })
          require("beads.palette").show_output(stdout or "", "mol pour " .. name)
        end
      end)
    end)
  end
  ask()
end

-- Show a formula's structure in the palette output float.
---@param name string
local function show(name)
  cli.run_plain({ "formula", "show", name }, function(ok, stdout)
    if ok then
      require("beads.palette").show_output(stdout or "", "formula show " .. name)
    end
  end)
end

-- Offer the per-formula actions (show structure / pour into a molecule).
---@param name string
local function choose_action(name)
  local actions = {
    { label = "pour — instantiate as a persistent molecule", fn = pour },
    { label = "show — view formula structure and variables", fn = show },
  }
  vim.ui.select(actions, {
    prompt = name,
    format_item = function(a)
      return a.label
    end,
  }, function(choice)
    if choice then
      choice.fn(name)
    end
  end)
end

--- Open the formula browser.
function M.open()
  cli.run_json({ "formula", "list" }, function(ok, raw)
    if not ok then
      return
    end
    local formulas = M.normalize(raw)
    if #formulas == 0 then
      local paths = cli.resolve_cwd() .. "/.beads/formulas, ~/.beads/formulas"
      util.info("bd: no formulas found (searched " .. paths .. ")")
      return
    end
    vim.ui.select(formulas, {
      prompt = "bd formulas",
      format_item = function(f)
        return f.description ~= "" and (f.name .. " — " .. f.description) or f.name
      end,
    }, function(choice)
      if choice then
        choose_action(choice.name)
      end
    end)
  end)
end

return M
