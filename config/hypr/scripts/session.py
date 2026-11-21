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
        out.append({"class": cls, "title": c.get("title", ""), "cmd": cmd, "workspace": ws,
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

def clients():
    try:
        return json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3).stdout or "[]")
    except Exception:
        return []

def place(addr, a):
    """put one window exactly where it was: its workspace, floating, same size, same spot (global coordinates)"""
    sel = "address:" + addr
    lua = (f"local s = '{sel}'; local w = hl.get_window(s); if not w then return end "
           f"if tostring(w.workspace and (w.workspace.name or w.workspace.id) or '') ~= '{lua_str(a['workspace'])}' then "
           f"hl.dispatch(hl.dsp.window.move({{ workspace = '{lua_str(a['workspace'])}', window = s, follow = false }})) end "
           f"if not w.floating then hl.dispatch(hl.dsp.window.float({{ action = 'enable', window = s }})) end "
           f"hl.dispatch(hl.dsp.window.resize({{ x = {a['w']}, y = {a['h']}, window = s }})) "
           f"hl.dispatch(hl.dsp.window.move({{ x = {a['x']}, y = {a['y']}, window = s }}))")
    subprocess.run(["hyprctl", "eval", lua], capture_output=True)

def restore():
    """launch the saved apps, then wait for their windows and put each one back in place.
    Window rules on exec only match the launched PID, and browsers / Electron apps / Steam open their
    window from another process, so instead every new window is matched by class (+ title when possible)
    and moved/resized with global coordinates. Apps like to reposition themselves right after they
    appear, so the placement is repeated a few times."""
    try:
        apps = json.load(open(STATE))
    except (OSError, ValueError):
        return
    if not apps:
        return
    before = {c["address"] for c in clients()}
    for a in apps:
        subprocess.run(["hyprctl", "dispatch", f"hl.dsp.exec_cmd('{lua_str(a['cmd'])}', {{ workspace = '{lua_str(a['workspace'])} silent' }})"],
                       capture_output=True)
        time.sleep(0.3)
    pending = list(range(len(apps)))
    taken = set(before)
    redo = []                       # (time, addr, app) - placements to repeat
    start = time.time()
    while (pending or redo) and time.time() - start < 90:
        now = time.time()
        cs = [c for c in clients() if c.get("mapped") and c["address"] not in taken]
        for i in list(pending):
            a = apps[i]
            same = [c for c in cs if c.get("class") == a["class"] and c["size"][0] > 0]
            # prefer the window with the same title (Steam opens small helper windows first); after 20 s take any
            pick = next((c for c in same if a.get("title") and c.get("title") == a["title"]), None)
            if pick is None and (not a.get("title") or now - start > 20 or a["class"] != "steam"):
                pick = next((c for c in same if c["size"][0] >= 400 and c["size"][1] >= 300), None)
            if pick is None:
                continue
            taken.add(pick["address"]); cs.remove(pick); pending.remove(i)
            place(pick["address"], a)
            redo += [(now + d, pick["address"], a) for d in (0.8, 2.0, 4.5)]
        for r in [r for r in redo if r[0] <= now]:
            redo.remove(r); place(r[1], r[2])
        time.sleep(0.25)

if __name__ == "__main__":
    {"save": save, "restore": restore}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
