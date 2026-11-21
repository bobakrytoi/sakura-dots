#!/usr/bin/env python3
"""sakura task manager - data collector.
Prints one JSON line per second: system stats + processes grouped into
"apps" (anything that owns a Hyprland window, with all its children) and
"background" (everything else, grouped by process name)."""
import json, os, pwd, subprocess, sys, threading, time

HZ = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
NCPU = os.cpu_count() or 1
ME = os.getuid()
INTERVAL = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0

users = {}
def uname(uid):
    if uid not in users:
        try: users[uid] = pwd.getpwuid(uid).pw_name
        except KeyError: users[uid] = str(uid)
    return users[uid]

def read(p):
    try:
        with open(p, "rb") as f: return f.read().decode(errors="replace")
    except OSError: return None

# ── static info ───────────────────────────────────────────
cpu_name = ""
for line in (read("/proc/cpuinfo") or "").splitlines():
    if line.startswith("model name"): cpu_name = line.split(":", 1)[1].strip(); break

def find_cpu_temp():
    base = "/sys/class/hwmon"
    try: mons = os.listdir(base)
    except OSError: return None
    for m in mons:
        name = (read(f"{base}/{m}/name") or "").strip()
        if name in ("k10temp", "coretemp", "zenpower"):
            # prefer Tctl / Package label, else temp1
            best = f"{base}/{m}/temp1_input"
            for i in range(1, 12):
                lab = (read(f"{base}/{m}/temp{i}_label") or "").strip()
                if lab in ("Tctl", "Tdie", "Package id 0"): best = f"{base}/{m}/temp{i}_input"; break
            return best
    return None
TEMP_PATH = find_cpu_temp()

# ── GPU (nvidia-smi streams in the background) ────────────
gpu = {}
def gpu_thread():
    q = "utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,name,fan.speed,clocks.gr"
    while True:
        try:
            p = subprocess.Popen(["nvidia-smi", f"--query-gpu={q}", "--format=csv,noheader,nounits", "-lms", "1000"],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        except FileNotFoundError:
            return
        for line in p.stdout:
            f = [x.strip() for x in line.split(",")]
            if len(f) < 8: continue
            def num(x):
                try: return float(x)
                except ValueError: return 0.0
            gpu.update(util=num(f[0]), memUsed=num(f[1]) * 1048576, memTotal=num(f[2]) * 1048576,
                       temp=num(f[3]), power=num(f[4]), name=f[5].replace("NVIDIA ", ""), fan=num(f[6]), clock=num(f[7]))
        time.sleep(2)
threading.Thread(target=gpu_thread, daemon=True).start()

# ── windows from Hyprland ─────────────────────────────────
def hypr_clients():
    try:
        out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=1).stdout
        return json.loads(out or "[]")
    except Exception:
        return []

# ── sampling state ────────────────────────────────────────
prev_cpu = None          # (total, idle, per-core list)
prev_proc = {}           # pid -> (ticks, read, write)
prev_net = prev_disk = None
prev_t = None

def disks_total():
    r = w = 0
    for line in (read("/proc/diskstats") or "").splitlines():
        f = line.split()
        if len(f) < 10: continue
        name = f[2]
        if name.startswith(("loop", "ram", "zram", "dm-", "sr")): continue
        # whole disks only: nvme0n1, sda, vda, mmcblk0
        if name.startswith("nvme") and "p" in name[4:]: continue
        if name.startswith("mmcblk") and "p" in name[6:]: continue
        if name[:2] in ("sd", "vd", "hd") and name[-1].isdigit(): continue
        r += int(f[5]) * 512; w += int(f[9]) * 512
    return r, w

def net_total():
    rx = tx = 0
    for line in (read("/proc/net/dev") or "").splitlines()[2:]:
        name, data = line.split(":", 1); name = name.strip()
        if name == "lo" or name.startswith(("docker", "veth", "virbr", "br-")): continue
        f = data.split(); rx += int(f[0]); tx += int(f[8])
    return rx, tx

