# sakura mono - sakura-cam: draws the home-screen icon (lens rings + a petal, sakura pink on night glass)
import math, sys
from PIL import Image, ImageDraw, ImageFilter
def icon(n):
    S = n * 4
    img = Image.new("RGB", (S, S), (11, 12, 18))
    glow = Image.new("RGB", (S, S), (11, 12, 18))
    d = ImageDraw.Draw(glow)
    d.ellipse((S*.12, S*.10, S*.88, S*.86), fill=(70, 46, 62))
    img = glow.filter(ImageFilter.GaussianBlur(S * .12))
    d = ImageDraw.Draw(img)
    acc = (242, 184, 208)
    c, R = S / 2, S * .27
    d.ellipse((c-R, c-R, c+R, c+R), outline=acc, width=int(S*.045))
    r = S * .095
    d.ellipse((c-r, c-r, c+r, c+r), fill=acc)
    # a small petal at the upper right of the ring
    px, py, pr = c + R*.92, c - R*.92, S*.075
    pts = []
    for i in range(64):
        t = i / 64 * 2 * math.pi
        x = math.sin(t) * pr * .62; y = -math.cos(t) * pr * (1.0 if math.cos(t) > 0 else .8)
        if abs(t - math.pi) < .35: y -= pr * .25 * (1 - abs(t - math.pi) / .35)   # the notch at the tip
        a = math.radians(40)
        pts.append((px + x*math.cos(a) - y*math.sin(a), py + x*math.sin(a) + y*math.cos(a)))
    d.polygon(pts, fill=(255, 214, 230))
    return img.resize((n, n), Image.LANCZOS)
for n, name in ((180, "apple-touch-icon.png"), (192, "icon-192.png"), (512, "icon-512.png")):
    icon(n).save("static/" + name)
