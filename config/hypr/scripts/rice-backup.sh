#!/usr/bin/env bash
# One-click backup of the whole rice (Settings > About > Back up the rice).
#   rice-backup.sh [--personal]
# Makes ~/sakura-backups/sakura-rice-YYYY-MM-DD_HH-MM.tar.gz: the installer from ~/sakura-dots, package lists made from
# what is installed now (the rice's, and all of yours), plus the CURRENT configs, login theme, icons, sounds,
# wallpapers and ~/.local/bin helpers.
# Home paths become __HOME__ (install.sh puts the right home back), so the archive works for a friend too.
# Machine-only bits are left out (monitor layout, weather location, notes/drawings) unless --personal is given.
# ~/sakura-dots itself is not touched. Prints the path of the archive.
set -e
H="$HOME"; DOTS="$H/sakura-dots"; OUTDIR="${SAKURA_BACKUP_DIR:-$H/sakura-backups}"
PERSONAL=0; [ "$1" = --personal ] && PERSONAL=1
stamp=$(date +%Y-%m-%d_%H-%M)
W=$(mktemp -d); R="$W/sakura-rice"; mkdir -p "$R"
trap 'rm -rf "$W"' EXIT

# 1. installer, package lists, docs, images (from the dots repo, if there is one)
if [ -d "$DOTS" ]; then
  for f in install.sh packages.txt aur.txt README.md images; do [ -e "$DOTS/$f" ] && cp -a "$DOTS/$f" "$R/"; done
fi

# 1b. package lists from what is installed NOW (the lists in the dots repo go stale):
#   packages.txt / aur.txt: the rice - the dots lists + what the newer parts need, only what is installed here,
#     minus what the rice no longer uses; split into repo / AUR by what pacman calls foreign
#   all-packages.txt / all-aur.txt: every package you installed yourself (install.sh --all-packages)
python3 -I -c '
import subprocess, sys
R, DOTS = sys.argv[1:3]
def q(*a): return subprocess.run(["pacman", *a], capture_output=True, text=True).stdout.split()
installed, foreign = set(q("-Qq")), set(q("-Qqm"))
def read(p):
    try: return [l.strip() for l in open(p) if l.strip() and not l.lstrip().startswith("#")]
    except OSError: return []
# the bar, video wallpapers + previews, the network menu, notifications, the update check
EXTRA = ["quickshell", "awww", "qt6-multimedia", "qt6-multimedia-ffmpeg", "ffmpeg", "ffmpegthumbnailer", "imagemagick", "libheif", "ghostscript",
         "cava", "wl-clipboard", "nm-connection-editor", "libnotify", "fakeroot", "socat",
         "yt-dlp", "mpv", "mpv-mpris", "zenity",   # Sakura Sound
         "gnome-keyring", "libsecret"]             # Password helper: vault key in the login keyring
GONE = {"swaync", "waybar"}       # replaced by quickshell (Notifs.qml, TopBar.qml)
want = []
for p in read(DOTS + "/packages.txt") + read(DOTS + "/aur.txt") + EXTRA:
    if p not in GONE and p not in want and (p in installed or p == "yay"): want.append(p)
def write(name, items): open(R + "/" + name, "w").write("".join(p + "\n" for p in items))
write("packages.txt", [p for p in want if p not in foreign and p != "yay"])
write("aur.txt", [p for p in want if p in foreign or p == "yay"])
write("all-packages.txt", q("-Qqen"))
write("all-aur.txt", q("-Qqem"))
' "$R" "$DOTS"

# 2. configs: the known ones + everything the rice itself points at (auto-discovery, so new apps come along):
#   - any ~/.config/<x> or ~/.local/bin/<x> mentioned in the rice's files (hypr, quickshell, found apps, helpers, launchers),
#     followed transitively;  - any ~/.config/<x> with its own shell.qml (separate qs apps: task manager, Sakura Sound…);
#   - any ~/.config/<x> that contains a .sakura-rice marker file.
#   Browsers, chat apps and other big/personal profiles are never taken.
mkdir -p "$R/config"
python3 -I - "$H" "$W/found" <<'PY'
import os, re, sys, glob
H, out = sys.argv[1], sys.argv[2]
C, B, A = H + "/.config", H + "/.local/bin", H + "/.local/share/applications"
BASE = "hypr quickshell waybar taskmgr sakura kitty swaync swayosd rofi capture cava fastfetch gtk-3.0 gtk-4.0 qt6ct uwsm starship.toml".split()
NEVER = {"BraveSoftware", "chromium", "google-chrome", "mozilla", "discord", "vesktop", "Code", "VSCodium", "Slack",
         "TelegramDesktop", "pulse", "systemd", "dconf", "gh", "git", "autostart", "Electron", "obs-studio", "Signal",
         "spotify", "steam", "libreoffice", "JetBrains", "github-copilot", "ibus", "fcitx5", "user-dirs.dirs", "mimeapps.list",
         "pavucontrol.ini", "QtProject.conf", "kdeglobals", "menus", "procps", "htop", "nvim", "go", "yay", "paru"}
