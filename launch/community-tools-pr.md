# gastownhall/beads — COMMUNITY_TOOLS.md PR

**Stage:** official. **Do not open until the repo is public, CI is green, and
`:help beads` works** (the file's own note expects working `bd`-CLI tools).

**Target file:** `docs/COMMUNITY_TOOLS.md` in `gastownhall/beads`.
**Section:** `## Editor Extensions`.
**Placement:** the list is "Ranked by activity and maturity" — add at the end of
Editor Extensions (a brand-new entry); maintainers may re-rank.

> ⚠️ **Fact-check before posting:** the plan/branding note referenced
> `joeblubaugh/nvim-beads`, but the live COMMUNITY_TOOLS Editor Extensions list
> actually contains **`fancypantalons/nvim-beads`** (and several VS Code
> extensions, incl. "Lista Beads"). There may be more than one `nvim-beads`.
> Verify the current contents at PR time and position beside whatever is
> actually there. Do not knock any of them.

---

## Exact entry (match the file's format precisely)

```markdown
- **[beads.nvim](https://github.com/tomfordweb/beads.nvim)** - Neovim plugin with a Telescope picker (live status/priority/type/label filtering), a floating detail view with in-place dependency navigation, a linked-issues sidebar, epic children/status, a dependency graph, change history, a command palette of `bd` diagnostics, and an agent-memory browser. Uses the `bd` CLI. Built by [@tomfordweb](https://github.com/tomfordweb). (Lua)
```

*(Single description line, leading `- `, bold linked name, ` - ` separator,
"Uses the `bd` CLI.", "Built by [@handle](url).", trailing `(Lua)` — exactly the
house style. Trim if maintainers prefer shorter; keep the `bd` CLI credit.)*

---

## PR title

```
docs: add beads.nvim to Community Tools (Editor Extensions)
```

## PR body scaffold

- **What:** Adds `beads.nvim`, a Neovim UI for `bd`, under Editor Extensions.
- **Why it qualifies:** Uses the `bd` CLI for all data access (`bd list --json`,
  `bd show`, etc.) — no direct Dolt or legacy `.beads/issues.jsonl` reads.
- **Status:** Public, CI green on Neovim 0.10–nightly, `:help beads` + Pages
  docs live.
- [owner: one friendly sentence — happy to adjust the blurb/placement.]

## Etiquette checklist

- [ ] Repo is public + CI green + `:help beads` works.
- [ ] Entry credits the `bd` CLI (it does).
- [ ] No comparison to / disparagement of `nvim-beads` or any other listed tool.
- [ ] Format matches sibling entries exactly (re-read the live file first).
- [ ] One small, focused PR — just the one line.
