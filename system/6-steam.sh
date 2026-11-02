#!/usr/bin/env bash
# Steam: enable the multilib repo (32-bit libs), then install Steam + 32-bit NVIDIA driver
set -e
if grep -q '^#\[multilib\]' /etc/pacman.conf; then
  sudo cp /etc/pacman.conf /etc/pacman.conf.bak-steam
  sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
fi
sudo pacman -Syu --needed --noconfirm steam lib32-nvidia-utils lib32-pipewire ttf-liberation
echo "DONE! Tell Claude."
