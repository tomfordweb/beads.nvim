#!/usr/bin/env bash
# Render the README demo + walkthrough GIFs headlessly (E9 + walkthroughs).
# Builds the VHS recording image and renders every tape against a FRESH
# throwaway demo bd DB (re-seeded per tape so journeys that mutate issues —
# create, status, edit — don't bleed into each other).
#
#   recording/record.sh                  # render all tapes
#   recording/record.sh browse status    # render only tapes/browse.tape + status.tape
#
# Outputs:
#   assets/demo.gif         (hero — recording/beads.tape)
#   assets/usage/<name>.gif (walkthroughs — recording/tapes/<name>.tape)
#
# Re-recordable per Neovim version (rebuild the image). Hermetic: only the repo
# and the host `bd` binary (bind-mounted; bd embeds Dolt) enter the container.
# Synthetic demo data only — nothing personal on screen.
#
# Requires: docker, and `bd` on PATH (glibc binary on a glibc image).
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
IMAGE="beads-nvim-vhs"
BD_BIN="$(command -v bd)"

[ -n "$BD_BIN" ] || { echo "bd not on PATH" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker not installed" >&2; exit 1; }

# Build the tape list. With no args: the hero demo + every tapes/*.tape.
# With args: just tapes/<arg>.tape for each arg.
TAPES=()
if [ "$#" -eq 0 ]; then
  TAPES+=("recording/beads.tape")
  for t in "$REPO"/recording/tapes/*.tape; do
    [ -e "$t" ] && TAPES+=("recording/tapes/$(basename "$t")")
  done
else
  for a in "$@"; do TAPES+=("recording/tapes/$a.tape"); done
fi

echo "==> building $IMAGE"
docker build -t "$IMAGE" "$REPO/recording"

mkdir -p "$REPO/assets/usage"

# Render every tape in one container; re-seed /demo before each so mutating
# journeys start clean. Each tape sets its own absolute Output under /work.
printf '%s\n' "${TAPES[@]}" | docker run --rm -i \
  -v "$REPO":/work \
  -v "$BD_BIN":/usr/local/bin/bd:ro \
  --entrypoint bash \
  "$IMAGE" -c '
    set -e
    while read -r tape; do
      echo "==> $tape"
      rm -rf /demo && mkdir -p /demo && cd /demo
      bd init >/dev/null 2>&1
      bd import /work/tests/fixtures/demo/issues.jsonl >/dev/null 2>&1
      bd show acme-web-1 >/dev/null 2>&1 || { echo "demo seed missing epic" >&2; exit 1; }
      vhs "/work/$tape"
    done
  '

echo "==> done"
ls -lh "$REPO"/assets/demo.gif "$REPO"/assets/usage/*.gif 2>/dev/null || true
