# shellcheck shell=bash
# Shared backup helper for the root-owned QML patch steps (10, 60, 61).
# Source it after setting SHELL_DIR and BAK_SUFFIX; then call `bak <file>`
# before patching <file>.
#
# Why not plain `cp -n`: backups made under omarchy 4.0 survived the 4.5
# update untouched (cp -n never refreshes), so `--revert` would have put
# 4.0 QML on top of a 4.5 shell. Backups are now tied to the installed
# omarchy version:
#   * a version stamp sits next to the shell (".barista<suffix>.version");
#     when the installed version differs, every <suffix> backup is dropped
#     first — they belong to files that no longer exist;
#   * a fresh backup is taken from the PACKAGE ARCHIVE in the pacman cache
#     when present (pristine even if a crashed earlier run already patched
#     the live file), else from the live file.

barista_pkg_version() { pacman -Q omarchy 2>/dev/null | awk '{print $2}'; }

barista_pkg_archive() {
  local v="$1"
  [[ -n $v ]] || return 0
  compgen -G "/var/cache/pacman/pkg/omarchy-$v-*.pkg.tar.zst" | head -n1
}

_BARISTA_BAK_SYNCED=""
_BARISTA_PKG_ARCHIVE=""

barista_bak_sync_version() {
  [[ -n $_BARISTA_BAK_SYNCED ]] && return 0
  _BARISTA_BAK_SYNCED=1
  local ver stamp old
  ver="$(barista_pkg_version)"
  [[ -n $ver ]] || return 0            # not a pacman install (tests): keep cp -n semantics
  stamp="$SHELL_DIR/.barista$BAK_SUFFIX.version"
  old="$(cat "$stamp" 2>/dev/null || true)"
  if [[ $old != "$ver" ]]; then
    local n=0 f
    while IFS= read -r -d '' f; do rm -f "$f"; n=$((n+1)); done \
      < <(find "$SHELL_DIR" "$(dirname "$SHELL_DIR")/default/themed" -name "*$BAK_SUFFIX" -print0 2>/dev/null)
    (( n )) && echo "backups: dropped $n stale *$BAK_SUFFIX from omarchy ${old:-unknown} (now $ver)"
    printf '%s\n' "$ver" >"$stamp"
  fi
  # Only the real install maps 1:1 onto archive paths.
  [[ $SHELL_DIR == /usr/share/omarchy/shell ]] && _BARISTA_PKG_ARCHIVE="$(barista_pkg_archive "$ver")"
  return 0
}

bak() {
  local f="$1" b="$1$BAK_SUFFIX"
  barista_bak_sync_version
  [[ -e $b ]] && return 0
  if [[ -n $_BARISTA_PKG_ARCHIVE ]] && bsdtar -xOf "$_BARISTA_PKG_ARCHIVE" "${f#/}" >"$b" 2>/dev/null && [[ -s $b ]]; then
    return 0
  fi
  rm -f "$b"
  cp "$f" "$b" 2>/dev/null || true
}
