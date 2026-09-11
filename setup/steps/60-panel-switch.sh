#!/bin/bash
# Step 60 — panel-switch: one-click switching between bar popouts.
# Problem: every cloned (barista.*) widget only sees its OWN bar button
# through PluginBarApi — Bar.qml scopes clickTargets per plugin
# (pluginClickTargets). KeyboardPanel's dismiss overlay forwards bar clicks
# via that scoped list, so with panel A open, clicking widget B's icon finds
# no target, falls through to root.close(), and the user must click B again.
# Fix (3 hunks, all idempotent, revert via .bak-barista2):
#   1. Ui/PluginBarApi.qml: new `allClickTargets` (full, unscoped list).
#      The existing scoped `clickTargets` is left untouched.
#   2. plugins/bar/Bar.qml: publish the full list into it on every sync
#      (syncPluginBarApiObjects already runs on clickTargets changes).
#   3. Ui/KeyboardPanel.qml: pressTargetAt prefers the full list (falls back
#      to the scoped one), and the dismiss overlay forwards bar clicks at any
#      time — stock only forwarded during the brief Exclusive focus prime, so
#      every post-prime click on another widget merely dismissed (2nd click
#      needed to open).
# System files: must run as root (sudo). Backs up every file to
# *.bak-barista2 (own suffix, so step 10's .bak-barista1 backups — including
# KeyboardPanel.qml's shadow opt-in — are never touched).
# Idempotent: skips hunks already applied. Usage: $0 [apply|revert].
set -euo pipefail
SHELL_DIR="${SHELL_DIR:-/usr/share/omarchy/shell}"
BAK_SUFFIX=".bak-barista2"
bak() { cp -n "$1" "$1$BAK_SUFFIX" 2>/dev/null || true; }

MODE="${1:-apply}"
if [[ "$MODE" == "revert" ]]; then
  n=0
  while IFS= read -r f; do
    mv "$f" "${f%$BAK_SUFFIX}"; n=$((n+1)); echo "panel-switch: restored ${f%$BAK_SUFFIX}"
  done < <(find "$SHELL_DIR" -name "*$BAK_SUFFIX" 2>/dev/null)
  echo "panel-switch: reverted $n files"
  exit 0
fi
[[ "$MODE" == "apply" ]] || { echo "usage: $0 [apply|revert]" >&2; exit 1; }
# Scratch-dir runs (SHELL_DIR overridden, e.g. tests) skip the root gate —
# only the real system path needs sudo.
if [[ "$SHELL_DIR" == "/usr/share/omarchy/shell" ]] && (( EUID != 0 )); then echo "panel-switch: must run as root (sudo)" >&2; exit 1; fi

echo "== 1. PluginBarApi.qml (full target list) =="
bak "$SHELL_DIR/Ui/PluginBarApi.qml"
python3 - <<'EOF'
import os, pathlib
p = pathlib.Path(os.environ.get("SHELL_DIR", "/usr/share/omarchy/shell")) / "Ui/PluginBarApi.qml"
src = p.read_text()
old = """  property var activePopout: null
  property var clickTargets: []
"""
new = """  property var activePopout: null
  property var clickTargets: []
  // barista: one-click panel switch — full bar target list (unscoped).
  // clickTargets above stays scoped to this plugin; KeyboardPanel prefers
  // this when present so a bar click reaches a *different* widget's button
  // while this panel's overlay is up.
  property var allClickTargets: []
"""
if "property var allClickTargets" in src:
    print("PluginBarApi: allClickTargets present, skipping")
elif old in src:
    p.write_text(src.replace(old, new, 1))
    print("PluginBarApi patched")
else:
    raise SystemExit("PluginBarApi: anchor not found (upstream changed?)")
EOF

echo "== 2. Bar.qml (publish full list) =="
bak "$SHELL_DIR/plugins/bar/Bar.qml"
python3 - <<'EOF'
import os, pathlib
p = pathlib.Path(os.environ.get("SHELL_DIR", "/usr/share/omarchy/shell")) / "plugins/bar/Bar.qml"
src = p.read_text()
old = """    api.clickTargets = root.pluginClickTargets(api.pluginId)
    api.layoutConfig = root.publicLayoutConfig()"""
