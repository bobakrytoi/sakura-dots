#!/usr/bin/env bash
# avatar.sh pick | set FILE | reset - the picture used in the dock, start menu, dashboard, lock screen and widgets
# (~/.config/hypr/assets/avatar.png; hyprlock reads it too). Crops to a centred square, 512 px. The old one is kept as avatar.prev.png.
A="$HOME/.config/hypr/assets/avatar.png"; mkdir -p "$(dirname "$A")"
SY="$(dirname "$(readlink -f "$0")")/sddm-sync.sh"   # copies it for the SDDM login screen
FF="$HOME/.config/fastfetch/make-logo.sh"   # refresh the fastfetch logo
case "$1" in
  pick)  f=$(zenity --file-selection --title="Avatar" --file-filter="Pictures | *.png *.jpg *.jpeg *.webp *.gif" 2>/dev/null) || exit 1 ;;
  set)   f="$2" ;;
  reset) [ -f "${A%.png}.prev.png" ] && cp "${A%.png}.prev.png" "$A"; "$FF" & "$SY" avatar >/dev/null 2>&1 & echo ok; exit 0 ;;
  *) exit 1 ;;
esac
[ -f "$f" ] || exit 1
[ -f "$A" ] && cp "$A" "${A%.png}.prev.png"
magick "$f[0]" -auto-orient -resize 512x512^ -gravity center -extent 512x512 "$A.tmp.png" && mv "$A.tmp.png" "$A" && { "$FF" & "$SY" avatar >/dev/null 2>&1 & echo ok; }
