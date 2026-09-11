-- Barista theme gate: single predicate every barista-owned hypr module
-- uses to decide whether to apply itself.
-- Reads the same theme.name file `omarchy theme set` writes, so it tracks
-- live theme switches without a reboot (hypr re-sources lua on reload).
-- Safe under the bind-scanner stub (no io): defaults to NOT barista, so a
-- foreign theme never inherits barista chrome from a stale require.
local M = {}

function M.active()
  local ok, f = pcall(io.open,
    (os.getenv("HOME") or "") .. "/.local/state/omarchy/current/theme.name", "r")
  if not ok or not f then
    return false
  end
  local name = f:read("*l") or ""
  f:close()
  name = name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
  return name == "barista"
end

return M
