#!/usr/bin/env bash
# clip.sh list          -> JSON lines {id, text, img, size} from cliphist (newest first, max 300)
# clip.sh thumb ID      -> cached png of an image entry (~/.cache/sakura/clip/ID.png)
# clip.sh copy ID       -> put entry ID back on the clipboard
# clip.sh delete ID     -> forget entry ID
# clip.sh wipe          -> forget everything (pins stay)
# clip.sh copyfile F    -> clipboard = file F (a pinned picture);  clip.sh copytext TEXT
cache="${XDG_CACHE_HOME:-$HOME/.cache}/sakura/clip"; mkdir -p "$cache"
case "$1" in
  list) cliphist list | head -300 | python3 -I -c '
import sys, json, re
for line in sys.stdin:
    line = line.rstrip("\n")
    if "\t" not in line: continue
    i, t = line.split("\t", 1)
    m = re.match(r"\[\[ binary data (.+?) (png|jpe?g|webp|gif|bmp) (\d+)x(\d+) \]\]", t)
    print(json.dumps({"id": i, "text": "" if m else t, "img": bool(m), "size": (m.group(3) + "×" + m.group(4)) if m else ""}, ensure_ascii=False))' ;;
  thumb) f="$cache/$2.png"; s="$cache/$2-s.jpg"   # full png (for pins) + a small jpg for the list
         [ -s "$f" ] || printf '%s\t\n' "$2" | cliphist decode > "$f" 2>/dev/null
         [ "$3" = small ] && { [ -s "$s" ] || magick "$f" -resize 240x144^ -quality 85 "$s" 2>/dev/null; [ -s "$s" ] && echo "$s" && exit; }
         [ -s "$f" ] && echo "$f" ;;
  thumbs) shift; for i in "$@"; do printf '%s\t%s\n' "$i" "$("$0" thumb "$i" small)"; done ;;   # many at once: id<TAB>path
  copy) printf '%s\t\n' "$2" | cliphist decode | wl-copy ;;
  delete) printf '%s\t\n' "$2" | cliphist delete; rm -f "$cache/$2.png" "$cache/$2-s.jpg" ;;
  wipe) cliphist wipe; rm -f "$cache"/*.png "$cache"/*.jpg ;;
  copyfile) wl-copy < "$2" ;;
  copytext) printf '%s' "$2" | wl-copy ;;
  full) printf '%s\t\n' "$2" | cliphist decode ;;
esac
