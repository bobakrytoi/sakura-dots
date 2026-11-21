"""Tiny mpv JSON-IPC client over a unix socket (no external deps).

mpv is started as   mpv --idle --no-video --input-ipc-server=SOCK
Requests carry a request_id; replies are matched to it. Events and
property changes (observe_property) are delivered to `on_event`.
"""
import ctypes, json, os, queue, signal, socket, subprocess, threading, time, itertools


def _die_with_parent():
    # PR_SET_PDEATHSIG: mpv gets SIGTERM when the backend dies, however it dies
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)
    except Exception:
        pass


class MpvError(Exception):
    pass


class Mpv:
    def __init__(self, sock_path, on_event=None, extra_args=()):
        self.sock_path = sock_path
        self.on_event = on_event or (lambda ev: None)
        self.extra_args = list(extra_args)
        self.proc = None
        self.sock = None
        self._ids = itertools.count(1)
        self._wait = {}            # request_id -> [Event, reply]
        self._wlock = threading.Lock()
        self._observed = {}        # name -> observe id
        self.alive = False
        self._evq = queue.Queue()
        threading.Thread(target=self._dispatch, daemon=True).start()

    def _dispatch(self):
        # events run on their own thread so the socket reader never blocks on
        # the consumer (the consumer may hold locks while waiting for replies)
        while True:
            ev = self._evq.get()
            try:
                self.on_event(ev)
            except Exception:
                pass

    # ── lifecycle ──────────────────────────────────────────────
    def start(self):
        os.makedirs(os.path.dirname(self.sock_path), exist_ok=True)
        try:
            os.unlink(self.sock_path)
        except FileNotFoundError:
            pass
        args = ["mpv", "--idle=yes", "--no-video", "--no-terminal", "--audio-display=no",
                "--input-ipc-server=" + self.sock_path, "--title=Sakura Sound",
                # mpv-mpris takes MPRIS Identity from audio-client-name (also the PipeWire stream name)
                "--audio-client-name=Sakura Sound",
                # no mpv-mpris here: the backend serves MPRIS itself (mpris.py) so controls reach the real queue
                "--load-scripts=no",
                "--keep-open=no", "--gapless-audio=weak",
                "--cache=yes", "--demuxer-max-bytes=64MiB",
                "--ytdl=no"] + self.extra_args
        self.proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, preexec_fn=_die_with_parent)
        for _ in range(100):
            if os.path.exists(self.sock_path):
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.connect(self.sock_path)
                    self.sock = s
                    break
                except OSError:
                    pass
            time.sleep(0.05)
        if not self.sock:
            raise MpvError("mpv socket did not appear")
        self.alive = True
        threading.Thread(target=self._reader, daemon=True).start()
        for name, oid in list(self._observed.items()):
            self.command("observe_property", oid, name, wait=False)

    def stop(self):
        self.alive = False
        try:
            self.command("quit", wait=False)
        except Exception:
            pass
        if self.proc:
            try:
                self.proc.wait(2)
            except Exception:
                self.proc.kill()

    # ── io ─────────────────────────────────────────────────────
    def _reader(self):
        buf = b""
        while self.alive:
            try:
                chunk = self.sock.recv(65536)
            except OSError:
                chunk = b""
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line.strip():
                    continue
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                rid = msg.get("request_id")
                if rid is not None and rid in self._wait and "event" not in msg:
                    slot = self._wait[rid]
                    slot[1] = msg
                    slot[0].set()
                elif "event" in msg:
                    self._evq.put(msg)
        was = self.alive
        self.alive = False
        for slot in list(self._wait.values()):
            slot[0].set()
        if was:
            self._evq.put({"event": "mpv-died"})

    def command(self, *args, wait=True, timeout=5.0):
        if not self.sock or not self.alive:
            raise MpvError("mpv not running")
        rid = next(self._ids)
        msg = {"command": list(args), "request_id": rid}
        slot = [threading.Event(), None]
        if wait:
            self._wait[rid] = slot
        data = (json.dumps(msg) + "\n").encode()
        with self._wlock:
            self.sock.sendall(data)
        if not wait:
            return None
        ok = slot[0].wait(timeout)
        self._wait.pop(rid, None)
        rep = slot[1]
        if not ok or rep is None:
            raise MpvError("timeout: %r" % (args,))
        if rep.get("error") not in ("success", None):
            raise MpvError(rep.get("error"))
        return rep.get("data")

    # ── helpers ────────────────────────────────────────────────
    def get(self, name, default=None):
        try:
            return self.command("get_property", name)
        except MpvError:
            return default

    def set(self, name, value):
        return self.command("set_property", name, value)

    def observe(self, name):
        if name in self._observed:
            return
        oid = len(self._observed) + 1
        self._observed[name] = oid
        if self.alive:
            self.command("observe_property", oid, name, wait=False)
