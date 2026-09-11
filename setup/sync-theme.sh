#!/bin/bash
# Sync theme files from this repo into the local barista theme dir.
# Dev workflow: edit in git, run this, tokens watcher pushes live.
# End users don't need this: `omarchy theme install <url>` stages the
# theme directly. Idempotent (copies only changed files).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_DIR="$HOME/.config/omarchy/themes/barista"

mkdir -p "$THEME_DIR"
n=0
for f in "$REPO_ROOT"/colors.toml "$REPO_ROOT"/shell.*.toml; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"
  if [[ -f "$THEME_DIR/$base" ]] && cmp -s "$f" "$THEME_DIR/$base"; then
    continue
  fi
  cp "$f" "$THEME_DIR/$base"
  echo "sync-theme: $base"
  n=$((n+1))
done
echo "sync-theme: $n file(s) updated in $THEME_DIR"
echo "tokens watcher pushes live on save; or run barista-tokens-apply."
