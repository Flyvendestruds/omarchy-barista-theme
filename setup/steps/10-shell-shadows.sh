#!/bin/bash
# Step 10 — shell-shadows: compositor-independent card shadows in omarchy-shell.
# Design: BorderSurface gains opt-in `shadow` (default false) + theme tokens
# on Style ([shadow] in shell.toml). Only top-level cards opt in; all nested
# controls, bar slabs, rows, tooltips stay flat automatically.
# System files: must run as root (sudo). Backs up every file to *.bak-barista1.
# Idempotent: skips hunks already applied. Usage: $0 [apply|revert].
set -euo pipefail
SHELL_DIR="/usr/share/omarchy/shell"
THEME_TPL="/usr/share/omarchy/default/themed/shell.toml.tpl"
BAK_SUFFIX=".bak-barista1"
bak() { cp -n "$1" "$1$BAK_SUFFIX" 2>/dev/null || true; }

MODE="${1:-apply}"
if [[ "$MODE" == "revert" ]]; then
  n=0
  for f in $(find "$SHELL_DIR" /usr/share/omarchy/default/themed -name "*$BAK_SUFFIX" 2>/dev/null); do
    mv "$f" "${f%$BAK_SUFFIX}"; n=$((n+1)); echo "shell-shadows: restored ${f%$BAK_SUFFIX}"
  done
  echo "shell-shadows: reverted $n files"
  exit 0
fi
[[ "$MODE" == "apply" ]] || { echo "usage: $0 [apply|revert]" >&2; exit 1; }
if (( EUID != 0 )); then echo "shell-shadows: must run as root (sudo)" >&2; exit 1; fi

echo "== 1. BorderSurface.qml (sibling shadow) =="
bak "$SHELL_DIR/Ui/BorderSurface.qml"
python3 - <<'EOF'
import pathlib
p = pathlib.Path('/usr/share/omarchy/shell/Ui/BorderSurface.qml')
src = p.read_text()
# Migrate: drop the MultiEffect layer implementation. A layer effect renders
# the WHOLE card subtree into an offscreen texture first — including text and
# icons — so the shadow pass picks up every glyph's alpha and the text looks
# embossed/shadowed. The sibling RectangularShadow below shadows only the
# card's rounded-rectangle silhouette; content stacked above it is untouched.
start = src.find('  // Compositor-independent drop shadow via the item layer')
if start != -1:
    end_marker = '    shadowVerticalOffset: Style.shadowOffsetY\n  }\n'
    end = src.find(end_marker, start)
    assert end != -1, "unterminated layer shadow block"
    src = src[:start] + src[end + len(end_marker):]
    print("BorderSurface: removed layer shadow")
# RectangularShadow and the old MultiEffect both live in QtQuick.Effects —
# keep the import unconditionally.
if 'import QtQuick.Effects' not in src:
    src = src.replace('import QtQuick\nimport qs.Commons',
                      'import QtQuick\nimport QtQuick.Effects\nimport qs.Commons', 1)
    print("BorderSurface: ensured QtQuick.Effects import")
if 'property bool shadow:' not in src:
    src = src.replace('''  readonly property bool usesOverlayBorder: Border.needsOverlay(borderSpec)''',
'''  // Opt-in drop shadow for top-level cards. Small controls, rows, bar
  // slabs and tooltips leave this false and stay flat.
  property bool shadow: false

  readonly property bool shadowActive: shadow && Style.shadowEnabled

  readonly property bool usesOverlayBorder: Border.needsOverlay(borderSpec)''', 1)
