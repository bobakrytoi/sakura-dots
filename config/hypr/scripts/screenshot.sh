#!/usr/bin/env bash
# screenshots: region | screen | edit
dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"
f="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
slurp_args=(-d -b 0e0e1088 -c f4b6c8ff -s ffffff10 -w 2)
case "$1" in
  region) g=$(slurp "${slurp_args[@]}") || exit 0; grim -g "$g" "$f" ;;
  screen) mon=$(hyprctl activeworkspace -j | python3 -c 'import json,sys;print(json.load(sys.stdin)["monitor"])'); grim -o "$mon" "$f" ;;
  edit)   g=$(slurp "${slurp_args[@]}") || exit 0
          grim -g "$g" - | satty --filename - --output-filename "$f" --copy-command wl-copy --early-exit --initial-tool brush --corner-roundness 12
          exit 0 ;;
esac
wl-copy < "$f"
"$HOME/.config/hypr/scripts/sfx.sh" screenshot &
notify-send -a "Screenshot" -i "$f" "Screenshot saved" "Copied to clipboard · ~/Pictures/Screenshots"