RX_CONF = re.compile(r"\.config/([A-Za-z0-9._-]+)")
RX_BIN = re.compile(r"\.local/bin/([A-Za-z0-9._-]+)")
def text(p, limit=2_000_000):
    try:
        if os.path.getsize(p) > limit: return ""
        with open(p, "rb") as f: b = f.read()
        return "" if b"\0" in b[:4096] else b.decode("utf-8", "replace")
    except OSError: return ""
def files(root):
    if os.path.isfile(root): yield root; return
    for d, dirs, fs in os.walk(root):
        dirs[:] = [x for x in dirs if not x.startswith(".bak") and x not in ("__pycache__", "node_modules", ".git")]
        for f in fs:
            if ".bak" in f: continue
            yield os.path.join(d, f)
def size(p):
    t = 0
    for f in files(p):
        try: t += os.path.getsize(f)
        except OSError: pass
    return t
conf, bins = set(), set()
def add_conf(n):
    if n in conf or n in NEVER or not os.path.exists(os.path.join(C, n)): return False
    if size(os.path.join(C, n)) > 80 * 1024 * 1024: return False
    conf.add(n); return True
def add_bin(n):
    p = os.path.join(B, n)
    if n in bins or not os.path.isfile(p) or not text(p): return False   # text scripts only, no binaries
    bins.add(n); return True
for n in BASE: add_conf(n)
for n in sorted(os.listdir(C)) if os.path.isdir(C) else []:
    p = os.path.join(C, n)
    if os.path.isdir(p) and (os.path.exists(p + "/shell.qml") or os.path.exists(p + "/.sakura-rice")): add_conf(n)
for f in glob.glob(A + "/sakura-*.desktop"):
    for m in RX_BIN.findall(text(f)): add_bin(m)
    for m in RX_CONF.findall(text(f)): add_conf(m)
for b in ("taskmgr", "sakura-tray-app", "open-with", "discord-clean.sh"): add_bin(b)
for _ in range(4):                                  # follow references until nothing new turns up
    grew = False
    for src in [os.path.join(C, n) for n in sorted(conf)] + [os.path.join(B, n) for n in sorted(bins)]:
        for f in files(src):
            t = text(f)
            if not t: continue
            for m in RX_CONF.findall(t): grew |= add_conf(m)
            for m in RX_BIN.findall(t): grew |= add_bin(m)
    if not grew: break
# launchers that start something we take, and the icons they use
desk, icons = set(), set()
for f in glob.glob(A + "/*.desktop"):
    t = text(f); n = os.path.basename(f)
    if n.startswith("sakura-") or n == "discord.desktop" or any("/.local/bin/" + b in t for b in bins) or any("/.config/" + c + "/" in t for c in conf if c not in BASE[:1]):
        desk.add(n)
        m = re.search(r"^Icon=(.+)$", t, re.M)
        if m: icons.add(m.group(1).strip())
with open(out, "w") as o:
    o.write("CONF " + " ".join(sorted(conf)) + "\n")
    o.write("BIN " + " ".join(sorted(bins)) + "\n")
    o.write("DESK " + " ".join(sorted(desk)) + "\n")
    o.write("ICON " + " ".join(sorted(icons)) + "\n")
