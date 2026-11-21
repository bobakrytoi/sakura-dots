#!/usr/bin/env bash
# wallplay.sh FILE HEIGHT -> prints the file the desktop should play for a video wallpaper on a screen HEIGHT px tall
# (the way iNiR does it): the original when it is no taller than ~115 % of the screen, otherwise a copy scaled to that
# height (same fps, near-lossless). Copies are made ONE AT A TIME (a queue lock - callers wait their turn) at the
# lowest CPU/disk priority, on the GPU (NVENC) or with x264. Cache: ~/.cache/sakura/wallplay/, newest 12 kept.
f="$1"; h="${2:-1080}"; [ -f "$f" ] || exit 1
dir="${XDG_CACHE_HOME:-$HOME/.cache}/sakura/wallplay"; mkdir -p "$dir"
src_h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$f" 2>/dev/null | head -1)
[ -n "$src_h" ] && [ "$src_h" -le $(( h * 115 / 100 )) ] && { echo "$f"; exit 0; }
out="$dir/$(printf '%s' "$f" | md5sum | cut -c1-16)-${h}.mp4"
[ -s "$out" ] && [ "$out" -nt "$f" ] && { echo "$out"; exit 0; }
exec 8>"$dir/.queue.lock"; flock 8                       # wait for our turn: never two encodes at once
[ -s "$out" ] && [ "$out" -nt "$f" ] && { echo "$out"; exit 0; }
tmp="$out.part"; rm -f "$tmp"
vf="scale=-2:${h}:flags=lanczos,format=yuv420p"
nice -n 19 ionice -c 3 ffmpeg -nostdin -loglevel error -y -i "$f" -an -sn -dn -vf "$vf" -c:v h264_nvenc -preset p4 -rc vbr -cq 17 -b:v 0 -g 60 -movflags +faststart -f mp4 "$tmp" \
  || nice -n 19 ionice -c 3 ffmpeg -nostdin -loglevel error -y -i "$f" -an -sn -dn -vf "$vf" -c:v libx264 -preset veryfast -crf 18 -g 60 -movflags +faststart -f mp4 "$tmp"
if [ -s "$tmp" ]; then mv "$tmp" "$out"; echo "$out"; else rm -f "$tmp"; echo "$f"; fi
ls -t "$dir"/*.mp4 2>/dev/null | tail -n +13 | xargs -r rm -f
