#!/usr/bin/env bash
# clipboard history
sel=$(cliphist list | rofi -dmenu -i -p "clipboard" -theme ~/.config/rofi/list.rasi) || exit 0
printf '%s' "$sel" | cliphist decode | wl-copy