def sample():
    global prev_cpu, prev_proc, prev_net, prev_disk, prev_t
    now = time.monotonic()
    dt = (now - prev_t) if prev_t else None

    # cpu
    lines = (read("/proc/stat") or "").splitlines()
    cores_raw = []
    total_line = None
    ctxt = 0
    for l in lines:
        if l.startswith("cpu "): total_line = l
        elif l.startswith("cpu"): cores_raw.append(l)
        elif l.startswith("ctxt"): ctxt = int(l.split()[1])
    def ti(l):
        v = [int(x) for x in l.split()[1:]]
        return sum(v[:8]), v[3] + v[4]
    tot, idl = ti(total_line)
    cores = [ti(l) for l in cores_raw]
    cpu = 0.0; core_pct = [0.0] * len(cores)
    if prev_cpu:
        dT, dI = tot - prev_cpu[0], idl - prev_cpu[1]
        cpu = max(0.0, min(100.0, 100 * (1 - dI / dT))) if dT > 0 else 0.0
        for i, (t, d) in enumerate(cores):
            if i < len(prev_cpu[2]):
                pt, pd = prev_cpu[2][i]
                core_pct[i] = max(0.0, min(100.0, 100 * (1 - (d - pd) / (t - pt)))) if t > pt else 0.0
    cpu_delta_ticks = (tot - prev_cpu[0]) if prev_cpu else 0
    prev_cpu = (tot, idl, cores)

    freq = 0.0
    try:
        fs = [int(read(f"/sys/devices/system/cpu/cpu{i}/cpufreq/scaling_cur_freq") or 0) for i in range(NCPU)]
        freq = max(fs) / 1e6 if fs else 0.0
    except ValueError: pass
    temp = None
    if TEMP_PATH:
        t = read(TEMP_PATH)
        if t: temp = int(t) / 1000

    # memory
    mem = {}
    for l in (read("/proc/meminfo") or "").splitlines():
        k, v = l.split(":"); mem[k] = int(v.split()[0]) * 1024
    memTotal = mem.get("MemTotal", 1); memAvail = mem.get("MemAvailable", 0)

    # net / disk
    rx, tx = net_total(); dr, dw = disks_total()
    netd = {"rx": 0, "tx": 0}; diskd = {"r": 0, "w": 0}
    if dt and prev_net:
        netd = {"rx": max(0, rx - prev_net[0]) / dt, "tx": max(0, tx - prev_net[1]) / dt}
        diskd = {"r": max(0, dr - prev_disk[0]) / dt, "w": max(0, dw - prev_disk[1]) / dt}
    prev_net, prev_disk = (rx, tx), (dr, dw)

    # processes
    procs = {}
    nthreads = 0
    new_prev = {}
    for d in os.listdir("/proc"):
        if not d.isdigit(): continue
        pid = int(d)
        st = read(f"/proc/{pid}/stat")
        if not st: continue
        try:
            rp = st.rindex(")")
            comm = st[st.index("(") + 1:rp]
            f = st[rp + 2:].split()
            state, ppid = f[0], int(f[1])
            ticks = int(f[11]) + int(f[12])
            threads = int(f[17])
            flags = int(f[6])
        except (ValueError, IndexError):
            continue
        if flags & 0x00200000 or ppid == 2 or pid == 2:   # kernel thread
            continue
        nthreads += threads
        status = read(f"/proc/{pid}/status") or ""
        rss = 0; uid = 0
        for l in status.splitlines():
            if l.startswith("RssAnon:"): rss += int(l.split()[1]) * 1024
            elif l.startswith("RssShmem:"): pass
            elif l.startswith("Uid:"): uid = int(l.split()[1])
        rb = wb = 0
        if uid == ME:
            io = read(f"/proc/{pid}/io")
            if io:
                for l in io.splitlines():
                    if l.startswith("read_bytes:"): rb = int(l.split()[1])
                    elif l.startswith("write_bytes:"): wb = int(l.split()[1])
        p_cpu = 0.0; p_disk = 0.0
        if pid in prev_proc and cpu_delta_ticks > 0:
            pt, pr, pw = prev_proc[pid]
            # share of the whole machine, like Windows does (0-100 for all cores)
            p_cpu = max(0.0, (ticks - pt)) / cpu_delta_ticks * 100
            if dt: p_disk = (max(0, rb - pr) + max(0, wb - pw)) / dt
        new_prev[pid] = (ticks, rb, wb)
        raw = read(f"/proc/{pid}/cmdline") or ""
        cmd = raw.replace("\0", " ").strip()
        if len(comm) >= 15 and raw:   # kernel cuts names at 15 chars; take the full one from argv[0]
            a0 = os.path.basename(raw.split("\0", 1)[0].split(" ", 1)[0])
            if a0.startswith(comm): comm = a0
        procs[pid] = {"pid": pid, "ppid": ppid, "name": comm, "cpu": round(p_cpu, 2), "mem": rss,
                      "disk": round(p_disk), "user": uname(uid), "own": uid == ME, "state": state,
                      "threads": threads, "cmd": cmd[:300]}
    prev_proc = new_prev
    prev_t = now

    # children map
    kids = {}
    for p in procs.values(): kids.setdefault(p["ppid"], []).append(p["pid"])
    def subtree(root):
        out, stack = [], [root]
        while stack:
            x = stack.pop()
            if x in procs: out.append(x)
            stack.extend(kids.get(x, []))
        return out

    # apps = hyprland windows grouped by class
    apps = {}
    claimed = set()
    for c in hypr_clients():
        pid = c.get("pid", -1)
        cls = c.get("class") or c.get("initialClass") or ""
        if pid not in procs or not cls: continue
        a = apps.setdefault(cls, {"key": "app:" + cls, "cls": cls, "titles": [], "roots": set()})
        if c.get("title"): a["titles"].append(c["title"])
        a["roots"].add(pid)
    # a root that lives inside another app's tree belongs to that app only
    app_list = []
    for cls, a in apps.items():
        pids = []
        for r in sorted(a["roots"]):
            for x in subtree(r):
                if x not in claimed: claimed.add(x); pids.append(x)
        if not pids: continue
        ch = sorted((procs[x] for x in pids), key=lambda p: -p["cpu"])
        app_list.append({"key": a["key"], "kind": "app", "cls": cls, "name": cls,
                         "title": a["titles"][0] if a["titles"] else "", "windows": len(a["titles"]),
                         "cpu": round(sum(p["cpu"] for p in ch), 2), "mem": sum(p["mem"] for p in ch),
                         "disk": sum(p["disk"] for p in ch), "count": len(ch), "own": True,
                         "pids": [p["pid"] for p in ch], "children": ch})

    # background = the rest, grouped by name
    bg = {}
    for pid, p in procs.items():
        if pid in claimed: continue
        g = bg.setdefault(p["name"], [])
        g.append(p)
    bg_list = []
    for name, ch in bg.items():
        ch.sort(key=lambda p: -p["cpu"])
        bg_list.append({"key": "bg:" + name, "kind": "bg", "cls": "", "name": name, "title": ch[0]["cmd"] if len(ch) == 1 else "",
                        "cpu": round(sum(p["cpu"] for p in ch), 2), "mem": sum(p["mem"] for p in ch),
                        "disk": sum(p["disk"] for p in ch), "count": len(ch), "own": all(p["own"] for p in ch),
                        "user": ch[0]["user"], "pids": [p["pid"] for p in ch], "children": ch})

    up = float((read("/proc/uptime") or "0").split()[0])
    return {
        "sys": {
            "cpu": round(cpu, 1), "cores": [round(x) for x in core_pct], "cpuName": cpu_name,
            "freq": round(freq, 2), "temp": temp, "ncpu": NCPU,
            "memTotal": memTotal, "memUsed": memTotal - memAvail, "memCached": mem.get("Cached", 0) + mem.get("Buffers", 0),
            "swapTotal": mem.get("SwapTotal", 0), "swapUsed": mem.get("SwapTotal", 0) - mem.get("SwapFree", 0),
            "net": netd, "disk": diskd, "gpu": dict(gpu),
            "procs": len(procs), "threads": nthreads, "uptime": up,
        },
        "apps": app_list,
        "bg": bg_list,
    }

sample()
time.sleep(0.4)
while True:
    try:
        sys.stdout.write(json.dumps(sample(), separators=(",", ":")) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        break
    except Exception as e:
        sys.stderr.write(f"collect: {e}\n")
    time.sleep(INTERVAL)
