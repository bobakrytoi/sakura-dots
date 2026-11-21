#!/usr/bin/env python3
"""Sakura Mic Studio backend.

Processing on Linux always needs a filter node, so we build one - but it is made
invisible in daily use: it is named after your real mic and is set as the system
input automatically, so Discord/games/browsers just use it without picking anything.

  mic.py apply            rebuild the effect chain and start it
  mic.py sync             push every value from mic.json into the running chain (instant)
  mic.py set K V [K V]    change controls (live when possible)
  mic.py live on|off|toggle       hear yourself in real time
  mic.py default on|off   use the processed mic as the system input
  mic.py status           JSON state
  mic.py levels           stream mic levels (one JSON line per ~50 ms)
  mic.py stop
"""
import json, math, os, re, shutil, signal, struct, subprocess, sys, time

HOME = os.path.expanduser("~")
CFG = HOME + "/.config/sakura/mic.json"
CONF = HOME + "/.config/sakura/mic-chain.conf"
SRC_NAME = "sakura_mic"          # processed microphone apps receive
CAP_NAME = "sakura_mic_capture"  # node that owns the live controls

DEFAULTS = {
    "enabled": True, "device": "", "deviceDesc": "", "autoDefault": True,
    "live": False,
    "denoise": 55.0,                       # rnnoise VAD %, 0 = off
    "gateOn": True, "gate": -42.0,
    "pitch": 0.0,                          # semitones
    "hpf": 90.0,
    "bass": 0.0, "mud": -1.0, "mid": 0.0, "presence": 3.0, "air": 2.0,
    "compOn": True, "compThresh": -20.0, "compRatio": 3.0,
    "gain": 0.0,                           # dB
}

PRESETS = {
    "natural": dict(pitch=0,  hpf=80,  bass=0,  mud=0,  mid=0, presence=1, air=1,
                    compOn=True,  compThresh=-20, compRatio=2.5, denoise=40, gateOn=True,  gate=-45, gain=0),
    "clear":   dict(pitch=2,  hpf=110, bass=-3, mud=-4, mid=0, presence=5, air=4,
                    compOn=True,  compThresh=-20, compRatio=3.5, denoise=60, gateOn=True,  gate=-42, gain=2),
    "bright":  dict(pitch=4,  hpf=130, bass=-5, mud=-5, mid=1, presence=6, air=6,
                    compOn=True,  compThresh=-22, compRatio=4.0, denoise=65, gateOn=True,  gate=-40, gain=3),
    "deep":    dict(pitch=-3, hpf=60,  bass=5,  mud=0,  mid=1, presence=2, air=0,
                    compOn=True,  compThresh=-18, compRatio=3.0, denoise=45, gateOn=True,  gate=-45, gain=1),
    "radio":   dict(pitch=0,  hpf=100, bass=3,  mud=-4, mid=2, presence=5, air=3,
                    compOn=True,  compThresh=-26, compRatio=6.0, denoise=60, gateOn=True,  gate=-40, gain=4),
    "flat":    dict(pitch=0,  hpf=20,  bass=0,  mud=0,  mid=0, presence=0, air=0,
                    compOn=False, compThresh=-20, compRatio=2.0, denoise=0,  gateOn=False, gate=-60, gain=0),
}


def load():
    cfg = dict(DEFAULTS)
    try:
        cfg.update(json.load(open(CFG)))
    except Exception:
        pass
    return cfg


def save(cfg):
    os.makedirs(os.path.dirname(CFG), exist_ok=True)
    json.dump(cfg, open(CFG, "w"), indent=2)


# ── optional plugins ────────────────────────────────────────────────────
def find_ladspa(*names):
    for d in ("/usr/lib/ladspa", "/usr/lib64/ladspa", HOME + "/.ladspa"):
        for n in names:
            p = os.path.join(d, n)
            if os.path.exists(p):
                return p
    return None



# ── real control-port names of a LADSPA plugin (names differ between builds) ──
_PORTS = {}


