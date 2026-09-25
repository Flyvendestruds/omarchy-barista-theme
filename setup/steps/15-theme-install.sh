#!/bin/bash
# Step 15 — theme-install: copy both barista variants into the local theme
# dirs so `omarchy theme set barista` / `barista-dark` both work.
# Needed because `omarchy theme install <url>` clones this repo as ONE theme
# (named after the repo): the root files land in themes/barista, but
# barista-dark/ stays nested inside and Omarchy never looks there.
# This step copies barista-dark/ -> ~/.config/omarchy/themes/barista-dark/
# (theme files only; backgrounds/ is user-owned and never touched, so a
# custom night wallpaper survives re-runs).
# Idempotent. No sudo needed.
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$STEP_DIR/../.." && pwd)"
SRC="$REPO_ROOT/barista-dark"
DEST="$HOME/.config/omarchy/themes/barista-dark"

do_apply() {
  [[ -d "$SRC" ]] || { echo "theme-install: $SRC missing" >&2; return 1; }
  mkdir -p "$DEST/backgrounds"
  n=0
  for f in "$SRC"/colors.toml "$SRC"/shell.*.toml; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    if [[ -f "$DEST/$base" ]] && cmp -s "$f" "$DEST/$base"; then
      continue
    fi
    cp "$f" "$DEST/$base"
    echo "theme-install: $base"
    n=$((n+1))
  done
  echo "theme-install: $n file(s) in $DEST (backgrounds untouched)"
  echo "theme-install: applied (switch with: omarchy theme set barista-dark)"
}

do_revert() {
  if [[ -d "$DEST" ]]; then
    # Remove only files this step owns; keep backgrounds/ (user wallpaper).
    rm -f "$DEST"/colors.toml "$DEST"/shell.*.toml
    echo "theme-install: removed theme files from $DEST (backgrounds kept)"
  else
    echo "theme-install: $DEST absent, nothing to remove"
  fi
  echo "theme-install: reverted"
}

case "${1:-apply}" in
  apply) do_apply;;
  revert) do_revert;;
  *) echo "usage: $0 [apply|revert]" >&2; exit 1;;
esac
