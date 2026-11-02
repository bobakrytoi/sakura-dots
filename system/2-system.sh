#!/usr/bin/env bash
# Step 2: login screen theme, drives, small package fixes
set -e
cd "$(dirname "$0")"

echo "==> Packages: add libnotify, remove dunst (conflicts with swaync)"
sudo pacman -S --needed --noconfirm libnotify
pacman -Q dunst &>/dev/null && sudo pacman -Rns --noconfirm dunst || true

echo "==> SDDM login theme"
sudo rm -rf /usr/share/sddm/themes/sakura
sudo cp -r sddm/sakura /usr/share/sddm/themes/sakura
sudo chmod -R a+rX /usr/share/sddm/themes/sakura
sudo mkdir -p /etc/sddm.conf.d /usr/share/sddm/faces
sudo tee /etc/sddm.conf.d/10-sakura.conf >/dev/null <<'EOF'
[Theme]
Current=sakura
CursorTheme=capitaine-cursors-light
CursorSize=24

[General]
Numlock=on
EOF
sudo cp "$HOME/.face" /usr/share/sddm/faces/$USER.face.icon

echo "==> Drives (NTFS -> /mnt, visible in Files)"
sudo mkdir -p /mnt/HDD-2TB /mnt/SSD-1TB /mnt/LocalDisk
sudo cp /etc/fstab /etc/fstab.bak-rice
OPTS="defaults,nofail,uid=1000,gid=1000,umask=022,windows_names,prealloc,x-systemd.device-timeout=5s"
add() { grep -q "$1" /etc/fstab || echo "UUID=$1  $2  ntfs3  $OPTS,x-gvfs-show,x-gvfs-name=$3  0 0" | sudo tee -a /etc/fstab >/dev/null; }
echo "# --- Windows drives (rice) ---" | sudo tee -a /etc/fstab >/dev/null
add A284763E8F007918 /mnt/HDD-2TB    "HDD%202TB"
add 3AD85F1FC820C601 /mnt/SSD-1TB    "SSD%201TB"
add 222AE81E2AE7ED2B /mnt/LocalDisk  "Local%20Disk"
sudo systemctl daemon-reload
for m in /mnt/HDD-2TB /mnt/SSD-1TB /mnt/LocalDisk; do
  if sudo mount "$m" 2>/dev/null; then echo "   OK  $m"; else echo "   FAIL $m  (see below)"; fi
done
sudo dmesg | grep -i ntfs3 | tail -5 || true

echo
echo "DONE! Tell Claude it finished (and paste any FAIL lines)."
