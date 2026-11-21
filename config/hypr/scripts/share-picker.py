#!/usr/bin/env python3
"""sakura screen-share picker for xdg-desktop-portal-hyprland.

xdph runs this (custom_picker_binary in ~/.config/hypr/xdph.conf) and reads stdout:
    [SELECTION]r/screen:DP-3 | r/window:<handle> | r/region:DP-1@x,y,w,h
("r" = allow a restore token). Exit 1 / no output = cancelled.

The UI is a separate Quickshell instance (share-picker-qs/shell.qml) with live
thumbnails; this script only collects the data, runs it and translates the answer.
Fallback: if quickshell gives no answer at all, the old rofi list is used.
Debug: ~/.cache/sakura/share-picker.log (last run).
"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
QS_DIR = os.path.join(HERE, "share-picker-qs")
RUN = os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir())
LOG = os.path.expanduser("~/.cache/sakura/share-picker.log")

try:
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    open(LOG, "w").close()
except Exception:
    pass


def sh(cmd, inp=None, **kw):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True, **kw)


def log(*a):
    try:
        with open(LOG, "a") as f:
            print(*a, file=f)
    except Exception:
        pass


def norm(a):
    return a.lower().removeprefix("0x")


# ── monitors ──────────────────────────────────────────────
try:
    mons = json.loads(sh(["hyprctl", "monitors", "-j"]).stdout)
except Exception:
    mons = []
mons.sort(key=lambda m: m["x"])
focused = next((m["name"] for m in mons if m.get("focused")), mons[0]["name"] if mons else "")

# ── windows (from xdph) ───────────────────────────────────
try:
    clients = json.loads(sh(["hyprctl", "clients", "-j"]).stdout)
except Exception:
    clients = []
addrs = {norm(c["address"]): c for c in clients}

raw = os.environ.get("XDPH_WINDOW_SHARING_LIST", "")
log("XDPH_WINDOW_SHARING_LIST =", repr(raw))
windows = []
for entry in raw.split("[HA>]"):
    if "[HC>]" not in entry:
        continue
    handle, rest = entry.split("[HC>]", 1)
    cls, rest = rest.split("[HT>]", 1) if "[HT>]" in rest else (rest, "")
    title, extra = rest.split("[HE>]", 1) if "[HE>]" in rest else (rest, "")
    if not handle.strip():
        continue
    # 4th field = hyprland window address; match it to hyprctl (decimal or hex)
    addr = ""
    cand = extra.strip()
    for base in (10, 16):
        try:
            h = format(int(cand, base), "x")
        except ValueError:
            continue
        if h in addrs:
            addr = h
            break
    if not addr:  # fall back to class + title
        used = {w["addr"] for w in windows}
        for a, c in addrs.items():
            if c.get("class") == cls and c.get("title") == title and a not in used:
                addr = a
                break
    c = addrs.get(addr, {})
    windows.append({"handle": handle.strip(), "cls": cls, "title": title, "addr": addr,
                    "ws": str(c.get("workspace", {}).get("name", ""))})

# ── settings (accent, glass, font, language) ──────────────
try:
    st = json.load(open(os.path.expanduser("~/.config/sakura/settings.json")))
except Exception:
    st = {}

# the picker sits on the focused monitor, so a live view of it would film itself: snapshot that one first
snap = ""
if focused:
    p = os.path.join(RUN, "sakura-share-snap.jpg")
    if sh(["grim", "-s", "0.35", "-t", "jpeg", "-q", "85", "-o", focused, p]).returncode == 0:
        snap = p

data = {
    "focused": focused, "snap": snap,
    "monitors": [{"name": m["name"], "w": m["width"], "h": m["height"],
                  "main": m["x"] == 0 and m["y"] == 0} for m in mons],
    "windows": windows,
    "accent": st.get("accent", "#f2b8d0"), "glass": st.get("glass", 0.55),
    "font": st.get("font", "Inter"), "lang": st.get("lang", "en"),
}
out = os.path.join(RUN, f"sakura-share-{os.getpid()}.out")
env = dict(os.environ, SAKURA_SHARE_DATA=json.dumps(data), SAKURA_SHARE_OUT=out)

sel = None
try:
    r = sh(["qs", "-p", QS_DIR], env=env, timeout=600)
    log("qs rc", r.returncode, r.stderr[-3000:])
    if os.path.exists(out):
        sel = open(out).read().strip()
        os.unlink(out)
        if not sel:
            sys.exit(1)
except subprocess.TimeoutExpired:
    sys.exit(1)
except FileNotFoundError:
    pass

if sel is None:  # quickshell gave no answer at all → old rofi list
    rows = [(f"Screen  {m['name']}", "video-display", f"screen:{m['name']}") for m in mons]
    rows += [(f"{w['cls']}  -  {w['title'][:57]}", w["cls"].lower() or "application-x-executable",
              f"window:{w['handle']}") for w in windows]
    rows.append(("Region", "applets-screenshooter", "region"))
    menu = "\n".join(f"{l}\0icon\x1f{i}" for l, i, _ in rows)
    r = sh(["rofi", "-dmenu", "-i", "-show-icons", "-format", "i", "-p", "share",
            "-theme", os.path.expanduser("~/.config/rofi/share.rasi")], menu)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit(1)
    sel = rows[int(r.stdout.strip())][2]

if sel == "region":
    g = sh(["slurp", "-f", "%o@%x,%y,%w,%h", "-b", "0e0e1088", "-c", data["accent"].lstrip("#") + "ff", "-w", "2"]).stdout.strip()
    if not g:
        sys.exit(1)
    # slurp gives global coords; xdph wants monitor-relative
    name, coords = g.split("@")
    x, y, w, h = map(int, coords.split(","))
    mon = next((m for m in mons if m["name"] == name), None)
    if mon:
        x -= mon["x"]; y -= mon["y"]
    sel = f"region:{name}@{x},{y},{w},{h}"

if not sel.startswith(("screen:", "window:", "region:")):
    sys.exit(1)
log("selection", sel)
print(f"[SELECTION]r/{sel}")
