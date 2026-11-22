#!/usr/bin/env python3
# sakura mono - sakura-cam: the iPhone as a webcam (like iVCam), no iOS app needed.
#
#   iPhone Safari (PWA)  --WebRTC-->  this server  -->  /dev/videoN "Sakura Cam" (v4l2loopback)
#                                                  -->  "Sakura Mic" (PipeWire pipe source, optional)
#
# Ports
#   8780  http   setup page for the phone + the CA profile (/ca)        - every interface
#   8781  https  the camera page (PWA), WebSocket /ws for signaling      - every interface
#   8782  http   local API for quickshell (SakuraCam.qml)                - 127.0.0.1 only
#       GET  /state          JSON state        GET /events   the same as Server-Sent Events, on every change
#       GET  /qr.svg?net=wifi|usb|auto          GET /preview.jpg  the current output frame (small)
#       POST /cmd  {"cmd": "stream", "on": true|false|"toggle"} | {"cmd": "set", "key": k, "value": v}
#                  {"cmd": "config", "cfg": {...}} | {"cmd": "focus", "x": .5, "y": .5} | {"cmd": "kick"}
#
# Settings live in ~/.config/sakura/settings.json -> "cam" (Settings > Sakura Cam writes them, SakuraCam.qml
# pushes them here). Certificates: certs.py. The venv is .venv next to this file (aiortc, aiohttp, ...).
import asyncio
import json
import os
import ssl
import subprocess
import sys
import time

import av
import segno
from aiohttp import WSMsgType, web
from aiortc import RTCConfiguration, RTCPeerConnection, RTCSessionDescription
from aiortc.mediastreams import MediaStreamError
from aiortc.rtcrtpsender import RTCRtpSender
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import certs        # noqa: E402
import v4l2out      # noqa: E402

HTTP_PORT, HTTPS_PORT, API_PORT = 8780, 8781, 8782
MDNS = "sakura-cam.local"
STATIC = os.path.join(HERE, "static")
SETTINGS = os.path.expanduser("~/.config/sakura/settings.json")
RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "sakura-cam")
FIFO = os.path.join(RUN, "mic.fifo")
FONT = "/usr/share/fonts/inter/InterVariable.ttf"

DEFAULTS = {"res": "1080p", "fps": 30, "camera": "back", "mirror": False, "rotate": 0, "fit": "fill",
            "mic": False, "bitrate": 8, "net": "auto", "zoom": 1.0, "autostream": True}
SIZES = {"720p": (1280, 720), "1080p": (1920, 1080)}


# aiortc's receive-side bandwidth estimate (REMB) starts low and climbs slowly; Safari obeys it and drops the
# frame rate to fit. On a LAN / USB cable the link is never the limit, so tell the phone "send what you want"
# (the configured bitrate + headroom) about twice a second instead.
REMB_BPS = [12_000_000]


def _patch_remb():
    from aiortc import rate
    orig = rate.RemoteBitrateEstimator.add
    def add(self, abs_send_time, arrival_time_ms, payload_size, ssrc):
        orig(self, abs_send_time, arrival_time_ms, payload_size, ssrc)
        last = getattr(self, "_sakura_last", 0)
        if arrival_time_ms - last >= 500:
            self._sakura_last = arrival_time_ms
            return REMB_BPS[0], list(self.ssrcs.keys()) or [ssrc]
        return None
    rate.RemoteBitrateEstimator.add = add


_patch_remb()


def log(*a):
    print("[sakura-cam]", *a, flush=True)


def device_holders(dev):
    """Names of the other processes that have the camera open (they pin its size: v4l2loopback refuses a new
    format while someone reads). Same user only, which is all /proc lets us see anyway."""
    names, me = [], os.getpid()
    try:
        target = os.path.realpath(dev)
        for pid in os.listdir("/proc"):
            if not pid.isdigit() or int(pid) == me:
                continue
            try:
                for fd in os.listdir(f"/proc/{pid}/fd"):
                    if os.path.realpath(f"/proc/{pid}/fd/{fd}") == target:
                        with open(f"/proc/{pid}/comm") as f:
                            n = f.read().strip()
                        if n not in names:
                            names.append(n)
                        break
            except OSError:
                pass
    except OSError:
        pass
    return names


def read_settings():
    try:
        with open(SETTINGS) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