def ladspa_controls(path, label):
    """list of control-input port names for <label> inside <path>"""
    key = (path, label)
    if key in _PORTS:
        return _PORTS[key]
    names = []
    try:
        out = subprocess.run(["analyseplugin", path], capture_output=True, text=True, timeout=15).stdout
        blocks = re.split(r"(?=Plugin Name:)", out)
        for b in blocks:
            m = re.search(r'Plugin Label:\s*"?([^"\n]+)"?', b)
            if not m or m.group(1).strip() != label:
                continue
            names = re.findall(r'"([^"]+)"\s+input,\s*control', b)
            break
    except Exception:
        names = []
    _PORTS[key] = names
    return names


def port(path, label, keyword, fallback):
    """the plugin's own name for the control we mean, matched loosely"""
    names = ladspa_controls(path, label)
    # prefer a name that STARTS with the keyword: "hold" must not match "Threshold"
    for n in names:
        if n.lower().startswith(keyword.lower()):
            return n
    for n in names:
        if keyword.lower() in n.lower():
            return n
    return fallback


PLUG = {
    "ns":    find_ladspa("librnnoise_ladspa.so"),
    "pitch": find_ladspa("tap_pitch.so", "pitch_scale_1194.so", "pitch_scale_1193.so"),
    "comp":  find_ladspa("sc4m_1916.so"),
    "gate":  find_ladspa("gate_1410.so"),
}


def first_label(path):
    """the label a .so really uses - guessing it wrong makes the whole chain fail to load"""
    try:
        out = subprocess.run(["analyseplugin", path], capture_output=True, text=True, timeout=15).stdout
        m = re.search(r'Plugin Label:\s*"?([^"\n]+)"?', out)
        if m:
            return m.group(1).strip()
    except Exception:
        pass
    return ""


def pitch_label():
    return first_label(PLUG["pitch"] or "") or "pitchScaleHQ"


def pitch_ctl():
    return "Semitone shift" if os.path.basename(PLUG["pitch"] or "") == "tap_pitch.so" else "Pitch co-efficient"


def pitch_value(cfg):
    semi = float(cfg["pitch"])
    if os.path.basename(PLUG["pitch"] or "") == "tap_pitch.so":
        return semi
    return round(2 ** (semi / 12.0), 5)


