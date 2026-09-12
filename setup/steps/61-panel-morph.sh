#!/bin/bash
# Step 61 — panel-morph: the new panel reshapes from the old one on switch,
# and every panel opens at a remembered size instead of a loading skeleton.
# Problem 1: with one-click switching (step 60) the old panel snaps shut and
# the new one fades in — two disjoint animations, no spatial continuity.
# Fix 1: the bar publishes the open popout's live card rect; an arriving panel
# whose card origin is within morphThreshold px on the same screen
# interpolates its card geometry old->new (position + size) while its content
# cross-fades in late. Far switches fall back to a gentle scale+fade in place.
# Problem 2: async panels (weather fetches, network scans) open at skeleton
# height (~105px) then jump as data lands — the morph target moves mid-flight.
# Fix 2: each panel persists its settled card size to
# ~/.local/state/omarchy/barista/panel-sizes.json (keyed by moduleName, width
# + height only — x/y re-derives from the anchor every open) and opens at
# max(live content, remembered size). Seed, never cap: live content always
# wins upward, and the size eases back via Behavior instead of jumping.
# Hunks (all idempotent, revert via .bak-barista3 — own suffix, so step 10's
# .bak-barista1 and step 60's .bak-barista2 backups are never touched):
#   1. plugins/bar/Bar.qml: activePopoutRect + notePopoutRect; lightweight
#      per-frame fan-out (syncPopoutRects) instead of the full object sync.
#   2. Ui/PluginBarApi.qml: activePopoutRect mirror + notePopoutRect
#      delegation (cloned barista.* widgets only see the facade).
#   3. Ui/KeyboardPanel.qml: morph state, beginMorph/reportRect, card
#      geometry interpolation, delayed content fade, appearScale fallback,
#      size memory (FileView persistence, seeded effective size, eased
#      release).
# System files: must run as root (sudo) on the real system path.
# Idempotent: skips hunks already applied. Usage: $0 [apply|revert].
set -euo pipefail
SHELL_DIR="${SHELL_DIR:-/usr/share/omarchy/shell}"
BAK_SUFFIX=".bak-barista3"
bak() { cp -n "$1" "$1$BAK_SUFFIX" 2>/dev/null || true; }

MODE="${1:-apply}"
if [[ "$MODE" == "revert" ]]; then
  n=0
  while IFS= read -r f; do
    mv "$f" "${f%$BAK_SUFFIX}"; n=$((n+1)); echo "panel-morph: restored ${f%$BAK_SUFFIX}"
  done < <(find "$SHELL_DIR" -name "*$BAK_SUFFIX" 2>/dev/null)
  echo "panel-morph: reverted $n files"
  exit 0
fi
[[ "$MODE" == "apply" ]] || { echo "usage: $0 [apply|revert]" >&2; exit 1; }
# Scratch-dir runs (SHELL_DIR overridden, e.g. tests) skip the root gate —
# only the real system path needs sudo.
if [[ "$SHELL_DIR" == "/usr/share/omarchy/shell" ]] && (( EUID != 0 )); then echo "panel-morph: must run as root (sudo)" >&2; exit 1; fi

echo "== 1. Bar.qml (publish open popout's card rect) =="
bak "$SHELL_DIR/plugins/bar/Bar.qml"
python3 - <<'EOF'
import os, pathlib
p = pathlib.Path(os.environ.get("SHELL_DIR", "/usr/share/omarchy/shell")) / "plugins/bar/Bar.qml"
src = p.read_text()

# 1a. rect store + reporter, next to activePopout.
old_state = """  property var activePopout: null
  property var barDragSource: null
"""
new_state = """  property var activePopout: null
  // barista: panel morph — live card rect ({x, y, width, height, screen})
  // of the open popout, reported by its KeyboardPanel. An arriving panel
  // snapshots this before requestPopout closes the departed one.
  property var activePopoutRect: null
  function notePopoutRect(rect) { activePopoutRect = rect }
  property var barDragSource: null
"""
if "function notePopoutRect(rect)" in src:
    print("Bar: rect store present, skipping")
elif old_state in src:
    src = src.replace(old_state, new_state, 1)
    print("Bar: rect store added")
else:
    raise SystemExit("Bar: activePopout anchor not found (upstream changed?)")

# 1a2. handoff snapshot: stash the departing rect at switch time, tagged
# with a per-switch request id. The arriving panel's beginMorph only trusts
# the snapshot when the id matches its own open (morphRequestId gate) —
# otherwise a reopened panel replays a stale snapshot (self-morph).
old_handoff = "  function requestPopout(owner) {\n    if (activePopout === owner) return\n"
new_handoff = "  property var morphFromRect: null\n  property int morphRequestSeq: 0\n  function requestPopout(owner) {\n    if (activePopout === owner) return\n    // barista: panel morph — handoff snapshot of the departing rect.\n    if (activePopout && activePopout !== owner) { morphRequestSeq += 1; morphFromRect = { rect: activePopoutRect, forKey: String(owner), requestId: morphRequestSeq } }\n"
if "morphRequestSeq += 1; morphFromRect" in src and "property int morphRequestSeq" in src:
    print("Bar: morph handoff present, skipping")
elif "morphFromRect = { rect: activePopoutRect" in src:
    # Upgrade: unsequenced handoff -> requestId-tagged handoff. Two live
    # generations exist: the bare line, and the bare line + separate seq
    # prop elsewhere. Normalize both to the single current form.
    if "property int morphRequestSeq" not in src:
        src = src.replace("  property var morphFromRect: null\n",
            "  property var morphFromRect: null\n  property int morphRequestSeq: 0\n", 1)
        print("Bar: morph seq prop added")
    src = src.replace(
        "if (activePopout && activePopout !== owner) morphFromRect = { rect: activePopoutRect, forKey: String(owner) }",
        "if (activePopout && activePopout !== owner) { morphRequestSeq += 1; morphFromRect = { rect: activePopoutRect, forKey: String(owner), requestId: morphRequestSeq } }", 1)
    print("Bar: morph handoff upgraded (requestId)")
elif old_handoff in src:
    src = src.replace(old_handoff, new_handoff, 1)
    print("Bar: morph handoff added")
else:
    raise SystemExit("Bar: requestPopout anchor not found (upstream changed?)")

# 1b. mirror the rect into facades. Anchored on the layoutConfig line (left
# untouched by step 60 either way), so steps 60 and 61 apply in any order.
# Heal: live Bar.qml carries the rect line twice (149 hunk ran 2x without a
# guard) — collapse before the presence check so re-apply converges.
DUP_RECT_LINE = "    api.activePopoutRect = root.activePopoutRect\n"
old_layout = "    api.layoutConfig = root.publicLayoutConfig()"
new_layout = ("    api.layoutConfig = root.publicLayoutConfig()\n"
              "    // barista: panel morph — mirror of the open popout's card rect.\n"
              "    api.activePopoutRect = root.activePopoutRect\n"
              "    // barista: panel morph — handoff snapshot + seq (shared refs).\n"
              "    api.morphFromRect = root.morphFromRect\n"
              "    api.morphRequestSeq = root.morphRequestSeq")
if DUP_RECT_LINE in src and src.count(DUP_RECT_LINE) > 1:
    first = src.find(DUP_RECT_LINE) + len(DUP_RECT_LINE)
    src = src[:first] + src[first:].replace(DUP_RECT_LINE, "", 1)
    print("Bar: rect mirror deduplicated")
