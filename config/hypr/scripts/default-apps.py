#!/usr/bin/env python3
"""Default apps for Settings > Apps.
  default-apps.py list            -> JSON {category: {"current": id|null, "options": [{id, name, icon}]}}
  default-apps.py set CAT ID      -> makes ID.desktop the default for every mime type of CAT (xdg-mime)"""
import json, os, subprocess, sys, glob, configparser

CATS = {
    "browser": ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"],
    "files":   ["inode/directory"],
    "text":    ["text/plain"],
    "images":  ["image/png", "image/jpeg", "image/webp", "image/gif"],
    "video":   ["video/mp4", "video/x-matroska", "video/webm"],
    "music":   ["audio/mpeg", "audio/flac", "audio/ogg"],
    "pdf":     ["application/pdf"],
    "terminal": [],
}
dirs = [os.path.expanduser("~/.local/share/applications"), "/usr/local/share/applications", "/usr/share/applications",
        "/var/lib/flatpak/exports/share/applications", os.path.expanduser("~/.local/share/flatpak/exports/share/applications")]

def entries():
    seen = {}
    for d in dirs:
        for f in glob.glob(os.path.join(d, "*.desktop")):
            i = os.path.basename(f)
            if i in seen: continue
            cp = configparser.RawConfigParser(strict=False, interpolation=None)
            try: cp.read(f, encoding="utf-8")
            except Exception: continue
            if not cp.has_section("Desktop Entry"): continue
            e = cp["Desktop Entry"]
            if e.get("NoDisplay", "false").lower() == "true" or e.get("Hidden", "false").lower() == "true": continue
            seen[i] = {"id": i, "name": e.get("Name", i), "icon": e.get("Icon", ""),
                       "mimes": [m for m in e.get("MimeType", "").split(";") if m],
                       "cats": e.get("Categories", "")}
    return seen

def query(m):
    try: return subprocess.run(["xdg-mime", "query", "default", m], capture_output=True, text=True, timeout=3).stdout.strip() or None
    except Exception: return None

if len(sys.argv) > 1 and sys.argv[1] == "set":
    cat, app = sys.argv[2], sys.argv[3]
    if cat == "terminal":
        p = os.path.expanduser("~/.config/xdg-terminals.list")
        open(p, "w").write(app + "\n")
    else:
        subprocess.run(["xdg-mime", "default", app] + CATS[cat])
    sys.exit(0)

E = entries()
out = {}
for cat, mimes in CATS.items():
    if cat == "terminal":
        opts = [e for e in E.values() if "TerminalEmulator" in e["cats"]]
        cur = None
        p = os.path.expanduser("~/.config/xdg-terminals.list")
        if os.path.exists(p):
            cur = (open(p).read().split() or [None])[0]
    else:
        opts = [e for e in E.values() if any(m in e["mimes"] for m in mimes)]
        cur = query(mimes[0])
    out[cat] = {"current": cur, "options": [{"id": e["id"], "name": e["name"], "icon": e["icon"]} for e in sorted(opts, key=lambda e: e["name"].lower())]}
print(json.dumps(out))
