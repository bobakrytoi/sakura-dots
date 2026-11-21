#!/usr/bin/env bash
# clipboard history: the quickshell window (Clipboard.qml); rofi if the shell isn't running
qs ipc call clipboard toggle 2>/dev/null && exit 0
sel=$(cliphist list | rofi -dmenu -i -p "clipboard" -theme ~/.config/rofi/list.rasi) || exit 0
printf '%s' "$sel" | cliphist decode | wl-copy