# ── network ─────────────────────────────────────────────────────────────────────────────────────
def interfaces():
    """Usable IPv4 addresses: [{if, ip, kind}] with kind usb (iPhone tethering) | wifi | lan. VPN/virtual skipped."""
    try:
        out = subprocess.run(["ip", "-j", "-4", "addr"], capture_output=True, text=True, timeout=3).stdout
        data = json.loads(out or "[]")
    except Exception:
        return []
    res = []
    for i in data:
        name = i.get("ifname", "")
        if name == "lo" or name.startswith(("wg", "tun", "tap", "docker", "veth", "br-", "virbr", "mullvad")):
            continue
        if "UP" not in i.get("flags", []):
            continue
        try:
            drv = os.path.basename(os.path.realpath(f"/sys/class/net/{name}/device/driver"))
        except OSError:
            drv = ""
        kind = "usb" if drv == "ipheth" else "wifi" if os.path.exists(f"/sys/class/net/{name}/wireless") else "lan"
        for a in i.get("addr_info", []):
            if a.get("family") == "inet" and a.get("local"):
                res.append({"if": name, "ip": a["local"], "kind": kind})
    return res


class Mdns:
    """Announces sakura-cam.local (A records) so the home-screen app keeps one address on Wi-Fi and USB."""
    def __init__(self):
        self.zc = None
        self.info = None
        self.ips = []

    def update(self, ips):
        if ips == self.ips:
            return
        self.ips = ips
        try:
            import socket
            from zeroconf import IPVersion, ServiceInfo, Zeroconf
            if self.zc is None:
                self.zc = Zeroconf(ip_version=IPVersion.V4Only)
            if self.info is not None:
                self.zc.unregister_service(self.info)
                self.info = None
            if not ips:
                return
            self.info = ServiceInfo("_https._tcp.local.", "Sakura Cam._https._tcp.local.",
                                    addresses=[socket.inet_aton(i) for i in ips], port=HTTPS_PORT,
                                    server=MDNS + ".", properties={"path": "/"})
            self.zc.register_service(self.info, allow_name_change=True)
        except Exception as e:
            log("mdns:", repr(e))

    def close(self):
        try:
            if self.zc:
                if self.info:
                    self.zc.unregister_service(self.info)
                self.zc.close()
        except Exception:
            pass


# ── Sakura Mic (PipeWire pipe source) ───────────────────────────────────────────────────────────
class Mic:
    def __init__(self):
        self.module = None
        self.fd = None
        self.resampler = None

    @staticmethod
    def _stale():
        try:
            out = subprocess.run(["pactl", "list", "short", "modules"], capture_output=True, text=True, timeout=3).stdout
        except Exception:
            return []
        return [l.split()[0] for l in out.splitlines() if "sakura_mic" in l]

    def on(self):
        if self.module:
            return True
        for m in self._stale():
            subprocess.run(["pactl", "unload-module", m], capture_output=True)
        os.makedirs(RUN, exist_ok=True)
        if not os.path.exists(FIFO):
            os.mkfifo(FIFO, 0o600)
        try:
            out = subprocess.run(["pactl", "load-module", "module-pipe-source", "source_name=sakura_mic",
                                  f"file={FIFO}", "format=s16le", "rate=48000", "channels=1",
                                  "source_properties=device.description='Sakura Mic' node.description='Sakura Mic' priority.session=10 priority.driver=10"],
                                 capture_output=True, text=True, timeout=5)
            if out.returncode != 0:
                log("mic: load-module failed:", out.stderr.strip())
                return False
            self.module = out.stdout.strip()
            self.fd = os.open(FIFO, os.O_RDWR | os.O_NONBLOCK)
            self.resampler = av.AudioResampler(format="s16", layout="mono", rate=48000)
            return True
        except Exception as e:
            log("mic:", e)
            return False

    def off(self):
        if self.fd is not None:
            try:
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None
        if self.module:
            subprocess.run(["pactl", "unload-module", self.module], capture_output=True)
            self.module = None
        self.resampler = None

    def write(self, frame):
        if self.fd is None or self.resampler is None:
            return
        try:
            for f in self.resampler.resample(frame):
                os.write(self.fd, bytes(f.planes[0])[: f.samples * 2])
        except (BlockingIOError, ValueError):
            pass
        except OSError:
            pass


