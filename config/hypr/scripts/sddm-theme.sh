#!/usr/bin/env bash
# sddm-theme.sh - install the sakura login theme (same look as the lock screen) into /usr/share/sddm/themes/sakura.
# Run it yourself (it asks for sudo once). The previous theme is kept in /usr/share/sddm/themes/sakura.bak.
# It also sets up /var/lib/sakura-sddm/ (owned by you, world-readable): after this, every wallpaper / accent / avatar
# change is copied there by sddm-sync.sh without sudo, and the login screen reads it (falling back to the theme's copies).
# Key sounds: the lock screen's wavs are copied into the theme (sounds/), played by Sounds.qml.
#   sddm-theme.sh          install
#   sddm-theme.sh test     preview in a window first (Esc / close it to quit)
set -e
SRC="$HOME/.config/sakura/sddm-theme"; DST=/usr/share/sddm/themes/sakura; SH=/var/lib/sakura-sddm
D="$(dirname "$(readlink -f "$0")")"
A=$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get("accent","#f2b8d0"))' "$HOME/.config/sakura/settings.json" 2>/dev/null || echo "#f2b8d0")
printf '[General]\ndefaultUser=%s\naccent=%s\n' "$USER" "$A" > "$SRC/theme.conf"
cp "$HOME/.config/hypr/assets/avatar.png" "$SRC/avatar.png"
mkdir -p "$SRC/sounds"
for s in key1 key2 key3 key-back key-enter; do cp "$HOME/.local/share/sounds/sakura/$s.wav" "$SRC/sounds/"; done
# the theme's own fallback background = a still of the current wallpaper (same code as the live sync)
ST="$SRC/.stage"; mkdir -p "$ST"; rm -f "$ST/.wall-src"
SAKURA_SDDM_DIR="$ST" "$D/sddm-sync.sh" wall && [ -s "$ST/background.jpg" ] && cp "$ST/background.jpg" "$SRC/background.jpg"
rm -rf "$ST"
if [ "$1" = test ]; then exec sddm-greeter-qt6 --test-mode --theme "$SRC"; fi
sudo sh -c "set -e
  install -d -o '$USER' -g '$(id -gn)' -m 755 '$SH'
  if [ -d '$DST' ]; then rm -rf '$DST.bak'; cp -a '$DST' '$DST.bak'; fi
  install -d -m 755 '$DST' '$DST/sounds'
  install -m 644 '$SRC'/Main.qml '$SRC'/Sounds.qml '$SRC'/theme.conf '$SRC'/avatar.png '$SRC'/background.jpg '$SRC'/metadata.desktop '$DST'/
  install -m 644 '$SRC'/sounds/*.wav '$DST'/sounds/
  ln -sfn '$SH/theme.conf.user' '$DST/theme.conf.user'"
"$D/sddm-sync.sh" all
echo "Installed. Wallpaper, accent and avatar now follow the desktop via $SH (no sudo). Old theme: $DST.bak"
