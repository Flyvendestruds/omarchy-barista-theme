-- Bar-aware top gap: reads ~/.config/omarchy/shell.json on every reload.
-- transparent bar  -> gaps_out top = 0 (bar floats over wallpaper)
-- solid bar        -> gaps_out top = 6
-- Honors bar.position: applies the gap on the bar side only, keeps
-- other sides on the theme default (BASE_GAPS_OUT).
-- This file loads AFTER hypr.my_theme_gen (see hyprland.lua order), so it
-- always wins over generated theme gaps on reload / theme switch / reboot.
-- No dependency on my_theme_gen: BASE_GAPS_OUT default matches your current
-- barista theme (6); adjust if your theme default changes.

local BAR_GAP_TRANSPARENT = 0
local BAR_GAP_SOLID = 6
local BASE_GAPS_OUT = 6

local function read_shell_config()
  local path = (os.getenv("HOME") or "") .. "/.config/omarchy/shell.json"
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a") or ""
  file:close()
  -- Minimal parse: shell.json is machine-generated (jq -S), look only for
  -- the exact keys we need. Falls back to top/transparent on parse failure.
  local transparent = content:match('"transparent"%s*:%s*(true)') ~= nil
  local position = content:match('"position"%s*:%s*"([a-z]+)"') or "top"
  return { transparent = transparent, position = position }
end

local bar = read_shell_config() or { transparent = true, position = "top" }
local edge_gap = bar.transparent and BAR_GAP_TRANSPARENT or BAR_GAP_SOLID

local gaps_out = {
  top = BASE_GAPS_OUT,
  right = BASE_GAPS_OUT,
  bottom = BASE_GAPS_OUT,
  left = BASE_GAPS_OUT,
}

if bar.position == "top" then
  gaps_out.top = edge_gap
elseif bar.position == "bottom" then
  gaps_out.bottom = edge_gap
elseif bar.position == "left" then
  gaps_out.left = edge_gap
elseif bar.position == "right" then
  gaps_out.right = edge_gap
end

hl.config({
  general = {
    gaps_out = gaps_out,
  },
})
