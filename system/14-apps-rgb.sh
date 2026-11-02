#!/usr/bin/env bash
# Step 14: RGB lighting (OpenRGB), app store (GNOME Software + Flathub), audio visualizer (cava)
set -e
echo "==> Packages"
sudo pacman -Syu --needed --noconfirm openrgb i2c-tools gnome-software packagekit archlinux-appstream-data flatpak cava

echo "==> RGB: access to motherboard / USB lighting controllers"
echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
sudo modprobe i2c-dev || true
getent group i2c >/dev/null || sudo groupadd i2c
sudo usermod -aG i2c "$USER"
sudo udevadm control --reload-rules && sudo udevadm trigger || true

echo "==> App store: Flathub"
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo systemctl restart packagekit 2>/dev/null || true

echo
echo "DONE! Tell Claude. (log out and back in once so the RGB permissions apply)"
