#!/usr/bin/env bash
# Rename drives in the file manager: D = HDD 2TB, E = SSD 1TB
set -e
sudo cp /etc/fstab /etc/fstab.bak-names
sudo sed -i 's/x-gvfs-name=HDD%202TB/x-gvfs-name=D%3A%20HDD%202TB/; s/x-gvfs-name=SSD%201TB/x-gvfs-name=E%3A%20SSD%201TB/' /etc/fstab
sudo systemctl daemon-reload
nautilus -q 2>/dev/null || true
grep x-gvfs-name /etc/fstab
echo "DONE! Tell Claude."