new = """    api.clickTargets = root.pluginClickTargets(api.pluginId)
    // barista: one-click panel switch — full list for cross-widget
    // forwarding. Runs on every sync (incl. onClickTargetsChanged).
    api.allClickTargets = root.clickTargets.slice()
    api.layoutConfig = root.publicLayoutConfig()"""
if "api.allClickTargets = root.clickTargets.slice()" in src:
    print("Bar: publish present, skipping")
elif old in src:
    p.write_text(src.replace(old, new, 1))
    print("Bar patched")
else:
    raise SystemExit("Bar: anchor not found (upstream changed?)")
EOF

echo "== 3. KeyboardPanel.qml (forward across widgets) =="
bak "$SHELL_DIR/Ui/KeyboardPanel.qml"
python3 - <<'EOF'
import os, pathlib
p = pathlib.Path(os.environ.get("SHELL_DIR", "/usr/share/omarchy/shell")) / "Ui/KeyboardPanel.qml"
src = p.read_text()
changed = False

old_guard = "      if (!root.anchorWindow || !root.anchorWindow.contentItem || !root.bar || !root.bar.clickTargets) return null\n      var p = barPoint(px, py)\n      var targets = root.bar.clickTargets\n"
new_guard = ("      // barista: one-click panel switch — prefer the full target list so a\n"
             "      // click on a *different* widget forwards to its button instead of\n"
             "      // merely dismissing this panel. Falls back to the scoped list.\n"
             "      if (!root.anchorWindow || !root.anchorWindow.contentItem || !root.bar) return null\n"
             "      var p = barPoint(px, py)\n"
             "      var targets = root.bar.allClickTargets || root.bar.clickTargets\n"
             "      if (!targets) return null\n")
if "root.bar.allClickTargets || root.bar.clickTargets" in src:
    print("KeyboardPanel: target lookup present, skipping")
elif old_guard in src:
    src = src.replace(old_guard, new_guard, 1)
    changed = True
    print("KeyboardPanel: target lookup patched")
else:
    raise SystemExit("KeyboardPanel: pressTargetAt anchor not found (upstream changed?)")

old_click = ("    onClicked: function(mouse) {\n"
             "      // While Exclusive is priming, Hyprland may route a click from another\n"
             "      // output here with translated coordinates. Never interpret that as a\n"
             "      // click on this output's bar.\n"
             "      if (root.focusPrimed && inBarRegion(mouse.x, mouse.y) && forwardBarClick(mouse.x, mouse.y, mouse.button)) return\n"
             "      root.close()\n"
             "    }")
new_click = ("    onClicked: function(mouse) {\n"
             "      // barista: one-click panel switch — forward bar clicks regardless of\n"
             "      // focus-prime state. Stock only forwarded during the brief Exclusive\n"
             "      // prime, so every post-prime click on another widget merely closed\n"
             "      // this panel and the new one needed a second click. If the click\n"
             "      // did not hand ownership to a sibling popout (plain button, not a\n"
             "      // panel), fall through to dismiss — the click was still consumed.\n"
             "      if (inBarRegion(mouse.x, mouse.y) && forwardBarClick(mouse.x, mouse.y, mouse.button)) {\n"
             "        if (bar && bar.activePopout === coordinatorKey) root.close()\n"
             "        return\n"
             "      }\n"
             "      root.close()\n"
             "    }")
if "barista: one-click panel switch — forward bar clicks regardless of" in src:
    print("KeyboardPanel: click forwarding present, skipping")
elif old_click in src:
    src = src.replace(old_click, new_click, 1)
    changed = True
    print("KeyboardPanel: click forwarding patched")
else:
    raise SystemExit("KeyboardPanel: onClicked anchor not found (upstream changed?)")

p.write_text(src)
print("KeyboardPanel patched" if changed else "KeyboardPanel already patched")
EOF
echo "panel-switch: done."
