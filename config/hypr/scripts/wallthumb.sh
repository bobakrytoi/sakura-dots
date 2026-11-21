#!/usr/bin/env bash
# wallthumb.sh FILE [SIZE]  -> prints a cached still of FILE: a frame for videos, a small copy for pictures.
# ~/.cache/sakura/thumbs/<md5 of the path>-<size>.jpg; rebuilt when FILE is newer. SIZE: width in px (0 = full).
f="$1"; size="${2:-640}"
[ -f "$f" ] || exit 1
dir="${XDG_CACHE_HOME:-$HOME/.cache}/sakura/thumbs"; mkdir -p "$dir"
out="$dir/$(printf '%s' "$f" | md5sum | cut -c1-16)-$size.jpg"
if [ ! -s "$out" ] || [ "$f" -nt "$out" ]; then
  case "${f,,}" in
    *.mp4|*.webm|*.mkv|*.mov|*.avi) ffmpegthumbnailer -i "$f" -o "$out" -s "$size" -t 15% -q 8 >/dev/null 2>&1 ;;
    *) if [ "$size" = 0 ]; then magick "$f[0]" "$out" 2>/dev/null; else magick "$f[0]" -resize "${size}x" -quality 85 "$out" 2>/dev/null; fi ;;
  esac
fi
[ -s "$out" ] && echo "$out"
