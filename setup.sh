#!/bin/bash
# Barista setup: applies everything under the umbrella that a theme install
# cannot carry (system QML patches, hypr lua modules, ...).
#   ./setup.sh          apply all steps (asks for sudo only for root steps)
#   ./setup.sh --step hypr-chrome        apply one step
#   ./setup.sh --revert                  revert all steps (reverse order)
#   ./setup.sh --revert --step shell-shadows
# Steps are idempotent; re-running is safe. Finish with: omarchy restart shell && hyprctl reload
set -euo pipefail
SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STEPS_ORDER=(shell-shadows hypr-chrome bar-gap theme-dev)
step_file() { case "$1" in
  shell-shadows) echo "$SETUP_ROOT/steps/10-shell-shadows.sh";;
  hypr-chrome)   echo "$SETUP_ROOT/steps/20-hypr-chrome.sh";;
  bar-gap)       echo "$SETUP_ROOT/steps/30-bar-gap.sh";;
  theme-dev)     echo "$SETUP_ROOT/steps/40-theme-dev.sh";;
  *) echo "unknown step: $1" >&2; exit 1;;
esac; }
step_needs_root() { [[ "$1" == "shell-shadows" ]]; }

MODE=apply
ONLY=""
while (( $# )); do
  case "$1" in
    --revert) MODE=revert; shift;;
    --step) ONLY="${2:?--step needs a name}"; shift 2;;
    -h|--help) sed -n '2,9p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

STEPS=()
if [[ -n "$ONLY" ]]; then STEPS=("$ONLY")
elif [[ "$MODE" == "revert" ]]; then STEPS=(theme-dev bar-gap hypr-chrome shell-shadows)
else STEPS=("${STEPS_ORDER[@]}"); fi

for step in "${STEPS[@]}"; do
  f="$(step_file "$step")"
  [[ -x "$f" ]] || chmod +x "$f"
  echo "### barista setup: $MODE $step"
  if step_needs_root "$step" && (( EUID != 0 )); then
    sudo "$f" "$MODE"
  else
    "$f" "$MODE"
  fi
done
echo "### barista setup: $MODE done."
echo "finish with: omarchy restart shell && hyprctl reload"
