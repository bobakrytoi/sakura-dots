#!/usr/bin/env bash
# called by gpu-screen-recorder after saving: $1 = file, $2 = type (replay / regular)
if [ "$2" = "replay" ]; then t="Instant Replay saved"; else t="Recording saved"; fi
notify-send -a "Capture" -i video-x-generic "$t" "$(basename "$1")"
"$HOME/.config/hypr/scripts/sfx.sh" saved