if 'RectangularShadow {' not in src:
    src = src.replace('''  border.width: Border.canUseNative(borderSpec) ? Border.uniformWidth(borderSpec) : 0
''',
'''  border.width: Border.canUseNative(borderSpec) ? Border.uniformWidth(borderSpec) : 0

  // Compositor-independent drop shadow. First child, negative z, so it
  // paints below the fill and tracks card geometry + radius. Unlike a
  // layer effect, this child shadows only the card silhouette — text and
  // icons stacked above it are unaffected.
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
# Tidy the blank lines the layer-block removal leaves behind: the removed
# block sat between two blank lines, so after the insert above there are
# three newlines between the shadow block and the Loader.
old = '''    spread: Style.shadowSpread
  }



  Loader {'''
new = '''    spread: Style.shadowSpread
  }

  Loader {'''
if old in src:
    src = src.replace(old, new, 1)
# NotificationCard sets clip:true on itself, which would clip this shadow
# child (QML clips children, blur included). border-radius clipping for the
# fill is already handled by the Rectangle itself; the card's inner scroll
# areas keep their own clip:true. So drop the self-clip on the card.
p.write_text(src)
print("BorderSurface patched (sibling shadow)")
EOF

echo "== 2. Style.qml (shadow tokens) =="
bak "$SHELL_DIR/Commons/Style.qml"
python3 - <<'EOF'
import pathlib, re
p = pathlib.Path('/usr/share/omarchy/shell/Commons/Style.qml')
src = p.read_text()
if 'shadowOverrides' not in src:
    # fresh install: insert the whole token block
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
  // RectangularShadow takes a pre-multiplied color (alpha folded in via
  // opacity).
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
  // RectangularShadow blur is in px, so the margin tracks it 1:1.
  readonly property int shadowMargin: shadowEnabled
    ? Math.ceil(shadowBlur + Math.max(Math.abs(shadowOffsetX), Math.abs(shadowOffsetY)))
    : 0
''', 1)
    print("Style: token block inserted")
else:
    print("Style: token block present, migrating values")
    # migrate blur default 0.9 (MultiEffect 0..1 era) -> 28px (RectangularShadow px)
    src2 = src.replace('shadowNum("blur", 0.9)', 'shadowNum("blur", 28)')
    if src2 != src:
        src = src2
        print("Style: blur default 0.9 -> 28")
    # drop shadowOpacity (MultiEffect-era): RectangularShadow consumes the
    # pre-multiplied shadowColor and nothing else reads this property.
    old_opacity = '''
  readonly property real shadowOpacity: shadowAlpha("opacity", 0.45)'''
    if old_opacity in src:
        src = src.replace(old_opacity, '', 1)
        print("Style: shadowOpacity removed")
    # update shadowMargin to px-blur form
    old_margin = """  readonly property int shadowMargin: (shadowEnabled && shadowOpacity > 0)
    ? Math.ceil(Math.min(1, shadowBlur) * 96 + Math.max(Math.abs(shadowOffsetX), Math.abs(shadowOffsetY)))
    : 0"""
    if old_margin in src:
        src = src.replace(old_margin,
"""  readonly property int shadowMargin: shadowEnabled
    ? Math.ceil(shadowBlur + Math.max(Math.abs(shadowOffsetX), Math.abs(shadowOffsetY)))
    : 0""", 1)
        print("Style: shadowMargin de-normalized")
    # refresh comments that reference the old design. NOTE: the \n sequences
    # below are QML/JS string escapes inside the generated python — they must
    # stay literal backslash-n through the shell heredoc. This is a no-op on
    # the live Style.qml (comment already refreshed); it only fires on older
    # checkouts.
    src = src.replace(
"  // Base color kept opaque: MultiEffect takes color + opacity separately.",
"  // RectangularShadow takes a pre-multiplied color (alpha folded in via\n  // opacity).",
)
# shared parser wiring (both branches): route [shadow] into shadowOverrides
if 'var shadowOut = {}' not in src:
    src = src.replace('''    var styleOut = {}
''', '''    var styleOut = {}
    var shadowOut = {}
''', 1)
    print("Style: shadowOut dict added")
if 'section === "shadow"' not in src:
    src = src.replace('''      } else if (section === "controls" || section === "style") {''',
'''      } else if (section === "shadow") {
        shadowOut[key] = raw
      } else if (section === "controls" || section === "style") {''', 1)
    print("Style: [shadow] parser branch added")
if 'shadowOverrides = shadowOut' not in src:
    src = src.replace('''    spacingOverrides = spacingOut
    styleOverrides = styleOut
''', '''    spacingOverrides = spacingOut
    styleOverrides = styleOut
    shadowOverrides = shadowOut
''', 1)
    print("Style: shadowOverrides assignment added")
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
# RectangularShadow blur is in px; also drives Style.shadowMargin bleed.
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
changed = False
old = '''  property int margin: Style.gapsOut
'''
new = '''  property int margin: Style.gapsOut
  // Transparent bleed around the card so the shadow never clips at the
  // window edge. The window grows with it, so anchor math stays consistent.
  readonly property int cardBleed: Style.shadowMargin
'''
if old in src and 'readonly property int cardBleed' not in src:
    src = src.replace(old, new, 1)
    changed = True
