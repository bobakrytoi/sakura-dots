#!/usr/bin/env python3
"""sakura - Windows-style autoscroll on the middle button, for every app under Hyprland.

Hyprland (hyprland.lua, block AUTOSCROLL) catches the wheel press/release and writes one byte
into a FIFO: d = wheel down, u = wheel up, s = stop (any click / Esc while autoscroll is latched).
This daemon decides what it was and scrolls through a virtual mouse on /dev/uinput
(plain ioctl, no python-evdev needed). The anchor is drawn by quickshell (Autoscroll.qml).

  quick click (< 220 ms, no drag)   -> a normal middle click is replayed (paste, close tab, new tab)
  press + drag away                 -> scrolls while held, stops on release
  press, hold still, release        -> latched: scrolls with the cursor until any click or Esc
"""
import fcntl, json, math, os, select, signal, socket, struct, subprocess, sys, time

RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
FIFO = f"{RUN}/sakura-autoscroll.fifo"
PIDF = f"{RUN}/sakura-autoscroll.pid"
HSOCK = f"{RUN}/hypr/{os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')}/.socket.sock"

HOLD_MS = 0.22      # longer than this = autoscroll instead of a click
DEAD = 14           # px around the anchor that do nothing
TICK = 1 / 125

# ── uinput ──────────────────────────────────────────────────────────────
EV_SYN, EV_KEY, EV_REL = 0, 1, 2
REL_X, REL_Y, REL_HWHEEL, REL_WHEEL, REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES = 0, 1, 6, 8, 11, 12
BTN_LEFT, BTN_RIGHT, BTN_MIDDLE = 0x110, 0x111, 0x112
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_RELBIT = 0x40045564, 0x40045565, 0x40045566
UI_DEV_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405C5503, 0x5501, 0x5502


class Mouse:
    def __init__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_REL)
        for b in (BTN_LEFT, BTN_RIGHT, BTN_MIDDLE):
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, b)
        for r in (REL_X, REL_Y, REL_WHEEL, REL_HWHEEL, REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES):
            fcntl.ioctl(self.fd, UI_SET_RELBIT, r)
        setup = struct.pack("HHHH80sI", 0x06, 0x5AC5, 0xA570, 1, b"sakura-autoscroll", 0)
        fcntl.ioctl(self.fd, UI_DEV_SETUP, setup)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)

    def emit(self, *evs):
        buf = b"".join(struct.pack("llHHi", 0, 0, t, c, v) for t, c, v in evs)
        os.write(self.fd, buf + struct.pack("llHHi", 0, 0, EV_SYN, 0, 0))

    def close(self):
        try:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY); os.close(self.fd)
        except OSError:
            pass


# ── hyprland ────────────────────────────────────────────────────────────
def hypr(cmd):
    try:
        s = socket.socket(socket.AF_UNIX); s.settimeout(0.5); s.connect(HSOCK); s.sendall(cmd.encode())
        out = b""
        while True:
            d = s.recv(4096)
            if not d: break
            out += d
        s.close(); return out.decode(errors="replace")
    except OSError:
        return ""


def cursor():
    try:
        j = json.loads(hypr("j/cursorpos")); return j["x"], j["y"]
    except (ValueError, KeyError):
        return None


