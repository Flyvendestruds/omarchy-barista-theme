#!/bin/bash
# Step 30 — bar-gap: keep the Hyprland bar-side gap in sync with
# shell.json bar transparency, live.
# Installs: ~/.local/bin/barista-bar-gap-{sync,watch}, user systemd watcher
# service, post-boot + theme-set hooks.
# Why a watcher (not just bar_gap.lua at hypr load): shell.json transparency
# can change at runtime via `omarchy bar transparent`; the watcher re-syncs
# gaps without a hypr reload. Theme-tied because barista's transparent-bar
# look (gaps_out top = 0 floating over wallpaper) is part of the theme.
# Idempotent. No sudo needed.
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$STEP_DIR/../files/bar-gap"
BIN_DIR="${HOME}/.local/bin"
UNIT_DIR="${HOME}/.config/systemd/user"
HOOK_BOOT_DIR="${HOME}/.config/omarchy/hooks/post-boot.d"
HOOK_THEME_DIR="${HOME}/.config/omarchy/hooks/theme-set.d"
SERVICE="barista-bar-gap-watcher.service"

install_file() { # src dest (executable flag optional $3)
  local src="$1" dest="$2" exec="${3:-false}"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    echo "bar-gap: $(basename "$dest") up to date"
  else
    [[ -f "$dest" && ! -f "$dest.bak-barista1" ]] && cp -n "$dest" "$dest.bak-barista1"
    cp "$src" "$dest"
    [[ "$exec" == "exec" ]] && chmod +x "$dest"
    echo "bar-gap: installed $(basename "$dest")"
  fi
}

manage_unit() { # apply|revert
  if [[ "$1" == "apply" ]]; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable --now "$SERVICE" >/dev/null 2>&1 \
      && echo "bar-gap: $SERVICE enabled+started" \
      || echo "bar-gap: $SERVICE installed (start with: systemctl --user enable --now $SERVICE)"
  else
    systemctl --user disable --now "$SERVICE" >/dev/null 2>&1 || true
    echo "bar-gap: $SERVICE stopped+disabled"
  fi
}

do_apply() {
  install_file "$FILES/bin/barista-bar-gap-sync" "$BIN_DIR/barista-bar-gap-sync" exec
  install_file "$FILES/bin/barista-bar-gap-watch" "$BIN_DIR/barista-bar-gap-watch" exec
  install_file "$FILES/systemd/barista-bar-gap-watcher.service" "$UNIT_DIR/$SERVICE"
  install_file "$FILES/hooks/bar-gap-sync.hook" "$HOOK_BOOT_DIR/bar-gap-sync.hook" exec
  install_file "$FILES/hooks/theme-set-bar-gap-sync.hook" "$HOOK_THEME_DIR/bar-gap-sync.hook" exec
  manage_unit apply
  # legacy names from before the barista rename: stop+disable, leave files
  if systemctl --user is-enabled omarchy-bar-gap-watcher.service >/dev/null 2>&1; then
    systemctl --user disable --now omarchy-bar-gap-watcher.service >/dev/null 2>&1 || true
    echo "bar-gap: retired legacy omarchy-bar-gap-watcher.service"
  fi
  echo "bar-gap: applied"
}

do_revert() {
  manage_unit revert
  for pair in "$BIN_DIR/barista-bar-gap-sync" "$BIN_DIR/barista-bar-gap-watch" \
             "$UNIT_DIR/$SERVICE" \
             "$HOOK_BOOT_DIR/bar-gap-sync.hook" "$HOOK_THEME_DIR/bar-gap-sync.hook"; do
    if [[ -f "$pair.bak-barista1" ]]; then
      mv "$pair.bak-barista1" "$pair"; echo "bar-gap: restored $(basename "$pair")"
    else
      rm -f "$pair"; echo "bar-gap: removed $(basename "$pair")"
    fi
  done
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  echo "bar-gap: reverted"
}

case "${1:-apply}" in
  apply) do_apply;;
  revert) do_revert;;
  *) echo "usage: $0 [apply|revert]" >&2; exit 1;;
esac
