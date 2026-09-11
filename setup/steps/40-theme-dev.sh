#!/bin/bash
# Step 40 — theme-dev: live-edit loop for the barista theme itself.
# Installs: ~/.local/bin/barista-tokens-apply + systemd path/service units
# that re-render shell.toml and push it to the running shell on every save.
# Dev-only: end users get the finished theme via `omarchy theme install`
# and never need this. Safe to skip on a fresh machine.
# Idempotent. No sudo needed.
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$STEP_DIR/../files/theme-dev"
BIN="$HOME/.local/bin/barista-tokens-apply"
UNIT_DIR="$HOME/.config/systemd/user"
PATH_UNIT="barista-tokens-watcher.path"
SVC_UNIT="barista-tokens-watcher.service"

do_apply() {
  mkdir -p "$(dirname "$BIN")" "$UNIT_DIR"
  if [[ -f "$BIN" ]] && cmp -s "$FILES/barista-tokens-apply" "$BIN"; then
    echo "theme-dev: barista-tokens-apply up to date"
  else
    [[ -f "$BIN" && ! -f "$BIN.bak-barista1" ]] && cp -n "$BIN" "$BIN.bak-barista1"
    cp "$FILES/barista-tokens-apply" "$BIN"
    chmod +x "$BIN"
    echo "theme-dev: installed barista-tokens-apply"
  fi
  for u in "$PATH_UNIT" "$SVC_UNIT"; do
    if [[ -f "$UNIT_DIR/$u" ]] && cmp -s "$FILES/$u" "$UNIT_DIR/$u"; then
      echo "theme-dev: $u up to date"
    else
      [[ -f "$UNIT_DIR/$u" && ! -f "$UNIT_DIR/$u.bak-barista1" ]] \
        && cp -n "$UNIT_DIR/$u" "$UNIT_DIR/$u.bak-barista1"
      cp "$FILES/$u" "$UNIT_DIR/$u"
      echo "theme-dev: installed $u"
    fi
  done
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now "$PATH_UNIT" >/dev/null 2>&1 \
    && echo "theme-dev: $PATH_UNIT enabled+started" \
    || echo "theme-dev: installed (start with: systemctl --user enable --now $PATH_UNIT)"
  echo "theme-dev: applied"
}

do_revert() {
  systemctl --user disable --now "$PATH_UNIT" >/dev/null 2>&1 || true
  for f in "$BIN" "$UNIT_DIR/$PATH_UNIT" "$UNIT_DIR/$SVC_UNIT"; do
    if [[ -f "$f.bak-barista1" ]]; then
      mv "$f.bak-barista1" "$f"; echo "theme-dev: restored $(basename "$f")"
    else
      rm -f "$f"; echo "theme-dev: removed $(basename "$f")"
    fi
  done
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  echo "theme-dev: reverted"
}

case "${1:-apply}" in
  apply) do_apply;;
  revert) do_revert;;
  *) echo "usage: $0 [apply|revert]" >&2; exit 1;;
esac
