#!/bin/sh
# SDDM runs this as root right before the login screen appears (X11).
# Both monitors are the same model, so the main one is found by its EDID serial
# (/usr/local/share/sakura/main-monitor-serial). It becomes "primary" and the leftmost screen;
# the sakura theme shows the password field only on the primary screen.
[ -x /usr/share/sddm/scripts/Xsetup ] && /usr/share/sddm/scripts/Xsetup
SERIAL=$(cat /usr/local/share/sakura/main-monitor-serial 2>/dev/null)
[ -n "$SERIAL" ] || exit 0
xrandr --verbose 2>/dev/null | python3 -I -c '
import sys, subprocess
want = sys.argv[1]
outs, cur, edid, grab = [], None, {}, False
for line in sys.stdin:
    if line and not line[0].isspace():
        grab = False
        p = line.split()
        if len(p) > 1 and p[1] == "connected": cur = p[0]; outs.append(cur); edid[cur] = ""
        else: cur = None
    elif cur and line.strip() == "EDID:": grab = True
    elif cur and grab:
        t = line.strip()
        if all(c in "0123456789abcdef" for c in t) and t: edid[cur] += t
        else: grab = False
def serial(h):
    try: e = bytes.fromhex(h)
    except ValueError: return ""
    for i in range(54, 126, 18):
        d = e[i:i + 18]
        if len(d) == 18 and d[:3] == b"\0\0\0" and d[3] == 0xFF:
            return d[5:].split(b"\n")[0].decode("ascii", "ignore").strip()
    return ""
main = next((o for o in outs if serial(edid.get(o, "")) == want), None)
if not main: sys.exit(0)
cmd = ["xrandr", "--output", main, "--auto", "--primary", "--pos", "0x0"]
prev = main
for o in outs:
    if o != main: cmd += ["--output", o, "--auto", "--right-of", prev]; prev = o
subprocess.run(cmd)
' "$SERIAL"
exit 0
