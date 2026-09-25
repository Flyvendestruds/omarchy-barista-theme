#!/bin/bash
# Sync theme files from this repo into the local barista theme dirs.
# Dev workflow: edit in git, run this, tokens watcher pushes live.
# End users don't need this: `omarchy theme install <url>` stages the
# theme directly. Idempotent (copies only changed files).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sync_one() { # src_dir dest_dir
  local src="$1" dest="$2" n=0 f base
  mkdir -p "$dest"
  for f in "$src"/colors.toml "$src"/shell.*.toml; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    if [[ -f "$dest/$base" ]] && cmp -s "$f" "$dest/$base"; then
      continue
    fi
    cp "$f" "$dest/$base"
    echo "sync-theme: $dest/$base"
    n=$((n+1))
  done
  echo "sync-theme: $n file(s) updated in $dest"
}

sync_one "$REPO_ROOT" "$HOME/.config/omarchy/themes/barista"
sync_one "$REPO_ROOT/barista-dark" "$HOME/.config/omarchy/themes/barista-dark"
echo "tokens watcher pushes live on save; or run barista-tokens-apply."
