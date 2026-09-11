#!/bin/bash
# Applies in-shell QML shadows to omarchy-shell (option 2).
# Design: BorderSurface gains opt-in `shadow` (default false) + theme tokens
# on Style ([shadow] in shell.toml). Only top-level cards opt in; all nested
# controls, bar slabs, rows, tooltips stay flat automatically.
# Usage: sudo ./apply-shadows.sh   (backs up every file to <file>.bak-shadow1)
set -euo pipefail
SHELL_DIR="/usr/share/omarchy/shell"
THEME_TPL="/usr/share/omarchy/default/themed/shell.toml.tpl"
bak() { cp -n "$1" "$1.bak-shadow1" 2>/dev/null || true; }

echo "== 1. BorderSurface.qml (opt-in shadow plane) =="
bak "$SHELL_DIR/Ui/BorderSurface.qml"
python3 - <<'EOF'
import pathlib
p = pathlib.Path('/usr/share/omarchy/shell/Ui/BorderSurface.qml')
src = p.read_text()
assert 'RectangularShadow' not in src, "already patched?"
src = src.replace('import QtQuick\nimport qs.Commons',
                  'import QtQuick\nimport QtQuick.Effects\nimport qs.Commons', 1)
src = src.replace('''  readonly property bool usesOverlayBorder: Border.needsOverlay(borderSpec)''',
'''  // Opt-in drop shadow for top-level cards. Small controls, rows, bar
  // slabs and tooltips leave this false and stay flat.
  property bool shadow: false

  readonly property bool shadowActive: shadow && Style.shadowEnabled

  readonly property bool usesOverlayBorder: Border.needsOverlay(borderSpec)''', 1)
src = src.replace('''  border.width: Border.canUseNative(borderSpec) ? Border.uniformWidth(borderSpec) : 0
''',
'''  border.width: Border.canUseNative(borderSpec) ? Border.uniformWidth(borderSpec) : 0

  // Compositor-independent drop shadow. First child, negative z, so it
  // paints below the fill and tracks card geometry + radius.
  RectangularShadow {
    anchors.fill: parent
    z: -1
    visible: root.shadowActive
    offset.x: Style.shadowOffsetX
    offset.y: Style.shadowOffsetY
    color: Style.shadowColor
    blur: Style.shadowBlur
    radius: root.radius
    spread: Style.shadowSpread
  }
''', 1)
p.write_text(src)
print("BorderSurface patched")
EOF

echo "== 2. Style.qml (shadow tokens) =="
bak "$SHELL_DIR/Commons/Style.qml"
python3 - <<'EOF'
import pathlib
p = pathlib.Path('/usr/share/omarchy/shell/Commons/Style.qml')
src = p.read_text()
assert 'shadowOverrides' not in src, "already patched?"
src = src.replace('''  property int cornerRadius: 0
  property int gapsOut: 5
''',
'''  property int cornerRadius: 0
  property int gapsOut: 5

  // ---------------------------------------------------------- shadow tokens
  //
  // Compositor-independent drop-shadow tuning for top-level cards
  // (BorderSurface with shadow: true). Values come from shell.toml
  // [shadow]; see default/themed/shell.toml.tpl.
  property var shadowOverrides: ({})

  function shadowRawNum(key) {
    var n = Number(shadowOverrides[key])
    return isFinite(n) ? n : null
  }
  function shadowNum(key, fallback) {
    var n = shadowRawNum(key)
    return n === null ? fallback : n
  }
  function shadowAlpha(key, fallback) {
    return Util.clampAlpha(shadowNum(key, fallback))
  }

  readonly property bool shadowEnabled: boolToken(shadowOverrides["enabled"], true)
  readonly property color shadowBaseColor: resolveStateColor(
    String(shadowOverrides["color"] || "").length > 0 ? String(shadowOverrides["color"]) : "#000000",
    Color.foreground, Color.accent, Color.urgent, Qt.rgba(0, 0, 0, 1))
  readonly property color shadowColor: Util.alpha(shadowBaseColor, shadowAlpha("opacity", 0.45))
  readonly property real shadowBlur: Math.max(0, shadowNum("blur", 28))
  readonly property real shadowSpread: shadowNum("spread", 0)
  readonly property real shadowOffsetX: shadowNum("offset-x", 0)
  readonly property real shadowOffsetY: shadowNum("offset-y", 6)

  // Bleed room the blur needs around the card so the window does not clip
  // it. PopupCard grows its window by this; fullscreen overlays don't need it.
  readonly property int shadowMargin: shadowEnabled
    ? Math.ceil(shadowBlur + Math.max(Math.abs(shadowOffsetX), Math.abs(shadowOffsetY)))
    : 0
''', 1)
src = src.replace('''      } else if (section === "controls" || section === "style") {''',
'''      } else if (section === "shadow") {
        shadowOut[key] = raw
      } else if (section === "controls" || section === "style") {''', 1)
src = src.replace('''    var styleOut = {}
''', '''    var styleOut = {}
    var shadowOut = {}
''', 1)
src = src.replace('''    spacingOverrides = spacingOut
    styleOverrides = styleOut
''', '''    spacingOverrides = spacingOut
    styleOverrides = styleOut
    shadowOverrides = shadowOut
''', 1)
p.write_text(src)
print("Style patched")
EOF

