-- Canned bd JSON output as Lua tables, pinned to bd 1.0.4 shapes.

local M = {}

-- Shape of one element from `bd list --json`.
M.list_issue = {
  id = "beads_nvim-x9s",
  title = "beads.nvim v1",
  status = "open",
  priority = 1,
  issue_type = "epic",
  created_at = "2026-06-11T11:34:00Z",
  updated_at = "2026-06-11T11:34:00Z",
  dependency_count = 0,
  dependent_count = 5,
  comment_count = 0,
}

-- Shape of `bd show <id> --json` (single-element array in real output);
-- dependencies carry full issue objects plus dependency_type.
M.show_issue = {
  id = "beads_nvim-hcl",
  title = "Phase 2: render module + picker",
  status = "in_progress",
  priority = 2,
  issue_type = "task",
  assignee = "Tom Ford",
  description = "Build the telescope picker.\n\nWith filter cycling.",
  labels = { "ui", "telescope" },
  created_at = "2026-06-11T11:34:00Z",
  updated_at = "2026-06-11T12:00:00Z",
  dependencies = {
    {
      id = "beads_nvim-ay7",
      title = "Phase 1: scaffold",
      status = "open",
      priority = 2,
      issue_type = "task",
      created_at = "2026-06-11T11:34:00Z",
      updated_at = "2026-06-11T11:34:00Z",
      dependency_type = "blocks",
    },
  },
  dependency_count = 1,
  dependent_count = 1,
  comment_count = 0,
}

-- Sparse issue with most optional fields absent, exercising normalize defaults.
M.sparse_issue = {
  id = "beads_nvim-b8c",
  title = "Phase 5: polish",
}

-- Shape of `bd show <id> --json` for a child issue: the parent appears in
-- dependencies as a parent-child entry alongside ordinary blockers.
M.show_child_issue = {
  id = "beads_nvim-u2f.1",
  title = "labels: manage from detail view",
  status = "open",
  priority = 2,
  issue_type = "feature",
  created_at = "2026-06-11T13:07:33Z",
  updated_at = "2026-06-11T13:07:33Z",
  parent = "beads_nvim-u2f",
  dependencies = {
    {
      id = "beads_nvim-u2f",
      title = "beads.nvim v2",
      status = "in_progress",
      priority = 2,
      issue_type = "epic",
      dependency_type = "parent-child",
    },
    {
      id = "beads_nvim-ay7",
      title = "Phase 1: scaffold",
      status = "closed",
      priority = 2,
      issue_type = "task",
      dependency_type = "blocks",
    },
  },
  dependency_count = 1,
  dependent_count = 2,
  comment_count = 3,
}

-- Shape of `bd dep list <id> --direction=up --json`: full issue objects with
-- dependency_type; parent-child entries are children, others are blocked.
M.dependents = {
  {
    id = "beads_nvim-u2f.1.1",
    title = "subtask one",
    status = "open",
    priority = 2,
    issue_type = "task",
    dependency_type = "parent-child",
  },
  {
    id = "beads_nvim-zz1",
    title = "blocked downstream work",
    status = "blocked",
    priority = 1,
    issue_type = "feature",
    dependency_type = "blocks",
  },
}

return M
