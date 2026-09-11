-- Barista look'n'feel: replaces my_theme_gen.lua (which applied barista
-- values globally to every theme). Gated: returns early unless barista is
-- the active theme, so other themes keep Omarchy stock decoration.
-- Values curated from my-theme.toml [window] + [hypr."decoration.shadow"]
-- passthrough + [[hypr_layer]] blur rule.
-- Source of truth lives HERE in git; edit + `hyprctl reload` to preview.
-- hyprland.lua loads this AFTER omarchy defaults, so it wins on conflict.
local gate_ok, gate = pcall(require, "hypr.barista-gate")
if not gate_ok or not gate or not gate.active() then
  return
end

hl.env("OMARCHY_MENU_FONT", "Inter")
hl.config({
  decoration = {
    active_opacity = 1.0,
    blur = {
      enabled = false,
    },
    border_part_of_window = true,
    dim_around = 0.3,
    dim_inactive = false,
    dim_modal = true,
    dim_strength = 0.15,
    fullscreen_opacity = 1.0,
    inactive_opacity = 0.99,
    rounding = 10,
    rounding_power = 3,
    shadow = {
      color = "rgba(4c4f6955)",
      enabled = false,
    },
  },
  general = {
    border_size = 2,
    gaps_in = 3,
    gaps_out = 6,
    layout = "dwindle",
  },
})
hl.config({ animations = { enabled = true } })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "windows", enabled = true, speed = 3.79, bezier = "easeOutQuint" })
hl.layer_rule({ match = { namespace = "^(omarchy-menu|omarchy-clipboard|omarchy-emojis|omarchy-image-selector|omarchy-polkit|omarchy-osd|omarchy-notifications|omarchy-keyboard-panel|omarchy-keyboard-panel-dismiss|omarchy-reminders|omarchy-network-qr|omarchy-disk-speedtest|omarchy-network-speedtest|omarchy-speed-test)$" }, blur = false })
