#!/usr/bin/env python3
# sakura v4 timer / alarm / notification sounds: soft "bubble pops" (the user picked this timbre from
# timbre-try.py, sample 1). A pop = sine gliding quickly up from f0 to f0+lift, round 4 ms attack,
# ~45 ms decay, low-passed - no ringing, no click. v1-v3 (marimba, felt, key thocks) were rejected.
# usage: bubble-synth.py OUT.wav   (file name picks: alarm-a/b/c, pomo, notify-a/b/c)
import math, wave, struct, sys, os

SR = 48000
out = sys.argv[1]

# v5 "bubble-knock": v4 bubbles were still "too ringy, make it more like a knock" → the bubble is
# lower (×0.62), glides less (×0.4), dies ~2× faster, and the lock-screen key click sits under it.
TONE, LIFT, DECAY, KNOCK = 0.62, 0.4, 0.5, 0.55
def _key():
    with wave.open(os.path.expanduser("~/.local/share/sounds/sakura/key-enter.wav")) as w:
        d = w.readframes(w.getnframes())
    x = [v / 32768 for v in struct.unpack("<%dh" % (len(d) // 2), d)]
    r = 0.85; n = int(len(x) / r)                     # a bit lower
    return [x[min(len(x) - 1, int(i * r))] for i in range(n)]
KEY = _key()
KPK = max(abs(v) for v in KEY)

def pop(b, start, f0=380, lift=520, glide=0.025, dec=0.045, g=1.0):
    s0 = int(start * SR); ph = 0.0
    f0 *= TONE; lift *= LIFT; dec *= DECAY
    for i in range(int((dec * 8) * SR)):
        if s0 + i >= len(b): break
        t = i / SR; f = f0 + lift * (1 - math.exp(-t / glide))
        ph += 2 * math.pi * f / SR
        b[s0 + i] += g * (0.5 - 0.5 * math.cos(math.pi * min(1.0, t / 0.004))) * math.exp(-t / dec) * math.sin(ph)
    for i, v in enumerate(KEY):
        if s0 + i < len(b): b[s0 + i] += g * KNOCK * v / KPK

def lp(b, fc, passes=2):
    a = math.exp(-2 * math.pi * fc / SR)
    for _ in range(passes):
        y = 0.0
        for i, x in enumerate(b): y = (1 - a) * x + a * y; b[i] = y

def room(b, mix):
    wet = [0.0] * len(b)
    for d, g in [(613, .40), (677, .38), (751, .36), (829, .35)]:
        line = [0.0] * d; idx = 0; l = 0.0
        for i, x in enumerate(b):
            y = line[idx]; l = 0.3 * y + 0.7 * l
            line[idx] = x + g * l; idx = (idx + 1) % d; wet[i] += y * 0.25
    for i in range(len(b)): b[i] = b[i] * (1 - mix) + wet[i] * mix

def write(b, path, peak_db):
    pk = max(abs(x) for x in b) or 1.0; g = 10 ** (peak_db / 20) / pk
    n = int(0.03 * SR)
    for i in range(n): b[-n + i] *= 1 - i / n
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * g * x)) for x in b))

kind = os.path.basename(out)
B = lambda sec: [0.0] * int(sec * SR)
if "alarm-a" in kind:      # (a) bubbles: bup-bup-bup rising, twice
    b = B(1.9)
    for base in (0.0, 0.85):
        for i, f0 in enumerate([340, 400, 470]):
            pop(b, base + 0.01 + i * 0.13, f0, 480 + 40 * i, g=0.85 + 0.07 * i)
    lp(b, 2500); room(b, 0.10); peak = -4
elif "alarm-b" in kind:    # (b) deep bubbles: slower, lower, bup-bup twice
    b = B(2.0)
    for base in (0.0, 0.9):
        for i, f0 in enumerate([240, 290]):
            pop(b, base + 0.01 + i * 0.18, f0, 330, glide=0.03, dec=0.06, g=0.9)
    lp(b, 2000); room(b, 0.12); peak = -4
elif "alarm-c" in kind:    # (c) bubbling: a little stream of uneven pops
    b = B(1.9)
    for t, f0, g in [(0.0, 360, .8), (0.09, 430, .7), (0.21, 330, .85), (0.29, 470, .7), (0.42, 390, .8),
                     (0.95, 350, .8), (1.04, 440, .7), (1.16, 320, .85), (1.24, 480, .7), (1.37, 400, .8)]:
        pop(b, t + 0.01, f0, 460, g=g)
    lp(b, 2500); room(b, 0.10); peak = -5
elif "pomo" in kind:       # pomodoro phase: two pops up
    b = B(0.5)
    pop(b, 0.01, 340, 480, g=0.9); pop(b, 0.14, 420, 520, g=0.85)
    lp(b, 2500); room(b, 0.08); peak = -7
elif "notify-a" in kind:   # notification (a): bup-bip
    b = B(0.4)
    pop(b, 0.01, 360, 480, g=0.9); pop(b, 0.11, 460, 520, g=0.8)
    lp(b, 2500); room(b, 0.08); peak = -10
elif "notify-b" in kind:   # (b): one bubble (the sample the user picked)
    b = B(0.35)
    pop(b, 0.01)
    lp(b, 2500); room(b, 0.06); peak = -10
elif "notify-c" in kind:   # (c): one deep bubble
    b = B(0.4)
    pop(b, 0.01, 250, 340, glide=0.03, dec=0.06)
    lp(b, 2000); room(b, 0.08); peak = -10
else:
    sys.exit("unknown " + kind)
write(b, out, peak)
