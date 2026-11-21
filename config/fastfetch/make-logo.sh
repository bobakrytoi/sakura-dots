#!/usr/bin/env bash
# builds fastfetch's logo.png (600x600, rounded corners) from the current avatar
magick "$HOME/.config/hypr/assets/avatar.png" -resize 600x600^ -gravity center -extent 600x600 \
  \( -size 600x600 xc:none -fill white -draw "roundrectangle 0,0 599,599 56,56" \) \
  -alpha set -compose DstIn -composite "$HOME/.config/fastfetch/logo.png.tmp" && mv "$HOME/.config/fastfetch/logo.png.tmp" "$HOME/.config/fastfetch/logo.png"
