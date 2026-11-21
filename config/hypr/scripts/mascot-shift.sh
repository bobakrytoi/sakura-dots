#!/bin/sh
# Triple Shift (3 taps within 0.9 s) → the mascot flexes (Mascot.qml flex mode). Called on every Shift release
# (hyprland.lua: SHIFT_L / SHIFT_R release binds); keeps the last two tap times in $XDG_RUNTIME_DIR.
f="${XDG_RUNTIME_DIR:-/tmp}/sakura-shift-taps"
now=$(date +%s%3N)
set -- $(cat "$f" 2>/dev/null)
last=${2:-$1}
[ -n "$last" ] && [ $((now - last)) -lt 90 ] && exit 0     # one release can arrive twice - count it once
if [ -n "$2" ] && [ $((now - $1)) -le 900 ]; then
  : > "$f"
  exec qs ipc call mascot flex
fi
echo "$last $now" > "$f"
