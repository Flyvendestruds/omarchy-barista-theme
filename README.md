# Barista

A warm, familiar Omarchy theme. Designed to feel at home in a café, not a
server room — familiar shapes, readable type, soft shadows. Different enough
to be yours, normal enough that nobody asks what OS that is.

```
omarchy theme install https://github.com/Flyvendestruds/omarchy-barista-theme
```

## What's inside

Light latte palette (`colors.toml`), borderless cards (`border-width = 0`
across popups/menu/notifications), and soft compositor-independent card
shadows (`shell.shadow.toml` — foreground-tinted, 0.33 opacity, 32px blur).

## Setup (everything a theme install can't carry)

`omarchy theme install` only stages theme files. Barista behavior that lives
elsewhere — the shell shadow patch, hypr window chrome — comes via `setup/`:

```
./setup.sh                    # everything (asks sudo for system steps only)
./setup.sh --step hypr-chrome # one step
./setup.sh --revert           # undo everything, reverse order
omarchy restart shell && hyprctl reload
```

| Step | What | Where |
|------|------|-------|
| `shell-shadows` | QML card shadows (`BorderSurface` + `Style` + card opt-ins + template default) | `/usr/share/omarchy` (sudo) |
| `hypr-chrome` | single-window-no-border + bar-aware gaps lua | `~/.config/hypr/` |
| `bar-gap` | live gap sync when bar transparency changes (watcher service + boot/theme hooks) | `~/.local/bin`, user systemd, hooks |

Without setup the theme still works — flat cards, stock borders. Shadows and
window chrome are the soft part.

## Fonts

Barista is designed around **Inter** for UI and **JetBrainsMono Nerd Font**
for monospace. These are system settings, not theme files — set them after
installing:

```
omarchy font set "JetBrainsMono Nerd Font"
font-ui-set Inter
```

## Wallpaper

Bring your own — drop images into `~/.config/omarchy/themes/barista/backgrounds/`.
The author's pick was a warm café-toned photo (Pexels, not redistributed here).
