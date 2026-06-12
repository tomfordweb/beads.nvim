#!/usr/bin/env bash
# Render the README demo GIF headlessly (E9). Builds the VHS recording image,
# seeds a throwaway demo bd DB from tests/fixtures/demo/ inside the container,
# and runs recording/beads.tape to produce assets/demo.gif.
#
#   recording/record.sh
#
# Re-recordable per Neovim version: the image installs whatever neovim the base
# Debian provides, so `docker build --no-cache` + re-run refreshes the asset.
# Hermetic: no host state leaks in except the repo (read-only-ish bind mount)
# and the host `bd` binary (bind-mounted; bd embeds Dolt, so nothing else is
# needed). Synthetic demo data only — no personal tracking on screen.
#
# Requires: docker, and `bd` on PATH (glibc binary, run on a glibc image).
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
IMAGE="beads-nvim-vhs"
BD_BIN="$(command -v bd)"

[ -n "$BD_BIN" ] || { echo "bd not on PATH" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker not installed" >&2; exit 1; }

echo "==> building $IMAGE"
docker build -t "$IMAGE" "$REPO/recording"

mkdir -p "$REPO/assets"

echo "==> seeding demo DB + recording (vhs)"
# One container run: seed /demo from the committed fixture, then render the tape
# with cwd=/demo so the plugin resolves /demo/.beads. The tape writes the GIF to
# /work/assets/demo.gif, which is the bind-mounted repo's assets/.
docker run --rm \
  -v "$REPO":/work \
  -v "$BD_BIN":/usr/local/bin/bd:ro \
  --entrypoint bash \
  "$IMAGE" -c '
    set -e
    mkdir -p /demo && cd /demo
    bd init >/dev/null 2>&1
    bd import /work/tests/fixtures/demo/issues.jsonl >/dev/null 2>&1
    bd show acme-web-1 >/dev/null 2>&1 || { echo "demo seed missing epic" >&2; exit 1; }
    vhs /work/recording/beads.tape
  '

echo "==> wrote $REPO/assets/demo.gif"
ls -lh "$REPO/assets/demo.gif"