# ── build the graph ─────────────────────────────────────────────────────
def build_conf(cfg):
    nodes, links, order, ports = [], [], [], {}

    def add(nid, text, pin, pout):
        if order:
            prev = order[-1]
            links.append('{ output = "%s:%s" input = "%s:%s" }' % (prev, ports[prev][1], nid, pin))
        nodes.append(text)
        ports[nid] = (pin, pout)
        order.append(nid)

    def builtin(nid, label, ctl):
        add(nid, "{ type = builtin name = %s label = %s control = { %s } }" % (nid, label, ctl), "In", "Out")

    def lad(nid, path, label, ctl, pin="Input", pout="Output"):
        add(nid, '{ type = ladspa name = %s plugin = "%s" label = %s control = { %s } }' % (nid, path, label, ctl),
            pin, pout)

    if PLUG["ns"]:
        lad("ns", PLUG["ns"], "noise_suppressor_mono",
            '"%s" = %.1f' % (port(PLUG["ns"], "noise_suppressor_mono", "vad", "VAD Threshold (%)"), cfg["denoise"]))
    builtin("hp", "bq_highpass", "Freq = %.1f Q = 0.7" % cfg["hpf"])
    if PLUG["gate"]:
        g = lambda kw, fb: port(PLUG["gate"], "gate", kw, fb)
        lad("gate", PLUG["gate"], "gate",
            '"%s" = %.1f "%s" = 2.0 "%s" = 220.0 "%s" = 260.0 "%s" = %.1f "%s" = 180.0 "%s" = 9000.0 "%s" = %.1f'
            % (g("threshold", "Threshold (dB)"), cfg["gate"] if cfg["gateOn"] else -70.0,
               g("attack", "Attack (ms)"), g("hold", "Hold (ms)"), g("decay", "Decay (ms)"),
               g("range", "Range (dB)"), -60.0 if cfg["gateOn"] else 0.0,
               g("lf key", "LF key filter (Hz)"), g("hf key", "HF key filter (Hz)"),
               g("output select", "Output select (-1 = key listen, 0 = gate, 1 = bypass)"),
               0.0 if cfg["gateOn"] else 1.0))
    if PLUG["pitch"] and abs(float(cfg["pitch"])) >= 0.25:
        lad("pitch", PLUG["pitch"], pitch_label(),
            '"%s" = %s' % (port(PLUG["pitch"], pitch_label(), "pitch", pitch_ctl()), pitch_value(cfg)))
    builtin("bass", "bq_lowshelf",  "Freq = 150.0  Q = 0.7 Gain = %.1f" % cfg["bass"])
    builtin("mud",  "bq_peaking",   "Freq = 400.0  Q = 1.2 Gain = %.1f" % cfg["mud"])
    builtin("mid",  "bq_peaking",   "Freq = 1200.0 Q = 1.0 Gain = %.1f" % cfg["mid"])
    builtin("pres", "bq_peaking",   "Freq = 3500.0 Q = 1.0 Gain = %.1f" % cfg["presence"])
    builtin("air",  "bq_highshelf", "Freq = 9000.0 Q = 0.7 Gain = %.1f" % cfg["air"])
    if PLUG["comp"]:
        c = lambda kw, fb: port(PLUG["comp"], "sc4m", kw, fb)
        lad("comp", PLUG["comp"], "sc4m",
            '"%s" = %.1f "%s" = %.2f "%s" = 10.0 "%s" = 180.0 "%s" = 3.0 "%s" = 0.0 "%s" = 0.0'
            % (c("threshold level", "Threshold level (dB)"), cfg["compThresh"] if cfg["compOn"] else 0.0,
               c("ratio", "Ratio (1:n)"), cfg["compRatio"] if cfg["compOn"] else 1.0,
               c("attack", "Attack time (ms)"), c("release", "Release time (ms)"),
               c("knee", "Knee radius (dB)"), c("makeup", "Makeup gain (dB)"), c("rms", "RMS/peak")))
    builtin("out", "linear", "Mult = %.4f Add = 0.0" % (10 ** (cfg["gain"] / 20.0)))

    first, last = order[0], order[-1]
    target = 'target.object = "%s"' % cfg["device"] if cfg.get("device") else ""
    desc = "Sakura Mic"      # short and unique, so apps do not show a confusing duplicate
    return (
        "# generated by Mic Studio - change things there, not here\n"
        "context.properties = { log.level = 0 }\n"
        "context.spa-libs = {\n"
        "    audio.convert.* = audioconvert/libspa-audioconvert\n"
        "    support.*       = support/libspa-support\n"
        "}\n"
        "context.modules = [\n"
        "    { name = libpipewire-module-rt args = {} flags = [ ifexists nofail ] }\n"
        "    { name = libpipewire-module-protocol-native }\n"
        "    { name = libpipewire-module-client-node }\n"
        "    { name = libpipewire-module-adapter }\n"
        "    { name = libpipewire-module-filter-chain\n"
        "      args = {\n"
        '        node.description = "%s"\n'
        '        media.name       = "%s"\n'
        "        filter.graph = {\n"
        "            nodes = [\n                %s\n            ]\n"
        "            links = [\n                %s\n            ]\n"
        '            inputs  = [ "%s:%s" ]\n'
        '            outputs = [ "%s:%s" ]\n'
        "        }\n"
        "        capture.props = {\n"
        '            node.name    = "%s"\n'
        "            node.passive = true\n"
        "            audio.position = [ MONO ]\n"
        "            %s\n"
        "        }\n"
        "        playback.props = {\n"
        '            node.name        = "%s"\n'
        '            node.description = "%s"\n'
        "            media.class      = Audio/Source\n"
        "            audio.position   = [ MONO ]\n"
        "            priority.session = 2500\n"
        "        }\n"
        "      }\n"
        "    }\n"
        "]\n"
        % (desc, desc,
           "\n                ".join(nodes), "\n                ".join(links),
           first, ports[first][0], last, ports[last][1],
           CAP_NAME, target, SRC_NAME, desc)
    )


