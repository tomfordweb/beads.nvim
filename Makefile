# Developer convenience targets. These mirror what CI runs (lint.yml, test.yml)
# so `make check` locally matches the pipeline. Requires: nvim, stylua, luacheck
# (and a plenary.nvim checkout for the tests — point PLENARY_DIR at it if it is
# not at the default lazy.nvim path).

LUA_PATHS := lua tests plugin

.PHONY: help test fmt fmt-check lint check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

test: ## Run the headless plenary test suite
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"

fmt: ## Apply stylua formatting in place
	stylua $(LUA_PATHS)

fmt-check: ## Check stylua formatting (no writes)
	stylua --check $(LUA_PATHS)

lint: ## Run luacheck (falls back to the CI-pinned docker image when not installed)
	@if command -v luacheck >/dev/null 2>&1; then \
		luacheck $(LUA_PATHS); \
	else \
		docker run --rm -v "$(CURDIR)":/data -w /data ghcr.io/lunarmodules/luacheck:v1.2.0 $(LUA_PATHS); \
	fi

check: fmt-check lint test ## Run formatting check, lint, and tests (CI parity)