# Upgrade: the full-sync mirror predates the seq line — add it so a freshly
# opened panel's own facade carries the current switch id for the gate.
# Runs BEFORE the presence check (which would otherwise converge early and
# skip the upgrade on already-patched trees).
SEQ_MIRROR = "    api.morphRequestSeq = root.morphRequestSeq\n"
if SEQ_MIRROR not in src and "api.morphFromRect = root.morphFromRect" in src:
    src = src.replace("    api.morphFromRect = root.morphFromRect\n",
        "    api.morphFromRect = root.morphFromRect\n" + SEQ_MIRROR, 1)
    print("Bar: seq mirror added")
if "api.morphFromRect = root.morphFromRect" in src:
    print("Bar: rect mirror present, skipping")
elif old_layout in src:
    src = src.replace(old_layout, new_layout, 1)
    print("Bar: rect mirror added")
else:
    raise SystemExit("Bar: sync anchor not found (upstream changed?)")

# 1c. lightweight fan-out. Live rects AND the sequenced handoff both fan
# out to open popout facades — syncPluginBarApiObjects only delivers to the
# arriving panel's own facade (created fresh at open), which never carries
# a handoff stashed before it existed. Anchored on onClickTargetsChanged
# (present in stock) so steps 60 and 61 apply in any order.
old_click = """  onClickTargetsChanged: syncAllPluginBarApiObjects()
"""
new_click = """  onClickTargetsChanged: syncAllPluginBarApiObjects()
  // barista: panel morph — live rect + handoff fan-out for morph
  // followers mid-flight. Clone-only gate: non-clone third-party facades
  // (weather-style, no morph code) would receive an unknown property
  // assignment otherwise. requestPluginPopout/releasePluginPopout already
  // guarantee the key is a registered clone (markPluginObject rejects
  // foreign targets), so the popout key's owner is always in
  // pluginObjectOwners here.
  onActivePopoutRectChanged: if (!root.activePopout) root.activePopoutRect = null; else syncPopoutRects()
  onMorphFromRectChanged: syncPopoutRects()
  function morphFacadeIds() {
    var out = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (record && record.popout) out.push(record.pluginId)
    }
    return out
  }
  function syncPopoutRects() {
    var ids = morphFacadeIds()
    for (var i = 0; i < ids.length; i++) {
      if (pluginBarApis[ids[i]]) {
        pluginBarApis[ids[i]].activePopoutRect = root.activePopoutRect
        pluginBarApis[ids[i]].morphFromRect = root.morphFromRect
        pluginBarApis[ids[i]].morphRequestSeq = root.morphRequestSeq
      }
    }
  }
"""
# Heal: an earlier revision installed the fan-out twice (ungated copy +
# gated copy) — a fatal "Property value set multiple times". Remove the
# ungated copy whenever the gated one is present.
UNGATED = """  // barista: panel morph \u2014 live rect fan-out for morph followers mid-flight.
  onActivePopoutRectChanged: if (!root.activePopout) root.activePopoutRect = null; else syncPopoutRects()
  function syncPopoutRects() {
    for (var id in pluginBarApis) pluginBarApis[id].activePopoutRect = root.activePopoutRect
  }
"""
if "function morphFacadeIds()" in src and UNGATED in src:
    src = src.replace(UNGATED, "")
    print("Bar: rect fan-out deduplicated (ungated copy removed)")
if "function morphFacadeIds()" in src and "function syncPopoutRects()" in src and UNGATED not in src:
    # Upgrade: fan out the sequenced handoff + seq alongside the live rect.
    upgraded = False
    if "onMorphFromRectChanged" not in src:
        src = src.replace(
            "  onActivePopoutRectChanged: if (!root.activePopout) root.activePopoutRect = null; else syncPopoutRects()",
            "  onActivePopoutRectChanged: if (!root.activePopout) root.activePopoutRect = null; else syncPopoutRects()\n  onMorphFromRectChanged: syncPopoutRects()", 1)
        print("Bar: handoff fan-out trigger added")
        upgraded = True
    if "morphRequestSeq = root.morphRequestSeq" not in src:
        src = src.replace(
            "        pluginBarApis[ids[i]].morphFromRect = root.morphFromRect",
            "        pluginBarApis[ids[i]].morphFromRect = root.morphFromRect\n        pluginBarApis[ids[i]].morphRequestSeq = root.morphRequestSeq", 1)
        print("Bar: seq fan-out added")
        upgraded = True
    if not upgraded:
        print("Bar: rect fan-out present, skipping")
elif old_click in src:
    src = src.replace(old_click, new_click, 1)
    print("Bar: rect fan-out added")
else:
    raise SystemExit("Bar: onClickTargetsChanged anchor not found (upstream changed?)")

# 1d. facade callback wiring.
old_cb = "      _releasePopout: function(owner) { root.releasePluginPopout(key, owner) },\n"
new_cb = old_cb + "      _notePopoutRect: function(rect) { root.notePopoutRect(rect) },\n"
if "_notePopoutRect: function(rect)" in src:
    print("Bar: facade callback present, skipping")
elif old_cb in src:
    src = src.replace(old_cb, new_cb, 1)
    print("Bar: facade callback added")
else:
    raise SystemExit("Bar: createObject anchor not found (upstream changed?)")

p.write_text(src)
print("Bar patched")
EOF

echo "== 2. PluginBarApi.qml (rect mirror + reporter) =="
bak "$SHELL_DIR/Ui/PluginBarApi.qml"
python3 - <<'EOF'
import os, pathlib
p = pathlib.Path(os.environ.get("SHELL_DIR", "/usr/share/omarchy/shell")) / "Ui/PluginBarApi.qml"
src = p.read_text()

old_prop = "  property var layoutConfig: ({})\n"
new_prop = ("  // barista: panel morph — mirror of the open popout's card rect\n"
            "  // ({x, y, width, height, screen}), fanned out by Bar. The scoped\n"
            "  // clickTargets above stay untouched.\n"
            "  property var activePopoutRect: null\n"
            "  // barista: panel morph — handoff snapshot (shared ref, see Bar).\n"
            "  property var morphFromRect: null\n"
            "  // barista: panel morph — per-switch sequence tagging the handoff.\n"
            "  property int morphRequestSeq: 0\n"
            "  property var layoutConfig: ({})\n")
# Heal: an earlier revision installed the rect-mirror block twice (dup
# activePopoutRect) — fatal "Duplicate property name". Collapse to one.
MIRROR_BLOCK = """  // barista: panel morph \u2014 mirror of the open popout's card rect
  // ({x, y, width, height, screen}), fanned out by Bar. The scoped
  // clickTargets above stay untouched.
  property var activePopoutRect: null
"""
if src.count(MIRROR_BLOCK) > 1:
    first = src.find(MIRROR_BLOCK) + len(MIRROR_BLOCK)
    src = src[:first] + src[first:].replace(MIRROR_BLOCK, "", 1)
    print("PluginBarApi: rect mirror deduplicated")
if "property int morphRequestSeq" not in src and "property var morphFromRect" in src:
    # Upgrade: sequenced handoff — add the seq mirror next to the snapshot.
    src = src.replace("  property var morphFromRect: null\n",
        "  property var morphFromRect: null\n  // barista: panel morph — per-switch sequence tagging the handoff.\n  property int morphRequestSeq: 0\n", 1)
    print("PluginBarApi: request seq added")