old = '''  implicitWidth: contentWidth
  implicitHeight: contentHeight
'''
new = '''  implicitWidth: contentWidth + cardBleed * 2
  implicitHeight: contentHeight + cardBleed * 2
'''
if old in src:
    src = src.replace(old, new, 1)
    changed = True
old = '''  BorderSurface {
    id: card
    anchors.fill: parent
    color: Color.popups.background
'''
new = '''  BorderSurface {
    id: card
    anchors.fill: parent
    anchors.margins: cardBleed
    shadow: true
    color: Color.popups.background
'''
if old in src:
    src = src.replace(old, new, 1)
    changed = True
p.write_text(src)
print("PopupCard patched" if changed else "PopupCard already patched")
EOF

echo "== 5. OSD (margin + opt in) =="
bak "$SHELL_DIR/plugins/osd/Osd.qml"
python3 - <<'EOF'
import pathlib
p = pathlib.Path('/usr/share/omarchy/shell/plugins/osd/Osd.qml')
src = p.read_text()
changed = False
old = '      anchors.bottomMargin: Style.space(67)\n'
if old in src and 'Style.shadowMargin' not in src:
    src = src.replace(old, '      anchors.bottomMargin: Style.space(67) + Style.shadowMargin\n', 1)
    changed = True
old = '''    BorderSurface {
      id: card
'''
new = '''    BorderSurface {
      id: card
      shadow: true
'''
if old in src and 'shadow: true' not in src:
    # only insert if this specific block lacks it
    src = src.replace(old, new, 1)
    changed = True
p.write_text(src)
print("OSD patched" if changed else "OSD already patched")
EOF

echo "== 6. Opt in top-level cards (menu, clipboard, emojis, keyboard, polkit, reminders, dialog, lock, notifications) =="
# NotificationCard is special: it sets clip:true on itself, which would
# clip the RectangularShadow child (QML clips children, blur included).
# The radius clipping the card needs is already handled by the Rectangle
# fill itself; the inner layout has no scrollable overflow to contain. So
# this hunk also drops the self-clip on the notification card.
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
    bak = str(p) + '.bak-barista1'
    pathlib.Path(bak).write_bytes(p.read_bytes()) if not pathlib.Path(bak).exists() else None
    lines = p.read_text().splitlines(keepends=True)
    # already opted in? the shadow prop follows the id line within a few lines
    opted = False
    for i, ln in enumerate(lines):
        if ln.strip() == idline:
            if 'shadow' in ''.join(lines[i+1:i+6]):
                opted = True
                break
    if opted:
        print(f"already opted in: {rel}")
        continue
    out, done = [], False
    for i, ln in enumerate(lines):
        out.append(ln)
        if not done and ln.strip() == idline:
            ahead = ''.join(lines[i+1:i+6])
            if 'shadow' not in ahead:
                ind = ln[:len(ln)-len(ln.lstrip())]
                out.append(f'{ind}shadow: true\n')
                done = True
    if not done:
        print(f"SKIP {rel}: id line not found (upstream changed?)")
        continue
    p.write_text(''.join(out))
    print(f"opted in: {rel}")

# NotificationCard self-clip would eat the sibling shadow (QML clips
# children, blur included). The Rectangle fill already clips to its own
# radius; the inner layout has no scrollable overflow to contain.
p = SHELL/'plugins/notifications/components/NotificationCard.qml'
src = p.read_text()
old = '''  borderSpec: cardBorderSpec
  clip: true
'''
new = '''  borderSpec: cardBorderSpec
'''
if old in src:
    src = src.replace(old, new, 1)
    p.write_text(src)
    print("unclipped: plugins/notifications/components/NotificationCard.qml")
else:
    print("unclipped already (or upstream changed): plugins/notifications/components/NotificationCard.qml")
EOF

echo "== 7. Menu height clamp (leave room for shadow bleed) =="
python3 - <<'EOF'
import pathlib
p = pathlib.Path('/usr/share/omarchy/shell/plugins/menu/Menu.qml')
src = p.read_text()
old = 'height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)'
new = 'height: Math.min(root.cardHeight, panel.height - Style.gapsOut - Style.shadowMargin - panel.effectiveCardTop)'
if old in src:
    src = src.replace(old, new, 1)
    p.write_text(src)
    print("Menu clamp patched")
else:
    print("Menu clamp already patched")
EOF

