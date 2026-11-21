#!/usr/bin/env python3
"""Generate sakura-settings / sakura-taskmgr icons (64-unit grid).
Big variant for >=32 px, simplified 'small' variant for 16/24 px."""
import math, sys, os

OUT = sys.argv[1]

def squircle(cx, cy, r, n=5.0, steps=160):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = cx + r * math.copysign(abs(c) ** (2 / n), c)
        y = cy + r * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{x:.2f},{y:.2f}")
    return "M" + " L".join(pts) + " Z"

def gear(r_out, r_in, teeth, hole, tw_out=0.5, tw_in=0.62, cx=32, cy=32):
    """Gear outline as a path; tooth top width/base width as fraction of pitch."""
    pts = []
    pitch = 2 * math.pi / teeth
    for k in range(teeth):
        a0 = k * pitch
        # base start, top start, top end, base end
        for frac, rr in ((-tw_in / 2, r_in), (-tw_out / 2, r_out), (tw_out / 2, r_out), (tw_in / 2, r_in)):
            a = a0 + frac * pitch
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d = "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + " Z"
    # hole (counter-clockwise via evenodd)
    d += f" M{cx + hole:.2f},{cy} A{hole},{hole} 0 1 0 {cx - hole:.2f},{cy} A{hole},{hole} 0 1 0 {cx + hole:.2f},{cy} Z"
    return d

TILE = squircle(32, 32, 27)
TILE_SH = squircle(32, 33.2, 27)

def tile(gid, top, bottom):
    return f'''
  <defs>
    <linearGradient id="{gid}" x1="0" y1="5" x2="0" y2="59" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>
    </linearGradient>
    <linearGradient id="{gid}-hl" x1="0" y1="5" x2="0" y2="59" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset=".45" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
    <clipPath id="{gid}-clip"><path d="{TILE}"/></clipPath>
  </defs>
  <path d="{TILE_SH}" fill="#000" opacity=".22"/>
  <path d="{TILE}" fill="url(#{gid})"/>
  <path d="{TILE}" fill="url(#{gid}-hl)"/>
  <path d="{TILE}" fill="none" stroke="#fff" stroke-opacity=".16" stroke-width="1" clip-path="url(#{gid}-clip)"/>'''

def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">{body}\n</svg>\n'

# ---------- Settings: rose tile, white gear ----------
def settings(small):
    if small:
        g = gear(19.5, 14.5, 6, 6.2, tw_out=0.42, tw_in=0.6)
    else:
        g = gear(18.5, 14.2, 8, 6.0, tw_out=0.44, tw_in=0.62)
    return svg(tile("s", "#f5a9c8", "#cf5f90") + f'''
  <g fill-rule="evenodd">
    <path d="{g}" fill="#7a2450" opacity=".22" transform="translate(0 1.2)"/>
    <path d="{g}" fill="#fff" stroke="#fff" stroke-width="{2.4 if small else 1.6}" stroke-linejoin="round"/>
  </g>''')

# ---------- Task manager: deep indigo tile, pulse graph ----------
def taskmgr(small):
    if small:
        line = "M12,35 L22,35 L27,22 L35,44 L40,31 L52,31"
        sw = 6.2
        grid = ""
    else:
        line = "M12,36 L20,36 L25,25 L32,44 L38,20 L43,33 L52,33"
        sw = 4.2
        grid = '''
  <g stroke="#fff" stroke-opacity=".08" stroke-width="1.2" stroke-linecap="round">
    <path d="M13 22.5h38M13 32h38M13 41.5h38"/>
  </g>'''
    area = line + " L52,50 L12,50 Z"
    return svg(tile("t", "#3d4775", "#1e2342") + f'''
  <defs>
    <linearGradient id="t-area" x1="0" y1="20" x2="0" y2="50" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#f2b8d0" stop-opacity=".55"/><stop offset="1" stop-color="#f2b8d0" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="t-line" x1="12" y1="0" x2="52" y2="0" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#f7c6da"/>
    </linearGradient>
  </defs>{grid}
  <path d="{area}" fill="url(#t-area)" clip-path="url(#t-clip)"/>
  <path d="{line}" fill="none" stroke="#000" stroke-opacity=".25" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" transform="translate(0 1.2)"/>
  <path d="{line}" fill="none" stroke="url(#t-line)" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"/>''')

# ---------- Calculator: lavender tile, + − × and a rose "=" ----------
def calc(small):
    sw = 5.6 if small else 4.4
    a, b = (17, 47) if small else (19, 45)   # glyph centres
    r = 7.2 if small else 6.0                # half-size of a glyph
    def plus(cx, cy):  return f"M{cx-r},{cy} H{cx+r} M{cx},{cy-r} V{cy+r}"
    def minus(cx, cy): return f"M{cx-r},{cy} H{cx+r}"
    def times(cx, cy):
        d = r * 0.78
        return f"M{cx-d},{cy-d} L{cx+d},{cy+d} M{cx+d},{cy-d} L{cx-d},{cy+d}"
    def equals(cx, cy):
        g = r * 0.5
        return f"M{cx-r},{cy-g} H{cx+r} M{cx-r},{cy+g} H{cx+r}"
    white = plus(a, a) + " " + minus(b, a) + " " + times(a, b)
    rose = equals(b, b)
    sep = "" if small else '''
  <g stroke="#fff" stroke-opacity=".10" stroke-width="1.2" stroke-linecap="round">
    <path d="M32 13v38M13 32h38"/>
  </g>'''
    return svg(tile("c", "#a594f2", "#5b48b5") + f'''{sep}
  <g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="{sw}">
    <path d="{white} {rose}" stroke="#2a1f66" stroke-opacity=".28" transform="translate(0 1.2)"/>
    <path d="{white}" stroke="#fff"/>
    <path d="{rose}" stroke="#ffd0e3"/>
  </g>''')

os.makedirs(OUT, exist_ok=True)
for name, fn in (("sakura-settings", settings), ("sakura-taskmgr", taskmgr), ("sakura-calc", calc)):
    open(f"{OUT}/{name}.svg", "w").write(fn(False))
    open(f"{OUT}/{name}-small.svg", "w").write(fn(True))
print("ok")