if "property var morphFromRect" in src and src.count(MIRROR_BLOCK) == 1:
    print("PluginBarApi: rect mirror present, skipping")
elif old_prop in src:
    src = src.replace(old_prop, new_prop, 1)
    print("PluginBarApi: rect mirror added")
else:
    raise SystemExit("PluginBarApi: layoutConfig anchor not found (upstream changed?)")

old_cbprop = "  property var _releasePopout: null\n"
new_cbprop = old_cbprop + "  property var _notePopoutRect: null\n"
if "property var _notePopoutRect" in src:
    print("PluginBarApi: callback prop present, skipping")
elif old_cbprop in src:
    src = src.replace(old_cbprop, new_cbprop, 1)
    print("PluginBarApi: callback prop added")
else:
    raise SystemExit("PluginBarApi: _releasePopout anchor not found (upstream changed?)")

old_fn = """  function releasePopout(owner) {
    if (_releasePopout) _releasePopout(owner)
  }
"""
new_fn = old_fn + """
  function notePopoutRect(rect) {
    if (_notePopoutRect) _notePopoutRect(rect)
  }
"""
if "function notePopoutRect(rect)" in src:
    print("PluginBarApi: reporter present, skipping")
elif old_fn in src:
    src = src.replace(old_fn, new_fn, 1)
    print("PluginBarApi: reporter added")
else:
    raise SystemExit("PluginBarApi: releasePopout anchor not found (upstream changed?)")

p.write_text(src)
print("PluginBarApi patched")
EOF

echo "== 3. KeyboardPanel.qml (morph the card, fade content late) =="
bak "$SHELL_DIR/Ui/KeyboardPanel.qml"
python3 - <<'EOF'
import os, pathlib
p = pathlib.Path(os.environ.get("SHELL_DIR", "/usr/share/omarchy/shell")) / "Ui/KeyboardPanel.qml"
src = p.read_text()

