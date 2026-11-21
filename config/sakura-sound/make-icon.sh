#!/usr/bin/env bash
# App icon = the in-app mark (SakuraMark.qml): five notched petals in the accent colour, dark core.
#   make-icon.sh [#rrggbb]   (default: accent from ~/.config/sakura/settings.json); skips if unchanged
c="${1:-$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/sakura/settings.json"))).get("accent","#f2b8d0"))' 2>/dev/null)}"
[[ "$c" =~ ^#[0-9a-fA-F]{6}$ ]] || c="#f2b8d0"
H="$HOME/.local/share/icons/hicolor"
stamp="$HOME/.cache/sakura-sound/icon-color"
[ "$(cat "$stamp" 2>/dev/null)" = "$c" ] && [ -f "$H/scalable/apps/sakura-sound.svg" ] && exit 0
mkdir -p "$H/scalable/apps" "$(dirname "$stamp")"
petal='M100 92 C66 74 58 30 82 8 L100 22 L118 8 C142 30 134 74 100 92 Z'
# explicit paths (Qt's SVG renderer doesn't support <use href>)
{
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">'
  echo "  <g fill=\"$c\">"
  for a in 0 72 144 216 288; do echo "    <path transform=\"rotate($a 100 100)\" d=\"$petal\"/>"; done
  echo '  </g>'
  echo '  <circle cx="100" cy="100" r="16" fill="#0f1119" fill-opacity=".9"/>'
  echo '</svg>'
} > "$H/scalable/apps/sakura-sound.svg"
: <<'SVG'
SVG
for s in 16 22 24 32 48 64 128 256 512; do
    mkdir -p "$H/${s}x${s}/apps"
    magick -background none -density 384 "$H/scalable/apps/sakura-sound.svg" -resize ${s}x${s} "$H/${s}x${s}/apps/sakura-sound.png"
done
gtk-update-icon-cache -f -t "$H" >/dev/null 2>&1
echo "$c" > "$stamp"
