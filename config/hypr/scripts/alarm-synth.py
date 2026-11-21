#!/usr/bin/env python3
# soft "creamy" timer / alarm / notification sounds for sakura - pure python (no numpy), 48 kHz mono 16-bit.
# v2 (2026-11-11): v1 was "too ringy" (звонкие) → everything an octave lower, felt-mallet instruments with
# almost no overtones, short sustain, steep low-pass ~1.6-2 kHz, a touch of room. Reference: lock-screen key
# clicks (spectral centroid ~300 Hz). v1 kept as alarm-synth.py.bak-v1.
# usage: alarm-synth.py OUT.wav   (the file name picks the sound: alarm-a/b/c, pomo, notify-a/b/c)
# then: ffmpeg lowpass + gain to the target LUFS (see HANDOFF.md 4.17)
import math, wave, struct, sys, os

SR = 48000
out = sys.argv[1]

def buf(sec): return [0.0] * int(SR * sec)

def env(t, atk, dec):
    a = 0.5 - 0.5 * math.cos(math.pi * min(1.0, t / atk)) if atk > 0 else 1.0
    return a * math.exp(-t / dec)

def note(b, start, f, partials, atk, gain=1.0):
    """partials: [(ratio, amp, decay_s)] - highs above 2.4 kHz are dropped outright"""
    s0 = int(start * SR)
    ps = [(2 * math.pi * f * r / SR, amp, dec) for r, amp, dec in partials if f * r < 2400]
    for i in range(len(b) - s0):
        t = i / SR
        v = 0.0
        for w, amp, dec in ps:
            v += amp * env(t, atk, dec) * math.sin(w * i)
        b[s0 + i] += gain * v

def lp(b, fc, passes=2):
    a = math.exp(-2 * math.pi * fc / SR)
    for _ in range(passes):
        y = 0.0
        for i, x in enumerate(b):
            y = (1 - a) * x + a * y; b[i] = y

def room(b, mix=0.10):
    # small, dark room: 4 heavily damped combs, no allpass shimmer
    wet = [0.0] * len(b)
    for d, g in [(1117, .62), (1188, .60), (1277, .58), (1356, .56)]:
        line = [0.0] * d; idx = 0; lpv = 0.0
        for i, x in enumerate(b):
            y = line[idx]; lpv = 0.35 * y + 0.65 * lpv
            line[idx] = x + g * lpv; idx = (idx + 1) % d
            wet[i] += y * 0.25
    for i in range(len(b)): b[i] = b[i] * (1 - mix) + wet[i] * mix

def fade_tail(b, sec=0.2):
    n = min(len(b), int(sec * SR))
    for i in range(n):
        b[len(b) - n + i] *= 0.5 + 0.5 * math.cos(math.pi * i / n)

def write(b, path):
    pk = max(abs(x) for x in b) or 1.0
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(32000 * 0.5 * x / pk)) for x in b))

hz = lambda m: 440.0 * 2 ** ((m - 69) / 12)

# felt-mallet marimba: nearly pure fundamental, a whisper of the 4th partial that dies in 40 ms
FELT = [(1.0, 1.0, 0.38), (2.0, 0.06, 0.12), (3.93, 0.03, 0.04)]
# muted wooden box (music-box body, not the tine): round, short
BOX = [(1.0, 1.0, 0.55), (2.0, 0.10, 0.20), (3.0, 0.03, 0.08)]
# soft pad: sine + a little octave, slow swell
PAD = [(1.0, 1.0, 0.9), (2.0, 0.12, 0.5)]
# muted kalimba (thumb on the tine)
TINE = [(1.0, 1.0, 0.30), (2.0, 0.05, 0.10)]

kind = os.path.basename(out)
if "alarm-a" in kind:      # (a) felt marimba, rising D3 F#3 A3 D4
    b = buf(2.0)
    for i, m in enumerate([50, 54, 57, 62]):
        note(b, 0.02 + i * 0.17, hz(m), FELT, 0.022, gain=0.85 + 0.05 * i)
    lp(b, 1800); room(b, 0.10)
elif "alarm-b" in kind:    # (b) wooden box, A3 E4 C#4 - slow and round
    b = buf(2.3)
    for t, m, g in [(0.02, 57, 0.8), (0.32, 64, 0.6), (0.62, 61, 0.7)]:
        note(b, t, hz(m), BOX, 0.025, gain=g)
    lp(b, 1700); room(b, 0.12)
elif "alarm-c" in kind:    # (c) warm pad Fmaj9 low, with one felt note on top
    b = buf(2.3)
    for m in [41, 45, 48, 52, 55]:
        for det in (-0.10, 0.10):
            note(b, 0.0, hz(m + det), PAD, 0.25, gain=0.15)
    note(b, 0.28, hz(60), FELT, 0.025, gain=0.45)
    lp(b, 1500); room(b, 0.12)
elif "pomo" in kind:       # pomodoro cue: two muted tines A3 → E4
    b = buf(0.8)
    note(b, 0.01, hz(57), TINE, 0.020, gain=0.8)
    note(b, 0.14, hz(64), TINE, 0.020, gain=0.65)
    lp(b, 1800); room(b, 0.08)
elif "notify-a" in kind:   # notification (a): two felt notes A3 → D4
    b = buf(0.5)
    note(b, 0.01, hz(57), FELT, 0.020, gain=0.8)
    note(b, 0.10, hz(62), FELT, 0.020, gain=0.7)
    lp(b, 1800); room(b, 0.08)
elif "notify-b" in kind:   # (b): one round wooden "pok", E4
    b = buf(0.45)
    note(b, 0.01, hz(64), [(1.0, 1.0, 0.16), (2.0, 0.05, 0.06)], 0.018, gain=0.8)
    lp(b, 1600); room(b, 0.08)
elif "notify-c" in kind:   # (c): muted tine C4 over a faint warm F2/A2 hum
    b = buf(0.5)
    for m in [41, 45]:
        note(b, 0.0, hz(m), [(1.0, 1.0, 0.25)], 0.04, gain=0.20)
    note(b, 0.02, hz(60), TINE, 0.020, gain=0.7)
    lp(b, 1500); room(b, 0.08)
else:
    sys.exit("unknown " + kind)
fade_tail(b)
write(b, out)
