#!/usr/bin/env bash
# prints a path to a small rounded cover of the current track (for the waybar image module); nothing if no cover
C="$HOME/.cache/covers"; mkdir -p "$C"
url=$(playerctl -i playerctld metadata mpris:artUrl 2>/dev/null | head -1)
[ -z "$url" ] && exit 0
key=$(printf '%s' "$url" | md5sum | cut -c1-16)
out="$C/$key.png"
if [ ! -s "$out" ]; then
  src="$C/$key.src"
  case "$url" in
    file://*) cp "$(python3 -I -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1][7:]))' "$url")" "$src" 2>/dev/null ;;
    http*)    curl -sL --max-time 4 -o "$src" "$url" ;;
    *)        exit 0 ;;
  esac
  [ -s "$src" ] || exit 0
  magick "$src" -resize 96x96^ -gravity center -extent 96x96 \
    \( -size 96x96 xc:none -fill white -draw "roundrectangle 0,0,95,95,22,22" \) -alpha off -compose CopyOpacity -composite "$out" 2>/dev/null
  rm -f "$src"
  # keep the cache small
  ls -t "$C"/*.png 2>/dev/null | tail -n +40 | xargs -r rm -f
fi
[ -s "$out" ] && echo "$out"
