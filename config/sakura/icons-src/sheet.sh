#!/bin/bash
# usage: sheet.sh ICONDIR OUT.png   (ICONDIR has sakura-*.svg and sakura-*-small.svg)
set -e
D=$1; OUT=$2; T=$(mktemp -d)
find_icon() { # theme name
  for t in "$@"; do :; done
}
pap=/usr/share/icons/Papirus-Dark/64x64/apps
others=("$pap/brave-browser.svg" "$pap/discord.svg" "$pap/kitty.svg" "$pap/org.gnome.Nautilus.svg")
pick() { for f in "$@"; do [ -f "$f" ] && { echo "$f"; return; }; done; }
ctx=(
 "$(pick /usr/share/icons/Adwaita/scalable/apps/org.gnome.Settings.svg /usr/share/icons/Adwaita/scalable/categories/applications-system.svg)"
 "$(pick /usr/share/icons/breeze/apps/48/systemsettings.svg /usr/share/icons/breeze/apps/48/preferences-system.svg)"
 "$(pick /usr/share/icons/breeze/apps/48/utilities-system-monitor.svg /usr/share/icons/breeze/apps/48/ksysguard.svg)"
 "$(pick $pap/utilities-system-monitor.svg)"
 "$(pick $pap/preferences-system.svg)"
)
rows=()
for bg in "#12141c" "#e9e7ee"; do
 for s in 16 24 48 96; do
  pad=$(( s/2 + 6 )); items=()
  for n in sakura-settings sakura-taskmgr; do
    src=$D/$n.svg; [ $s -le 24 ] && [ -f $D/$n-small.svg ] && src=$D/$n-small.svg
    rsvg-convert -w $s -h $s "$src" -o $T/$n-$s.png; items+=($T/$n-$s.png)
  done
  i=0; for f in "${others[@]}" "${ctx[@]}"; do [ -n "$f" ] || continue; i=$((i+1))
    rsvg-convert -w $s -h $s "$f" -o $T/o$i-$s.png 2>/dev/null && items+=($T/o$i-$s.png); done
  magick -background "$bg" "${items[@]}" -gravity center -extent 120x$((s+16)) +append $T/row-$bg-$s.png
  rows+=($T/row-$bg-$s.png)
 done
done
magick -background "#12141c" "${rows[@]}" -append -bordercolor "#12141c" -border 12 "$OUT"
echo "$OUT"; rm -rf $T
