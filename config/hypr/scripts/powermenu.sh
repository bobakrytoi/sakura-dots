#!/usr/bin/env bash
# power menu: the shell's full-screen session screen (quickshell SessionScreen.qml); rofi if the shell is down
qs ipc call session open >/dev/null 2>&1 && exit 0
opts="\n󰍃\n󰒲\n󰜉\n"
ch=$(echo -e "$opts" | rofi -dmenu -p "$(uptime -p | sed 's/up /uptime: /')" -theme ~/.config/rofi/power.rasi) || exit 0
case "$ch" in
  "")   loginctl lock-session ;;
  "󰍃") ~/.config/hypr/scripts/session.py save; uwsm stop || hyprctl dispatch 'hl.dsp.exit()' ;;
  "󰒲")  systemctl suspend ;;
  "󰜉") ~/.config/hypr/scripts/session.py save; systemctl reboot ;;
  "")    ~/.config/hypr/scripts/session.py save; systemctl poweroff ;;
esac
