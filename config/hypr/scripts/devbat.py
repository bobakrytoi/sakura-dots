#!/usr/bin/env python3
# sakura: battery of wireless peripherals, read straight from hidraw (read-only queries).
# Prints one JSON array: [{"id","name","kind","percent","charging"}] ("asleep": true and no percent when the
# device is there but asleep). Offline devices are omitted.
#  - Logitech G733 (046d:0ab5): HID++ 2.0, feature 0x1F20 (ADC voltage) -> percent via
#    HeadsetControl's G633/G733 calibration. State 0x03 = charging.
#  - Glorious Model O/O-/D/D- Wireless (258a): Sinowealth feature report, protocol from korkje/mxw.
#    Wired PID = cable in = charging.
import os, sys, json, time, fcntl, select

def hidraws():
    out = []
    base = "/sys/class/hidraw"
    for n in sorted(os.listdir(base)):
        try:
            ue = open(f"{base}/{n}/device/uevent").read()
            hid = [l.split("=", 1)[1] for l in ue.splitlines() if l.startswith("HID_ID=")][0]
            _, vid, pid = hid.split(":")
            try:
                iface = int(open(f"{base}/{n}/device/../bInterfaceNumber").read().strip(), 16)
            except Exception:
                iface = -1
            out.append((f"/dev/{n}", int(vid, 16), int(pid, 16), iface))
        except Exception:
            pass
    return out

# ---------- Logitech G733 ----------
G733_PIDS = {0x0AB5, 0x0AFE}
CAL_P = [100, 80, 60, 40, 20, 10, 5, 0]
CAL_V = [4100, 3950, 3850, 3750, 3650, 3500, 3300, 3150]

def volt_pct(mv):
    if mv >= CAL_V[0]: return 100
    for i in range(1, len(CAL_V)):
        if mv >= CAL_V[i]:
            v0, v1, p0, p1 = CAL_V[i - 1], CAL_V[i], CAL_P[i - 1], CAL_P[i]
            return round(p1 + (p0 - p1) * (mv - v1) / (v0 - v1))
    return 0

def hidpp(fd, idx, func, params=b""):
    msg = bytes([0x11, 0xFF, idx, (func << 4) | 0x1]) + params
    os.write(fd, msg + bytes(20 - len(msg)))
    end = time.time() + 0.6
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if not r: continue
        d = os.read(fd, 64)
        if len(d) >= 6 and d[0] == 0x11 and d[1] == 0xFF:
            if d[2] == idx: return d
            if d[2] == 0xFF and d[3] == idx: return None  # HID++ error: headset off / out of range
    return None

def g733(dev):
    try:
        fd = os.open(dev, os.O_RDWR | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        r = hidpp(fd, 0x00, 0, bytes([0x1F, 0x20]))
        if not r or r[4] == 0: return None
        a = hidpp(fd, r[4], 0)
        if not a: return None
        mv = (a[4] << 8) | a[5]
        if mv == 0: return None
        return {"id": "g733", "name": "G733", "kind": "headset",
                "percent": volt_pct(mv), "charging": a[6] == 0x03, "mv": mv}
    finally:
        os.close(fd)

# ---------- Glorious (Sinowealth) ----------
GLO = {0x2011: ("Model O", True), 0x2022: ("Model O", False),
       0x2013: ("Model O-", True), 0x2024: ("Model O-", False),
       0x2012: ("Model D", True), 0x2023: ("Model D", False),
       0x2014: ("Model D-", True), 0x2025: ("Model D-", False)}

def ioc(nr, size): return (3 << 30) | (size << 16) | (ord('H') << 8) | nr

def glorious(dev, pid):
    name, wired = GLO[pid]
    try:
        fd = os.open(dev, os.O_RDWR)
    except OSError:
        return None
    try:
        b = bytearray(65); b[3] = 2; b[4] = 2; b[6] = 0x83
        fcntl.ioctl(fd, ioc(6, 65), bytes(b))
        time.sleep(0.05)
        r = bytearray(65)
        fcntl.ioctl(fd, ioc(7, 65), r)
    except OSError:
        return None
    finally:
        os.close(fd)
    if r[6] != 0x83 or r[1] != 0xA1:   # A0/A2/A3/A4 = asleep / waking / unknown: there, but no reading
        return {"id": "glorious", "name": name, "kind": "mouse", "asleep": True, "charging": wired}
    return {"id": "glorious", "name": name, "kind": "mouse",
            "percent": max(1, min(100, r[8])), "charging": wired}

def main():
    out, seen = [], set()
    for dev, vid, pid, iface in hidraws():
        try:
            if vid == 0x046D and pid in G733_PIDS and "g733" not in seen:
                d = g733(dev)
                if d: out.append(d); seen.add("g733")
            elif vid == 0x258A and pid in GLO and iface == 2 and "glorious" not in seen:
                d = glorious(dev, pid)
                if d: out.append(d); seen.add("glorious")
        except Exception:
            pass
    print(json.dumps(out))

main()
