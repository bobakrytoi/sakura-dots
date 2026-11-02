#!/usr/bin/env bash
# GameMode: CPU to performance + higher priority while a game runs
sudo pacman -S --needed --noconfirm gamemode lib32-gamemode && sudo usermod -aG gamemode "$USER" && echo "DONE! Tell Claude. (re-login once for the group to apply)"
