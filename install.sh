#!/usr/bin/env bash
# sakura mono installer
#   ./install.sh              copy configs, scripts, icons and sounds into your home
#   ./install.sh --packages   install the packages first (pacman + yay)
# Everything it replaces is moved to ~/.sakura-backup-<date> first.
# Login screen and boot splash are separate: system/install-system.sh
set -e
cd "$(dirname "$0")"
BK="$HOME/.sakura-backup-$(date +%Y%m%d-%H%M%S)"

if [ "$1" = --packages ]; then
  echo ":: packages"
  sudo pacman -Syu --needed $(grep -v '^#' packages.txt)
  if ! command -v yay >/dev/null; then
    tmp=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
  fi
  yay -S --needed $(grep -v '^#' aur.txt)
fi

# copy one item, backing up whatever is already there
put() {  # put <src> <dst>
  if [ -e "$2" ] || [ -L "$2" ]; then
    mkdir -p "$BK/$(dirname "${2#"$HOME"/}")"
    mv "$2" "$BK/${2#"$HOME"/}"
  fi
  mkdir -p "$(dirname "$2")"
  cp -a "$1" "$2"
}

echo ":: configs (old ones go to $BK)"
for d in config/*; do put "$d" "$HOME/.config/$(basename "$d")"; done
for f in local/bin/*; do put "$f" "$HOME/.local/bin/$(basename "$f")"; done
for f in local/share/applications/* local/share/kio/servicemenus/*; do put "$f" "$HOME/.${f#local/}"; done
for d in local/share/icons/* local/share/sounds/sakura local/share/sakura/ambient; do
  [ "$d" = local/share/icons/hicolor ] && continue
  put "$d" "$HOME/.${d#local/}"
done
mkdir -p "$HOME/.local/share/icons"; cp -a local/share/icons/hicolor "$HOME/.local/share/icons/"
mkdir -p "$HOME/Pictures/Wallpapers"; cp -n wallpapers/* "$HOME/Pictures/Wallpapers/"
put local/share/kaplya "$HOME/.local/share/kaplya"

# mpv UI: uosc isn't in the repo (it ships 18 MB of helper binaries), take the release it was set up with
if [ ! -f "$HOME/.config/mpv/scripts/uosc/main.lua" ] && command -v curl >/dev/null; then
  echo ":: mpv: uosc 5.13.0"
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/uosc.zip" https://github.com/tomasklaen/uosc/releases/download/5.13.0/uosc.zip \
    && (cd "$HOME/.config/mpv" && bsdtar -xf "$tmp/uosc.zip" --exclude 'script-opts/*') || echo "   failed, get it from github.com/tomasklaen/uosc"
  rm -rf "$tmp"
fi

echo ":: fixing paths for $HOME"
grep -rlI "__HOME__" "$HOME/.config" "$HOME/.local/share/applications" "$HOME/.local/share/kio" 2>/dev/null \
  | xargs -r sed -i "s|__HOME__|$HOME|g"
sed -i "s|__USER__|$USER|" "$HOME/.config/sakura/sddm-theme/theme.conf"
chmod +x "$HOME"/.config/hypr/scripts/* "$HOME"/.local/bin/* "$HOME"/.local/share/kio/servicemenus/sakura-*.desktop 2>/dev/null || true

echo ":: gtk, icons, cursor"
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark-Sakura' 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Sakura' 2>/dev/null || true
gsettings set org.gnome.desktop.interface font-name 'Inter 11' 2>/dev/null || true
mkdir -p "$HOME/.icons/default"; printf '[Icon Theme]\nInherits=Bibata-Modern-Sakura\n' > "$HOME/.icons/default/index.theme"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo
echo "done. log out and pick Hyprland (uwsm)."
echo "then set your monitors in Settings > Displays (Super, gear icon)."
echo "login screen + boot splash: ./system/install-system.sh"
