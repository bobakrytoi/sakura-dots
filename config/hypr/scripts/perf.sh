#!/usr/bin/env python3
"""system stats for the dashboard (one JSON line). keeps a tiny state file to compute CPU / network rates."""
import json, os, re, shutil, subprocess, time
ST = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "sakura-perf.json")
now = time.time()
try: prev = json.load(open(ST))
except Exception: prev = {}

with open("/proc/stat") as f: c = [int(x) for x in f.readline().split()[1:]]
idle, total = c[3] + c[4], sum(c)
cpu = 0.0
if "idle" in prev:
    dt, di = total - prev["total"], idle - prev["idle"]
    cpu = max(0.0, min(100.0, 100.0 * (1 - di / dt))) if dt > 0 else 0.0

rx = tx = 0
for line in open("/proc/net/dev").readlines()[2:]:
    name, data = line.split(":", 1)
    name = name.strip()
    if name == "lo" or name.startswith(("wg", "tun", "docker", "veth", "virbr")): continue
    f = data.split(); rx += int(f[0]); tx += int(f[8])
down = up = 0.0
if "rx" in prev and now > prev["t"]:
    down = max(0, rx - prev["rx"]) / (now - prev["t"]); up = max(0, tx - prev["tx"]) / (now - prev["t"])
json.dump({"idle": idle, "total": total, "rx": rx, "tx": tx, "t": now}, open(ST, "w"))

mem = {}
for line in open("/proc/meminfo"):
    k, v = line.split(":"); mem[k] = int(v.split()[0]) * 1024
memUsed = mem["MemTotal"] - mem["MemAvailable"]

cpuName = ""
for line in open("/proc/cpuinfo"):
    if line.startswith("model name"): cpuName = line.split(":", 1)[1].strip(); break
temp = None
try:
    s = json.loads(subprocess.run(["sensors", "-j"], capture_output=True, text=True, timeout=2).stdout or "{}")
    for chip, v in s.items():
        if chip.startswith(("coretemp", "k10temp", "zenpower")):
            for k, sub in v.items():
                if isinstance(sub, dict) and k.startswith(("Package", "Tctl", "Tdie")):
                    temp = next((x for n, x in sub.items() if n.endswith("_input")), None)
            if temp is None:
                for k, sub in v.items():
                    if isinstance(sub, dict):
                        temp = next((x for n, x in sub.items() if n.endswith("_input")), None)
                        if temp: break
except Exception: pass

gpu = None
try:
    o = subprocess.run(["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw",
                        "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=2).stdout.strip()
    if o:
        n, u, t, mu, mt, p = [x.strip() for x in o.split("\n")[0].split(",")]
        gpu = {"name": n, "usage": float(u), "temp": float(t), "memUsed": float(mu) * 1048576, "memTotal": float(mt) * 1048576,
               "power": float(p) if re.match(r"^[\d.]+$", p) else None}
except Exception: pass

disks = []
for mp, label in (("/", "C: System"), ("/mnt/HDD-2TB", "D: HDD 2TB"), ("/mnt/SSD-1TB", "E: SSD 1TB"), ("/mnt/LocalDisk", "Local Disk")):
    if os.path.ismount(mp) or mp == "/":
        try:
            u = shutil.disk_usage(mp); disks.append({"label": label, "used": u.used, "total": u.total})
        except OSError: pass

up_s = float(open("/proc/uptime").read().split()[0])
print(json.dumps({"cpu": round(cpu, 1), "cpuName": cpuName, "cpuTemp": temp, "memUsed": memUsed, "memTotal": mem["MemTotal"],
                  "gpu": gpu, "disks": disks, "down": down, "up": up, "rxTotal": rx, "txTotal": tx, "uptime": up_s}))
