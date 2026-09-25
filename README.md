# Barista

A warm, familiar Omarchy theme. Designed to feel at home in a café, not a
server room — familiar shapes, readable type, soft shadows. Different enough
to be yours, normal enough that nobody asks what OS that is.

```
omarchy theme install https://github.com/Flyvendestruds/omarchy-barista-theme
./setup.sh                    # installs barista-dark + behavior (asks sudo for system steps only)
```

Barista Dark (warm espresso night variant) ships in `barista-dark/` but
`omarchy theme install` only stages the root as `barista` — run `./setup.sh`
(or `./setup.sh --step theme-install`) to install it, then
`omarchy theme set barista-dark`.

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
./setup.sh --step weather     # optional weather add-on only
./setup.sh --revert           # undo everything, reverse order
omarchy restart shell && hyprctl reload
```

| Step | What | Where |
|------|------|-------|
| `shell-shadows` | QML card shadows (`BorderSurface` + `Style` + card opt-ins + template default) + live per-side shell gaps (toasts/OSD track the bar edge) | `/usr/share/omarchy` (sudo) |
| `theme-install` | installs `barista-dark/` into `~/.config/omarchy/themes/` (theme install only stages `barista`) | `~/.config/omarchy/themes/` |
| `hypr-chrome` | gated looknfeel (rounding/gaps/borders, replaces `my_theme_gen`) + single-window borders + bar-aware gaps | `~/.config/hypr/` |
| `bar-gap` | live gap sync when bar transparency changes; runs only while barista is active (theme-set/post-boot gates) | `~/.local/bin`, user systemd, hooks |
| `theme-dev` | live-edit loop (`barista-tokens-apply` + watcher units). Dev-only, skip on fresh machines | `~/.local/bin`, user systemd |
| `update-hook` | post-update repair (re-runs `shell-shadows` after `omarchy update`, notifies) | `~/.config/omarchy/hooks/post-update.d` |
| `panel-switch` | one-click switching between bar popouts (clicking another widget opens it instead of just closing the current one) | `/usr/share/omarchy` (sudo) |
| `panel-morph` | morph between panels (new card reshapes from the old one when close; gentle scale+fade when far) | `/usr/share/omarchy` (sudo) |
| `weather` *(optional)* | barista weather add-on: installs + enables [omarchy-barista-weather](https://github.com/Flyvendestruds/omarchy-barista-weather) (hourly strip, PNG icons, sky-tinted card). Skipped unless you run `./setup.sh --step weather` | `~/.config/omarchy/plugins/` |

> `setup.sh` runs every step including `weather`. To skip the add-on, run
> the steps you want individually (`./setup.sh --step hypr-chrome`, …) or
> `./setup.sh --revert --step weather` afterwards — stock weather returns.

Without setup the theme still works — flat cards, stock borders. Shadows and
window chrome are the soft part.

## Hacking on barista

Theme files live at the repo root (`colors.toml`, `shell.*.toml`); the dark
variant lives in `barista-dark/` (same layout, warm espresso palette).
Push them live with `./setup/sync-theme.sh` (copies into
`~/.config/omarchy/themes/barista/` and `.../barista-dark/`); the tokens
watcher re-renders `shell.toml` and pushes it to the running shell on every
save. Hypr chrome lives in `setup/files/hypr-chrome/` — edit there, re-run
`./setup.sh --step hypr-chrome`, `hyprctl reload` to preview.

`barista-dark/backgrounds/` ships only a `.gitkeep` — bring your own night
wallpaper (the author's pick, Osaka Jade's `2-shaded-entrance.jpg`, is stock
Omarchy art, not redistributed here).

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