echo "== 8. User plugin overrides (~/.config/omarchy/plugins/barista.*) =="
# User-owned, patched WITHOUT root: run as $SUDO_USER when under sudo
# (under sudo, $HOME is /root and expanduser("~") points at the wrong
# place), else as the current user. SUDO_USER detection first, because a
# root-owned shell (pkexec, su) may also have a stale $HOME.
REAL_HOME="${SUDO_HOME:-}"
if [[ -z "$REAL_HOME" && -n "${SUDO_USER:-}" ]]; then
  REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi
if [[ -z "$REAL_HOME" && (( EUID != 0 )) ]]; then
  REAL_HOME="$HOME"
fi
if [[ -z "$REAL_HOME" || ! -d "$REAL_HOME/.config/omarchy/plugins" ]]; then
  echo "hunk 8: no user plugin dir visible (HOME=$HOME SUDO_USER=${SUDO_USER:-unset}) — skipping." >&2
  echo "hunk 8: re-run WITHOUT sudo to patch the user overrides."
fi
if [[ -n "$REAL_HOME" && -d "$REAL_HOME/.config/omarchy/plugins" ]]; then
  OV_HOME="$REAL_HOME" python3 - <<'EOF'
import pathlib, os
HOME = pathlib.Path(os.environ.get("OV_HOME") or os.path.expanduser("~"))
OV = HOME/'.config/omarchy/plugins'
# (override file, anchor id line) — same semantics as hunk 6
targets = {
    'barista.clipboard/Clipboard.qml': 'id: card',
    'barista.emojis/Emojis.qml': 'id: card',
    'barista.polkit/PolkitAgent.qml': 'id: card',
    'barista.reminders/ReminderFlow.qml': 'id: card',
    'barista.notifications/components/NotificationCard.qml': 'id: root',
}
for rel, idline in targets.items():
    p = OV/rel
    if not p.exists():
        print(f"no override, skip: {rel}")
        continue
    lines = p.read_text().splitlines(keepends=True)
    opted = False
    for i, ln in enumerate(lines):
        if ln.strip() == idline and 'shadow' in ''.join(lines[i+1:i+6]):
            opted = True
            break
    if opted:
        print(f"already opted in: {rel}")
        continue
    out, done = [], False
    for i, ln in enumerate(lines):
        out.append(ln)
        if not done and ln.strip() == idline:
            if 'shadow' not in ''.join(lines[i+1:i+6]):
                ind = ln[:len(ln)-len(ln.lstrip())]
                out.append(f'{ind}shadow: true\n')
                done = True
    if not done:
        print(f"SKIP {rel}: id line not found (customized beyond recognition?)")
        continue
    p.write_text(''.join(out))
    print(f"opted in: {rel}")

# Same self-clip fix as hunk 6, for the cloned notification card.
p = OV/'barista.notifications/components/NotificationCard.qml'
if p.exists():
    src = p.read_text()
    old = '''  borderSpec: cardBorderSpec
  clip: true
'''
    if old in src:
        src = src.replace(old, '''  borderSpec: cardBorderSpec
''', 1)
        p.write_text(src)
        print("unclipped: barista.notifications/components/NotificationCard.qml")
    else:
        print("unclipped already (or customized): barista.notifications/components/NotificationCard.qml")
else:
    print("no override, skip: barista.notifications/components/NotificationCard.qml")

# OSD override: margin + opt-in (mirrors hunk 5)
p = OV/'barista.osd/Osd.qml'
if p.exists():
    src = p.read_text()
    changed = False
    old = '      anchors.bottomMargin: Style.space(67)\n'
    if old in src and 'Style.shadowMargin' not in src:
        src = src.replace(old, '      anchors.bottomMargin: Style.space(67) + Style.shadowMargin\n', 1)
        changed = True
    old = '''    BorderSurface {
      id: card
'''
    if old in src and 'shadow: true' not in src:
        src = src.replace(old, '''    BorderSurface {
      id: card
      shadow: true
''', 1)
        changed = True
    p.write_text(src)
    print("OSD override patched" if changed else "OSD override already patched")
else:
    print("no override, skip: barista.osd/Osd.qml")
