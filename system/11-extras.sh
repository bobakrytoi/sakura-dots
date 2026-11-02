#!/usr/bin/env bash
# Step 11: screen recorder + boot splash + pink cursor on the login screen
set -e
cd "$(dirname "$0")"
B=".bak-$(date +%Y%m%d-%H%M)"

echo "==> Packages"
sudo pacman -S --needed --noconfirm gpu-screen-recorder plymouth

echo "==> Boot splash theme"
sudo rm -rf /usr/share/plymouth/themes/sakura
sudo cp -r plymouth/sakura /usr/share/plymouth/themes/sakura
sudo plymouth-set-default-theme sakura

echo "==> Initramfs: plymouth hook + early NVIDIA (smooth splash)"
sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf$B
grep -q 'plymouth' /etc/mkinitcpio.conf || sudo sed -i 's/^HOOKS=(base udev /HOOKS=(base udev plymouth /' /etc/mkinitcpio.conf
grep -q '^MODULES=(.*nvidia' /etc/mkinitcpio.conf || sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/; s/^MODULES=( /MODULES=(/' /etc/mkinitcpio.conf
grep -E '^(MODULES|HOOKS)' /etc/mkinitcpio.conf
sudo mkinitcpio -P

echo "==> Kernel options: quiet boot + splash"
PARAMS="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0 nvidia_drm.modeset=1"
if sudo test -d /boot/loader/entries; then
  echo "   systemd-boot detected"
  for f in $(sudo ls /boot/loader/entries/*.conf); do
    sudo cp "$f" "/boot/loader/entries/$(basename "$f" .conf)$B.conf.bak" 2>/dev/null || true
    for p in $PARAMS; do
      sudo grep -q "^options.* $p\( \|$\)" "$f" || sudo sed -i "s|^options .*|& $p|" "$f"
    done
    sudo grep '^options' "$f"
  done
  sudo rm -f /boot/loader/entries/*.conf.bak
elif [ -f /etc/default/grub ]; then
  echo "   GRUB detected"
  sudo cp /etc/default/grub /etc/default/grub$B
  for p in $PARAMS; do
    grep -q "GRUB_CMDLINE_LINUX_DEFAULT=.*$p" /etc/default/grub || sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $p\"|" /etc/default/grub
  done
  grep '^GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub
  sudo grub-mkconfig -o /boot/grub/grub.cfg
else
  echo "   !! bootloader not recognised - add these kernel options yourself: $PARAMS"
fi

echo "==> Pink cursor on the login screen"
sudo rm -rf /usr/share/icons/Bibata-Modern-Sakura
sudo cp -r "$HOME/.local/share/icons/Bibata-Modern-Sakura" /usr/share/icons/
sudo chmod -R a+rX /usr/share/icons/Bibata-Modern-Sakura
sudo sed -i 's/^CursorTheme=.*/CursorTheme=Bibata-Modern-Sakura/' /etc/sddm.conf.d/10-sakura.conf
grep CursorTheme /etc/sddm.conf.d/10-sakura.conf

echo
echo "DONE! Tell Claude. The boot splash shows on the next reboot."
