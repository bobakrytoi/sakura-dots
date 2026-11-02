#!/usr/bin/env bash
# Step 3: AUR helper (yay) + Brave + Mullvad VPN
set -e
if ! command -v yay &>/dev/null; then
  echo "==> Installing yay (AUR helper)"
  tmp=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
fi
echo "==> Installing Brave + Mullvad VPN"
yay -S --needed --noconfirm --answerdiff None --answerclean None brave-bin mullvad-vpn-bin
sudo systemctl enable --now mullvad-daemon
echo
echo "DONE! Tell Claude it finished."
