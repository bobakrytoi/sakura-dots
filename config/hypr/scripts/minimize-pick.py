#!/usr/bin/env python3
"""Pick a minimized window (special:minimized) - used by `minimize.sh restore`.

Prints the chosen window address (0x…) or nothing (cancelled / none). The UI is a
separate Quickshell instance (minimize-qs/shell.qml, same look as share-picker-qs);
if it gives no answer at all, the old rofi list is used.
Test hook: SAKURA_MIN_AUTO=<n> picks item n after 2.5 s (-1 = cancel).
"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
QS_DIR = os.path.join(HERE, "minimize-qs")
RUN = os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir())


def sh(cmd, inp=None, **kw):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True, **kw)


try:
    clients = json.loads(sh(["hyprctl", "clients", "-j"]).stdout)
except Exception:
    clients = []
wins = [{"addr": c["address"], "cls": c["class"], "title": c["title"]}
        for c in clients if c["workspace"]["name"] == "special:minimized"]
if not wins:
    sys.exit(0)

try:
    mons = json.loads(sh(["hyprctl", "monitors", "-j"]).stdout)
except Exception:
    mons = []
focused = next((m["name"] for m in mons if m.get("focused")), "")
try:
    st = json.load(open(os.path.expanduser("~/.config/sakura/settings.json")))
except Exception:
    st = {}

data = {"focused": focused, "windows": wins,
        "accent": st.get("accent", "#f2b8d0"), "glass": st.get("glass", 0.55),
        "font": st.get("font", "Inter"), "lang": st.get("lang", "en")}
out = os.path.join(RUN, f"sakura-min-{os.getpid()}.out")
env = dict(os.environ, SAKURA_MIN_DATA=json.dumps(data), SAKURA_MIN_OUT=out)

sel = None
try:
    sh(["qs", "-p", QS_DIR], env=env, timeout=600)
    if os.path.exists(out):
        sel = open(out).read().strip()
        os.unlink(out)
except subprocess.TimeoutExpired:
    sys.exit(0)
except FileNotFoundError:
    pass

if sel is None:  # quickshell gave no answer at all → old rofi list
    rows = "\n".join(c["addr"] + "\t" + c["cls"] + "  -  " + (c["title"] if len(c["title"]) < 60 else c["title"][:57] + "…")
                     for c in wins)
    r = sh(["rofi", "-dmenu", "-i", "-p", "minimized", "-display-columns", "2", "-display-column-separator", "\t",
            "-theme", os.path.expanduser("~/.config/rofi/list.rasi")], rows)
    sel = r.stdout.split("\t")[0].strip() if r.returncode == 0 else ""

if sel and any(c["addr"] == sel for c in wins):
    print(sel)
