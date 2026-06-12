# Headless recording image for the README demo GIF (E9).
#
# Builds on the official VHS image (ttyd + ffmpeg + a headless terminal) and
# adds just enough to run the real plugin: Neovim plus its runtime deps
# (plenary, telescope). `bd` and the repo are bind-mounted at run time by
# record.sh so the image carries no project code or binaries and never goes
# stale — re-recording per Neovim version only means rebuilding this layer.
FROM ghcr.io/charmbracelet/vhs:latest

ENV DEBIAN_FRONTEND=noninteractive

# Neovim: install the official *stable* tarball, not Debian's neovim — current
# telescope.nvim requires >= 0.11 and trixie still ships 0.10.x. git fetches the
# two Lua deps; telescope is pinned to a release tag for reproducible re-records.
# build-essential: nvim-treesitter compiles the markdown parsers from source at
# image-build time (TSInstallSync below), so a C/C++ toolchain must be present.
RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates curl xz-utils build-essential \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSL -o /tmp/nvim.tar.gz \
       https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz \
  && tar -C /opt -xzf /tmp/nvim.tar.gz && rm /tmp/nvim.tar.gz \
  && ln -s /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim \
  && git clone --depth 1 https://github.com/nvim-lua/plenary.nvim /deps/plenary.nvim \
  && git clone --depth 1 --branch 0.1.8 https://github.com/nvim-telescope/telescope.nvim /deps/telescope.nvim \
  # Optional UI enhancers — recorded so the README GIFs show the recommended
  # experience (bordered modal selects/inputs + toast notifications). These are
  # documented as optional in the README, never runtime deps of the plugin.
  && git clone --depth 1 https://github.com/stevearc/dressing.nvim /deps/dressing.nvim \
  && git clone --depth 1 https://github.com/rcarriga/nvim-notify /deps/nvim-notify \
  # master branch: stable TSInstallSync command + require('nvim-treesitter.configs').setup
  # API that recording/init.lua uses (the new `main` rewrite dropped both).
  && git clone --depth 1 --branch master https://github.com/nvim-treesitter/nvim-treesitter /deps/nvim-treesitter

# Compile the markdown parsers into the nvim-treesitter checkout now, so the
# detail / edit buffers (filetype=markdown) get real treesitter highlighting on
# camera without a first-run :TSInstall. Headless, parsers persist in the image.
RUN nvim --headless \
      --cmd 'set rtp^=/deps/nvim-treesitter' \
      -c 'runtime! plugin/nvim-treesitter.lua' \
      -c 'TSInstallSync markdown markdown_inline' \
      -c 'quitall' \
  && test -f /deps/nvim-treesitter/parser/markdown.so

# Where record.sh bind-mounts the repo; the tape and init.lua reference /work.
WORKDIR /work
