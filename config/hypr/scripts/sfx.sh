#!/usr/bin/env bash
# play a soft system sound:  sfx.sh notify|screenshot|volume|saved|login|error   (off if ~/.config/sakura/sounds-off exists)
[ -e "$HOME/.config/sakura/sounds-off" ] && exit 0
f="$HOME/.local/share/sounds/sakura/$1.wav"
[ -f "$f" ] && exec pw-play --volume 0.6 "$f" >/dev/null 2>&1
