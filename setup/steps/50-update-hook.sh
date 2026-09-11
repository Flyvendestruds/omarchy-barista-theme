#!/bin/bash
# Step 50 — update-hook: re-apply root-owned patches after `omarchy update`.
# Installs a post-update.d hook that re-runs step 10 (shell-shadows) against
# the local clone and notifies. User-owned, no sudo. Idempotent.
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$STEP_DIR/../files/update-hook"
HOOK_DIR="${HOME}/.config/omarchy/hooks/post-update.d"
HOOK="barista-setup.hook"

do_apply() {
  mkdir -p "$HOOK_DIR"
  if [[ -f "$HOOK_DIR/$HOOK" ]] && cmp -s "$FILES/$HOOK" "$HOOK_DIR/$HOOK"; then
    echo "update-hook: $HOOK up to date"
  else
    [[ -f "$HOOK_DIR/$HOOK" && ! -f "$HOOK_DIR/$HOOK.bak-barista1" ]] \
      && cp -n "$HOOK_DIR/$HOOK" "$HOOK_DIR/$HOOK.bak-barista1"
    cp "$FILES/$HOOK" "$HOOK_DIR/$HOOK"
    chmod +x "$HOOK_DIR/$HOOK"
    echo "update-hook: installed $HOOK"
  fi
  echo "update-hook: applied"
}

do_revert() {
  if [[ -f "$HOOK_DIR/$HOOK.bak-barista1" ]]; then
    mv "$HOOK_DIR/$HOOK.bak-barista1" "$HOOK_DIR/$HOOK"
    echo "update-hook: restored $HOOK"
  else
    rm -f "$HOOK_DIR/$HOOK"
    echo "update-hook: removed $HOOK"
  fi
  echo "update-hook: reverted"
}

case "${1:-apply}" in
  apply) do_apply;;
  revert) do_revert;;
  *) echo "usage: $0 [apply|revert]" >&2; exit 1;;
esac