PY
CONF=$(sed -n 's/^CONF //p' "$W/found"); BINS=$(sed -n 's/^BIN //p' "$W/found")
DESK=$(sed -n 's/^DESK //p' "$W/found"); ICONS=$(sed -n 's/^ICON //p' "$W/found")
for n in $CONF; do cp -a "$H/.config/$n" "$R/config/"; done
[ -f "$DOTS/config/bashrc-sakura.sh" ] && cp "$DOTS/config/bashrc-sakura.sh" "$R/config/"
# leftovers that only make sense here
find "$R/config" \( -name '*.bak*' -o -name '*.tmp' -o -name '*.orig' -o -name '__pycache__' \) -prune -exec rm -rf {} + 2>/dev/null || true
rm -f "$R/config/hypr/monitors.lua"
# per-app rules: .backupignore (globs relative to the app folder) and an executable backup-clean (gets the copied folder)
for d in "$R"/config/*/; do
  [ -f "$d/.backupignore" ] && [ $PERSONAL = 0 ] && while IFS= read -r g; do
      case "$g" in ''|'#'*) continue ;; esac
      (cd "$d" && rm -rf -- $g) 2>/dev/null || true
    done < "$d/.backupignore"
  [ -x "$d/backup-clean" ] && [ $PERSONAL = 0 ] && "$d/backup-clean" "$d" || true
done
# never share: caches, logs, browser cookies, history/db files of any app (the known rice files keep theirs)
if [ $PERSONAL = 0 ]; then
  find "$R/config" \( -iname '*cookie*' -o -iname '*.log' -o -iname '*.sqlite' -o -iname '*.sqlite3' -o -iname '*.db' \
       -o -iname '*history*' -o -iname 'Cache' -o -iname 'cache' -o -iname 'GPUCache' -o -iname 'Code Cache' \) -prune -exec rm -rf {} + 2>/dev/null || true
fi
if [ $PERSONAL = 0 ]; then
  rm -f "$R/config/sakura/weather.json" "$R/config/sakura/weather.json".* "$R/config/sakura/timers.json" "$R/config/sakura/tray.json"
  # settings without this PC's monitor names (the next PC picks its own)
  python3 -I - "$R/config/sakura/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
try: c = json.load(open(p))
except Exception: sys.exit()
for k in ("mainMonitor", "secondMonitor"): c.pop(k, None)
json.dump(c, open(p, "w"), indent=2, ensure_ascii=False)
PY
fi

# 3. login theme, boot splash, system scripts
[ -d "$H/.config/rice" ] && { mkdir -p "$R/system"; cp -a "$H/.config/rice/." "$R/system/"; rm -rf "$R/config/rice"; }

# 4. assets: icons, cursor, sounds, app launchers, wallpapers, avatar, helpers
mkdir -p "$R/local/share/icons" "$R/local/share/sounds" "$R/local/share/applications" "$R/local/bin" "$R/wallpapers"
for i in Papirus-Dark-Sakura Bibata-Modern-Sakura custom; do [ -d "$H/.local/share/icons/$i" ] && cp -a "$H/.local/share/icons/$i" "$R/local/share/icons/"; done
# app icons in hicolor (our apps' own icons: sakura-settings, sakura-taskmgr, sakura-sound, … and whatever the launchers use)
if [ -d "$H/.local/share/icons/hicolor" ]; then
  ( cd "$H/.local/share/icons" && for ic in $ICONS; do find hicolor -path "*/apps/$ic.*" ! -name '*.bak*'; done; find hicolor -path '*/apps/sakura-*' ! -name '*.bak*'; ls hicolor/index.theme 2>/dev/null ) \
    | sort -u | while read -r f; do mkdir -p "$R/local/share/icons/$(dirname "$f")"; cp -a "$H/.local/share/icons/$f" "$R/local/share/icons/$f"; done
fi
[ -d "$H/.local/share/sounds/sakura" ] && cp -a "$H/.local/share/sounds/sakura" "$R/local/share/sounds/"
for d in $DESK; do cp -a "$H/.local/share/applications/$d" "$R/local/share/applications/"; done
# Discord through discord-clean.sh (clears its cache on every start)
[ -f "$H/.local/share/applications/discord.desktop" ] && cp -a "$H/.local/share/applications/discord.desktop" "$R/local/share/applications/"
for b in $BINS; do cp -a "$H/.local/bin/$b" "$R/local/bin/"; done
# Dolphin right-click menus of our own (Compress… / Extract - hypr/scripts/archive.sh)
ls "$H"/.local/share/kio/servicemenus/sakura-*.desktop >/dev/null 2>&1 && { mkdir -p "$R/local/share/kio/servicemenus"; cp -a "$H"/.local/share/kio/servicemenus/sakura-*.desktop "$R/local/share/kio/servicemenus/"; }
cp -a "$H/Pictures/Wallpapers/." "$R/wallpapers/" 2>/dev/null || true
[ -f "$H/.config/hypr/assets/avatar.png" ] && { mkdir -p "$R/images"; cp "$H/.config/hypr/assets/avatar.png" "$R/images/avatar.png"; }
if [ $PERSONAL = 1 ] && [ -d "$H/.local/share/sakura" ]; then mkdir -p "$R/local/share"; cp -a "$H/.local/share/sakura" "$R/local/share/"; fi

