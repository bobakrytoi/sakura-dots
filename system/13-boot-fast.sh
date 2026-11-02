#!/usr/bin/env bash
# Switch the initramfs to systemd: the splash starts right away instead of after waiting for every USB device
set -e
B=".bak-$(date +%Y%m%d-%H%M)"
sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf$B
sudo sed -i 's/^HOOKS=.*/HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)/' /etc/mkinitcpio.conf
grep '^HOOKS' /etc/mkinitcpio.conf

# fewer retries for the broken USB device (halves the time spent on it)
grep -q 'usbcore.use_both_schemes' /etc/kernel/cmdline || \
  echo "$(cat /etc/kernel/cmdline) usbcore.use_both_schemes=0" | sudo tee /etc/kernel/cmdline >/dev/null
cat /etc/kernel/cmdline

if sudo mkinitcpio -P; then
  echo
  echo "DONE! Images built fine. Tell Claude, then reboot."
else
  echo "!! build failed - restoring the old config"
  sudo cp /etc/mkinitcpio.conf$B /etc/mkinitcpio.conf
  sudo mkinitcpio -P
  echo "Restored. Tell Claude what the error said."
fi