# ── live controls ───────────────────────────────────────────────────────
def controls(cfg):
    c = {
        "hp:Freq": cfg["hpf"], "bass:Gain": cfg["bass"], "mud:Gain": cfg["mud"],
        "mid:Gain": cfg["mid"], "pres:Gain": cfg["presence"], "air:Gain": cfg["air"],
        "out:Mult": 10 ** (cfg["gain"] / 20.0),
    }
    if PLUG["ns"]:
        c["ns:" + port(PLUG["ns"], "noise_suppressor_mono", "vad", "VAD Threshold (%)")] = cfg["denoise"]
    if PLUG["pitch"] and abs(float(cfg["pitch"])) >= 0.25:
        c["pitch:" + port(PLUG["pitch"], pitch_label(), "pitch", pitch_ctl())] = pitch_value(cfg)
    if PLUG["gate"]:
        g = lambda kw, fb: "gate:" + port(PLUG["gate"], "gate", kw, fb)
        c[g("threshold", "Threshold (dB)")] = cfg["gate"] if cfg["gateOn"] else -90.0
        c[g("range", "Range (dB)")] = -60.0 if cfg["gateOn"] else 0.0
        c[g("output select", "Output select (-1 = key listen, 0 = gate, 1 = bypass)")] = 0.0 if cfg["gateOn"] else 1.0
    if PLUG["comp"]:
        cc = lambda kw, fb: "comp:" + port(PLUG["comp"], "sc4m", kw, fb)
        c[cc("threshold level", "Threshold level (dB)")] = cfg["compThresh"] if cfg["compOn"] else 0.0
        c[cc("ratio", "Ratio (1:n)")] = cfg["compRatio"] if cfg["compOn"] else 1.0
    return c


def run(*a):
    return subprocess.run(a, capture_output=True, text=True, timeout=12)


def dump():
    try:
        return json.loads(run("pw-dump").stdout or "[]")
    except Exception:
        return []


def props(o):
    return ((o.get("info") or {}).get("props") or {})


def node_id(name, objs=None):
    if not name:
        return None
    for o in (objs if objs is not None else dump()):
        if props(o).get("node.name") == name:
            return o["id"]
    return None


def push(pairs):
    nid = node_id(CAP_NAME)
    if not nid:
        return False
    body = " ".join('"%s" %f' % (k, float(v)) for k, v in pairs.items())
    run("pw-cli", "s", str(nid), "Props", "{ params = [ %s ] }" % body)
    return True


def pids(pattern):
    r = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True)
    return [int(x) for x in r.stdout.split()]


def kill(pattern):
    for p in pids(pattern):
        try:
            os.kill(p, signal.SIGTERM)
        except OSError:
            pass


def default_source_name(objs=None):
    for o in (objs if objs is not None else dump()):
        if (o.get("props") or {}).get("metadata.name") == "default":
            for e in o.get("metadata", []):
                if e.get("key") == "default.audio.source":
                    return (e.get("value") or {}).get("name", "")
    return ""


def set_default(mode):
    cfg = load()
    objs = dump()
    if mode != "off":
        nid = node_id(SRC_NAME, objs)
        if nid:
            run("wpctl", "set-default", str(nid))
    else:
        nid = node_id(cfg.get("device"), objs)
        if not nid:
            for o in objs:
                p = props(o)
                if p.get("media.class") == "Audio/Source" and p.get("node.name") != SRC_NAME \
                        and "monitor" not in p.get("node.name", ""):
                    nid = o["id"]
                    break
        if nid:
            run("wpctl", "set-default", str(nid))


