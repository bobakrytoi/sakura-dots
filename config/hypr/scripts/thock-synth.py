#!/usr/bin/env python3
# sakura v3 timer / alarm / notification sounds, built from the lock-screen key clicks the user likes
# (~/.local/share/sounds/sakura/key1-3, key-enter: soft "creamy" thocks). No tones, no ringing: just
# those thocks, a bit lower, in gentle knock patterns, with a tiny low "body" thump and a dark room.
# usage: thock-synth.py SRC_DIR OUT.wav   (file name picks: alarm-a/b/c, pomo, notify-a/b/c)
# v1/v2 (tonal marimba/bells) were rejected as "звонкие" - see HANDOFF.md 4.17.
import math, wave, struct, sys, os

SR = 48000
src, out = sys.argv[1], sys.argv[2]

def load(name):
    with wave.open(os.path.join(src, name + ".wav")) as w:
        assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2
        d = w.readframes(w.getnframes())
    return [v / 32768 for v in struct.unpack("<%dh" % (len(d) // 2), d)]

K = {k: load(k) for k in ["key1", "key2", "key3", "key-enter", "key-back"]}

def pitched(x, r):
    """r < 1 = lower and a little longer (tape-style)"""
    n = int(len(x) / r); y = [0.0] * n
    for i in range(n):
        p = i * r; j = int(p); f = p - j
        a = x[j] if j < len(x) else 0.0; b = x[j + 1] if j + 1 < len(x) else 0.0
        y[i] = a + (b - a) * f
    return y

def body(f=140, dec=0.035, atk=0.004):
    """a very short, soft low thump under the click (felt, not a note)"""
    n = int(0.15 * SR)
    return [(0.5 - 0.5 * math.cos(math.pi * min(1, i / SR / atk))) * math.exp(-i / SR / dec) * math.sin(2 * math.pi * f * i / SR) for i in range(n)]

def place(b, t, x, g):
    s = int(t * SR)
    for i, v in enumerate(x):
        if s + i < len(b): b[s + i] += g * v

def lp(b, fc):
    a = math.exp(-2 * math.pi * fc / SR); y = 0.0
    for i, x in enumerate(b):
        y = (1 - a) * x + a * y; b[i] = y

def room(b, mix):
    wet = [0.0] * len(b)
    for d, g in [(613, .45), (677, .43), (751, .41), (829, .40)]:
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
        w.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, int(32767 * g * x)))) for x in b))

def thock(k, r=1.0, bf=None, bg=0.0):
    x = pitched(K[k], r)
    if bf:
        y = body(bf); x = x + [0.0] * max(0, len(y) - len(x))
        for i, v in enumerate(y): x[i] += bg * v
    return x

kind = os.path.basename(out)
if "alarm-a" in kind:      # (a) soft double knock, twice: "tok-tok ... tok-tok"
    b = [0.0] * int(1.9 * SR)
    for t, k, g in [(0.0, "key1", 0.9), (0.15, "key-enter", 0.8), (0.85, "key2", 0.9), (1.0, "key-enter", 0.8)]:
        place(b, t + 0.01, thock(k, 0.92, 150, 0.15), g)
    lp(b, 4500); room(b, 0.12); peak = -4
elif "alarm-b" in kind:    # (b) the same knock, deeper and rounder
    b = [0.0] * int(2.0 * SR)
    for t, k, g in [(0.0, "key1", 0.9), (0.17, "key-enter", 0.8), (0.9, "key3", 0.9), (1.07, "key-enter", 0.8)]:
        place(b, t + 0.01, thock(k, 0.75, 110, 0.25), g)
    lp(b, 3200); room(b, 0.14); peak = -4
elif "alarm-c" in kind:    # (c) light patter, like fingers on a desk: tok-tok-tok ... tok-tok-tok
    b = [0.0] * int(1.9 * SR)
    for base in (0.0, 0.85):
        for i, (k, r) in enumerate([("key1", 0.86), ("key2", 0.92), ("key3", 0.98)]):
            place(b, base + i * 0.12 + 0.01, thock(k, r, 140, 0.12), 0.8 + 0.07 * i)
    lp(b, 4200); room(b, 0.12); peak = -5
elif "pomo" in kind:       # pomodoro phase: two soft toks
    b = [0.0] * int(0.6 * SR)
    place(b, 0.01, thock("key1", 0.9, 140, 0.15), 0.9)
    place(b, 0.15, thock("key-enter", 0.9, 140, 0.15), 0.8)
    lp(b, 4200); room(b, 0.10); peak = -7
elif "notify-a" in kind:   # notification (a): "tok-tok"
    b = [0.0] * int(0.45 * SR)
    place(b, 0.01, thock("key1", 0.92, 150, 0.12), 0.9)
    place(b, 0.12, thock("key-enter", 0.92, 150, 0.12), 0.8)
    lp(b, 4200); room(b, 0.10); peak = -10
elif "notify-b" in kind:   # (b): one deep creamy thock
    b = [0.0] * int(0.4 * SR)
    place(b, 0.01, thock("key-enter", 0.78, 110, 0.25), 1.0)
    lp(b, 3200); room(b, 0.12); peak = -10
elif "notify-c" in kind:   # (c): quick light triple patter
    b = [0.0] * int(0.45 * SR)
    for i, (k, r) in enumerate([("key1", 0.9), ("key2", 0.95), ("key3", 1.0)]):
        place(b, 0.01 + i * 0.075, thock(k, r, 150, 0.1), 0.75 + 0.1 * i)
    lp(b, 4200); room(b, 0.10); peak = -11
else:
    sys.exit("unknown " + kind)
write(b, out, peak)
