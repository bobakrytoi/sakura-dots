#!/usr/bin/env bash
# Puts the normal VS Code logo into Code - OSS (the small icon at the top-left of the window).
# Code - OSS ships a plain "OSS" logo inside /usr/lib/code, so this needs root once:
#     sudo ~/.config/hypr/scripts/vscode-icon.sh
# It also installs a pacman hook, so the logo is put back after every `code` update.
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo:  sudo $0"; exit 1; }
U=${SUDO_USER:-$(logname 2>/dev/null)}; H=$(getent passwd "$U" | cut -d: -f6)
SRC="$H/.config/sakura/vscode/code-icon.svg"
[ -f "$SRC" ] || SRC=/usr/share/icons/Papirus/64x64/apps/visual-studio-code.svg
install -Dm644 "$SRC" /usr/local/share/sakura/code-icon.svg
apply() {
  for f in /usr/lib/code/out/media/code-icon.svg /usr/lib/code/out/vs/workbench/browser/media/code-icon.svg; do
    [ -f "$f" ] && cp /usr/local/share/sakura/code-icon.svg "$f"
  done
  return 0
}
apply
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/sakura-code-icon.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = code

[Action]
Description = Restoring the VS Code logo in Code - OSS...
When = PostTransaction
Exec = /bin/sh -c 'for f in /usr/lib/code/out/media/code-icon.svg /usr/lib/code/out/vs/workbench/browser/media/code-icon.svg; do [ -f "$f" ] && cp /usr/local/share/sakura/code-icon.svg "$f"; done; true'
HOOK
echo "done - restart VS Code to see the new icon"
