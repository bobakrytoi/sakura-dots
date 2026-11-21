#!/usr/bin/env python3
# audition: 6 different soft timbres (one short hit each) so the user can pick the "creamy" one.
# usage: timbre-try.py OUT_DIR
import math, wave, struct, sys, os, random

SR = 48000
od = sys.argv[1]; os.makedirs(od, exist_ok=True)
random.seed(3)

def lp(b, fc, passes=2):
    a = math.exp(-2 * math.pi * fc / SR)
    for _ in range(passes):
        y = 0.0
        for i, x in enumerate(b): y = (1 - a) * x + a * y; b[i] = y

def write(b, name, peak_db=-10):
    pk = max(abs(x) for x in b) or 1.0; g = 10 ** (peak_db / 20) / pk
    n = int(0.03 * SR)
    for i in range(n): b[-n + i] *= 1 - i / n
    with wave.open(os.path.join(od, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * g * x)) for x in b))

def smooth(t, a): return 0.5 - 0.5 * math.cos(math.pi * min(1.0, t / a))

# 1 - bubble pop: sine that glides up quickly, very short, round (like a soft water drop)
b = []
ph = 0.0
for i in range(int(0.35 * SR)):
    t = i / SR; f = 380 + 520 * (1 - math.exp(-t / 0.025))
    ph += 2 * math.pi * f / SR
    b.append(smooth(t, 0.004) * math.exp(-t / 0.045) * math.sin(ph))
lp(b, 2500); write(b, "1-pop")

# 2 - felt piano: muted soft piano-ish note C4, few harmonics, short sustain
b = []
for i in range(int(0.7 * SR)):
    t = i / SR; f = 261.6
    v = sum(a * math.exp(-t / d) * math.sin(2 * math.pi * f * h * t) for h, a, d in [(1, 1, .25), (2, .35, .12), (3, .12, .06), (4, .05, .04)])
    b.append(smooth(t, 0.008) * v)
lp(b, 1800); write(b, "2-felt-piano")

# 3 - air: soft breathy whoosh (filtered noise swell), no tone, no click
b = [random.uniform(-1, 1) for _ in range(int(0.6 * SR))]
lp(b, 900, 3)
for i in range(len(b)):
    t = i / SR; b[i] *= smooth(t, 0.12) * math.exp(-max(0, t - 0.12) / 0.12)
write(b, "3-air")

# 4 - bloom: low warm sine swell (like a soft OS "hum"), round in and out
b = []
for i in range(int(0.8 * SR)):
    t = i / SR
    v = math.sin(2 * math.pi * 196 * t) + 0.25 * math.sin(2 * math.pi * 392 * t) + 0.15 * math.sin(2 * math.pi * 294 * t)
    b.append(smooth(t, 0.06) * math.exp(-max(0, t - 0.06) / 0.18) * v)
lp(b, 1500); write(b, "4-bloom")

# 5 - lo-fi pluck: rounded synth pluck (triangle + closing filter), like a soft UI tap in a lo-fi track
b = []
for i in range(int(0.5 * SR)):
    t = i / SR; f = 330
    tri = 2 * abs(2 * ((f * t) % 1) - 1) - 1
    b.append(smooth(t, 0.006) * math.exp(-t / 0.12) * tri)
a = 0.0; y = 0.0
for i, x in enumerate(b):        # filter closes from ~2.5 kHz to ~500 Hz
    fc = 500 + 2000 * math.exp(-i / SR / 0.04); a = math.exp(-2 * math.pi * fc / SR)
    y = (1 - a) * x + a * y; b[i] = y
lp(b, 2500, 1); write(b, "5-lofi-pluck")

# 6 - soft "boop": two-partial rounded tone with pitch dipping slightly, like a gentle phone UI sound
b = []; ph = 0.0
for i in range(int(0.4 * SR)):
    t = i / SR; f = 520 - 60 * (1 - math.exp(-t / 0.05))
    ph += 2 * math.pi * f / SR
    b.append(smooth(t, 0.012) * math.exp(-t / 0.08) * (math.sin(ph) + 0.15 * math.sin(2 * ph)))
lp(b, 2000); write(b, "6-boop")
