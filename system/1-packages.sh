#!/usr/bin/env bash
# Шаг 1: установка пакетов для райса
set -e
PKGS=(
  # панель, лаунчер, уведомления, обои, OSD, док
  waybar rofi swaync awww swayosd nwg-dock-hyprland
  # экосистема Hyprland
  hyprlock hypridle hyprpolkitagent hyprpicker xdg-desktop-portal-gtk
  # проводник
  nautilus gvfs gvfs-mtp file-roller sushi ffmpegthumbnailer xdg-user-dirs
  # внешний вид
  adw-gtk-theme papirus-icon-theme capitaine-cursors nwg-look qt6ct kvantum
  qt5-wayland qt6-wayland
  # шрифты
  inter-font noto-fonts-cjk ttf-nerd-fonts-symbols
  # звук
  pipewire-pulse wireplumber pavucontrol
  # утилиты
  cliphist wl-clipboard brightnessctl playerctl satty imagemagick
  # приложения
  loupe mpv gnome-text-editor gnome-calculator btop fastfetch starship
)
sudo pacman -Syu --needed "${PKGS[@]}"
echo
echo "ГОТОВО! Напиши Claude, что пакеты установились."
