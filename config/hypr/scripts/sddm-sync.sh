#!/usr/bin/env bash
# sddm-sync.sh - keep the SDDM login screen in step with the desktop, without sudo.
# Writes into /var/lib/sakura-sddm/ (yours, world-readable; made once by sddm-theme.sh), which the sakura SDDM theme reads:
#   background.jpg      a still of the current wallpaper (a frame for videos), cropped to the main monitor, jpg q90
#   avatar.png          ~/.config/hypr/assets/avatar.png
#   theme.conf.user     [General] accent=…  (the theme dir has a symlink theme.conf.user -> here; SDDM reads it over theme.conf)
# Usage:  sddm-sync.sh [all]        everything (cheap: skips what hasn't changed)
#         sddm-sync.sh wall [FILE]  the wallpaper (FILE, else the one in settings.json)
#         sddm-sync.sh avatar | accent [#hex]
# Hooked from wallpaper.sh (set/show/restore), accent.sh (set/apply), avatar.sh. Quiet no-op if the dir isn't set up.
O="${SAKURA_SDDM_DIR:-/var/lib/sakura-sddm}"
[ -d "$O" ] && [ -w "$O" ] || exit 0
S="$HOME/.config/sakura/settings.json"
D="$(dirname "$(readlink -f "$0")")"
exec 9>"$O/.lock"; flock 9
umask 022
cfg() { python3 -I -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))
except Exception: print("")' "$S" "$1" 2>/dev/null; }

wall() {
  local f="${1:-$(cfg wallpaper)}"
  [ -f "$f" ] || f="$HOME/Pictures/Wallpapers/main.jpg"
  [ -f "$f" ] || return 0
  # main monitor size (settings.json mainMonitor, else the one at x=0), fallback 1920x1080
  local wh; wh=$(hyprctl monitors -j 2>/dev/null | python3 -I -c 'import json,sys
want = sys.argv[1]
try: ms = json.load(sys.stdin)
except Exception: ms = []
m = next((m for m in ms if m["name"] == want), None) or next((m for m in ms if m["x"] == 0), None)
print("%dx%d" % (m["width"], m["height"]) if m else "")' "$(cfg mainMonitor)")
  [ -n "$wh" ] || wh=1920x1080
  local key; key="$f|$(stat -c %Y "$f")|$wh"
  [ -s "$O/background.jpg" ] && [ "$(cat "$O/.wall-src" 2>/dev/null)" = "$key" ] && return 0
  local img="$f"
  case "${f,,}" in *.mp4|*.webm|*.mkv|*.mov|*.avi) img=$("$D/wallthumb.sh" "$f" 0) || return 0 ;; esac
  [ -s "$img" ] || return 0
  magick "$img[0]" -auto-orient -resize "$wh^" -gravity center -extent "$wh" -strip -quality 90 "$O/.bg.tmp.jpg" 2>/dev/null || return 0
  chmod 644 "$O/.bg.tmp.jpg" && mv -f "$O/.bg.tmp.jpg" "$O/background.jpg" && printf '%s' "$key" > "$O/.wall-src"
}
avatar() {
  local a="$HOME/.config/hypr/assets/avatar.png"
  [ -f "$a" ] || return 0
  cmp -s "$a" "$O/avatar.png" && return 0
  cp -f "$a" "$O/.av.tmp.png" && chmod 644 "$O/.av.tmp.png" && mv -f "$O/.av.tmp.png" "$O/avatar.png"
}
accent() {
  local hx="${1:-$(cfg accent)}"; [[ "$hx" =~ ^#[0-9a-fA-F]{6}$ ]] || hx="#f2b8d0"
  local t; t=$(printf '[General]\ndefaultUser=%s\naccent=%s\n' "$USER" "$hx")
  [ "$(cat "$O/theme.conf.user" 2>/dev/null)" = "$t" ] && return 0
  printf '%s\n' "$t" > "$O/.conf.tmp" && chmod 644 "$O/.conf.tmp" && mv -f "$O/.conf.tmp" "$O/theme.conf.user"
}
case "$1" in
  wall)   wall "$2" ;;
  avatar) avatar ;;
  accent) accent "$2" ;;
  *)      wall; avatar; accent ;;
esac
exit 0
