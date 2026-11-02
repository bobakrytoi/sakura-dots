#!/usr/bin/env bash
# Делает обои 1920x1080 из маленьких картинок:
# размытый затемненный фон + сама картинка карточкой со скругленными углами и тенью.
set -e
SRC="$HOME/.config/rice/src"
OUT="$HOME/Pictures/Wallpapers"
W=1920; H=1080; CARD_H=820; R=36
mkdir -p "$OUT"
tmp=$(mktemp -d)
n=1
for f in "$SRC"/*.jpg; do
  o="$OUT/sakura-$(printf %02d $n).png"
  # фон
  magick "$f" -strip -colorspace sRGB -type TrueColor -resize "${W}x${H}^" -gravity center -extent ${W}x${H} \
    -blur 0x28 -evaluate multiply 0.5 -fill '#0e0e10' -colorize 25% "$tmp/bg.png"
  # карточка
  magick "$f" -strip -colorspace sRGB -type TrueColor -filter Lanczos -resize "x${CARD_H}" -resize "1500x${CARD_H}>" "$tmp/card.png"
  read cw ch < <(magick identify -format '%w %h\n' "$tmp/card.png")
  magick -size ${cw}x${ch} xc:none -fill white -draw "roundrectangle 0,0,$((cw-1)),$((ch-1)),$R,$R" "$tmp/mask.png"
  magick "$tmp/card.png" "$tmp/mask.png" -alpha off -compose CopyOpacity -composite "$tmp/card_r.png"
  magick "$tmp/card_r.png" -fill none -stroke 'rgba(255,255,255,0.28)' -strokewidth 2 \
    -draw "roundrectangle 1,1,$((cw-2)),$((ch-2)),$R,$R" "$tmp/card_r.png"
  magick "$tmp/card_r.png" \( +clone -background black -shadow 70x30+0+18 \) +swap \
    -background none -layers merge +repage "$tmp/card_s.png"
  magick "$tmp/bg.png" "$tmp/card_s.png" -gravity center -geometry +0+8 -composite "$o"
  echo "✓ $o"
  n=$((n+1))
done
rm -rf "$tmp"
