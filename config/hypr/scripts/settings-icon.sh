#!/usr/bin/env bash
# Settings app icon in the system accent: dark glass tile + accent gear (works with any palette).
#   settings-icon.sh [#rrggbb]   (default: accent from settings.json); skips if unchanged. Called by accent.sh.
c="${1:-$(python3 -I -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/sakura/settings.json"))).get("accent","#f2b8d0"))' 2>/dev/null)}"
[[ "$c" =~ ^#[0-9a-fA-F]{6}$ ]] || c="#f2b8d0"
H="$HOME/.local/share/icons/hicolor"; T="$H/scalable/apps/sakura-settings.svg.tpl"
stamp="$HOME/.cache/sakura/settings-icon-color"
[ -f "$T" ] || exit 0
[ "$(cat "$stamp" 2>/dev/null)" = "$c" ] && exit 0
mkdir -p "$(dirname "$stamp")"
python3 -I - "$T" "$H/scalable/apps/sakura-settings.svg" "$c" <<'PY'
import sys
t = open(sys.argv[1]).read(); c = sys.argv[3]
t = (t.replace('stop-color="#f5a9c8"', 'stop-color="#2c3144"')      # tile: neutral dark glass
      .replace('stop-color="#cf5f90"', 'stop-color="#141722"')
      .replace('fill="#7a2450" opacity=".22"', 'fill="#000" opacity=".35"')   # gear shadow
      .replace('fill="#fff" stroke="#fff"', f'fill="{c}" stroke="{c}"'))       # gear = accent
open(sys.argv[2], "w").write(t)
PY
for s in 16 22 24 32 48 64 128 256 512; do
    mkdir -p "$H/${s}x${s}/apps"
    magick -background none -density 384 "$H/scalable/apps/sakura-settings.svg" -resize ${s}x${s} "$H/${s}x${s}/apps/sakura-settings.png"
done
gtk-update-icon-cache -f -t "$H" >/dev/null 2>&1
echo "$c" > "$stamp"
