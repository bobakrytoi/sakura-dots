#!/usr/bin/env bash
# start menu: quickshell if available, otherwise the rofi launcher
if command -v qs >/dev/null; then
  pgrep -x quickshell >/dev/null || pgrep -x qs >/dev/null || { setsid qs >/dev/null 2>&1 & sleep 0.6; }
  qs ipc call menu toggle
else
  pkill -x rofi || rofi -show drun
fi
