-- Bar-aware top gap: reads ~/.config/omarchy/shell.json on every reload.
-- transparent bar (and bar shown) -> gaps_out on the bar side = 0
-- solid bar OR bar hidden (bar-off toggle) -> gaps_out = live base size.
-- A hidden bar leaves an empty strip at gap 0, so hidden counts as solid.
-- Honors bar.position: applies the zero on the bar side only, keeps
-- your other sides as they are (read live from Hyprland, never a
-- hardcoded constant, so manual tweaks survive reloads).

-- Barista-gated: no-op unless barista is the active theme (see
-- barista-gate.lua). Other themes keep Omarchy stock gaps.
do
  local gate_ok, gate = pcall(require, "hypr.barista-gate")
  if not gate_ok or not gate or not gate.active() then
    return
  end
end

local BAR_GAP_TRANSPARENT = 0
-- Non-bar side default when the live value is unreadable (first boot
-- before any gaps_out exists). Otherwise the base comes from Hyprland
-- itself (see live_base below), so manual tweaks survive reloads.
local FALLBACK_BASE = 6

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

-- bar-off toggle: ~/.local/state/omarchy/toggles/bar-off exists while the
-- bar is hidden. A hidden bar must keep the solid gap, otherwise windows
-- sit at gap 0 with an empty strip where the bar was.
local function bar_hidden()
  local path = (os.getenv("HOME") or "") .. "/.local/state/omarchy/toggles/bar-off"
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

local hidden = bar_hidden()

-- Base = live gaps_out with the bar side excluded, so a manual size set
-- in looknfeel (or via hyprctl) sticks across reloads instead of being
-- reset to a hardcoded constant. get_config returns either a scalar
-- ("6") or a css-style side string ("0 6 6 6", order T R B L).
-- NOTE: files that load AFTER this one (default.hypr.toggles, user config
-- below the requires) overwrite gaps_out wholesale — this file can only
-- preserve sizes set by EARLIER files (omarchy defaults, looknfeel).
local function live_base(position)
  local ok, v = pcall(hl.get_config, "general.gaps_out")
  local sides = {}
  if ok and v ~= nil then
    if type(v) == "table" then
      for _, k in ipairs({ "top", "right", "bottom", "left" }) do
        local n = tonumber(v[k] or v[string.sub(k, 1, 1)])
        if n ~= nil and n >= 0 then
          sides[k] = n
        end
      end
    else
      local nums = {}
      for num in tostring(v):gmatch("-?%d+%.?%d*") do
        local n = tonumber(num)
        if n ~= nil and n >= 0 then
          table.insert(nums, n)
        end
      end
      local keys = { "top", "right", "bottom", "left" }
      if #nums == 1 then
        for _, k in ipairs(keys) do
          sides[k] = nums[1]
        end
      elseif #nums == 4 then
        for i, k in ipairs(keys) do
          sides[k] = nums[i]
        end
      end
    end
  end
  local peak = nil
  for k, n in pairs(sides) do
    if k ~= position and (peak == nil or n > peak) then
      peak = n
    end
  end
  return peak or FALLBACK_BASE
end

local base = live_base(bar.position)
local edge_gap = (bar.transparent and not hidden) and BAR_GAP_TRANSPARENT or base

local gaps_out = {
  top = base,
  right = base,
  bottom = base,
  left = base,
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
