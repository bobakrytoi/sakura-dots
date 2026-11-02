#!/usr/bin/env python3
"""Custom screen-share picker for xdg-desktop-portal-hyprland (rofi based)."""
import json, os, subprocess, sys

ICON_SCREEN = "video-display"
ICON_REGION = "applets-screenshooter"

def sh(cmd, inp=None):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)

rows = []   # (label, icon, selection)

# monitors
try:
    mons = json.loads(sh(["hyprctl", "monitors", "-j"]).stdout)
except Exception:
    mons = []
for m in sorted(mons, key=lambda m: m["x"]):
    side = "left · main" if m["x"] == 0 else "right"
    rows.append((f"Screen  {m['name']}  ({side})", ICON_SCREEN, f"screen:{m['name']}"))

# windows from xdph
raw = os.environ.get("XDPH_WINDOW_SHARING_LIST", "")
for entry in raw.split("[HA>]"):
    if "[HC>]" not in entry:
        continue
    handle, rest = entry.split("[HC>]", 1)
    cls, rest = rest.split("[HT>]", 1) if "[HT>]" in rest else (rest, "")
    title = rest.split("[HE>]", 1)[0]
    if not handle.strip():
        continue
    t = title if len(title) < 60 else title[:57] + "…"
    rows.append((f"{cls}  —  {t}", cls.lower() or "application-x-executable", f"window:{handle}"))

rows.append(("Region  (select with mouse)", ICON_REGION, "region"))

menu = "\n".join(f"{label}\0icon\x1f{icon}" for label, icon, _ in rows)
r = sh(["rofi", "-dmenu", "-i", "-show-icons", "-format", "i", "-p", "share",
        "-theme", os.path.expanduser("~/.config/rofi/share.rasi")], menu)
if r.returncode != 0 or not r.stdout.strip():
    sys.exit(1)
sel = rows[int(r.stdout.strip())][2]

if sel == "region":
    g = sh(["slurp", "-f", "%o@%x,%y,%w,%h", "-b", "0e0e1088", "-c", "f2b8d0ff", "-w", "2"]).stdout.strip()
    if not g:
        sys.exit(1)
    # slurp gives global coords; xdph wants monitor-relative
    name, coords = g.split("@")
    x, y, w, h = map(int, coords.split(","))
    mon = next((m for m in mons if m["name"] == name), None)
    if mon:
        x -= mon["x"]; y -= mon["y"]
    sel = f"region:{name}@{x},{y},{w},{h}"

print(f"[SELECTION]r/{sel}")
