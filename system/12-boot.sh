#!/usr/bin/env bash
# Boot: quiet + splash for the UKI (systemd-boot), sakura early splash, shorter wait for the broken USB device
set -e
B=".bak-$(date +%Y%m%d-%H%M)"
PARAMS="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0 nvidia_drm.modeset=1 usbcore.initial_descriptor_timeout=500"

sudo cp /etc/kernel/cmdline /etc/kernel/cmdline$B
line=$(cat /etc/kernel/cmdline)
for p in $PARAMS; do
  case " $line " in *" ${p%%=*}"*) ;; *) line="$line $p" ;; esac
done
echo "$line" | sudo tee /etc/kernel/cmdline >/dev/null
echo "cmdline: $(cat /etc/kernel/cmdline)"

sudo cp "$HOME/.config/rice/plymouth/sakura/splash.bmp" /usr/share/plymouth/themes/sakura/splash.bmp
sudo cp /etc/mkinitcpio.d/linux.preset /etc/mkinitcpio.d/linux.preset$B
sudo sed -i 's|^default_options=.*|default_options="--splash /usr/share/plymouth/themes/sakura/splash.bmp"|' /etc/mkinitcpio.d/linux.preset

sudo mkinitcpio -P
echo
echo "DONE! Tell Claude, then reboot to see the boot splash."
