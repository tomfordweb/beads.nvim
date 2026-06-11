# Contributing to beads.nvim

Thanks for your interest in improving **beads.nvim**, the Neovim UI for the
[`bd`](https://github.com/gastownhall/beads) issue tracker. This guide covers
local setup, the test/lint expectations, and how changes land.

## Ground rules

- **All changes go through a pull request.** `main` is protected — no direct
  pushes or force-pushes (see [Branch protection](#branch-protection)).
- Keep PRs focused. One logical change per PR is easier to review than a
  grab-bag.
- Be kind. This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Local setup

You need:

- Neovim ≥ 0.10
- [`bd`](https://github.com/gastownhall/beads) on `$PATH` (only the integration
  suite needs it; unit tests run without it)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) and
  [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

The repo dogfoods beads for its own issue tracking. The live `.beads/` working
data is intentionally **not** committed (it is gitignored); tests use the
synthetic fixture under `tests/fixtures/demo/` instead.

## Running the tests

```sh
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

- Unit suites run without `bd`.
- The integration suite exercises a real `bd` binary against a throwaway
  database in a tmpdir and is **skipped** when `bd` is absent.
- Point `PLENARY_DIR` / `TELESCOPE_DIR` at your local checkouts if they are not
  at the default lazy.nvim paths.

Tests must always set an explicit `cwd` when invoking `bd` so they never walk up
into a real project's `.beads/`. The integration spec demonstrates the pattern.

## Formatting and linting

CI runs both; please run them before opening a PR.

```sh
stylua --check lua tests plugin     # formatting (config: stylua.toml)
luacheck lua tests plugin           # linting   (config: .luacheckrc)
```

`stylua lua tests plugin` (without `--check`) applies the formatting.

A `Makefile` wraps these for convenience: `make test`, `make fmt`,
`make fmt-check`, `make lint`, and `make check` (formatting check + lint +
tests, matching CI). Run `make help` for the full list.

## Documentation is single-source

User docs live in **`README.md`**. The Vim help file `doc/beads.txt` and the
GitHub Pages site are both generated from it by CI (panvimdoc + mkdocs-material)
— do not hand-edit `doc/beads.txt`. If your change affects behaviour, update
`README.md`; the docs workflow regenerates the rest.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <description>

<optional body>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.

## Pull request checklist

- [ ] Tests pass locally (`PlenaryBustedDirectory`)
- [ ] `stylua --check` and `luacheck` are clean
- [ ] `README.md` updated if behaviour or config changed
- [ ] No personal data, secrets, or real `.beads/` content in the diff

## Branch protection

`main` is protected on GitHub (configured in repo settings, not in-repo):

- Require a pull request before merging
- Require the `test`, `lint`, and `docs` status checks to pass
- Disallow force-pushes and direct pushes to `main`

Maintainers: enable these under **Settings → Branches → Branch protection
rules** before accepting external contributions.