# 5. home paths -> __HOME__, login user -> __USER__ (install.sh puts the friend's own back)
grep -rlI -- "$H" "$R" 2>/dev/null | while read -r f; do sed -i "s|$H|__HOME__|g" "$f"; done
grep -rlI -- "defaultUser=$USER" "$R" 2>/dev/null | while read -r f; do sed -i "s|defaultUser=$USER\$|defaultUser=__USER__|" "$f"; done
# the login avatar is stored per user name: let the script use whoever runs it
grep -rlI -- "faces/$USER.face.icon" "$R" 2>/dev/null | while read -r f; do sed -i "s|faces/$USER.face.icon|faces/\$USER.face.icon|g" "$f"; done

# 6. the installer also has to copy ~/.local/bin and (personal) notes/drawings
if [ -f "$R/install.sh" ] && ! grep -q 'local/bin' "$R/install.sh"; then
  sed -i 's|^cp -a wallpapers/\* "\$HOME/Pictures/Wallpapers/"|&\nmkdir -p "$HOME/.local/bin"; cp -a local/bin/* "$HOME/.local/bin/" 2>/dev/null \|\| true; chmod +x "$HOME"/.local/bin/* 2>/dev/null \|\| true\n[ -d local/share/sakura ] \&\& cp -a local/share/sakura "$HOME/.local/share/"|' "$R/install.sh"
  sed -i 's|^echo "  monitors are set for.*|echo "  monitors: pick the main one in Settings > Displays (Win → Settings)"|' "$R/install.sh"
fi
if [ -f "$R/install.sh" ]; then
  grep -q 'local/bin" 2>/dev/null | xargs' "$R/install.sh" || sed -i 's|grep -rlI "__HOME__" "\$HOME/.config" "\$HOME/.local/share/applications"|grep -rlI "__HOME__" "$HOME/.config" "$HOME/.local/share/applications" "$HOME/.local/bin"|' "$R/install.sh"
  grep -q '__USER__" "\$HOME/.config"' "$R/install.sh" || sed -i 's|^grep -rlI "__HOME__" "\$HOME/.config".*|&\ngrep -rlI "__USER__" "$HOME/.config" 2>/dev/null \| xargs -r sed -i "s\|__USER__\|$USER\|g"|' "$R/install.sh"
  grep -q 'icons/hicolor' "$R/install.sh" || sed -i 's|^gtk-update-icon-cache -f -t "\$HOME/.local/share/icons/Papirus-Dark-Sakura".*|&\ngtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null \|\| true|' "$R/install.sh"
fi
if [ -f "$R/install.sh" ] && ! grep -q 'local/share/kio' "$R/install.sh"; then
  python3 -I - "$R/install.sh" <<'KIO'
import sys
p = sys.argv[1]; L = open(p).read().split("\n")
add = '[ -d local/share/kio ] && { mkdir -p "$HOME/.local/share/kio"; cp -a local/share/kio/. "$HOME/.local/share/kio/"; grep -rlI "__HOME__" "$HOME/.local/share/kio" | xargs -r sed -i "s|__HOME__|$HOME|g"; chmod +x "$HOME"/.local/share/kio/servicemenus/*.desktop; }'
i = next((n for n, l in enumerate(L) if l.startswith("cp -a wallpapers/")), None)
if i is not None: L.insert(i + 1, add); open(p, "w").write("\n".join(L))
KIO
fi
{ echo "what is inside (found automatically):"; sed 's/^/  /' "$W/found"; } > "$R/INCLUDED.txt"
printf 'sakura mono rice backup\nmade: %s\nfrom: %s@%s\npersonal data: %s\n\nrestore / install:  tar xf this-archive.tar.gz && cd sakura-rice && ./install.sh   (--packages, --system)\n' \
  "$(date '+%F %T')" "$USER" "$(cat /etc/hostname 2>/dev/null)" "$([ $PERSONAL = 1 ] && echo yes || echo no)" > "$R/BACKUP.txt"

mkdir -p "$OUTDIR"
out="$OUTDIR/sakura-rice-$stamp.tar.gz"
tar -C "$W" -czf "$out" sakura-rice
# keep the 5 newest archives
ls -1t "$OUTDIR"/sakura-rice-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
echo "$out"
