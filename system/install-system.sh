#!/usr/bin/env bash
# Login screen (SDDM), pink cursor on it and the Plymouth boot splash. Asks for sudo.
# Run ./install.sh first, this one uses the files it put in ~/.config.
#   system/install-system.sh [MONITOR-SERIAL]
# MONITOR-SERIAL is optional: the EDID serial of the screen that should get the password field
# when you have two identical monitors (hyprctl monitors -j | grep serial). Without it SDDM picks as usual.
set -e
cd "$(dirname "$0")"

echo ":: sddm theme"
"$HOME/.config/hypr/scripts/sddm-theme.sh"

echo ":: sddm config + cursor"
sudo install -d /etc/sddm.conf.d /usr/local/share/sakura
sudo install -m644 sddm/10-sakura.conf sddm/20-sakura-main-screen.conf /etc/sddm.conf.d/
sudo install -m755 sddm/sddm-xsetup.sh /usr/local/share/sakura/
sudo install -m644 sddm/code-icon.svg /usr/local/share/sakura/
sudo rm -rf /usr/share/icons/Bibata-Modern-Sakura
sudo cp -r "$HOME/.local/share/icons/Bibata-Modern-Sakura" /usr/share/icons/
sudo chmod -R a+rX /usr/share/icons/Bibata-Modern-Sakura
if [ -n "$1" ]; then
  echo "$1" | sudo tee /usr/local/share/sakura/main-monitor-serial >/dev/null
fi

echo ":: plymouth splash"
sudo rm -rf /usr/share/plymouth/themes/sakura
sudo cp -r plymouth/sakura /usr/share/plymouth/themes/sakura
sudo plymouth-set-default-theme sakura
echo "   add the plymouth hook to /etc/mkinitcpio.conf and 'quiet splash' to your kernel line,"
echo "   then run: sudo mkinitcpio -P"

echo "done."