def live(mode):
    cfg = load()
    on = {"on": True, "off": False}.get(mode, not pids("pw-loopback.*" + SRC_NAME))
    kill("pw-loopback.*" + SRC_NAME)
    if on:
        subprocess.Popen(
            ["pw-loopback", "-C", SRC_NAME, "--playback-props",
             'node.name=sakura_mic_live node.description="Sakura Mic - live monitor"'],
            start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    cfg["live"] = on
    save(cfg)


def apply():
    cfg = load()
    # remember which real mic we are processing
    if not cfg.get("device"):
        name = default_source_name()
        if name and name != SRC_NAME:
            cfg["device"] = name
    for o in dump():
        p = props(o)
        if p.get("node.name") == cfg.get("device"):
            cfg["deviceDesc"] = p.get("node.description") or p.get("node.nick") or cfg["device"]
    save(cfg)

    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    open(CONF, "w").write(build_conf(cfg))
    kill("pipewire -c " + CONF)
    time.sleep(0.4)
    if not cfg.get("enabled", True):
        live("off")
        set_default("off")
        return
    def launch():
        subprocess.Popen(["pipewire", "-c", CONF], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(30):
            time.sleep(0.2)
            if node_id(SRC_NAME):
                return True
        return False

    if not launch():
        # a plugin refused to load - fall back to the built-in EQ only, never leave the mic dead
        kill("pipewire -c " + CONF)
        time.sleep(0.3)
        for k in PLUG:
            PLUG[k] = None
        open(CONF, "w").write(build_conf(cfg))
        launch()
    if cfg.get("autoDefault", True):
        set_default("on")
    if cfg.get("live"):
        live("on")


def status():
    objs = dump()
    srcs = []
    for o in objs:
        p = props(o)
        if p.get("media.class") == "Audio/Source" and p.get("node.name") != SRC_NAME \
                and "monitor" not in p.get("node.name", ""):
            srcs.append({"name": p.get("node.name", ""),
                         "desc": p.get("node.description") or p.get("node.nick") or p.get("node.name", "")})
    print(json.dumps({
        "running": bool(node_id(SRC_NAME, objs)),
        "live": bool(pids("pw-loopback.*" + SRC_NAME)),
        "isDefault": default_source_name(objs) == SRC_NAME,
        "sources": srcs,
        "plugins": {k: bool(v) for k, v in PLUG.items()},
        "config": load(),
    }))


def levels():
    if not shutil.which("pw-cat"):
        return
    p = subprocess.Popen(["pw-cat", "-r", "--target", SRC_NAME, "--format", "s16",
                          "--rate", "16000", "--channels", "1", "--latency", "50ms", "-"],
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    p.stdout.read(44)
    n = 800
    while True:
        data = p.stdout.read(n * 2)
        if not data or len(data) < 2:
            break
        s = struct.unpack("<%dh" % (len(data) // 2), data[:len(data) // 2 * 2])
        peak = max(abs(x) for x in s) / 32768.0 or 1e-6
        rms = (sum(x * x for x in s) / len(s)) ** 0.5 / 32768.0 or 1e-6
        print(json.dumps({"rms": round(20 * math.log10(rms), 1),
                          "peak": round(20 * math.log10(peak), 1)}), flush=True)


def main():
    a = sys.argv[1:] or ["status"]
    cmd = a[0]
    if cmd == "apply":
        apply()
    elif cmd == "sync":
        if not push(controls(load())):
            apply()
    elif cmd == "set":
        cfg = load()
        was_pitch = abs(float(cfg.get("pitch", 0))) >= 0.25
        structural = False
        i = 1
        while i < len(a) - 1:
            k, v = a[i], a[i + 1]
            i += 2
            if k in ("enabled", "compOn", "gateOn", "live", "autoDefault"):
                cfg[k] = v in ("1", "true", "True", "on")
                if k in ("enabled", "autoDefault"):
                    structural = True
            elif k == "device":
                cfg[k] = v
                structural = True
            elif k == "preset":
                cfg.update(PRESETS.get(v, {}))
            else:
                try:
                    cfg[k] = float(v)
                except ValueError:
                    cfg[k] = v
        if (abs(float(cfg.get("pitch", 0))) >= 0.25) != was_pitch:
            structural = True
        save(cfg)
        if structural or not node_id(CAP_NAME):
            apply()
        else:
            push(controls(cfg))
            if cfg.get("live") != bool(pids("pw-loopback.*" + SRC_NAME)):
                live("on" if cfg.get("live") else "off")
    elif cmd == "live":
        live(a[1] if len(a) > 1 else "toggle")
    elif cmd == "default":
        set_default(a[1] if len(a) > 1 else "on")
    elif cmd == "stop":
        live("off")
        kill("pipewire -c " + CONF)
        set_default("off")
    elif cmd == "levels":
        levels()
    else:
        status()


main()
