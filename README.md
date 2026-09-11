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

## Shadows need the shell patch

`shell.shadow.toml` is read by a small patch to omarchy-shell
(`BorderSurface` + `Style` + card opt-ins). Stock Omarchy ignores it and the
theme renders flat — still fine, just less soft. To get shadows, apply the
patch from this repo's companion scripts (requires the Omarchy source tree):

```
sudo ./shadow-patch/apply-shadows.sh
omarchy restart shell
```

Revert anytime with `sudo ./shadow-patch/revert-shadows.sh`.

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
