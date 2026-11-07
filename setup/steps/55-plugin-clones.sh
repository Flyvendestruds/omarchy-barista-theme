#!/bin/bash
# Step 55 — plugin-clones: rebuild the barista.* shell plugin clones from the
# INSTALLED stock plugins, then re-apply the barista look (tabular figures,
# sentence-case labels, card shadows, gap-following OSD/toast margins, 3000K
# night light). Clones are frozen copies of upstream code, so after an
# `omarchy update` they must be regenerated or they drift out of step with
# the new shell (omarchy 4.5: 0px toast/OSD margins, empty theme picker).
# Hand-maintained forks (barista.reminders, barista.weather,
# barista.keyboard-rgb) are never touched — see MANAGED in barista-clones.py.
# Previous copies go to ~/.local/state/omarchy/barista/plugin-backups/<stamp>/.
# Run AFTER step 10 (shadow support is detected from the live BorderSurface).
# Idempotent. No sudo needed. Usage: $0 [apply|revert|check]
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$STEP_DIR/../files/plugin-clones/barista-clones.py"

if (( EUID == 0 )); then
  echo "plugin-clones: run as your user, not root (writes ~/.config/omarchy/plugins)" >&2
  exit 1
fi

case "${1:-apply}" in
  apply|revert|check) python3 "$GEN" "${1:-apply}";;
  *) echo "usage: $0 [apply|revert|check]" >&2; exit 1;;
esac