# 3a0. Quickshell.Io import for the size-memory FileView. Idempotent: only
# add when missing (stock imports are QtQuick + Quickshell + Wayland +
# qs.Commons; the Io import is absent).
old_imports = """import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
"""
new_imports = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
"""
if "import Quickshell.Io" in src:
    print("KeyboardPanel: Io import present, skipping")
elif old_imports in src:
    src = src.replace(old_imports, new_imports, 1)
    print("KeyboardPanel: Io import added")
else:
    raise SystemExit("KeyboardPanel: import anchor not found (upstream changed?)")

# 3a. morph state + snapshot/report functions, next to the popout flags.
old_flags = """  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  property bool focusPrimed: false
"""
new_flags = """  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  property bool focusPrimed: false

  // barista: panel morph — the arriving panel reshapes from the departing
  // one's card instead of close-then-open (two disjoint fades). Bar
  // publishes the open popout's card rect; on a switch between nearby
  // cards on the same screen the card interpolates old->new geometry while
  // content cross-fades in late. Fresh opens, same-panel reopens, and far
  // switches fall back to a gentle scale+fade in place (appearScale).
  property var morphFrom: null
  property bool morphing: false
  property real morphT: 1.0
  // Far-switch / fresh-open fallback: gentle grow to full size, driven by
  // scaleAnim (explicit restart, never a Behavior — sets must snap).
  property real appearScale: 0.96
  property int morphThreshold: 600
  // Below this origin distance the two cards overlap: reopen/resize, not a
  // switch — skip the reshape and appear in place. Set to 0: stacked panels
  // (tray cluster, same width/anchor, height-only differences) always take
  // the morph path instead. Proximity no longer decides; only identity does
  // (same panel reopen still skips when the size also matches).
  property int morphMinDistance: 0
  // Below this size delta the card is already there: skip the reshape.
  property int morphMinSizeDelta: 24
  property int morphDuration: 240
  // Frozen flight target (snapshot of cardOrigin/content size at switch
  // time) so data arriving mid-morph can't move the goalposts.
  property var morphTo: null
  // Hold the departing card mapped briefly on switch-close so the new
  // card reshapes over it instead of over empty screen.
  property bool holdForMorph: false

  // barista: panel size memory — seed, never cap. Async panels (weather
  // fetches, network scans) open at skeleton height then jump as data
  // lands. The settled card size is persisted per moduleName (width +
  // height only; x/y re-derives from the anchor every open) and reopened
  // at max(live content, remembered size). Live content always wins
  // upward, so growing lists and expanding prompts are never clamped; the
  // ease back down is animated via the card Behavior below.
  // Identity: the panel's moduleName. Panel-based panels expose it
  // directly; KeyboardPanel is also instantiated raw (menu, OSD), where the
  // owner is the BarWidget — which carries the same moduleName. Resolved
  // through a helper so both shapes work with zero edits to any panel.
  // Screen-gated: a size remembered on another output never seeds this one.
  property var sizeMemory: ({})
  property bool sizeMemoryLoaded: false
  // Identity: the panel's moduleName. Resolution order covers every
  // instantiation shape with zero edits to any panel:
  //  1. owner.moduleName — Panel-based panels pass owner: root where root
  //     is the Panel carrying moduleName: "omarchy.*" (weather, network,
  //     clock, ...). This is the common case.
  //  2. root.moduleName — set explicitly on the KeyboardPanel by whoever
  //     instantiates it (the script does NOT set it; a panel may).
  //  3. coordinator key fallback (unique per instance, session-scoped).
  function sizePanelId() {
    var k = ""
    try { k = (owner && owner.moduleName) ? String(owner.moduleName) : "" } catch (e) { k = "" }
    if (!k) { try { k = root.moduleName ? String(root.moduleName) : "" } catch (e2) { k = "" } }
    if (!k) { try { k = String(coordinatorKey) } catch (e3) { k = "" } }
    return k
  }
  property string moduleName: ""
  readonly property string sizeMemoryKey: sizePanelId()
  readonly property string sizeMemoryPath: (function() {
    var h = ""
    try { h = String(Quickshell.env("HOME") || "") } catch (e) { h = "" }
    return (h !== "" ? h : "~") + "/.local/state/omarchy/barista/panel-sizes.json"
  })()
  readonly property var rememberedSize: {
    if (!sizeMemoryLoaded || !sizeMemoryKey) return null
    var e = sizeMemory[sizeMemoryKey]
    if (!e) return null
    var myScreen = ""
    try { myScreen = screen ? String(screen.name || "") : "" } catch (e2) { myScreen = "" }
    // Screen-gated: only seed when the memory came from this output.
    if (e.screen && myScreen && String(e.screen) !== myScreen) return null
    var w = Number(e.width), h = Number(e.height)
    if (!isFinite(w) || !isFinite(h) || w <= 0 || h <= 0) return null
    return { width: Math.round(w), height: Math.round(h), screen: String(e.screen || myScreen) }
  }
  // Effective size: max(live, remembered). Width/height resolved
  // separately so a narrow-but-tall memory still seeds height.
  readonly property int effContentWidth: {
    var live = Number(contentWidth) || 0
    var mem = rememberedSize ? Number(rememberedSize.width) : 0
    return Math.round(Math.max(live, isFinite(mem) ? mem : 0))
  }
  readonly property int effContentHeight: {
    var live = Number(contentHeight) || 0
    var mem = rememberedSize ? Number(rememberedSize.height) : 0
    return Math.round(Math.max(live, isFinite(mem) ? mem : 0))
  }
  function persistSize(rect) {
    if (!sizeMemoryKey || !rect) return
    var w = Math.round(Number(rect.width)), h = Math.round(Number(rect.height))
    if (!isFinite(w) || !isFinite(h) || w <= 0 || h <= 0) return
    var nm = ""
    try { nm = String(rect.screen || (screen ? screen.name : "") || "") } catch (e) { nm = "" }
    var next = {}
    for (var k in sizeMemory) next[k] = sizeMemory[k]
    next[sizeMemoryKey] = { width: w, height: h, screen: nm }
    sizeMemory = next
    sizeSaveTimer.restart()
  }
  function loadSizeMemory(raw) {
    var parsed = null
    try { parsed = raw && String(raw).trim() !== "" ? JSON.parse(raw) : null } catch (e) { parsed = null }
    sizeMemory = (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
    sizeMemoryLoaded = true
  }
  function flushSizeMemory() {
    if (!sizeMemoryLoaded) return
    var text = ""
    try { text = JSON.stringify(sizeMemory, null, 2) + "\n" } catch (e) { return }
    sizeMemoryFile.setText(text)
  }

  // Content stays out for the first stretch of the reshape so reflowing
  // text doesn't smear mid-flight, then fades in over the remainder.
  readonly property real morphContentOpacity: morphT <= 0.35 ? 0.0 : Math.min(1, (morphT - 0.35) / 0.65)

  // Mirror of this card's live geometry for the next switch. Guards first:
  // the open flag, then the bar facade, then the card id (QML evaluates the
  // property block eagerly at creation, before `card` exists — so the card
  // guard must run on its own line, never OR-ed into the earlier return).
  // report/report-morph logs are ALWAYS on (cheap, switch-time only).
  // Settling gate: per-frame morph reports (card x/y/w/h notifiers below)
  // fire through the whole reshape, so the shared live rect would carry
  // mid-flight geometry. Only settled reports (not morphing, and not in
  // the 140ms fade-out where open is already false) update the shared
  // rect — in-flight sizes never poison the next switch's source.
  // minReportHeight drops skeleton reports (one-line-height cards while a
  // panel's async content hasn't landed): they carry no geometry signal,
  // only noise. The size-memory seed covers the visual side.
  property bool morphDebug: false
  property int minReportHeight: 120
  function reportRect() {
    if (!open) return
    if (morphing) return
    if (!bar || typeof bar.notePopoutRect !== "function") return
    var live = null
    try { live = card } catch (e) { return }
    if (!live) return
    var lw = Math.round(Number(live.width)), lh = Math.round(Number(live.height))
    if (!isFinite(lw) || !isFinite(lh) || lw <= 0 || lh < minReportHeight) return
    var nm = ""
    try { nm = screen ? String(screen.name || "") : "" } catch (e) { nm = "" }
    lastRect = { x: Math.round(live.x), y: Math.round(live.y), width: lw, height: lh, screen: nm }
    bar.notePopoutRect({
      x: Math.round(live.x),
      y: Math.round(live.y),
      width: lw,
      height: lh,
      screen: nm
    })
  }

  // Last settled card rect on THIS instance ({x, y, width, height, screen}).
  // Updated by reportRect while open.
  property var lastRect: null
  // Handoff gate: only trust the shared snapshot when it was stashed FOR
  // THIS open (requestId match). The shared morphFromRect belongs to the
  // most recent switch; without the gate a reopened panel replays a stale
  // snapshot whose live rect was already re-reported by the panel that is
  // still open — self-morph across the bar.
  property int morphRequestId: 0
  function liveRect() {
    var r = null
    try { r = bar ? bar.activePopoutRect : null } catch (e) { r = null }
    if (r && isFinite(Number(r.x)) && isFinite(Number(r.y))) {
      // Stale-source guard: the shared rect belongs to the DEPARTED panel,
      // not to us. It is only a valid morph source when it matches OUR
      // anchor position — i.e. the departed card actually overlaps where we
      // are about to appear. A rect from the other side of the bar (a
      // same-spot skip or a far switch away) must never source our reshape;
      // fall through to lastRect (own settled geometry), which yields a
      // same-spot skip and a clean scale+fade in place.
      var rx0 = Number(r.x), ry0 = Number(r.y)
      var pdx = cardOrigin.x - rx0, pdy = cardOrigin.y - ry0
      var pdist = Math.sqrt(pdx * pdx + pdy * pdy)
      if (pdist > morphThreshold) return lastRect
      return r
    }
    return lastRect
  }
  function handoffRect() {
    var h = null
    try { h = bar ? bar.morphFromRect : null } catch (e) { h = null }
    if (!h || !h.rect) return null
    // Coordinator keys are object refs stringified — compare by identity
    // instead: the snapshot is consumable once, by the next opener.
    if (h.consumed) return null
    if (Number(h.requestId || 0) !== morphRequestId) return null
    return h.rect
  }
  function beginMorph() {
    morphFrom = null
    morphing = false
    morphTo = null
    var r = liveRect()
    var handoff = handoffRect()
    if (handoff) r = handoff
    console.log("barista-morph: begin src=" + (handoff ? "handoff" : (r ? "live" : "none")) + " switching=" + popoutSwitching + " r=" + JSON.stringify(r) + " target=" + cardOrigin.x + "," + cardOrigin.y + " " + contentWidth + "x" + contentHeight)
    if (!r) return false
    var myScreen = ""
    try { myScreen = screen ? String(screen.name || "") : "" } catch (e2) { myScreen = "" }
    var rScreen = ""
    try { rScreen = String(r.screen || "") } catch (e3) { rScreen = "" }
    if (myScreen && rScreen && myScreen !== rScreen) return false
    var rx = Number(r.x), ry = Number(r.y)
    if (!isFinite(rx) || !isFinite(ry)) return false
    var dx = cardOrigin.x - rx, dy = cardOrigin.y - ry
    var posDist = Math.sqrt(dx * dx + dy * dy)
    if (posDist > morphThreshold) {
      console.log("barista-morph: skip (far, " + Math.round(posDist) + "px)")
      return false
    }
    var rw = Number(r.width), rh = Number(r.height)
    // Same-PANEL reopen (not same-spot): skip only when the source rect is
    // this panel's own settled geometry and the size already matches.
    // Stacked panels share width/anchor and differ only in height — those
    // MUST morph (vertical reshape in place), never scale+fade. Proximity
    // alone (posDist < morphMinDistance, now 0) must not suppress the
    // reshape; only identity + matching size does.
    if (posDist <= morphMinDistance) {
      var dw0 = Math.abs(Number(effContentWidth) - (isFinite(rw) ? rw : Number(effContentWidth)))
      var dh0 = Math.abs(Number(effContentHeight) - (isFinite(rh) ? rh : Number(effContentHeight)))
      if (Math.max(dw0, dh0) < morphMinSizeDelta) {
        console.log("barista-morph: skip (same spot, maxDelta=" + Math.round(Math.max(dw0, dh0)) + "px)")
        return false
      }
    }
    morphFrom = {
      x: Math.round(rx),
      y: Math.round(ry),
      width: Math.max(1, Math.round(isFinite(rw) && rw > 0 ? rw : effContentWidth)),
      height: Math.max(1, Math.round(isFinite(rh) && rh > 0 ? rh : effContentHeight))
    }
    // Freeze the flight target at the EFFECTIVE size (max(live, remembered))
    // so data arriving mid-morph (weather fetch, lazy content) moves content
    // only, never card geometry.
    morphTo = { x: cardOrigin.x, y: cardOrigin.y, width: effContentWidth, height: effContentHeight }
    morphing = true
    morphT = 0
    try { if (bar && bar.morphFromRect) bar.morphFromRect.consumed = true } catch (e) {}
    morphAnim.restart()
    console.log("barista-morph: MORPH " + morphFrom.x + "," + morphFrom.y + " " + morphFrom.width + "x" + morphFrom.height + " -> " + morphTo.x + "," + morphTo.y + " " + morphTo.width + "x" + morphTo.height)
    return true
  }

  onCardOriginChanged: reportRect()
  onContentWidthChanged: reportRect()
  onContentHeightChanged: reportRect()
  onScreenChanged: reportRect()
"""
# `new_flags` below is the full intended block (props + fixed reportRect +
# beginMorph + change notifiers). Order matters: repair (broken live) first,
# then fresh (stock), because the broken live text CONTAINS old_flags.
# LIVE HEAL: the running tree was patched from an EARLIER revision of this
# script (no morphTo/holdForMorph/liveRect/always-on logs) and its
# presence-checks ("morph state present, skipping") converge on that older
# content. Detect that generation explicitly and rebuild the whole
# morph-state block from new_flags so the new props land on real systems.
# Note: "try { k = root.moduleName" also matches the FIXED resolver (as
# its second branch), so it must not alone trigger a rebuild — otherwise
# every run rebuilds forever. Only the OLD order (root first, owner second)
# marks a stale generation.
OLD_RESOLVER_ORDER = "try { k = root.moduleName" in src and src.find("try { k = root.moduleName") < src.find("owner && owner.moduleName")
LIVE_OLD_MARKERS = (
    "property bool morphDebug" in src
    and ("property int morphRequestId" not in src
         or "property int morphMinDistance" not in src
         or "property int morphMinDistance: 0" not in src
         or "sizeMemoryFile" not in src
         or OLD_RESOLVER_ORDER)
)
# Gated reportRect (settling gate + minReportHeight): live systems predate
# it when the guard text is absent.
LIVE_OLD_REPORT = "if (morphing) return" not in src
# Stale-source guard in liveRect(): live systems predate it when absent.
LIVE_OLD_STALE = "var pdist = Math.sqrt(pdx * pdx + pdy * pdy)" not in src
# Live-file dedupe: a previous repair pass self-duplicated the fixed fn
# block. Collapse exact duplicate fixed-block copies BEFORE the presence
# check, so re-apply converges instead of skipping a broken duplicate.
DUP_BEGIN = "  function beginMorph() {"
DUP_TAIL = "  onScreenChanged: reportRect()\n"
count = src.count(DUP_TAIL)
if count > 1:
    # keep the FIRST full block (props-adjacent), drop later copies: each
    # duplicate spans from its beginMorph fn line to its onScreenChanged line.
    first_end = src.find(DUP_TAIL) + len(DUP_TAIL)
    rest = src[first_end:]
    removed = 0
    while rest.count(DUP_TAIL) > 0:
        b = rest.find(DUP_BEGIN)
        e = rest.find(DUP_TAIL) + len(DUP_TAIL)
        assert b != -1 and e > b, "duplicate bounds"
        # also drop the stale comment header directly above the dup fn
        cmt = "  // Snapshot the departing popout's rect and start the reshape. Returns\n  // false when there is nothing usable to morph from (caller falls back).\n  // Must run BEFORE bar.requestPopout (which closes the departed panel).\n"
        if rest[max(0, b - len(cmt)):b] == cmt:
            b -= len(cmt)
        rest = rest[:b] + rest[e:]
        removed += 1
    src = src[:first_end] + rest
    print(f"KeyboardPanel: collapsed {removed} duplicate block(s)")
# Also collapse the doubled 3-line stale comment left above the fixed
# reportRect when both copies are present.
STALE_CMT = "  // Mirror of this card's live geometry for the next switch. Reads the\n  // card (not cardOrigin) so a chained switch mid-morph starts from the\n  // true visual position rather than the in-flight target.\n"
if src.count(STALE_CMT) == 1 and src.count("  // Mirror of this card's live geometry for the next switch. Guards first:") == 1:
    src = src.replace(STALE_CMT, "")
    print("KeyboardPanel: dropped stale reportRect comment")
# Upgrade path: live has the no-debug fixed block (from the dedupe repair).
# Swap the whole morph-state block (props marker -> onScreenChanged) for the
# current baked new_flags so debug lines land without touching other hunks.
BROKEN_REPORT = "    if (!open || !card || !bar || typeof bar.notePopoutRect"
# Self-heal: collapse any duplicated stock-flag lines the upgrade itself
# added on an earlier run (dup popoutSwitching/focusPrimed), then rebuild the
# whole morph-state block from the ORIGINAL stock anchor when morphDebug is
# missing or the flags are doubled. Runs BEFORE the presence check.
UPGRADE_ANCHOR = "  property bool popoutSwitching: false\n  property bool popoutSwitchClosing: false\n  property bool focusPrimed: false\n"
# Rebuild when the live block predates any baked marker of the current
# new_flags: sizeMemoryFile (this revision's stamp) covers every earlier
# generation (no-debug, dup-flags, debug-but-no-morphTo, unsequenced,
# unseeded).
need_heal = ("sizeMemoryFile" not in src) or LIVE_OLD_MARKERS or LIVE_OLD_REPORT or LIVE_OLD_STALE
if need_heal and UPGRADE_ANCHOR in src and "try { live = card } catch (e) { return }" in src:
    ms = src.find(UPGRADE_ANCHOR)
    me = src.find("  onScreenChanged: reportRect()\n", ms)
    assert ms != -1 and me != -1 and me > ms, "morph-state block bounds"
    me += len("  onScreenChanged: reportRect()\n")
    if src[me:me+1] == "\n":
        me += 1
    src = src[:ms] + new_flags + src[me:]
    print("KeyboardPanel: morph state rebuilt (old generation replaced)")
if "sizeMemoryFile" in src and "function reportRect()" in src and src.count(DUP_TAIL) == 1:
    if "function sizePanelId()" not in src:
        pass  # falls through to the identity upgrade below
    else:
        print("KeyboardPanel: morph state present, skipping")
# Upgrade: size-memory identity — early revision keyed on owner.moduleName
# only, which is empty for raw KeyboardPanel users (owner is the Panel root,
# moduleName lives on the Panel/BarWidget). Add the moduleName prop +
# sizePanelId() resolver so every instantiation resolves its own id.
OLD_IDKEY = """  readonly property string sizeMemoryKey: {
    var k = ""
    try { k = (owner && owner.moduleName) ? String(owner.moduleName) : "" } catch (e) { k = "" }
    if (!k) { try { k = String(coordinatorKey) } catch (e2) { k = "" } }
    return k
  }"""
NEW_IDKEY = """  function sizePanelId() {
    var k = ""
    try { k = (owner && owner.moduleName) ? String(owner.moduleName) : "" } catch (e) { k = "" }
    if (!k) { try { k = root.moduleName ? String(root.moduleName) : "" } catch (e2) { k = "" } }
    if (!k) { try { k = String(coordinatorKey) } catch (e3) { k = "" } }
    return k
  }
  property string moduleName: ""
  readonly property string sizeMemoryKey: sizePanelId()"""
if OLD_IDKEY in src and "function sizePanelId()" not in src:
    src = src.replace(OLD_IDKEY, NEW_IDKEY, 1)
    print("KeyboardPanel: size identity upgraded (moduleName resolver)")
elif "function sizePanelId()" in src and BROKEN_REPORT not in src and 'property string moduleName: ""' in src:
    print("KeyboardPanel: size identity present, skipping")
elif BROKEN_REPORT in src and "property bool morphDebug" not in src:
    # Repair: an older broken revision is live. The broken reportRect body
    # runs from its function line to its closing brace; the fixed block that
    # must stand in its place is extracted from new_flags (same content the
    # fresh path installs), from the fixed-report comment through the
    # onScreenChanged notifier.
    fn_start = src.find("  function reportRect() {")
    fn_end = src.find("\n  }\n\n  // Snapshot the departing", src.find("  function reportRect() {"))
    assert fn_start != -1 and fn_end != -1, "broken reportRect bounds"
    fixed_start = new_flags.find("  // Mirror of this card")
    fixed_end = new_flags.find("  onScreenChanged: reportRect()\n") + len("  onScreenChanged: reportRect()\n")
    assert fixed_start != -1 and fixed_end > fixed_start, "fixed block bounds"
    src = src[:fn_start] + new_flags[fixed_start:fixed_end] + src[fn_end + len("\n  }\n"):]
    print("KeyboardPanel: morph state repaired (broken reportRect replaced)")
elif BROKEN_REPORT in src:
    src = src.replace(old_flags, new_flags, 1)
    print("KeyboardPanel: morph state added")
else:
    raise SystemExit("KeyboardPanel: popout flags anchor not found (upstream changed?)")

# 3b. snapshot before requestPopout; cleanup + scale snap on close.
# NOTE: beginMorph() must run BEFORE bar.requestPopout (which closes the
# departed panel and overwrites the shared live rect). The old order called
# it after — then the open branch's own reportRect() overwrote the shared
# rect with OUR origin before the departed panel's close could report, so
# the next switch's handoff was our own geometry (self-morph).
old_switch = """    if (open) {
      popoutSwitchClosing = false
      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey
      bar.requestPopout(coordinatorKey)
      if (popoutSwitching) popoutSwitchTimer.restart()
    } else {
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false
      if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
      if (popoutSwitchClosing) closeSwitchTimer.restart()
    }
"""
new_switch = """    if (open) {
      popoutSwitchClosing = false
      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey
      // barista: panel morph — adopt the pending switch id BEFORE beginMorph
      // so the sequenced handoff gate trusts this switch's snapshot. Fresh
      // opens (no switch) keep id 0 and never touch the handoff.
      if (popoutSwitching) {
        try { morphRequestId = Number(bar.morphRequestSeq || 0) + 1 } catch (e) { morphRequestId = 0 }
      }
      // barista: panel morph — begin BEFORE requestPopout closes the
      // departed panel; fall back to scale+fade when far away or fresh.
      var morphed = popoutSwitching ? beginMorph() : false
      if (morphed) {
        // Morph owns the transition: geometry interpolates old->new and
        // opacity stays 1 throughout. The scale fallback must NOT run here
        // — appearScale easing 0.96->1.0 on top of the reshape reads as a
        // second, competing pop-in on the same card.
        scaleAnim.stop()
        appearScale = 1.0
      } else {
        morphing = false
        morphFrom = null
        morphTo = null
        appearScale = 0.96
        scaleAnim.restart()
      }
      bar.requestPopout(coordinatorKey)
      if (popoutSwitching) popoutSwitchTimer.restart()
      // Skip our own report on a morphed switch: the shared live rect must
      // keep the DEPARTED panel's geometry until its close reports (or not —
      // beginMorph already snapshotted it). Reporting here would overwrite it
      // with our morph start (= same values) then mid-flight values.
    } else {
      // Switch-close: hold the old card mapped briefly so the arriving card
      // reshapes over it; plain dismiss closes immediately as before.
      // Persist the settled size on EVERY close (switch or dismiss) so the
      // next open seeds from reality, not from a skeleton.
      persistSize(lastRect)
      var switching = !!popoutSwitchClosing
      if (switching) {
        holdForMorph = true
        holdTimer.restart()
      }
      morphAnim.stop()
      scaleAnim.stop()
      morphing = false
      morphFrom = null
      morphTo = null
      morphT = 1.0
      appearScale = 0.96
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false
      if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
      if (popoutSwitchClosing) closeSwitchTimer.restart()
    }
"""
SWITCH_MARKER = "var morphed = popoutSwitching ? beginMorph() : false"
ADOPT_ID = "morphRequestId = Number(bar.morphRequestSeq"
if SWITCH_MARKER in src:
    # Upgrade in place: fix ordering (morph before requestPopout), adopt the
    # pending switch id before beginMorph (sequenced handoff gate), drop the
    # self-report on morphed switches, add hold-for-morph on switch-close.
    # Idempotent: only touch when the old text is still present.
    OLD_ORDER = "      bar.requestPopout(coordinatorKey)\n      if (popoutSwitching) popoutSwitchTimer.restart()\n      reportRect()\n"
    if OLD_ORDER in src:
        src = src.replace(
            "      var morphed = popoutSwitching ? beginMorph() : false",
            "      // begin BEFORE requestPopout (see note above).\n      var morphed = popoutSwitching ? beginMorph() : false", 1)
        src = src.replace(OLD_ORDER,
            "      bar.requestPopout(coordinatorKey)\n      if (popoutSwitching) popoutSwitchTimer.restart()\n", 1)
        print("KeyboardPanel: switch order fixed (morph before requestPopout, no self-report)")
    if ADOPT_ID not in src and "popoutSwitching = bar.activePopout" in src:
        OLD_ADOPT = """      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey"""
        NEW_ADOPT = """      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey
      // Adopt the pending switch id BEFORE beginMorph so the sequenced
      // handoff gate trusts this switch's snapshot (fresh opens keep id
      // 0 and never touch the handoff).
      if (popoutSwitching) {
        try { morphRequestId = Number(bar.morphRequestSeq || 0) + 1 } catch (e) { morphRequestId = 0 }
      }"""
        if OLD_ADOPT in src and NEW_ADOPT not in src:
            src = src.replace(OLD_ADOPT, NEW_ADOPT, 1)
            print("KeyboardPanel: switch id adopt added")
    OLD_CLOSE = """    } else {
      morphAnim.stop()
      scaleAnim.stop()
      morphing = false
      morphFrom = null
      morphT = 1.0
"""
    NEW_CLOSE = """    } else {
      // Switch-close: hold the old card mapped briefly so the arriving card
      // reshapes over it; plain dismiss closes immediately as before.
      // Persist the settled size on EVERY close (switch or dismiss) so the
      // next open seeds from reality, not from a skeleton.
      persistSize(lastRect)
      var switching = !!popoutSwitchClosing
      if (switching) {
        holdForMorph = true
        holdTimer.restart()
      }
      morphAnim.stop()
      scaleAnim.stop()
      morphing = false
      morphFrom = null
      morphTo = null
      morphT = 1.0
"""
    if OLD_CLOSE in src:
        src = src.replace(OLD_CLOSE, NEW_CLOSE, 1)
        print("KeyboardPanel: switch-close hold added")
    elif "persistSize(lastRect)" not in src and "popoutSwitchClosing = !!(owner" in src:
        # Live already has the hold block (previous revision): insert just
        # the persistSize call above the switching var.
        OLD_PERSIST_ANCHOR = """      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false"""
        NEW_PERSIST_ANCHOR = """      // Persist the settled size on EVERY close (switch or dismiss) so
      // the next open seeds from reality, not from a skeleton.
      persistSize(lastRect)
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false"""
        if OLD_PERSIST_ANCHOR in src:
            # Anchor sits in both the fresh template (new_switch, not yet
            # installed) and live; only patch live (SWITCH_MARKER branch).
            # The fresh template already carries persistSize — guard it.
            if "persistSize(lastRect)\n      popoutSwitchClosing" not in src:
                src = src.replace(OLD_PERSIST_ANCHOR, NEW_PERSIST_ANCHOR, 1)
                print("KeyboardPanel: close persist added")
        else:
            print("KeyboardPanel: switch handoff present, skipping")
    # Scale-vs-morph exclusivity: the morphed branch must stop scaleAnim and
    # snap appearScale to 1. Verify both lines are present (older revisions
    # restarted scaleAnim unconditionally, double-animating the card).
    if "scaleAnim.stop()" in src and "appearScale = 1.0" in src:
        print("KeyboardPanel: scale-vs-morph exclusivity present, skipping")
    else:
        raise SystemExit("KeyboardPanel: morphed branch missing scale stop (upstream changed?)")
elif old_switch in src:
    src = src.replace(old_switch, new_switch, 1)
    print("KeyboardPanel: switch handoff added")
else:
    raise SystemExit("KeyboardPanel: onOpenChanged anchor not found (upstream changed?)")

# 3c. morph engine: drives morphT 0->1; cleanup flips bindings back to
# cardOrigin at identical values (no jump). holdTimer keeps the departing
# card mapped through the arriving card's reshape, then releases it.
old_timer = """  Timer {
    id: closeSwitchTimer
    interval: 1
    onTriggered: root.popoutSwitchClosing = false
  }
"""
new_timer = old_timer + """
  // barista: panel morph — departing-side hold. The old surface stays
  // mapped (transparent except its card) while the new card flies; the
  // dismiss overlay is already off (enabled: root.open) so this is purely
  // visual. 120ms covers the reshape's visible first half; the card's own
  // 140ms fade then takes it out.
  Timer {
    id: holdTimer
    interval: 120
    onTriggered: root.holdForMorph = false
  }

  // barista: panel size memory — debounced disk write. Persist only fires
  // on close (persistSize) and settles here, so per-frame morph reports
  // never touch the disk.
  Timer {
    id: sizeSaveTimer
    interval: 400
    onTriggered: root.flushSizeMemory()
  }

  // barista: panel size memory — shared settled-size store. One file for
  // every panel (keyed by moduleName inside), so stock and third-party
  // panels benefit with zero edits to any panel. watchChanges picks up
  // hand edits; atomicWrites avoids half-written JSON on crash.
  // Mkdir first: FileView can't observe a file that doesn't exist yet
  // (same pattern as Bar.qml's bar-off toggle watcher).
  Process {
    id: sizeMemoryMkdir
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/omarchy/barista"]
    onExited: sizeMemoryFile.reload()
  }
  FileView {
    id: sizeMemoryFile
    path: root.sizeMemoryPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSizeMemory(text())
    onLoadFailed: root.loadSizeMemory("")
  }

  // barista: panel morph engine — card geometry below interpolates
  // old->new rect while content fades in late.
  NumberAnimation {
    id: morphAnim
    target: root
    property: "morphT"
    from: 0
    to: 1
    duration: root.morphDuration
    easing.type: Easing.OutCubic
    onFinished: {
      root.morphing = false
      root.morphFrom = null
      root.morphTo = null
      root.morphT = 1.0
    }
  }

  // Fallback grow for far switches / fresh opens. Explicit restart from
  // the open branch — a Behavior would also animate the snap-back to 0.96.
  NumberAnimation {
    id: scaleAnim
    target: root
    property: "appearScale"
    to: 1.0
    duration: 170
    easing.type: Easing.OutCubic
  }
"""
if "id: holdTimer" in src and "id: morphAnim" in src:
    # Upgrade: engine predates the size-memory block — insert it when missing.
    if "id: sizeMemoryFile" not in src and old_timer in src:
        src = src.replace(old_timer, new_timer, 1)
        print("KeyboardPanel: size memory block added")
    else:
        print("KeyboardPanel: morph engine present, skipping")
elif "id: morphAnim" not in src and old_timer in src:
    src = src.replace(old_timer, new_timer, 1)
    print("KeyboardPanel: morph engine added")
else:
    raise SystemExit("KeyboardPanel: closeSwitchTimer anchor not found (upstream changed?)")
# Heal: run1 of this revision inserted holdTimer AND the full engine next to
# the pre-existing engine (dup morphAnim/scaleAnim). Collapse the older copy:
# drop the second engine block's duplicate ids, keeping the first.
DUP_ENGINE = """  // barista: panel morph engine — card geometry below interpolates
  // old->new rect while content fades in late.
  NumberAnimation {
    id: morphAnim"""
if src.count(DUP_ENGINE) > 1:
    first = src.find(DUP_ENGINE)
    second = src.find(DUP_ENGINE, first + len(DUP_ENGINE))
    # second engine block spans to the end of its scaleAnim sibling
    end_marker = """    duration: 170
    easing.type: Easing.OutCubic
  }
"""
    end = src.find(end_marker, second)
    assert end != -1, "dup engine bounds"
    end += len(end_marker)
    if src[end:end+1] == "\n":
        end += 1
    src = src[:second] + src[end:]
    print("KeyboardPanel: duplicate morph engine removed")
# The same double-insert can leave two holdTimer blocks (new_timer next to a
# pre-existing engine that already had one). Collapse to a single holdTimer.
if src.count("id: holdTimer") > 1:
    hfirst = src.find("id: holdTimer")
    hsecond = src.find("id: holdTimer", hfirst + len("id: holdTimer"))
    hstart = src.rfind("Timer {", 0, hsecond)
    hendm = "onTriggered: root.holdForMorph = false"
    hend = src.find(hendm, hsecond)
    assert hstart != -1 and hend != -1, "dup hold bounds"
    hend = src.find("\n  }", hend) + len("\n  }")
    if src[hend:hend+1] == "\n":
        hend += 1
    src = src[:hstart] + src[hend:]
    print("KeyboardPanel: duplicate hold timer removed")

# 3d. card geometry: seeded effective size at rest, frozen morphTo
# mid-flight, eased release after. At rest the card renders
# max(live, remembered) so skeleton opens are invisible; mid-morph it
# interpolates toward the frozen snapshot; when live content outgrows the
# seed the Behavior eases the correction instead of jumping (network-list
# growth, password prompt expansion — never clamped, only smoothed).
old_geom = """    x: root.cardOrigin.x
    y: root.cardOrigin.y
    width: root.contentWidth
    height: root.contentHeight
"""
new_geom = """    // barista: panel morph + size memory — at rest the card renders the
    // seeded effective size; mid-morph it interpolates from the departing
    // rect toward the frozen morphTo snapshot; scale is the far-switch
    // fallback (appearScale) and stays 1 mid-morph.
    x: root.morphing && root.morphFrom && root.morphTo ? Math.round(root.morphFrom.x + (root.morphTo.x - root.morphFrom.x) * root.morphT) : root.cardOrigin.x
    y: root.morphing && root.morphFrom && root.morphTo ? Math.round(root.morphFrom.y + (root.morphTo.y - root.morphFrom.y) * root.morphT) : root.cardOrigin.y
    width: root.morphing && root.morphFrom && root.morphTo ? Math.max(1, Math.round(root.morphFrom.width + (root.morphTo.width - root.morphFrom.width) * root.morphT)) : root.effContentWidth
    height: root.morphing && root.morphFrom && root.morphTo ? Math.max(1, Math.round(root.morphFrom.height + (root.morphTo.height - root.morphFrom.height) * root.morphT)) : root.effContentHeight
    // Eased release: live content outgrowing the seed grows smoothly instead
    // of jumping. Disabled mid-morph (morphT drives geometry there).
    Behavior on width {
      enabled: !root.morphing
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on height {
      enabled: !root.morphing
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    scale: root.morphing ? 1.0 : root.appearScale
    onXChanged: root.reportRect()
    onYChanged: root.reportRect()
    onWidthChanged: root.reportRect()
    onHeightChanged: root.reportRect()
"""
GEOM_MARKER = "root.effContentWidth"
if GEOM_MARKER in src:
    print("KeyboardPanel: card geometry present, skipping")
elif src.count(old_geom) == 1 and "root.morphFrom.x + (root.cardOrigin.x" not in src and "root.morphTo.x - root.morphFrom.x" not in src:
    src = src.replace(old_geom, new_geom, 1)
    print("KeyboardPanel: card geometry added")
elif "root.morphTo.x - root.morphFrom.x" in src and GEOM_MARKER not in src:
    # Upgrade: frozen-morphTo geometry -> seeded effective size at rest +
    # eased release. Swap the two rest bindings, keep flight + handlers.
    # Anchors include the full morphTo.width/height interpolation terms so
    # the replace converges (RUN2 must be a no-op once effContent is live).
    src = src.replace(
        "Math.round(root.morphFrom.width + (root.morphTo.width - root.morphFrom.width) * root.morphT)) : root.contentWidth",
        "Math.round(root.morphFrom.width + (root.morphTo.width - root.morphFrom.width) * root.morphT)) : root.effContentWidth", 1)
    src = src.replace(
        "Math.round(root.morphFrom.height + (root.morphTo.height - root.morphFrom.height) * root.morphT)) : root.contentHeight\n    scale:",
        "Math.round(root.morphFrom.height + (root.morphTo.height - root.morphFrom.height) * root.morphT)) : root.effContentHeight\n    // Eased release: live content outgrowing the seed grows smoothly instead\n    // of jumping. Disabled mid-morph (morphT drives geometry there).\n    Behavior on width {\n      enabled: !root.morphing\n      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }\n    }\n    Behavior on height {\n      enabled: !root.morphing\n      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }\n    }\n    scale:", 1)
    print("KeyboardPanel: card geometry upgraded (seeded size + eased release)")
else:
    raise SystemExit("KeyboardPanel: card geometry anchor not found (upstream changed?)")

# 3e. card opacity: stay mapped through the switch handoff.
# Stock: `open || card.opacity > 0 || popoutSwitching`. The old panel's
# `open` flips false the moment the new panel's requestPopout closes it —
# opacity then animates 1->0 over 140ms, so the departing card is already
# fading (or gone) while the arriving card reshapes: close-then-open, no
# continuous surface. Fix: keep BOTH surfaces fully opaque through the
# handoff window —
#   * arriving card: opacity 1 during morph (no fade-in; the reshape IS the
#     transition, content cross-fades late instead),
#   * departing card: opacity 1 while holdForMorph (120ms), then fade out.
# The 120ms hold covers the reshape's visible first half; the cards overlap
# spatially (same-bar switches interpolate within morphThreshold), so this
# reads as one surface reshaping, not two fading.
old_visible = "  visible: open || card.opacity > 0 || popoutSwitching\n"
new_visible = "  // barista: panel morph — hold the departing surface mapped through\n  // the switch so the new card reshapes over the old one.\n  visible: open || card.opacity > 0 || popoutSwitching || holdForMorph\n"
if new_visible in src:
    print("KeyboardPanel: hold visible present, skipping")
elif old_visible in src:
    src = src.replace(old_visible, new_visible, 1)
    print("KeyboardPanel: hold visible added")
else:
    raise SystemExit("KeyboardPanel: visible anchor not found (upstream changed?)")

old_cardfade = """    Behavior on opacity {
      enabled: !root.popoutSwitching && !root.popoutSwitchClosing
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
"""
# Opacity is a switch, not an animation, during handoff: 1 while open,
# morphing, or held; the 140ms fade applies ONLY to plain dismiss and the
# post-hold release. Without the morphing/hold terms the departing card
# fades the instant the switch fires and the arriving card fades in from
# 0 — the "disappears, next opens" the logs can't show (MORPH lines fire
# correctly either way; only the pixels tell).
new_cardfade = """    opacity: (root.open || root.morphing || root.holdForMorph || root.popoutSwitching) ? 1.0 : 0

    Behavior on opacity {
      enabled: !root.popoutSwitching && !root.popoutSwitchClosing && !root.morphing && !root.holdForMorph
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
"""
NEW_OPACITY_BINDING = "    opacity: (root.open || root.morphing || root.holdForMorph || root.popoutSwitching) ? 1.0 : 0"
if NEW_OPACITY_BINDING in src and new_cardfade in src:
    print("KeyboardPanel: card fade present, skipping")
elif old_cardfade in src:
    src = src.replace(old_cardfade, new_cardfade, 1)
    print("KeyboardPanel: card fade added")
elif "    opacity: root.open || root.popoutSwitching ? 1.0 : 0" in src:
    # Upgrade: morphing-only fade (previous revision) -> handoff hold fade:
    # swap the binding AND extend the Behavior guard with the hold term.
    src = src.replace(
        "    opacity: root.open || root.popoutSwitching ? 1.0 : 0",
        "    opacity: (root.open || root.morphing || root.holdForMorph || root.popoutSwitching) ? 1.0 : 0", 1)
    src = src.replace(
        "      enabled: !root.popoutSwitching && !root.popoutSwitchClosing && !root.morphing\n",
        "      enabled: !root.popoutSwitching && !root.popoutSwitchClosing && !root.morphing && !root.holdForMorph\n", 1)
    print("KeyboardPanel: card fade upgraded (handoff hold)")
else:
    raise SystemExit("KeyboardPanel: card fade anchor not found (upstream changed?)")

# 3f. content cross-fade: out for the first stretch, in over the remainder.
old_content = """      opacity: root.popoutSwitching ? (root.open ? 1.0 : 0) : 1.0

      Behavior on opacity {
        enabled: root.popoutSwitching
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
"""
new_content = """      // barista: panel morph — content cross-fades in over the second
      // half of the reshape so reflowing text doesn't smear mid-flight.
      opacity: root.morphing ? root.morphContentOpacity : (root.popoutSwitching ? (root.open ? 1.0 : 0) : 1.0)

      Behavior on opacity {
        enabled: root.popoutSwitching && !root.morphing
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
"""
if "root.morphContentOpacity : (root.popoutSwitching" in src:
    print("KeyboardPanel: content fade present, skipping")
elif old_content in src:
    src = src.replace(old_content, new_content, 1)
    print("KeyboardPanel: content fade added")
else:
    raise SystemExit("KeyboardPanel: content fade anchor not found (upstream changed?)")

p.write_text(src)
print("KeyboardPanel patched")
EOF
echo "panel-morph: done."
