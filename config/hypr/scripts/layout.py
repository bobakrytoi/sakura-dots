#!/usr/bin/env python3
"""waybar: current keyboard layout (EN/RU), updated instantly from Hyprland events"""
import json, os, socket, subprocess, sys

def short(name):
    n = (name or "").lower()
    if "russian" in n: return "RU"
    if "english" in n: return "EN"
    return (name or "??")[:2].upper()

def emit(name):
    print(json.dumps({"text": short(name), "tooltip": f"{name}\nclick or Alt+Shift to switch"}), flush=True)

def current():
    try:
        kb = json.loads(subprocess.run(["hyprctl", "devices", "-j"], capture_output=True, text=True).stdout)["keyboards"]
        real = [k for k in kb if "keyboard" in k["name"] or "qk61" in k["name"]] or kb
        return real[-1]["active_keymap"]
    except Exception:
        return "English (US)"

emit(current())
path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"], ".socket2.sock")
s = socket.socket(socket.AF_UNIX); s.connect(path)
buf = b""
while True:
    data = s.recv(4096)
    if not data: break
    buf += data
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        line = line.decode(errors="ignore")
        if line.startswith("activelayout>>"):
            emit(line.split(",", 1)[1] if "," in line else current())
