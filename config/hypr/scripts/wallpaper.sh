#!/usr/bin/env bash
# wallpaper.sh restore      -> show the wallpaper chosen in Settings (or ~/Pictures/Wallpapers/main.jpg)
# wallpaper.sh set FILE     -> show FILE now and remember it (~/.config/sakura/settings.json "wallpaper")
# wallpaper.sh list         -> pictures and videos in ~/Pictures/Wallpapers and ~/Pictures
# wallpaper.sh show FILE    -> show FILE now, don't touch settings.json
# wallpaper.sh still FILE   -> the picture awww shows for FILE (a frame for videos; quickshell plays the video on top)
S="$HOME/.config/sakura/settings.json"
D="$(dirname "$(readlink -f "$0")")"
# transition + fill from settings.json (Settings > Wallpaper): wallTransition, wallDuration, wallFill
read -r tt td tf < <(python3 -I -c 'import json,sys
try: c = json.load(open(sys.argv[1]))
except Exception: c = {}
print(c.get("wallTransition", "grow"), c.get("wallDuration", 1.2), c.get("wallFill", "crop"))' "$S" 2>/dev/null)
anim=(--transition-type "${tt:-grow}" --transition-pos center --transition-fps 120 --transition-duration "${td:-1.2}" --resize "${tf:-crop}")
still() { case "${1,,}" in *.mp4|*.webm|*.mkv|*.mov) "$D/wallthumb.sh" "$1" 0 ;; *) echo "$1" ;; esac; }
case "$1" in
  list)  dir=$(python3 -I -c 'import json,sys,os;print(os.path.expanduser(json.load(open(sys.argv[1])).get("wallDir","~/Pictures/Wallpapers")))' "$S" 2>/dev/null)
         find "${dir:-$HOME/Pictures/Wallpapers}" "$HOME/Pictures/Wallpapers" "$HOME/Pictures" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \) 2>/dev/null | sort -u ;;
  still) [ -f "$2" ] && still "$2" ;;
  show)  [ -f "$2" ] || exit 1; img=$(still "$2"); [ -n "$img" ] && awww img "$img" "${anim[@]}" ;;   # show without saving (Settings saves)
  set)   [ -f "$2" ] || exit 1
         img=$(still "$2"); [ -n "$img" ] && awww img "$img" "${anim[@]}"
         python3 -I - "$S" "$2" <<'PY'
import json, sys, os
p, f = sys.argv[1], sys.argv[2]
try: c = json.load(open(p))
except Exception: c = {}
c["wallpaper"] = f
open(p + ".tmp", "w").write(json.dumps(c, indent=2, ensure_ascii=False)); os.replace(p + ".tmp", p)
PY
         ;;
  *)     f=$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get("wallpaper",""))' "$S" 2>/dev/null)
         [ -f "$f" ] || f="$HOME/Pictures/Wallpapers/main.jpg"
         [ -f "$f" ] || f=$("$0" list | head -1)
         [ -n "$f" ] && img=$(still "$f") && [ -n "$img" ] && awww img "$img" "${anim[@]}" ;;
esac
# the SDDM login screen follows the wallpaper (a still in /var/lib/sakura-sddm; no-op if not set up)
case "$1" in set|show) setsid -f "$D/sddm-sync.sh" wall "$2" >/dev/null 2>&1 ;; restore|"") setsid -f "$D/sddm-sync.sh" all >/dev/null 2>&1 ;; esac
# Discord (Vencord) theme follows the wallpaper too (debounced inside)
case "$1" in set|show) setsid -f "$D/vencord-theme.sh" "$2" >/dev/null 2>&1 ;; restore|"") setsid -f "$D/vencord-theme.sh" >/dev/null 2>&1 ;; esac
