# rockerBOO/awesome-neovim — PR + GitHub topics

**Stage:** official (after feedback, repo public + green). Two parts: the
awesome-neovim list entry, and the GitHub repo topics that make **dotfyle**
auto-index the plugin.

---

## Part 1 — awesome-neovim list entry

**Target:** `README.md` in `rockerBOO/awesome-neovim`.
**Category:** `## Project` (project/workflow management). No beads entry exists
there yet. Entries are insertion-order within a category, not strictly
alphabetical — append to the category.

**Exact entry (match the house format: `- [owner/repo](url) - Description.`):**

```markdown
- [tomfordweb/beads.nvim](https://github.com/tomfordweb/beads.nvim) - Telescope UI for the `bd` dependency-aware issue tracker: filterable issue browser, floating detail view with dependency navigation, dependency graph, epics, change history, and an agent-memory browser. **(requires Neovim 0.10)**
```

Notes:
- Single line, ends with a period before the version annotation.
- The `**(requires Neovim X.X)**` suffix is the file's convention for a version
  floor — keep it (our floor is 0.10.0).
- If a maintainer prefers it under a different heading (e.g. a Git/issue
  category), defer to them.

**PR title:**

```
Add tomfordweb/beads.nvim under Project
```

**PR body:** one line — "Adds beads.nvim, a Telescope UI for the `bd` issue
tracker, under Project." awesome-neovim PRs are tiny by convention; the repo's
lint checks the entry format (alphabetized link check, trailing period), so
re-read CONTRIBUTING and run their lint expectations before submitting.

---

## Part 2 — GitHub repo topics (do this on the repo settings, not a PR)

dotfyle indexes any public repo tagged `neovim-plugin` (plus `neovim`/`nvim`).
Set these topics on `tomfordweb/beads.nvim`:

```
neovim, neovim-plugin, nvim, lua, telescope, issue-tracker, beads, bd, project-management
```

- `neovim-plugin` is the one dotfyle keys on — don't omit it.
- Once tagged + public, dotfyle picks it up automatically (no submission).

---

## Sequencing

1. awesome-neovim PR **after** the COMMUNITY_TOOLS PR is in (or at least after
   public + green) — keeps the story consistent.
2. Set GitHub topics at publish time (part of the repo-go-public checklist), so
   dotfyle indexing starts immediately.