# ── the camera ──────────────────────────────────────────────────────────────────────────────────
class Cam:
    def __init__(self):
        self.cfg = dict(DEFAULTS)
        self.cfg.update({k: v for k, v in (read_settings().get("cam") or {}).items() if k in DEFAULTS})
        REMB_BPS[0] = int(self.cfg["bitrate"] * 1.5e6)
        self.out = v4l2out.V4L2Out()
        self.mic = Mic()
        self.mdns = Mdns()
        self.ifaces = []
        self.listeners = set()          # asyncio.Queue per SSE client
        self.ws = None                  # the phone's WebSocket
        self.pc = None
        self.dc = None
        self.phone = {}                 # what the phone reports (caps, lens list, settings, ua)
        self.connected = False
        self.streaming = False          # video frames are coming
        self.want = bool(self.cfg["autostream"])
        self.last_frame = 0.0
        self.in_size = (0, 0)
        self.fps_in = 0.0
        self._fps_n = 0
        self._fps_t = time.time()
        self.rtt = 0
        self.proc_ms = 0.0
        self.held = []                    # apps pinning the device size while it differs from the setting
        self.graph = None
        self.graph_key = None
        self.placeholder = None
        self.placeholder_key = None
        self.preview = b""
        self.preview_want = 0.0
        self.preview_streams = 0          # open /preview.mjpeg connections
        self.preview_n = 0
        self.preview_t = 0.0
        self.started = time.time()
        self.stream_since = 0.0
        self.ssl = None

    # ── state ──
    _rd_t = 0.0
    _rd_v = False

    def readers(self, dev):
        """Another app has the camera open (cached 1 s: this is asked on every frame while sizes differ)."""
        now = time.time()
        if now - self._rd_t > 1.0:
            self._rd_t, self._rd_v = now, bool(device_holders(dev))
        return self._rd_v

    def out_size(self):
        if self.out.size:
            return self.out.size
        return SIZES.get(self.cfg["res"], SIZES["1080p"])

    def urls(self):
        by = {}
        for i in self.ifaces:
            by.setdefault(i["kind"], i["ip"])
        return {k: f"http://{ip}:{HTTP_PORT}/" for k, ip in by.items()}

    def state(self):
        s = self.settings_view()
        dev = v4l2out.find_device()
        return {
            "running": True,
            "connected": self.connected,
            "streaming": self.streaming,
            "want": self.want,
            "since": int(self.stream_since * 1000),
            "phone": self.phone,
            "in": {"w": self.in_size[0], "h": self.in_size[1], "fps": round(self.fps_in, 1), "proc": round(self.proc_ms, 1)},
            "out": {"device": dev or "", "w": self.out_size()[0], "h": self.out_size()[1],
                    "error": self.out.error if not dev or self.out.error else "",
                    "want": SIZES.get(self.cfg["res"], SIZES["1080p"])[1], "held": self.held},
            "mic": {"on": bool(self.mic.module), "want": bool(self.cfg["mic"])},
            "rtt": self.rtt,
            "ifaces": self.ifaces,
            "urls": self.urls(),
            "mdns": MDNS,
            "cfg": s,
        }

    def settings_view(self):
        return dict(self.cfg)

    def changed(self):
        msg = json.dumps(self.state())
        for q in list(self.listeners):
            try:
                q.put_nowait(msg)
            except asyncio.QueueFull:
                pass

    # ── phone messages ──
    async def send_phone(self, m):
        data = json.dumps(m)
        if self.dc is not None and self.dc.readyState == "open":
            try:
                self.dc.send(data)
                return
            except Exception:
                pass
        if self.ws is not None and not self.ws.closed:
            try:
                await self.ws.send_str(data)
            except Exception:
                pass

    def phone_cfg(self):
        st = read_settings()
        return {"t": "cfg", "cfg": self.cfg, "want": self.want, "lang": st.get("lang", "en"),
                "accent": st.get("accent") or "#f2b8d0", "hosts": [i["ip"] for i in self.ifaces] + [MDNS]}

    async def on_phone(self, m):
        t = m.get("t")
        if t == "hello":
            self.phone = {"ua": m.get("ua", ""), "name": m.get("name", "iPhone")}
            await self.send_phone(self.phone_cfg())
        elif t == "offer":
            await self.answer(m)
        elif t == "status":
            p = dict(self.phone)
            p.update({k: v for k, v in m.items() if k != "t"})
            self.phone = p
            if "want" in m:
                self.want = bool(m["want"])
            if "zoomReq" in m and not p.get("zoomNative"):           # pinch on the phone -> digital zoom here
                self.cfg["zoom"] = max(1.0, min(4.0, float(m["zoomReq"] or 1)))
            if "setMic" in m:                                         # mic button on the phone
                self.cfg["mic"] = bool(m["setMic"])
                (self.mic.on() if self.cfg["mic"] else self.mic.off())
            for k in ("zoomReq", "setMic"):
                p.pop(k, None)
            self.changed()
        elif t == "pong":
            self.rtt = int((time.time() * 1000) - m.get("ts", 0))
        elif t == "ping":
            await self.send_phone({"t": "pong", "ts": m.get("ts", 0)})

    async def answer(self, m):
        await self.close_pc()
        pc = RTCPeerConnection(RTCConfiguration(iceServers=[]))
        self.pc = pc

        @pc.on("datachannel")
        def on_dc(ch):
            self.dc = ch

            @ch.on("message")
            def on_msg(data):
                try:
                    asyncio.ensure_future(self.on_phone(json.loads(data)))
                except ValueError:
                    pass

        @pc.on("track")
        def on_track(track):
            if track.kind == "video":
                asyncio.ensure_future(self.video_loop(track))
            elif track.kind == "audio":
                asyncio.ensure_future(self.audio_loop(track))

        @pc.on("connectionstatechange")
        async def on_state():
            log("pc:", pc.connectionState)
            if pc.connectionState in ("failed", "closed") and self.pc is pc:
                self.streaming = False
                self.changed()

        await pc.setRemoteDescription(RTCSessionDescription(sdp=m["sdp"], type="offer"))
        # H.264 first: the iPhone encodes it in hardware (cooler, less battery than VP8)
        try:
            caps = RTCRtpSender.getCapabilities("video").codecs
            pref = [c for c in caps if c.mimeType == "video/H264"] + [c for c in caps if c.mimeType not in ("video/H264",)]
            for tr in pc.getTransceivers():
                if tr.kind == "video":
                    tr.setCodecPreferences(pref)
        except Exception as e:
            log("codec prefs:", e)
        ans = await pc.createAnswer()
        await pc.setLocalDescription(ans)
        await self.send_phone({"t": "answer", "sdp": pc.localDescription.sdp})

    async def close_pc(self):
        if self.pc is not None:
            pc, self.pc, self.dc = self.pc, None, None
            try:
                await pc.close()
            except Exception:
                pass
        self.streaming = False

    # ── media ──
    def build_graph(self, frame):
        W, H = self.out_size()
        c = self.cfg
        key = (frame.width, frame.height, frame.format.name, W, H, c["mirror"], int(c["rotate"]) % 360, c["fit"],
               round(float(c["zoom"]), 2) if not self.phone.get("zoomNative") else 1.0)
        if key == self.graph_key and self.graph is not None:
            return
        g = av.filter.Graph()
        chain = [g.add_buffer(width=frame.width, height=frame.height, format=frame.format.name,
                              time_base=frame.time_base or __import__("fractions").Fraction(1, 90000))]

        def add(name, args=""):
            f = g.add(name, args)
            chain[-1].link_to(f)
            chain.append(f)

        rot = key[6]
        if rot == 90:
            add("transpose", "clock")
        elif rot == 270:
            add("transpose", "cclock")
        elif rot == 180:
            add("hflip")
            add("vflip")
        if c["mirror"]:
            add("hflip")
        z = key[8]
        if z and z > 1.01:
            add("crop", f"w=trunc(iw/{z}/2)*2:h=trunc(ih/{z}/2)*2")
        if c["fit"] == "fit":
            add("scale", f"w={W}:h={H}:force_original_aspect_ratio=decrease:flags=bicubic")
            add("pad", f"w={W}:h={H}:x=(ow-iw)/2:y=(oh-ih)/2:color=0x0b0c12")
        else:
            add("scale", f"w={W}:h={H}:force_original_aspect_ratio=increase:flags=bicubic")
            add("crop", f"w={W}:h={H}")
        add("format", "yuv420p")
        add("buffersink")
        g.configure()
        self.graph, self.graph_key = g, key

    def process(self, frame):
        """Runs in a worker thread: frame -> output I420 bytes (+ a small preview jpeg when asked)."""
        self.build_graph(frame)
        self.graph.push(frame)
        out = self.graph.pull()
        data = out.to_ndarray(format="yuv420p").tobytes()
        now = time.time()
        if (self.preview_streams > 0 or now - self.preview_want < 2.5) and now - self.preview_t > 0.030:
            self.preview_t = now
            import io
            buf = io.BytesIO()
            out.reformat(width=640, height=int(640 * out.height / out.width) // 2 * 2, format="rgb24") \
               .to_image().save(buf, "JPEG", quality=72)
            self.preview = buf.getvalue()
            self.preview_n += 1
        return data

    async def video_loop(self, track):
        loop = asyncio.get_running_loop()
        log("video track")
        while True:
            try:
                frame = await track.recv()
            except MediaStreamError:
                break
            except Exception as e:
                log("recv:", e)
                break
            if track is None or self.pc is None:
                break
            self.in_size = (frame.width, frame.height)
            self.out.open(*SIZES.get(self.cfg["res"], SIZES["1080p"]), readers=self.readers)     # keeps the old size if an app holds it
            t0 = time.perf_counter()
            try:
                data = await loop.run_in_executor(None, self.process, frame)
                self.proc_ms = self.proc_ms * 0.9 + (time.perf_counter() - t0) * 100
            except Exception as e:
                log("process:", e)
                self.graph = None
                continue
            self.out.write(data)
            now = time.time()
            self.last_frame = now
            self._fps_n += 1
            if not self.streaming:
                self.streaming = True
                self.stream_since = now
                self.changed()
        log("video track ended")
        self.streaming = False
        self.changed()

    async def audio_loop(self, track):
        while True:
            try:
                frame = await track.recv()
            except Exception:
                break
            if self.cfg["mic"]:
                self.mic.write(frame)

    # ── placeholder (no phone / paused): a calm sakura card, so apps always see a working camera ──
    def make_placeholder(self, W, H):
        st = read_settings()
        lang = st.get("lang", "en")
        acc = st.get("accent") or "#f2b8d0"
        key = (W, H, lang, acc, self.connected, self.want)
        if key == self.placeholder_key:
            return self.placeholder
        ac = tuple(int(acc[i:i + 2], 16) for i in (1, 3, 5))
        img = Image.new("RGB", (W, H), (11, 12, 18))
        glow = Image.new("RGB", (W, H), (11, 12, 18))
        d = ImageDraw.Draw(glow)
        r = int(H * 0.42)
        d.ellipse((W // 2 - r, H // 2 - r - H // 10, W // 2 + r, H // 2 + r - H // 10),
                  fill=tuple(int(11 + (c - 11) * 0.22) for c in ac))
        img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(H // 6)), 1.0)
        d = ImageDraw.Draw(img)
        s = H / 1080
        # the lens: two rings
        cx, cy, R = W // 2, int(H * 0.40), int(70 * s)
        d.ellipse((cx - R, cy - R, cx + R, cy + R), outline=ac, width=max(2, int(5 * s)))
        d.ellipse((cx - R // 3, cy - R // 3, cx + R // 3, cy + R // 3), fill=ac)
        try:
            f1 = ImageFont.truetype(FONT, int(64 * s))
            f1.set_variation_by_axes([600])
            f2 = ImageFont.truetype(FONT, int(30 * s))
            f2.set_variation_by_axes([450])
        except Exception:
            f1 = f2 = ImageFont.load_default()
        ru = lang == "ru"
        title = "Sakura Cam"
        if self.connected and not self.want:
            sub = "Пауза" if ru else "Paused"
        elif self.connected:
            sub = "Камера запускается…" if ru else "Starting the camera…"
        else:
            sub = "Открой Sakura Cam на телефоне" if ru else "Open Sakura Cam on your phone"
        d.text((cx, int(H * 0.58)), title, font=f1, fill=(236, 238, 245), anchor="mm")
        d.text((cx, int(H * 0.58) + int(62 * s)), sub, font=f2, fill=(150, 156, 172), anchor="mm")
        frame = av.VideoFrame.from_image(img).reformat(format="yuv420p")
        self.placeholder = frame.to_ndarray(format="yuv420p").tobytes()
        self.placeholder_key = key
        return self.placeholder

    async def idle_loop(self):
        """5 fps placeholder while no frames come; fps counter; interfaces / cert / mDNS refresh."""
        loop = asyncio.get_running_loop()
        tick = 0
        while True:
            await asyncio.sleep(0.2)
            tick += 1
            now = time.time()
            if now - self.last_frame > 0.6:
                if self.streaming:
                    self.streaming = False
                    self.changed()
                self.out.open(*SIZES.get(self.cfg["res"], SIZES["1080p"]), readers=self.readers)
                if self.out.fd is not None:
                    W, H = self.out.size
                    data = await loop.run_in_executor(None, self.make_placeholder, W, H)
                    self.out.write(data)
            if now - self._fps_t >= 1.0:
                self.fps_in = self._fps_n / (now - self._fps_t)
                self._fps_n, self._fps_t = 0, now
                if self.streaming:
                    self.changed()
            if tick % 10 == 0:
                want_h = SIZES.get(self.cfg["res"], SIZES["1080p"])[1]
                held = await loop.run_in_executor(None, device_holders, self.out.dev) if (self.out.size and self.out.size[1] != want_h) else []
                if held != self.held:
                    self.held = held
                    self.changed()
                await self.refresh_net()
                if self.connected:
                    await self.send_phone({"t": "ping", "ts": int(now * 1000)})

    async def refresh_net(self):
        ifs = await asyncio.get_running_loop().run_in_executor(None, interfaces)
        if ifs == self.ifaces:
            return
        self.ifaces = ifs
        ips = [i["ip"] for i in ifs]
        if certs.ensure_server([MDNS, "localhost"], ips + ["127.0.0.1"]) and self.ssl is not None:
            self.ssl.load_cert_chain(certs.SRV_CRT, certs.SRV_KEY)
            log("server certificate re-issued for", ", ".join(ips))
        await asyncio.get_running_loop().run_in_executor(None, self.mdns.update, ips)
        log("interfaces:", ", ".join(f'{i["if"]}={i["ip"]} ({i["kind"]})' for i in ifs) or "none")
        self.changed()

    # ── commands (quickshell) ──
    async def apply(self, key, value):
        if key not in DEFAULTS:
            return
        if key in ("mirror", "mic", "autostream"):
            value = bool(value)
        elif key in ("fps", "rotate", "bitrate"):
            value = int(value)
        elif key == "zoom":
            value = max(1.0, min(10.0, float(value)))
        self.cfg[key] = value
        if key == "bitrate":
            REMB_BPS[0] = int(value * 1.5e6)
        if key == "mic":
            (self.mic.on() if value else self.mic.off())
        if key in ("camera", "res", "fps", "bitrate", "zoom", "mic"):
            await self.send_phone({"t": "set", key: value})
        self.changed()

    async def command(self, m):
        c = m.get("cmd")
        if c == "stream":
            on = m.get("on")
            self.want = (not self.want) if on in (None, "toggle") else bool(on)
            await self.send_phone({"t": "stream", "on": self.want})
            self.changed()
        elif c == "set":
            await self.apply(m.get("key"), m.get("value"))
        elif c == "config":
            for k, v in (m.get("cfg") or {}).items():
                if k in DEFAULTS and self.cfg.get(k) != v:
                    await self.apply(k, v)
        elif c == "focus":
            await self.send_phone({"t": "focus", "x": float(m.get("x", .5)), "y": float(m.get("y", .5))})
        elif c == "torch":
            await self.send_phone({"t": "torch", "on": m.get("on", "toggle")})
        elif c == "kick":
            await self.send_phone({"t": "kick"})
            await self.close_pc()
        return {"ok": True}


cam = Cam()


# ── web: phone side ─────────────────────────────────────────────────────────────────────────────
def static(name, ctype=None, cache="no-cache"):
    async def h(req):
        return web.FileResponse(os.path.join(STATIC, name), headers={"Cache-Control": cache,
                                **({"Content-Type": ctype} if ctype else {})})
    return h


async def h_ca(req):
    return web.Response(body=certs.ca_der(), headers={
        "Content-Type": "application/x-x509-ca-cert",
        "Content-Disposition": 'attachment; filename="sakura-cam.crt"'})


def mobileconfig():
    """An iOS configuration profile with the CA as a root certificate (com.apple.security.root): Safari opens it as
    a profile (Settings > Profile Downloaded), which a bare .crt download does not always do."""
    import plistlib
    import uuid
    ns = uuid.UUID("5a6b0c1e-5a6b-4c4d-9e8f-0a5a6c7a0c0e")
    der = certs.ca_der()
    cert = {"PayloadType": "com.apple.security.root", "PayloadVersion": 1,
            "PayloadIdentifier": "mono.sakura.cam.ca", "PayloadUUID": str(uuid.uuid5(ns, "ca" + der.hex()[:32])).upper(),
            "PayloadDisplayName": "Sakura Cam local CA", "PayloadDescription": "Lets Safari open the Sakura Cam page over HTTPS.",
            "PayloadCertificateFileName": "sakura-cam.cer", "PayloadContent": der}
    prof = {"PayloadType": "Configuration", "PayloadVersion": 1, "PayloadIdentifier": "mono.sakura.cam",
            "PayloadUUID": str(uuid.uuid5(ns, "profile" + der.hex()[:32])).upper(), "PayloadDisplayName": "Sakura Cam",
            "PayloadDescription": "Certificate for the Sakura Cam page on your PC (local network only).",
            "PayloadOrganization": "sakura mono", "PayloadRemovalDisallowed": False, "PayloadContent": [cert]}
    return plistlib.dumps(prof)


async def h_profile(req):
    return web.Response(body=mobileconfig(), headers={"Content-Type": "application/x-apple-aspen-config",
                                                      "Content-Disposition": 'inline; filename="sakura-cam.mobileconfig"'})


async def h_font(req):
    return web.FileResponse(FONT, headers={"Cache-Control": "max-age=604800", "Content-Type": "font/ttf"})


async def h_theme(req):
    st = read_settings()
    return web.json_response({"accent": st.get("accent") or "#f2b8d0", "lang": st.get("lang", "en")})


async def h_ping(req):
    return web.json_response({"ok": True, "name": "sakura-cam"}, headers={"Access-Control-Allow-Origin": "*"})


async def h_ws(req):
    ws = web.WebSocketResponse(heartbeat=10)
    await ws.prepare(req)
    old = cam.ws
    if old is not None and not old.closed:
        try:
            await old.send_str(json.dumps({"t": "kick"}))
            await old.close()
        except Exception:
            pass
    await cam.close_pc()
    cam.ws = ws
    cam.connected = True
    log("phone connected from", req.remote)
    cam.changed()
    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                try:
                    await cam.on_phone(json.loads(msg.data))
                except ValueError:
                    pass
            elif msg.type == WSMsgType.ERROR:
                break
    finally:
        if cam.ws is ws:
            cam.ws = None
            cam.connected = False
            cam.phone = {}
            await cam.close_pc()
            log("phone gone")
            cam.changed()
    return ws


@web.middleware
async def log_setup(req, handler):
    # setup page: which steps the phone reached (no addresses beyond the LAN IP, nothing else)
    if req.path not in ("/ping", "/theme", "/style.css", "/font/inter.ttf"):
        log("setup:", req.remote, req.method, req.path, (req.headers.get("User-Agent") or "")[:60])
    return await handler(req)


def phone_app(setup):
    app = web.Application(middlewares=[log_setup] if setup else [])
    r = app.router
    if setup:
        r.add_get("/", static("setup.html", "text/html; charset=utf-8"))
        r.add_get("/ca", h_ca)
        r.add_get("/sakura-cam.crt", h_ca)
        r.add_get("/sakura-cam.mobileconfig", h_profile)
    else:
        r.add_get("/", static("index.html", "text/html; charset=utf-8"))
        r.add_get("/ws", h_ws)
        r.add_get("/sw.js", static("sw.js", "text/javascript"))
        r.add_get("/manifest.webmanifest", static("manifest.webmanifest", "application/manifest+json"))
    r.add_get("/ping", h_ping)
    r.add_get("/theme", h_theme)
    r.add_get("/font/inter.ttf", h_font)
    for f in ("app.js", "style.css", "icon-192.png", "icon-512.png", "apple-touch-icon.png", "keepawake.mp4"):
        r.add_get("/" + f, static(f))
    return app


# ── web: quickshell side (localhost) ────────────────────────────────────────────────────────────
async def a_state(req):
    return web.json_response(cam.state())


async def a_events(req):
    resp = web.StreamResponse(headers={"Content-Type": "text/event-stream", "Cache-Control": "no-cache"})
    await resp.prepare(req)
    q = asyncio.Queue(maxsize=64)
    cam.listeners.add(q)
    try:
        await resp.write(("data: " + json.dumps(cam.state()) + "\n\n").encode())
        while True:
            try:
                msg = await asyncio.wait_for(q.get(), 15)
                while not q.empty():            # only the newest state matters
                    msg = q.get_nowait()
                await resp.write(("data: " + msg + "\n\n").encode())
            except asyncio.TimeoutError:
                await resp.write(b": keepalive\n\n")
    except (ConnectionResetError, asyncio.CancelledError):
        pass
    finally:
        cam.listeners.discard(q)
    return resp


async def a_cmd(req):
    try:
        m = await req.json()
    except Exception:
        return web.json_response({"ok": False, "error": "bad json"}, status=400)
    return web.json_response(await cam.command(m))


async def a_qr(req):
    net = req.query.get("net", cam.cfg.get("net", "auto"))
    urls = cam.urls()
    url = urls.get(net) if net != "auto" else (urls.get("usb") or urls.get("wifi") or urls.get("lan"))
    url = url or next(iter(urls.values()), f"http://{MDNS}:{HTTP_PORT}/")
    qr = segno.make(url, error="m")
    import io
    buf = io.BytesIO()
    qr.save(buf, kind="svg", scale=10, border=0, dark=req.query.get("dark", "#0f1119"),
            light=req.query.get("light", None) or None)
    return web.Response(body=buf.getvalue(), headers={"Content-Type": "image/svg+xml", "Cache-Control": "no-store",
                                                      "X-Url": url})


async def a_preview(req):
    cam.preview_want = time.time()
    if not cam.preview or not cam.streaming:
        return web.Response(status=204)
    return web.Response(body=cam.preview, headers={"Content-Type": "image/jpeg", "Cache-Control": "no-store"})


async def a_mjpeg(req):
    """The panel's live preview as multipart JPEG (QtMultimedia plays it), so the panel never holds the v4l2
    device: a second reader there would block other apps (v4l2loopback: one streaming reader at a time)."""
    resp = web.StreamResponse(headers={"Content-Type": "multipart/x-mixed-replace; boundary=sakuraframe",
                                       "Cache-Control": "no-store"})
    await resp.prepare(req)
    cam.preview_streams += 1
    # exactly 25 fps (the newest frame each tick): players time an mjpeg stream at 25 fps, faster would pile up delay
    nxt = time.perf_counter()
    try:
        while True:
            if cam.preview:
                jpg = cam.preview
                await resp.write(b"--sakuraframe\r\nContent-Type: image/jpeg\r\nContent-Length: "
                                 + str(len(jpg)).encode() + b"\r\n\r\n" + jpg + b"\r\n")
            nxt += 0.04
            await asyncio.sleep(max(0.0, nxt - time.perf_counter()))
    except (ConnectionResetError, asyncio.CancelledError):
        pass
    finally:
        cam.preview_streams -= 1
    return resp


def api_app():
    app = web.Application()
    app.router.add_get("/state", a_state)
    app.router.add_get("/events", a_events)
    app.router.add_post("/cmd", a_cmd)
    app.router.add_get("/qr.svg", a_qr)
    app.router.add_get("/preview.jpg", a_preview)
    app.router.add_get("/preview.mjpeg", a_mjpeg)
    return app


async def main():
    certs.ensure_ca()
    cam.ifaces = interfaces()
    ips = [i["ip"] for i in cam.ifaces]
    certs.ensure_server([MDNS, "localhost"], ips + ["127.0.0.1"])
    ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ctx.load_cert_chain(certs.SRV_CRT, certs.SRV_KEY)
    cam.ssl = ctx
    await asyncio.get_running_loop().run_in_executor(None, cam.mdns.update, ips)    # zeroconf's sync API must not run on the loop
    if cam.cfg["mic"]:
        cam.mic.on()

    runners = []
    for app, host, port, sctx in ((phone_app(True), "0.0.0.0", HTTP_PORT, None),
                                  (phone_app(False), "0.0.0.0", HTTPS_PORT, ctx),
                                  (api_app(), "127.0.0.1", API_PORT, None)):
        runner = web.AppRunner(app, access_log=None)
        await runner.setup()
        await web.TCPSite(runner, host, port, ssl_context=sctx).start()
        runners.append(runner)
    log("up:", ", ".join(f'{i["kind"]} http://{i["ip"]}:{HTTP_PORT}/' for i in cam.ifaces) or "no network",
        "| device:", v4l2out.find_device() or "missing (v4l2loopback not loaded)")
    try:
        await cam.idle_loop()
    finally:
        cam.mic.off()
        cam.out.close()
        await asyncio.get_running_loop().run_in_executor(None, cam.mdns.close)
        for r in runners:
            await r.cleanup()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
