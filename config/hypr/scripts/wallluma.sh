#!/usr/bin/env bash
# wallluma.sh FILE -> brightness of the wallpaper as a 32x18 grid (0..255, row by row, space separated),
# cropped like awww does (fill). Desktop widgets use it to pick dark or light text under themselves.
f="$1"; [ -f "$f" ] || exit 1
case "${f,,}" in *.mp4|*.webm|*.mkv|*.mov) f=$("$(dirname "$(readlink -f "$0")")/wallthumb.sh" "$f" 640) ;; esac
magick "$f[0]" -resize 32x18^ -gravity center -extent 32x18 -colorspace Gray -depth 8 txt:- 2>/dev/null \
  | awk 'NR>1 { match($0, /\(([0-9.]+)/, m); printf "%d ", m[1] }'
