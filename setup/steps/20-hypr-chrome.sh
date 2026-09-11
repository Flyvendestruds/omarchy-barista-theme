#!/bin/bash
# Step 20 — hypr-chrome: barista window chrome as gated lua modules.
# Installs four files into ~/.config/hypr/ and rewires hyprland.lua:
#   barista-gate.lua            theme predicate (all modules use it)
#   barista-looknfeel.lua       rounding/gaps/borders/anim (replaces my_theme_gen)
#   bar_gap.lua                 bar-aware gaps (gated)
#   single-window-no-border.lua single-window borders (gated)
# hyprland.lua surgery: my_theme_gen require -> barista-looknfeel require,
# plus requires for the other three. No sudo needed.
# Idempotent: re-runs sync changed files and ensure requires exactly once.
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$STEP_DIR/../.." && pwd)"
FILES="$REPO_ROOT/setup/files/hypr-chrome"
HYPR_DIR="${HOME}/.config/hypr"
HYPR_MAIN="$HYPR_DIR/hyprland.lua"

FILES_WANTED=(barista-gate.lua barista-looknfeel.lua single-window-no-border.lua bar_gap.lua)
REQUIRES_WANTED=(hypr.barista-looknfeel hypr.single-window-no-border hypr.bar_gap)
# legacy ungated entry this step used to install
LEGACY_REQUIRES=(hypr.my_theme_gen)

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
  local mod="$1"
  if grep -Eq "require\(['\"]${mod}['\"]\)" "$HYPR_MAIN"; then
    echo "hypr-chrome: require ${mod} already present"
    return 0
  fi
  [[ -f "$HYPR_MAIN" ]] || { echo "hypr-chrome: $HYPR_MAIN missing" >&2; return 1; }
  [[ ! -f "$HYPR_MAIN.bak-barista1" ]] && cp -n "$HYPR_MAIN" "$HYPR_MAIN.bak-barista1"
  if ! grep -q "barista: window chrome" "$HYPR_MAIN"; then
    printf '\n-- barista: window chrome (gated looknfeel, gaps, single-window borders).\n' >> "$HYPR_MAIN"
  fi
  printf 'require("%s")\n' "$mod" >> "$HYPR_MAIN"
  echo "hypr-chrome: added require ${mod}"
}

surgery_main() {
  # Replace the global my_theme_gen require with the gated barista module.
  # Matches: pcall(require, "hypr.my_theme_gen") with any quote/spacing.
  if grep -Eq "pcall\(require,[[:space:]]*['\"]hypr\.my_theme_gen['\"]\)" "$HYPR_MAIN"; then
    [[ ! -f "$HYPR_MAIN.bak-barista1" ]] && cp -n "$HYPR_MAIN" "$HYPR_MAIN.bak-barista1"
    sed -i -E "s|pcall\(require,[[:space:]]*['\"]hypr\.my_theme_gen['\"]\)|require(\"hypr.barista-looknfeel\")|" "$HYPR_MAIN"
    echo "hypr-chrome: my_theme_gen -> barista-looknfeel"
  fi
  # Comment above the old require names the generated file; keep history clean.
  sed -i "/my single-file theme (generated, last word on look'n'feel)/d" "$HYPR_MAIN" 2>/dev/null || true
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
  for mod in "${REQUIRES_WANTED[@]}" "${LEGACY_REQUIRES[@]}"; do
    if grep -Eq "require\(['\"]${mod}['\"]\)|pcall\(require,[[:space:]]*['\"]${mod}['\"]\)" "$HYPR_MAIN" 2>/dev/null; then
      sed -i "/require(\(['\"]\)${mod}\1)/d; /pcall(require,[[:space:]]*\(['\"]\)${mod}\1)/d; /-- barista: window chrome/d" "$HYPR_MAIN"
      echo "hypr-chrome: removed require ${mod}"
    fi
  done
  if [[ -f "$HYPR_MAIN.bak-barista1" ]] \
    && ! grep -Eq "require\(['\"]hypr\.(barista-looknfeel|single-window-no-border|bar_gap)['\"]\)" "$HYPR_MAIN"; then
    mv "$HYPR_MAIN.bak-barista1" "$HYPR_MAIN"
    echo "hypr-chrome: restored hyprland.lua"
  fi
}

case "${1:-apply}" in
  apply) install_files
    surgery_main
    for mod in "${REQUIRES_WANTED[@]}"; do ensure_require "$mod"; done
    echo "hypr-chrome: applied (reload hyprland to take effect: hyprctl reload)";;
  revert) revert_files; echo "hypr-chrome: reverted";;
  *) echo "usage: $0 [apply|revert]" >&2; exit 1;;
esac
