#!/usr/bin/env bash
# system updates for the bar:  updates.sh            -> waybar JSON (empty when everything is up to date)
#                              updates.sh install    -> run the update in a terminal, then refresh the bar
# Checks like `checkupdates`: syncs a private copy of the package databases (no root, the real db is untouched),
# plus AUR (yay) and flatpak.
C="${XDG_CACHE_HOME:-$HOME/.cache}/sakura-updates"; mkdir -p "$C"
case "$1" in
  install)
    exec kitty --class sakura-updates --title "System update" sh -c '
      echo "✿ updating the system"; echo
      if command -v yay >/dev/null; then yay -Syu; else sudo pacman -Syu; fi
      command -v flatpak >/dev/null && flatpak update
      echo; echo "✿ done - press Enter to close"; read _
      pkill -RTMIN+19 waybar; rm -f "$HOME/.cache/sakura-updates/last.json"' ;;
esac
DB="$C/db"; mkdir -p "$DB"
ln -sfn /var/lib/pacman/local "$DB/local"
fakeroot -- pacman -Sy --dbpath "$DB" --logfile /dev/null --disable-sandbox >/dev/null 2>&1
repo=$(pacman -Qu --dbpath "$DB" 2>/dev/null)
aur=$(command -v yay >/dev/null && timeout 40 yay -Qua 2>/dev/null)
fp=$(command -v flatpak >/dev/null && timeout 30 flatpak remote-ls --updates --columns=application 2>/dev/null)
python3 -I - "$repo" "$aur" "$fp" <<'PY'
import json, sys
repo, aur, fp = ([l for l in a.splitlines() if l.strip()] for a in sys.argv[1:4])
n = len(repo) + len(aur) + len(fp)
if n == 0:
    print(json.dumps({"text": "", "tooltip": "", "class": "none"})); sys.exit()
def part(title, lines, k=12):
    if not lines: return ""
    more = f"\n  … +{len(lines) - k}" if len(lines) > k else ""
    return f"<b>{title} ({len(lines)})</b>\n" + "\n".join("  " + l for l in lines[:k]) + more + "\n"
tip = part("pacman", repo) + part("AUR", aur) + part("flatpak", fp) + "\nclick: update"
print(json.dumps({"text": str(n), "tooltip": tip.strip(), "class": "many" if n >= 50 else "some", "alt": "some"}))
PY
