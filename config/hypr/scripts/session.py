#!/usr/bin/env python3
"""Save / restore open apps with their workspace, position and size.
   session.py save     -> ~/.local/state/hypr-session.json
   session.py restore  -> relaunch them in the same place
"""
import glob, json, os, re, subprocess, sys, time

STATE = os.path.expanduser("~/.local/state/hypr-session.json")
SKIP = {"", "org.quickshell", "xdg-desktop-portal-gtk", "hyprland-share-picker",
        "com.gabm.satty", "org.gnome.NautilusPreviewer", "btop"}
MULTI = {"kitty"}            # apps where every launch = one more window

def desktop_exec(cls):
    """find the launch command of an app from its .desktop file"""
    dirs = [os.path.expanduser("~/.local/share/applications"), "/usr/share/applications"]
    lc = cls.lower()
    best = None
    for d in dirs:
        for f in glob.glob(os.path.join(d, "*.desktop")):
            name = os.path.basename(f)[:-8].lower()
            try:
                txt = open(f, encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            main = txt.split("\n[", 1)[0]          # only the [Desktop Entry] group
            wm = re.search(r"^StartupWMClass=(.*)$", main, re.M)
            ex = re.search(r"^Exec=(.*)$", main, re.M)
            term = re.search(r"^Terminal=true", main, re.M)
            if not ex or term:
                continue
            if name == lc or (wm and wm.group(1).strip().lower() == lc):
                best = re.sub(r"\s%[a-zA-Z]", "", ex.group(1)).strip()
                return best
    return best

def proc_cmd(pid):
    """fallback for apps without a matching .desktop file: the command the process was started with"""
    try:
        args = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
    except OSError:
        return None
    args = [a.decode(errors="ignore") for a in args if a]
    if not args:
        return None
    exe = os.path.basename(args[0])
    # skip helpers / sandboxes that can't be relaunched directly
    if exe in ("bwrap", "steamwebhelper", "pressure-vessel-wrap", "wine-preloader") or "/proc/" in args[0]:
        return None
    return " ".join("'" + a.replace("'", "'\\''") + "'" if (" " in a or "'" in a) else a for a in args)

def save():
    clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout or "[]")
    out, seen = [], set()
    for c in sorted(clients, key=lambda c: -c.get("focusHistoryID", 0)):   # oldest first, focused last
        cls = c.get("class", "")
        ws = c.get("workspace", {}).get("name", "")
        if cls in SKIP or not c.get("mapped") or not ws or ws.startswith("special:"):
            continue
        if cls in seen and cls not in MULTI:
            continue
        cmd = desktop_exec(cls) or proc_cmd(c.get("pid", 0))
        if not cmd:
            continue
        seen.add(cls)
        out.append({"class": cls, "cmd": cmd, "workspace": ws,
                    "x": c["at"][0], "y": c["at"][1], "w": c["size"][0], "h": c["size"][1],
                    "fullscreen": c.get("fullscreen", 0)})
    if not out and os.path.exists(STATE):
        return            # never overwrite a good session with an empty one (e.g. during shutdown)
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    json.dump(out, open(tmp, "w"), indent=2)
    os.replace(tmp, STATE)

def lua_str(s):
    return s.replace("\\", "\\\\").replace("'", "\\'")

def restore():
    try:
        apps = json.load(open(STATE))
    except (OSError, ValueError):
        return
    for a in apps:
        rules = (f"{{ workspace = '{a['workspace']} silent', float = true, "
                 f"move = '{a['x']} {a['y']}', size = '{a['w']} {a['h']}' }}")
        subprocess.run(["hyprctl", "dispatch", f"hl.dsp.exec_cmd('{lua_str(a['cmd'])}', {rules})"],
                       capture_output=True)
        time.sleep(0.4)

if __name__ == "__main__":
    {"save": save, "restore": restore}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
