#!/usr/bin/env bash
# lock the screen; key sounds are enabled only while locked (see "lock key sounds" in hyprland.lua)
pidof hyprlock >/dev/null && exit 0
qs ipc call pwhelper screenLocked >/dev/null 2>&1 &     # Password helper: lock the vault with the screen (if set)
# Settings > Power & Sleep > Lock screen = "sakura": the quickshell lock (Lock.qml); hyprlock otherwise / as a fallback
mode=$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get("lockScreen","hyprlock"))' "$HOME/.config/sakura/settings.json" 2>/dev/null)
[ "$mode" = sakura ] && qs ipc call lock lock 2>/dev/null && exit 0
hyprctl eval '__setLockKeys(true)' >/dev/null 2>&1
# main monitor + wallpaper for hyprlock.conf, and the cover of what is playing (so it is there at once)
"$HOME/.config/hypr/scripts/lock-info.sh" vars
"$HOME/.config/hypr/scripts/lock-info.sh" art >/dev/null
hyprlock
hyprctl eval '__setLockKeys(false)' >/dev/null 2>&1
