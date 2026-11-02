# ✿ sakura mono — Arch + Hyprland rice

Dark sakura theme for **Arch Linux + Hyprland (Lua config, 0.57)** with a fully custom shell written in **Quickshell**:
start menu, dock, dashboard, Alt+Tab, capture overlay, settings app, volume mixer and more.

> i use arch btw

## What's inside

| Part | What it does |
|---|---|
| **Start menu** (Win) | Search apps, files, calculator (`2^10+15% of 200`), currency (`100 usd to uah`), commands (`reboot`, `lock`…), web search. Pinned apps, volume, quick toggles, settings, player |
| **Dock** | Pinned + running apps, drag to reorder, right-click menu, avatar start button |
| **Dashboard** (click the clock) | Weather, calendar, CPU/RAM/GPU rings, record-style player with live visualizer + synced lyrics, performance page, 7-day forecast |
| **Alt+Tab** | Live window previews, minimized windows too |
| **Capture** (Alt+Z) | ShadowPlay-like: instant replay, recording, screenshot, hotkeys and quality settings (gpu-screen-recorder, NVENC) |
| **Settings app** | Sound devices, displays, **Color Control** (digital vibrance, contrast, gamma, night light), network/VPN, appearance, keyboard/mouse, power & sleep, **RGB lighting** (OpenRGB) |
| **Volume mixer** (click the volume) | Output device + per-app volume |
| **Window snapping** | Drag to an edge/corner → half/quarter/fill with a pink outline preview |
| **Desktop widgets** | Big clock, date, weather, now playing on the wallpaper |
| **Game mode** | Fullscreen games get no blur/animations, tearing + VRR; color correction stays |
| **Extras** | Custom icons, pink Bibata cursor, soft system sounds, Plymouth boot splash, SDDM login theme, fastfetch, terminal toys (`fun`) |

## Install

```bash
git clone -b ARCH <this repo> sakura-dots && cd sakura-dots
./install.sh --packages          # configs + all packages
./install.sh --packages --system # + login theme and boot splash (sudo)
```

Then log out and choose **Hyprland (uwsm)**.

Set your monitors in the `MONITORS` block of `~/.config/hypr/hyprland.lua` (made for 2× 1920×1080 @ 200 Hz, `DP-3` left/main, `DP-1` right).

## Keybinds

| Keys | Action |
|---|---|
| Win | Start menu |
| Super+Q / Enter | Terminal |
| Super+E | Files |
| Super+B | Browser |
| Super+C | Close window |
| Super+Up / Down | Maximize / minimize |
| Super+F | Fullscreen |
| Super+T | Float / tile |
| Super+G | Center a lost window |
| Super+V | Clipboard history |
| Super+N | Notifications |
| Super+L | Lock |
| Super+/ | All keybinds |
| Alt+Tab | Switch windows |
| Alt+Z | Capture overlay |
| Alt+Shift+F10 | Save instant replay |
| Alt+F9 | Record |
| Super+Shift+S / Print | Screenshot area |
| Alt+Shift | Switch keyboard layout |

## Layout

```
config/      → ~/.config        (hypr, quickshell, waybar, rofi, kitty, swaync, …)
local/       → ~/.local/share   (icons, cursor, sounds, app overrides)
wallpapers/  → ~/Pictures/Wallpapers
images/      anime art used in menus, avatar
system/      Plymouth + SDDM themes and the step-by-step setup scripts
packages.txt / aur.txt   package lists
```
