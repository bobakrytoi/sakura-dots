#!/usr/bin/env python3
"""apply ~/.config/sakura/rgb.json to every OpenRGB device, picking the right mode name per device.
   rgb.py apply | login | rescan"""
import json, os, re, subprocess, sys
CFG = os.path.expanduser("~/.config/sakura/rgb.json")
CACHE = os.path.expanduser("~/.cache/sakura-rgb-devices.json")
WANT = {   # effect -> mode names to try, in order
    "static":    ["static", "direct"],
    "breathing": ["breathing", "breath", "custom breathing"],
    "rainbow":   ["spectrum cycle", "rainbow", "spectrum", "rainbow wave"],
    "off":       ["off"],
}

def scan():
    out = subprocess.run(["openrgb", "--noautoconnect", "-ld"], capture_output=True, text=True, timeout=90).stdout
    devs, cur = [], None
    for line in out.splitlines():
        m = re.match(r"^(\d+): (.+)$", line)
        if m: cur = {"index": int(m.group(1)), "name": m.group(2).strip(), "modes": []}; devs.append(cur); continue
        t = re.match(r"^\s+Type:\s*(.*)$", line)
        if t and cur is not None: cur["type"] = t.group(1).strip().lower()
        m = re.match(r"^\s+Modes:\s*(.*)$", line)
        if m and cur is not None:
            cur["modes"] = [x.strip("'[]").lower() for x in re.findall(r"'[^']+'|\[[^\]]+\]|\S+", m.group(1))]
    json.dump(devs, open(CACHE, "w"), indent=2)
    return devs

def devices():
    try: return json.load(open(CACHE))
    except Exception: return scan()

def led_color(hexc, dtype):
    """RAM LEDs turn pastel colors into warm white/yellow: give them the same hue, but saturated"""
    if dtype != "dram": return hexc
    import colorsys
    r, g, b = (int(hexc[i:i + 2], 16) / 255 for i in (0, 2, 4))
    h, sat, v = colorsys.rgb_to_hsv(r, g, b)
    if sat < 0.05: return hexc                 # white / grey stays as is
    r, g, b = colorsys.hsv_to_rgb(h, max(sat, 0.85), v)
    return "".join("%02X" % round(x * 255) for x in (r, g, b))

def pick(modes, effect, dtype=""):
    order = WANT[effect]
    # ASUS Aura motherboards (and their ARGB headers) only keep a color in Direct mode;
    # RAM sticks only keep it in Static. Everything else: Static first, Direct as fallback.
    if effect == "static" and dtype == "motherboard": order = ["direct", "static"]
    for name in order:
        if name in modes: return name
    return None

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "apply"
    try: cfg = json.load(open(CFG))
    except Exception: cfg = {"enabled": True, "color": "f2b8d0", "mode": "static", "brightness": 100, "atLogin": True}
    if cmd == "login" and not cfg.get("atLogin", True): return
    devs = scan() if cmd == "rescan" else devices()
    c, b = cfg.get("color", "f2b8d0"), cfg.get("brightness", 100) / 100
    hexc = "".join("%02X" % round(int(c[i:i + 2], 16) * b) for i in (0, 2, 4))
    effect = cfg.get("mode", "static") if cfg.get("enabled", True) else "off"
    args = ["openrgb", "--noautoconnect"]
    for d in devs:
        mode = pick(d["modes"], effect, d.get("type", ""))
        color = led_color(hexc, d.get("type", ""))
        if mode is None:                       # no "off" mode: black static instead
            mode, color = pick(d["modes"], "static", d.get("type", "")), "000000"
        if mode is None: continue
        args += ["-d", str(d["index"]), "-m", mode]
        if effect != "rainbow" and mode != "off": args += ["-c", color]
    r = subprocess.run(args, capture_output=True, text=True, timeout=90)
    if r.returncode != 0:                      # devices changed? rescan once and retry
        devs = scan()
        subprocess.run([a for a in args], capture_output=True, text=True, timeout=90)

main()