EOF
fi
echo "== 9. Style.qml (barista gap-following margins) =="
# Half of the effective Hyprland gaps_out, refreshed live — notifications,
# menus, popups and OSD all anchor off Style.gapsOut, so one value moves
# every shell surface at once. Stock gap math (half) is kept.
# Per-side halves (gapTop/gapRight/gapBottom/gapLeft): the bar-gap sync
# zeroes the bar edge (e.g. "0 6 6 6" with a transparent top bar), so the
# bar-side shell margin must be 0 too — windows sit at 0 there, and shell
# surfaces should sit at the same line. The other three sides keep their
# own halves. gapsOut (max of sides) stays as the legacy scalar for menus,
# popups and inner clamps that never touch the bar edge.
# Barista tie-in: body gated by `baristaGapLive`. The stock shell knows
# nothing about themes, so step 30's bar-gap-sync publishes BOTH the
# effective gaps_out (css "T R B L") AND the active theme name (barista?)
# to ~/.local/state/omarchy/barista/gaps_out. That single state file is the
# shell's clock for the bar-gap: no Hyprland event stream exists in QML
# (configreloaded fires only on full reload, not on `hyprctl keyword` /
# `hl.config()` live eval), so the shell polls the file every 2s AND
# re-polls right after theme switches land (see shell applyTheme hunk).
# Non-barista themes reset all five values to the stock default, so foreign
# themes never inherit barista spacing from a stale state file.
# shell.qml is touched too — back it up like every other system file.
bak "$SHELL_DIR/shell.qml"
python3 - <<'EOF'
import pathlib
p = pathlib.Path('/usr/share/omarchy/shell/Commons/Style.qml')
src = p.read_text()
MARK = 'barista: gap-following margins'
if MARK in src:
    print("Style: gap-following margins already patched")
else:
    old = '''  function applyGapsOutJson(raw) {
    try {
      var json = JSON.parse(raw || "{}")
      var css = String(json.css || "")
      var parts = css.match(/-?\\d+(?:\\.\\d+)?/g) || []
      var n = parts.length > 0 ? Number(parts[0]) : Number(json.int)
      if (isFinite(n) && n >= 0) gapsOut = Math.max(0, Math.round(n / 2))
    } catch (e) {
      // hyprctl missing / Hyprland not running — leave the previous value.
    }
  }'''
    assert old in src, "applyGapsOutJson not found"
    new = '''  // barista: gap-following margins.
  // Per-side halves of the effective gaps_out (css "T R B L"): the bar-gap
  // sync zeroes the bar edge, and shell surfaces on that edge must sit at
  // the same line as windows (0), not at the roomy max-side value. The
  // other sides keep their own halves. gapsOut (max of sides, halved) stays
  // as the legacy scalar for menus/popups/inner clamps that never touch
  // the bar edge.
  function applyGapsOutJson(raw) {
    try {
      var json = JSON.parse(raw || "{}")
      var css = String(json.css || "")
      var parts = css.match(/-?\\d+(?:\\.\\d+)?/g) || []
      var vals = []
      for (var i = 0; i < parts.length; i++) {
        var v = Number(parts[i])
        if (isFinite(v) && v >= 0) vals.push(v)
      }
      if (vals.length === 0) vals.push(Number(json.int))
      var peak = vals.length > 0 ? vals[0] : NaN
      for (var j = 1; j < vals.length; j++) if (vals[j] > peak) peak = vals[j]
      if (isFinite(peak) && peak >= 0) applyGapValue(peak, 5)
    } catch (e) {
      // hyprctl missing / Hyprland not running — leave the previous value.
    }
  }

  // barista: gap-following margins: single choke point for the margin value. Non-barista themes
  // always reset to the stock default so a stale state file can never
  // leak barista spacing onto a foreign theme.
  function applyGapValue(n, stockDefault) {
    var dflt = (isFinite(stockDefault) && stockDefault >= 0) ? stockDefault : 5
    if (!baristaGapLive) { gapsOut = dflt; gapTop = dflt; gapRight = dflt; gapBottom = dflt; gapLeft = dflt; return }
    if (isFinite(n) && n >= 0) gapsOut = Math.max(0, Math.round(n / 2))
  }

  // Per-side halves of the effective gaps_out. Set by parseGapState (which
  // sees all four sides); the hyprctl path above only knows the max, so it
  // leaves the sides alone. Consumers on a screen edge (notification top
  // margin, OSD bottom margin, popupCard/popout clearance) bind here so the
  // bar-side margin is 0 exactly when windows sit at 0 there. Legacy
  // gapsOut keeps serving inner clamps that never touch an edge.
  property int gapTop: 5
  property int gapRight: 5
  property int gapBottom: 5
  property int gapLeft: 5

  property bool baristaGapLive: baristaThemeActive

  // The shell has no theme concept; step 30 publishes the live theme name
  // next to the gaps state (see gapStateFile below). Default false so a
  // missing/unreadable file can never enable barista behavior.
  property bool baristaThemeActive: false

  // Effective gaps_out published by step 30's bar-gap-sync
  // (~/.local/state/omarchy/barista/gaps_out, css "T R B L" + theme line).
  // Polled: no Hyprland event stream reaches QML for live `hyprctl keyword`
  // / hl.config() changes — configreloaded only fires on full reloads.
  property FileView gapStateFile: FileView {
    id: gapStateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/barista/gaps_out"
    watchChanges: true
    printErrors: false
    // text() is stale inside onFileChanged itself — reload() re-reads, and
    // the fresh content arrives via onLoaded -> parseGapState (same pattern
    // as Color.userShellFile above).
    onFileChanged: gapStateFile.reload()
    onLoaded: root.parseGapState()
    onLoadFailed: root.applyGapValue(NaN, 5)
  }

  // Single-flight parse: the watcher FileView re-reads before parsing.
  // css order is "top right bottom left" (hyprctl getoption css format).
  function parseGapState() {
    var lines = String(gapStateFile.text() || "").split("\\n")
    var css = lines.length > 0 ? lines[0] : ""
    var theme = lines.length > 1 ? String(lines[1] || "").replace(/^\\s+|\\s+$/g, "").toLowerCase() : ""
    root.baristaThemeActive = (theme === "barista")
    var parts = String(css).match(/-?\\d+(?:\\.\\d+)?/g) || []
    var vals = []
    for (var i = 0; i < parts.length; i++) {
      var v = Number(parts[i])
      if (isFinite(v) && v >= 0) vals.push(v)
    }
    while (vals.length < 4) vals.push(vals.length > 0 ? vals[0] : NaN)
    function half(v) { return (isFinite(v) && v >= 0) ? Math.max(0, Math.round(v / 2)) : 5 }
    if (root.baristaGapLive) {
      gapTop = half(vals[0]); gapRight = half(vals[1]); gapBottom = half(vals[2]); gapLeft = half(vals[3])
      var peak = vals[0]
      for (var j = 1; j < 4; j++) if (vals[j] > peak) peak = vals[j]
      root.applyGapValue(peak, 5)
    } else {
      root.applyGapValue(NaN, 5)
    }
  }

  // Poll the state file: covers live gap edits between FileView events.
  // No Hyprland event stream reaches QML for `hyprctl keyword` /
  // hl.config() edits — configreloaded only fires on full reloads.
  property Timer gapPollTimer: Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: gapStateFile.reload()
  }

'''
    src = src.replace(old, new, 1)
    print("Style: gap-following parser + state poll installed")
    p.write_text(src)
    print("Style patched (gap-following margins)")

