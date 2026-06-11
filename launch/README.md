# launch/ — pre-launch scaffolds

Working drafts for taking **beads.nvim** public. These are **scaffolds only**
— outlines, hooks, talking points, and exact PR/listing text. You write the
final prose in your own voice; nothing here is meant to be posted verbatim
(except the listing entries explicitly marked *exact text*, which still want a
once-over).

## Files

| File | Stage | What it is |
|------|-------|------------|
| [`blurb.md`](blurb.md) | source | The one-paragraph "what it is" + canonical feature bullets every post reuses. Single source — edit here, copy out. Plus the screenshot/asciinema shot list. |
| [`reddit-rneovim.md`](reddit-rneovim.md) | feedback | r/neovim "I built X" post scaffold. |
| [`discord-blurb.md`](discord-blurb.md) | feedback | Short share for Neovim show-and-tell / plugins channels. |
| [`medium-post.md`](medium-post.md) | feedback | Long-form post outline + section hooks. |
| [`discussion-276-comment.md`](discussion-276-comment.md) | official | Comment scaffold for Beads Discussion #276 "Beads UI — make your pick". |
| [`community-tools-pr.md`](community-tools-pr.md) | official | Exact entry + PR text for `gastownhall/beads` `docs/COMMUNITY_TOOLS.md`. |
| [`awesome-neovim-entry.md`](awesome-neovim-entry.md) | official | Exact entry + PR text for `rockerBOO/awesome-neovim`, plus GitHub topics for dotfyle. |

## Sequencing (do not skip)

1. **Feedback pass first** — only after the repo is **public, CI green, and
   `:help beads` works**. Post reddit / discord / medium, gather feedback,
   iterate.
2. **Official listings second** — only once feedback is incorporated and it's
   stable. Discussion #276 → COMMUNITY_TOOLS PR → awesome-neovim PR.

## Ground rules baked into every draft

- **Credit the official project.** Link `gastownhall/beads`; beads.nvim is a
  UI *for* `bd`, not a fork of it.
- **No disparagement of `joeblubaugh/nvim-beads`.** It holds the `beads`
  luarocks name and is already in COMMUNITY_TOOLS. We differentiate by repo
  name (`beads.nvim` ≠ `nvim-beads`) and by depth of UI — never by knocking it.
- **No PII.** Public copy uses the repo/handle, links, and screenshots — not a
  personal email or full name beyond the LICENSE.

> This directory is a working artifact, not part of the shipped plugin. Decide
> at publish time whether to keep it in the scrubbed launch commit or drop it.
