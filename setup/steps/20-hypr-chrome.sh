#!/bin/bash
# Step 20 — hypr-chrome: single-window borders + bar-aware gaps.
# Installs two lua modules into ~/.config/hypr/ and wires the require lines
# into hyprland.lua (user-owned files, no sudo needed).
# Idempotent: re-runs copy changed files and ensure requires exactly once.
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$STEP_DIR/../.." && pwd)"
FILES="$REPO_ROOT/setup/files/hypr-chrome"
HYPR_DIR="${HOME}/.config/hypr"
HYPR_MAIN="$HYPR_DIR/hyprland.lua"

FILES_WANTED=(single-window-no-border.lua bar_gap.lua)
REQUIRES_WANTED=(hypr.single-window-no-border hypr.bar_gap)

install_files() {
  mkdir -p "$HYPR_DIR"
  for f in "${FILES_WANTED[@]}"; do
    if [[ -f "$HYPR_DIR/$f" ]] && cmp -s "$FILES/$f" "$HYPR_DIR/$f"; then
      echo "hypr-chrome: $f up to date"
    else
      [[ -f "$HYPR_DIR/$f" && ! -f "$HYPR_DIR/$f.bak-barista1" ]] \
        && cp -n "$HYPR_DIR/$f" "$HYPR_DIR/$f.bak-barista1"
      cp "$FILES/$f" "$HYPR_DIR/$f"
      echo "hypr-chrome: installed $f"
    fi
  done
}

ensure_require() {
  local mod="$1" dotted="${1//-/_}"
  # match require("hypr.x") / require('hypr.x') with any spacing
  if grep -Eq "require\(['\"]${mod}['\"]\)" "$HYPR_MAIN"; then
    echo "hypr-chrome: require ${mod} already present"
    return 0
  fi
  [[ -f "$HYPR_MAIN" ]] || { echo "hypr-chrome: $HYPR_MAIN missing" >&2; return 1; }
  [[ ! -f "$HYPR_MAIN.bak-barista1" ]] && cp -n "$HYPR_MAIN" "$HYPR_MAIN.bak-barista1"
  if ! grep -q "barista: window chrome" "$HYPR_MAIN"; then
    printf '\n-- barista: window chrome (single-window borders, bar-aware gaps).\n' >> "$HYPR_MAIN"
  fi
  printf 'require("%s")\n' "$mod" >> "$HYPR_MAIN"
  echo "hypr-chrome: added require ${mod}"
}

revert_files() {
  for f in "${FILES_WANTED[@]}"; do
    if [[ -f "$HYPR_DIR/$f.bak-barista1" ]]; then
      mv "$HYPR_DIR/$f.bak-barista1" "$HYPR_DIR/$f"
      echo "hypr-chrome: restored $f"
    else
      rm -f "$HYPR_DIR/$f"
      echo "hypr-chrome: removed $f"
    fi
  done
  for mod in "${REQUIRES_WANTED[@]}"; do
    if grep -Eq "require\(['\"]${mod}['\"]\)" "$HYPR_MAIN" 2>/dev/null; then
      sed -i "/require(\(['\"]\)${mod}\1)/d; /-- barista: window chrome/d" "$HYPR_MAIN"
      echo "hypr-chrome: removed require ${mod}"
    fi
  done
  if [[ -f "$HYPR_MAIN.bak-barista1" ]] \
    && ! grep -Eq "require\(['\"]hypr\.(single-window-no-border|bar_gap)['\"]\)" "$HYPR_MAIN"; then
    mv "$HYPR_MAIN.bak-barista1" "$HYPR_MAIN"
    echo "hypr-chrome: restored hyprland.lua"
  fi
}

case "${1:-apply}" in
  apply) install_files
    for mod in "${REQUIRES_WANTED[@]}"; do ensure_require "$mod"; done
    echo "hypr-chrome: applied (reload hyprland to take effect: hyprctl reload)";;
  revert) revert_files; echo "hypr-chrome: reverted";;
  *) echo "usage: $0 [apply|revert]" >&2; exit 1;;
esac