# Independent IPC hunk with its own marker: a package update can
# revert shell.qml without reverting Style.qml.
sp = pathlib.Path('/usr/share/omarchy/shell/shell.qml')
ssrc = sp.read_text()
if 'Style.gapStateFile.reload()' in ssrc:
    print("shell.qml: gap re-poll already present")
else:
    old_ipc = '''    function applyTheme(colorsB64: string, shellB64: string): string {
      var colorsRaw = ""
      var shellRaw = ""
      try { colorsRaw = Qt.atob(String(colorsB64 || "")) } catch (e) { colorsRaw = "" }
      try { shellRaw = Qt.atob(String(shellB64 || "")) } catch (e2) { shellRaw = "" }
      Color.loadColors(colorsRaw)
      Color.loadShell(shellRaw)
      Style.scheduleRefresh()
      return "ok"
    }'''
    assert old_ipc in ssrc, "shell applyTheme IPC not found"
    new_ipc = old_ipc.replace("      Style.scheduleRefresh()\\n",
                              "      Style.scheduleRefresh()\\n      Style.gapStateFile.reload()\\n")
    ssrc = ssrc.replace(old_ipc, new_ipc, 1)
    sp.write_text(ssrc)
    print("shell.qml: applyTheme re-polls gap state")
EOF

