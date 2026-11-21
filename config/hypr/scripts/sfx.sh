#!/usr/bin/env bash
# play a soft system sound:  sfx.sh notify|screenshot|volume|saved|login|error
# off: ~/.config/sakura/sounds-off exists, or the event is in settings.json "sfxOff"; volume: "sfxVolume" (0..1)
[ -e "$HOME/.config/sakura/sounds-off" ] && exit 0
f="$HOME/.local/share/sounds/sakura/$1.wav"; [ -f "$f" ] || exit 0
v=$(python3 -I -c 'import json,sys
try: c = json.load(open(sys.argv[1]))
except Exception: c = {}
print("off" if sys.argv[2] in c.get("sfxOff", []) else c.get("sfxVolume", 0.6))' "$HOME/.config/sakura/settings.json" "$1" 2>/dev/null)
[ "$v" = off ] && exit 0
exec pw-play --volume "${v:-0.6}" "$f" >/dev/null 2>&1
