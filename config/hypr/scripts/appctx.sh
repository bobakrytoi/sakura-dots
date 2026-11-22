#!/usr/bin/env bash
# sakura mono - actions for the start menu's right-click menu on an app (shell.qml, mctx).
#   appctx.sh locate    <desktop-id>   show the .desktop file in Dolphin
#   appctx.sh edit      <desktop-id>   copy the shortcut to ~/.local/share/applications (if needed) and open it in the editor
#   appctx.sh uninstall <desktop-id>   remove the package that owns it (in kitty: you type the sudo password there)
#   appctx.sh kill      <desktop-id>   force-quit every window of the app (kill -9 by pid)
set -u
act=${1:-}; id=${2:-}
[ -z "$act" ] || [ -z "$id" ] && exit 1
id=${id%.desktop}

find_desktop() {
    local d
    for d in "$HOME/.local/share/applications" "$HOME/.local/share/flatpak/exports/share/applications" \
             /var/lib/flatpak/exports/share/applications /usr/local/share/applications /usr/share/applications; do
        [ -f "$d/$id.desktop" ] && { echo "$d/$id.desktop"; return 0; }
    done
    return 1
}

notify() { notify-send -a "Start" -i "${3:-dialog-information}" "$1" "${2:-}"; }

case "$act" in
locate)
    f=$(find_desktop) || { notify "Shortcut not found" "$id"; exit 1; }
    exec dolphin --select "$f" ;;
edit)
    f=$(find_desktop) || { notify "Shortcut not found" "$id"; exit 1; }
    own="$HOME/.local/share/applications/$id.desktop"
    [ "$f" != "$own" ] && cp -n "$f" "$own"
    if command -v code >/dev/null; then exec code "$own"; else exec kitty -e "${EDITOR:-nano}" "$own"; fi ;;
uninstall)
    f=$(find_desktop) || { notify "Shortcut not found" "$id"; exit 1; }
    case "$f" in
    *flatpak*)
        exec kitty --class sakura-uninstall --title "Uninstall" -e bash -c "flatpak uninstall '$id'; echo; read -rp 'Enter = close'" ;;
    "$HOME"/.local/*)
        # a shortcut of your own: may still point at a package, check the original
        sys=/usr/share/applications/$id.desktop
        if [ -f "$sys" ]; then f=$sys; else
            exec kitty --class sakura-uninstall --title "Uninstall" -e bash -c "echo 'Это твой собственный ярлык, пакета за ним нет:'; echo '$f'; read -rp 'Удалить ярлык? [y/N] ' a; [ \"\$a\" = y ] && rm -v '$f'; read -rp 'Enter = закрыть'"
        fi ;;
    esac
    pkg=$(pacman -Qqo "$f" 2>/dev/null) || { notify "No package owns this app" "$f" dialog-warning; exit 1; }
    exec kitty --class sakura-uninstall --title "Uninstall $pkg" -e bash -c "echo 'Удаляю пакет: $pkg'; echo; sudo pacman -Rns '$pkg'; echo; read -rp 'Enter = закрыть'" ;;
kill)
    pids=$(hyprctl clients -j | python3 -c '
import json, sys
key = sys.argv[1].lower()
for c in json.load(sys.stdin):
    cls = (c.get("class") or "").lower()
    if cls == key or cls == key.split(".")[-1] or key.endswith("." + cls):
        print(c["pid"])' "$id" | sort -u)
    [ -z "$pids" ] && { notify "Nothing to kill" "$id"; exit 0; }
    kill -9 $pids ;;
esac