echo "== 10. Edge-anchored margins follow per-side gaps =="
# Notification toasts sit top-right; OSD sits bottom-center; popups clear
# the bar strip. All three derived their edge standoff from the single
# max-side scalar (or barSize+scalar), so toggling bar transparency — which
# only zeroes the bar-edge side — never moved the edge-anchored margin.
# Fix: pass the per-side halves (hunk 9) into the margin math.
# Stock files AND barista.* user overrides (which shadow them) both get the
# same edit — the override is what the shell actually loads. Non-barista
# themes are unaffected: hunk 9 resets all five values to stock default.
python3 - <<'EOF'
import pathlib, os
SHELL = pathlib.Path('/usr/share/omarchy/shell')
HOME = pathlib.Path(os.path.expanduser("~"))
OV = HOME/'.config/omarchy/plugins'
MARK = 'barista: per-side edge margins'

def patch(path, old, new, sentinel=None):
    try:
        src = path.read_text()
    except FileNotFoundError:
        print(f"skip (missing): {path}")
        return
    if (sentinel or new) in src:
        print(f"already patched {path}")
        return
    if old not in src:
        print(f"SKIP {path.name}: anchor not found")
        return
    path.write_text(src.replace(old, new, 1))
    print(f"patched {path}")

# -- notifications Service.qml
# (1) clearance: use the per-side gap of the touched corner.
clearance_old = """  readonly property int barClearance: liveBarSize + Style.gapsOut"""
clearance_new = """  // %s: clearance uses the per-side gap of the touched
  // corner (gapTop for a top bar), so the toast top margin is 26
  // under a transparent bar and 29 under a solid one — matching
  // windows at 0 vs 6. Falls back to the scalar off-barista (all 5).
  readonly property int barClearance: liveBarSize + (barPosition === "top" ? Style.gapTop : barPosition === "right" ? Style.gapRight : Style.gapsOut)""" % MARK
patch(SHELL/'plugins/notifications/Service.qml', clearance_old, clearance_new)
patch(OV/'barista.notifications/Service.qml', clearance_old, clearance_new)

# (2) placement call: thread the per-side halves through.
place_old = """      readonly property var popupPlacement: NotificationLogic.popupPlacement(
        service.barPosition, service.barClearance, Style.gapsOut)"""
place_new = """      // %s: gapTop/gapRight carry the bar-edge halves so the toast
      // corner margins move with the touched screen edges.
      readonly property var popupPlacement: NotificationLogic.popupPlacement(
        service.barPosition, service.barClearance, Style.gapsOut, Style.gapTop, Style.gapRight)""" % MARK
patch(SHELL/'plugins/notifications/Service.qml', place_old, place_new)
patch(OV/'barista.notifications/Service.qml', place_old, place_new)

# -- NotificationLogic.js: 4th/5th args (top/right per-side halves);
# defaults preserve stock behavior when called with 3 args.
js_old = """function popupPlacement(barPosition, barClearance, gapsOut) {
  var position = String(barPosition || "top")
  var clearance = Number(barClearance)
  var gap = Number(gapsOut)
  if (!isFinite(clearance)) clearance = 0
  if (!isFinite(gap)) gap = 0

  return {
    anchors: { top: true, bottom: false, left: false, right: true },
    margins: {
      top: position === "top" ? clearance : gap,
      bottom: gap,
      left: gap,
      right: position === "right" ? clearance : gap
    }
  }
}"""
js_new = """// %s: gapTop/gapRight are the per-side halves (hunk 9). The toast
// touches the top-right corner, so those two margins follow the touched
// edges; bottom/left keep the scalar (inner clamps, never edge-touched).
// NOTE: clearance already includes the per-side gap (Service.qml adds
// gapTop/gapRight, not the scalar), so use it directly — no re-adding.
function popupPlacement(barPosition, barClearance, gapsOut, gapTop, gapRight) {
  var position = String(barPosition || "top")
  var clearance = Number(barClearance)
  var gap = Number(gapsOut)
  var topGap = isFinite(Number(gapTop)) ? Number(gapTop) : gap
  var rightGap = isFinite(Number(gapRight)) ? Number(gapRight) : gap
  if (!isFinite(clearance)) clearance = 0
  if (!isFinite(gap)) gap = 0

  return {
    anchors: { top: true, bottom: false, left: false, right: true },
    margins: {
      top: position === "top" ? clearance : topGap,
      bottom: gap,
      left: gap,
      right: position === "right" ? clearance : rightGap
    }
  }
}""" % MARK
patch(SHELL/'plugins/notifications/NotificationLogic.js', js_old, js_new)
patch(OV/'barista.notifications/NotificationLogic.js', js_old, js_new)

