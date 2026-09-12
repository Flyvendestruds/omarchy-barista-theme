#!/bin/bash
# Step 70 — weather: optional barista weather add-on (own repo, standalone).
# Installs the barista.weather bar widget from
# https://github.com/Flyvendestruds/omarchy-barista-weather.git and enables it
# in place of stock omarchy.weather (clonedFrom restores stock on remove).
# Skipped automatically when barista.weather is already installed (e.g.
# added by hand); re-running pulls updates via `omarchy plugin update`.
# No sudo needed.
set -euo pipefail

PLUGIN_ID="barista.weather"
PLUGIN_URL="https://github.com/Flyvendestruds/omarchy-barista-weather.git"
PLUGINS_DIR="${HOME}/.config/omarchy/plugins"

do_apply() {
  if [[ -d "$PLUGINS_DIR/$PLUGIN_ID" ]]; then
    echo "weather: $PLUGIN_ID already installed"
    if [[ -d "$PLUGINS_DIR/$PLUGIN_ID/.git" ]]; then
      omarchy plugin update "$PLUGIN_ID" --yes \
        && echo "weather: updated" \
        || echo "weather: update failed (keeping installed copy)" >&2
    fi
  else
    omarchy plugin add "$PLUGIN_URL" --enable --yes
    echo "weather: installed + enabled"
  fi
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 \
    && echo "weather: enabled" \
    || echo "weather: already enabled"
  echo "weather: applied (finish with: omarchy restart shell)"
}

do_revert() {
  if [[ -d "$PLUGINS_DIR/$PLUGIN_ID" ]]; then
    omarchy plugin remove "$PLUGIN_ID" --yes \
      && echo "weather: removed (stock omarchy.weather takes its slot back)" \
      || echo "weather: remove failed" >&2
  else
    echo "weather: not installed, nothing to remove"
  fi
  echo "weather: reverted (finish with: omarchy restart shell)"
}

case "${1:-apply}" in
  apply) do_apply;;
  revert) do_revert;;
  *) echo "usage: $0 [apply|revert]" >&2; exit 1;;
esac
