#!/usr/bin/env bash
# ✿ sakura mono — installer
#   ./install.sh            copy configs + assets into your home (backs up what it replaces)
#   ./install.sh --packages also install all packages (pacman + AUR via yay)
#   ./install.sh --system   also install boot splash, login theme, drive/boot tweaks (asks for sudo)
set -e
cd "$(dirname "$0")"
REPO="$PWD"; BK="$HOME/.sakura-backup-$(date +%Y%m%d-%H%M%S)"

if [[ " $* " == *" --packages "* ]]; then
  echo "==> packages"
  sudo pacman -Syu --needed $(grep -vxF -f <(pacman -Qqm 2>/dev/null) packages.txt | tr '\n' ' ')
  command -v yay >/dev/null || { tmp=$(mktemp -d); git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/y"; (cd "$tmp/y" && makepkg -si --noconfirm); }
  yay -S --needed $(grep -v '^yay' aur.txt | tr '\n' ' ')
fi

echo "==> configs (backup of replaced files: $BK)"
mkdir -p "$BK/.config"
for d in config/*; do
  n=$(basename "$d"); [ "$n" = bashrc-sakura.sh ] && continue
  [ -e "$HOME/.config/$n" ] && cp -a "$HOME/.config/$n" "$BK/.config/" 2>/dev/null || true
  cp -a "$d" "$HOME/.config/"
done
mkdir -p "$HOME/.local/share/icons" "$HOME/.local/share/sounds" "$HOME/.local/share/applications" "$HOME/Pictures/Wallpapers" "$HOME/.config/rice/src" "$HOME/.icons/default"
cp -a local/share/icons/* "$HOME/.local/share/icons/"
cp -a local/share/sounds/* "$HOME/.local/share/sounds/"
cp -a local/share/applications/* "$HOME/.local/share/applications/"
cp -a wallpapers/* "$HOME/Pictures/Wallpapers/"
cp -a images/src*.jpg "$HOME/.config/rice/src/"
mkdir -p "$HOME/.config/hypr/assets"; cp images/avatar.png "$HOME/.config/hypr/assets/avatar.png"
printf '[Icon Theme]\nInherits=Bibata-Modern-Sakura\n' > "$HOME/.icons/default/index.theme"

echo "==> fixing paths for $HOME"
grep -rlI "__HOME__" "$HOME/.config" "$HOME/.local/share/applications" 2>/dev/null | xargs -r sed -i "s|__HOME__|$HOME|g"
chmod +x "$HOME"/.config/hypr/scripts/* 2>/dev/null || true

grep -q "sakura mono" "$HOME/.bashrc" 2>/dev/null || cat config/bashrc-sakura.sh >> "$HOME/.bashrc"

echo "==> GTK / icons / cursor"
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark-Sakura' 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Sakura' 2>/dev/null || true
gsettings set org.gnome.desktop.interface font-name 'Inter 11' 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/Papirus-Dark-Sakura" 2>/dev/null || true

if [[ " $* " == *" --system "* ]]; then
  echo "==> system: login theme, boot splash"
  mkdir -p "$HOME/.config/rice"; cp -a system/* "$HOME/.config/rice/"
  sed -i "s|__USER__|$USER|" "$HOME/.config/rice/sddm/sakura/theme.conf"
  bash "$HOME/.config/rice/2-system.sh" || true
  bash "$HOME/.config/rice/11-extras.sh" || true
  echo "   boot: see system/12-boot.sh and 13-boot-fast.sh (systemd-boot + UKI). Run them only if your boot setup matches."
fi

echo
echo "✿ done. Log out and pick Hyprland (uwsm) — or run: hyprctl reload"
echo "  monitors are set for DP-3 (left, main) + DP-1 (right) at 200 Hz: edit the MONITORS block in ~/.config/hypr/hyprland.lua"