# -- OSD: bottom-anchored card; follow the bottom per-side half.
osd_old = "      anchors.bottomMargin: Style.space(67) + Style.shadowMargin"
osd_new = "      // %s\n      anchors.bottomMargin: Style.space(67) + Style.shadowMargin + Style.gapBottom - Style.gapsOut" % MARK
patch(SHELL/'plugins/osd/Osd.qml', osd_old, osd_new)
patch(OV/'barista.osd/Osd.qml', osd_old, osd_new)
print("hunk 10 done")
EOF

echo "== 11. Panel/popout bar standoff follows per-side gaps =="
# Weather/clock/audio/... panels (KeyboardPanel, centerOnBar) and bar
# popouts (PopupCard) clear the bar strip with the max-side scalar, so the
# bar-side standoff never moved on transparency toggle — same bug hunk 10
# fixed for toasts/OSD. Point the bar-edge standoff at the per-side halves
# (hunk 9). Parallel clamps and size caps keep the scalar (never bar-touching).
# Stock only: no barista.* overrides exist for these Ui components.
bak "$SHELL_DIR/Ui/KeyboardPanel.qml"
bak "$SHELL_DIR/Ui/PopupCard.qml"
python3 - <<'EOF'
import pathlib
SHELL = pathlib.Path('/usr/share/omarchy/shell')
MARK = 'barista: per-side edge margins'

def patch(path, old, new, sentinel=None):
    try:
        src = path.read_text()
    except FileNotFoundError:
        print(f"skip (missing): {path}")
        return
    if (sentinel or new) in src:
        print(f"already patched {path}")
        return
    if old not in src:
        print(f"SKIP {path.name}: anchor not found")
        return
    path.write_text(src.replace(old, new, 1))
    print(f"patched {path}")

# -- KeyboardPanel: gap is the bar-edge standoff (cardOrigin y = barH + gap,
# _barStripSize, available-size bar subtraction). barPos already exists.
kb_old = "  property int gap: Style.gapsOut  // distance between bar edge and panel"
kb_new = """  // %s: bar-edge standoff follows the bar-side half (0 under a
  // transparent bar), so centered panels hug the bar exactly like windows.
  property int gap: barPos === "top" ? Style.gapTop : barPos === "bottom" ? Style.gapBottom : barPos === "left" ? Style.gapLeft : barPos === "right" ? Style.gapRight : Style.gapsOut  // distance between bar edge and panel""" % MARK
patch(SHELL/'Ui/KeyboardPanel.qml', kb_old, kb_new)

# -- PopupCard: add barGap for the perpendicular (away-from-bar) offsets;
# margin keeps serving parallel clamps and size caps.
pc_old_margin = "  property int margin: Style.gapsOut\n"
pc_new_margin = """  property int margin: Style.gapsOut
  // %s: standoff from the bar edge follows the bar-side half (0 under a
  // transparent bar). margin keeps serving parallel clamps and size caps.
  readonly property string barPos: bar ? bar.position : "top"
  property int barGap: barPos === "top" ? Style.gapTop : barPos === "bottom" ? Style.gapBottom : barPos === "left" ? Style.gapLeft : barPos === "right" ? Style.gapRight : Style.gapsOut
""" % MARK
patch(SHELL/'Ui/PopupCard.qml', pc_old_margin, pc_new_margin)

pc_pairs = [
  ("      var localY = target.height + root.margin",
   "      var localY = target.height + root.barGap"),
  ("        localY = -popupHeight - root.margin",
   "        localY = -popupHeight - root.barGap"),
  ("        localX = target.width + root.margin",
   "        localX = target.width + root.barGap"),
  ("        localX = -popupWidth - root.margin",
   "        localX = -popupWidth - root.barGap"),
  ('          cy = root.bar.position === "bottom" ? -popupHeight - root.margin : window.height + root.margin',
   '          cy = root.bar.position === "bottom" ? -popupHeight - root.barGap : window.height + root.barGap'),
  ('          cx = root.bar.position === "left" ? window.width + root.margin : -popupWidth - root.margin',
   '          cx = root.bar.position === "left" ? window.width + root.barGap : -popupWidth - root.barGap'),
]
for old, new in pc_pairs:
    patch(SHELL/'Ui/PopupCard.qml', old, new)
print("hunk 11 done")
EOF
echo "shell-shadows: done."