procs = []
def anchor(shown, x=0, y=0, v=0, h=0):
    global procs
    procs = [p for p in procs if p.poll() is None]
    procs.append(subprocess.Popen(["qs", "ipc", "call", "--", "autoscroll", "state", str(int(shown)), str(int(x)), str(int(y)), str(v), str(h)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))


def speed(d):
    """notches per second for a distance in px from the anchor (sign kept)."""
    a = abs(d) - DEAD
    if a <= 0: return 0.0
    n = a * 0.055 + (a / 100.0) ** 2 * 2.6
    return math.copysign(min(n, 90.0), d)


# ── state machine ───────────────────────────────────────────────────────
class AS:
    def __init__(self, m):
        self.m = m; self.state = "idle"; self.skip_up = False
        self.reset()

    def reset(self):
        self.acc = [0.0, 0.0]; self.lo = [0, 0]; self.engaged = False; self.dirs = (0, 0)

    def stop(self):
        if self.state == "sticky": hypr("eval __asSetSticky(false)")
        if self.state in ("hold", "sticky"): anchor(False)
        self.state = "idle"; self.reset()

    def click(self):
        # let our own click through the Hyprland bind, then put the bind back
        hypr("eval __asPass(true)")
        self.m.emit((EV_KEY, BTN_MIDDLE, 1)); self.m.emit((EV_KEY, BTN_MIDDLE, 0))
        time.sleep(0.04)
        hypr("eval __asPass(false)")

    def on(self, c):
        now = time.monotonic()
        if c == "d":
            if self.state == "idle":
                p = cursor()
                if not p: self.click(); return
                self.p0 = p; self.t0 = now; self.state = "pending"; self.reset()
            elif self.state == "sticky":
                self.stop(); self.skip_up = True
        elif c == "u":
            if self.skip_up: self.skip_up = False; return
            if self.state == "pending":
                self.state = "idle"; self.click()
            elif self.state == "hold":
                if self.engaged: self.stop()
                else:
                    self.state = "sticky"; hypr("eval __asSetSticky(true)")
        elif c == "s":
            self.stop()

    def tick(self):
        p = cursor()
        if not p: return
        dx, dy = p[0] - self.p0[0], p[1] - self.p0[1]
        if self.state == "pending":
            if time.monotonic() - self.t0 < HOLD_MS and max(abs(dx), abs(dy)) <= DEAD + 4: return
            self.state = "hold"; anchor(True, *self.p0)
        if max(abs(dx), abs(dy)) > DEAD: self.engaged = True
        sv, sh = speed(dy), speed(dx)
        evs = []
        # down/right from the anchor = content goes down/right = wheel down (negative) / hwheel right (positive)
        for i, (s, hi, lo, sign) in enumerate(((sv, REL_WHEEL_HI_RES, REL_WHEEL, -1), (sh, REL_HWHEEL_HI_RES, REL_HWHEEL, 1))):
            if s == 0: self.acc[i] = 0.0; continue
            self.acc[i] += s * 120 * TICK
            n = int(self.acc[i])
            if n:
                self.acc[i] -= n
                evs.append((EV_REL, hi, sign * n))
                self.lo[i] += n
                k = int(self.lo[i] / 120)
                if k: self.lo[i] -= k * 120; evs.append((EV_REL, lo, sign * k))
        if evs: self.m.emit(*evs)
        dirs = ((sv > 0) - (sv < 0), (sh > 0) - (sh < 0))
        if dirs != self.dirs:
            self.dirs = dirs; anchor(True, self.p0[0], self.p0[1], dirs[0], dirs[1])


def alive(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f: return b"autoscroll" in f.read()
    except OSError:
        return False


def main():
    try:
        old = int(open(PIDF).read().strip())
        if old != os.getpid() and alive(old):
            print("already running", file=sys.stderr); return
    except (OSError, ValueError):
        pass
    if not os.path.exists(FIFO): os.mkfifo(FIFO, 0o600)
    fd = os.open(FIFO, os.O_RDWR | os.O_NONBLOCK)   # RDWR: never EOF, writers never block
    m = Mouse()
    with open(PIDF, "w") as f: f.write(str(os.getpid()))
    a = AS(m)

    def quit_(*_):
        try: a.stop()
        except Exception: pass
        for p in (PIDF, FIFO):
            try: os.unlink(p)
            except OSError: pass
        hypr("eval __asSync()")
        m.close(); sys.exit(0)
    signal.signal(signal.SIGTERM, quit_); signal.signal(signal.SIGINT, quit_); signal.signal(signal.SIGHUP, quit_)

    time.sleep(0.3)          # let libinput pick up the device
    hypr("eval __asSync()")  # turn the Hyprland binds on
    next_t = 0.0
    while True:
        active = a.state != "idle"
        timeout = max(0.0, next_t - time.monotonic()) if active else 2.0
        r, _, _ = select.select([fd], [], [], timeout)
        if r:
            try: data = os.read(fd, 64).decode(errors="ignore")
            except BlockingIOError: data = ""
            for c in data:
                if c in "dus":
                    try: a.on(c)
                    except Exception as e: print("autoscroll:", e, file=sys.stderr); a.stop()
        if a.state != "idle" and time.monotonic() >= next_t:
            try: a.tick()
            except Exception as e: print("autoscroll:", e, file=sys.stderr); a.stop()
            next_t = time.monotonic() + TICK
        elif a.state == "idle":
            next_t = 0.0
            if not r and not os.path.exists(PIDF): quit_()   # pid file gone = asked to stop


if __name__ == "__main__":
    main()