echo "== 3. shell.toml.tpl ([shadow] defaults) =="
bak "$THEME_TPL"
if ! grep -q '^\[shadow\]' "$THEME_TPL"; then
cat >> "$THEME_TPL" <<'EOF'

[shadow]
# Compositor-independent card shadows (BorderSurface with shadow: true).
# enabled = false restores the flat look without touching QML.
enabled  = true
# Palette role (foreground, accent, ...) or hex. Alpha comes from opacity.
color    = "#000000"
opacity  = 0.45
# Blur radius in px; also drives Style.shadowMargin bleed.
blur     = 28
# Spread in px; 0 follows the card silhouette.
spread   = 0
offset-x = 0
offset-y = 6
EOF
echo "template appended"
else echo "template already has [shadow], skipping"; fi

echo "== 4. PopupCard (bleed window + opt in) =="
bak "$SHELL_DIR/Ui/PopupCard.qml"
python3 - <<'EOF'
import pathlib
p = pathlib.Path('/usr/share/omarchy/shell/Ui/PopupCard.qml')
src = p.read_text()
assert 'shadowMargin' not in src, "already patched?"
old = '''  property int margin: Style.gapsOut
'''
assert old in src
src = src.replace(old, '''  property int margin: Style.gapsOut
  // Transparent bleed around the card so the shadow never clips at the
  // window edge. The window grows with it, so anchor math stays consistent.
  readonly property int cardBleed: Style.shadowMargin
''', 1)
old = '''  implicitWidth: contentWidth
  implicitHeight: contentHeight
'''
assert old in src
src = src.replace(old, '''  implicitWidth: contentWidth + cardBleed * 2
  implicitHeight: contentHeight + cardBleed * 2
''', 1)
old = '''  BorderSurface {
    id: card
    anchors.fill: parent
    color: Color.popups.background
'''
assert old in src
src = src.replace(old, '''  BorderSurface {
    id: card
    anchors.fill: parent
    anchors.margins: cardBleed
    shadow: true
    color: Color.popups.background
''', 1)
p.write_text(src)
print("PopupCard patched")
EOF

echo "== 5. OSD (margin + opt in) =="
bak "$SHELL_DIR/plugins/osd/Osd.qml"
python3 - <<'EOF'
import pathlib
p = pathlib.Path('/usr/share/omarchy/shell/plugins/osd/Osd.qml')
src = p.read_text()
old = '      anchors.bottomMargin: Style.space(67)\n'
assert old in src, "osd margin not found"
if 'Style.shadowMargin' not in src:
    src = src.replace(old, '      anchors.bottomMargin: Style.space(67) + Style.shadowMargin\n', 1)
old = '''    BorderSurface {
      id: card
'''
assert old in src
if 'shadow: true' not in src:
    src = src.replace(old, '''    BorderSurface {
      id: card
      shadow: true
''', 1)
p.write_text(src)
print("OSD patched")
EOF

echo "== 6. Opt in top-level cards (menu, clipboard, emojis, keyboard, polkit, reminders, dialog, lock, notifications) =="
python3 - <<'EOF'
import pathlib, re
SHELL = pathlib.Path('/usr/share/omarchy/shell')
# file -> id line that marks the top-level card block to opt in
targets = {
    'plugins/menu/Menu.qml': 'id: card',
    'plugins/clipboard/Clipboard.qml': 'id: card',
    'plugins/emojis/Emojis.qml': 'id: card',
    'Ui/KeyboardPanel.qml': 'id: card',
    'plugins/polkit/PolkitAgent.qml': 'id: card',
    'plugins/reminders/ReminderFlow.qml': 'id: card',
    'Ui/ConfirmDialog.qml': 'id: card',
    'plugins/lock/LockView.qml': 'id: inputField',
    'plugins/notifications/components/NotificationCard.qml': 'id: root',
}
for rel, idline in targets.items():
    p = SHELL/rel
    bak = str(p) + '.bak-shadow1'
    pathlib.Path(bak).write_bytes(p.read_bytes()) if not pathlib.Path(bak).exists() else None
    lines = p.read_text().splitlines(keepends=True)
    out, done = [], False
    for i, ln in enumerate(lines):
        out.append(ln)
        if not done and ln.strip() == idline:
            ahead = ''.join(lines[i+1:i+6])
            if 'shadow' not in ahead:
                ind = ln[:len(ln)-len(ln.lstrip())]
                out.append(f'{ind}shadow: true\n')
                done = True
    assert done, f"no block opted in for {rel}"
    p.write_text(''.join(out))
    print(f"opted in: {rel}")
EOF

echo "== 7. Menu height clamp (leave room for shadow bleed) =="
python3 - <<'EOF'
import pathlib
p = pathlib.Path('/usr/share/omarchy/shell/plugins/menu/Menu.qml')
src = p.read_text()
old = 'height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)'
assert old in src, "menu height expr not found"
if 'shadowMargin' not in src:
    src = src.replace(old,
        'height: Math.min(root.cardHeight, panel.height - Style.gapsOut - Style.shadowMargin - panel.effectiveCardTop)', 1)
    p.write_text(src)
    print("Menu clamp patched")
else:
    print("Menu clamp already patched")
EOF
echo "done. backups: *.bak-shadow1"
