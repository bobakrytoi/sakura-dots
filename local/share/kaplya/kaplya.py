#!/usr/bin/env python3
"""kaplya - у каждого окна терминала своя жидкая капля из символов.

Когда два окна с `kaplya` рядом, капли вытягиваются друг к другу и сливаются
в одну длинную каплю через края окон. Растаскиваешь окна - она тянется как
ириска, тоньшает (масса сохраняется), шейка рвётся, половинки отскакивают и дрожат.
Сдвинешь обратно - снова слипнутся. С 3 окнами так же для каждой пары.

Первый запуск поднимает сервер-симуляцию (unix-сокет в $XDG_RUNTIME_DIR),
остальные подключаются. Физика - в глобальных координатах экрана, каждое окно
рисует символами только то, что попало в его прямоугольник.

  kaplya     - запустить в текущем окне (q, Esc или Ctrl+C - выйти)
"""
import base64
import fcntl
import json
import math
import os
import random
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import termios
import time
import zlib

import numpy as np

RUN = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/kaplya-{os.getuid()}"
SOCK = os.path.join(RUN, "kaplya.sock")
LOCK = os.path.join(RUN, "kaplya.lock")
SETTINGS = os.path.expanduser("~/.config/sakura/settings.json")

# ---------------------------------------------------------------- simulation
# Каждая капля - тело (шар с желейной дрожью) + «вытяжки» к соседям.
# Вытяжка - та же капля, а не отдельная нить: её масса забирается из тела
# (масса сохраняется), профиль толстый у основания и сужается к соседу.
R_BLOB = 95.0     # радиус капли в покое, px
MASS = math.pi * R_BLOB ** 2
PROF = 2.6        # насколько быстро вытяжка сужается от основания
NECK0, L_REF = 30.0, 265.0   # толщина шейки при «естественной» длине
R_MIN = 10.0      # тоньше этого шейка рвётся, px
LEAN = 520.0      # с какого зазора капли начинают клониться друг к другу
CONNECT = 260.0   # зазор между окнами, при котором капли тянутся и слипаются, px
K_E, C_E = 28.0, 6.5      # пружина вытяжки (недодемпфирована - пружинит)
K_C, C_C = 60.0, 8.0      # тело догоняет своё окно с запаздыванием
W2, W3, WG = 13.0, 18.0, 3.2   # частоты и затухание дрожи
DT = 1 / 60
UT = math.sqrt(1 - 0.42 ** (1 / 3))   # ядро (1-u²)³ = порог 0.42 при u = UT


def rect_gap(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    dx = max(bx - (ax + aw), ax - (bx + bw), 0)
    dy = max(by - (ay + ah), ay - (by + bh), 0)
    return math.hypot(dx, dy)


def clamp_to_rect(p, r, inset=0.0):
    x, y, w, h = r
    i = min(inset, w / 2 - 1, h / 2 - 1)
    return np.array([min(max(p[0], x + i), x + w - i), min(max(p[1], y + i), y + h - i)])


class Blob:
    def __init__(self, c):
        self.c = np.array(c, float)
        self.v = np.zeros(2)
        self.a = np.zeros(3)      # дрожь: 2-я и 3-я моды (амплитуда)
        self.av = np.zeros(3)
        self.ph = np.zeros(3)     # их направление
        self.rb = R_BLOB
        # своя неровная форма: гармоники контура (m, амплитуда, фаза, дрейф)
        rnd = random.Random()
        self.form = [(m, rnd.uniform(lo, hi), rnd.uniform(0, 2 * math.pi), rnd.uniform(-0.25, 0.25))
                     for m, lo, hi in ((2, 0.07, 0.15), (3, 0.05, 0.12), (4, 0.03, 0.08), (5, 0.02, 0.05))]
        # бугорок сбоку: угол, размер, вылет, скорость обхода
        self.lump = (rnd.uniform(0, 2 * math.pi), rnd.uniform(0.38, 0.52), rnd.uniform(0.5, 0.68),
                     rnd.uniform(-0.12, 0.12))
        self.seed = rnd.uniform(0, 100)

    def contour(self, t):
        """Гармоники формы на момент t (медленно перетекают) + бугорок."""
        h = []
        for m, amp, ph, dr in self.form:
            h += [m, amp * (1 + 0.35 * math.sin(t * 0.6 + self.seed + m)), ph + dr * t]
        ang, size, off, sp = self.lump
        ang += sp * t + 0.25 * math.sin(t * 0.4 + self.seed)
        return h, [math.cos(ang) * off, math.sin(ang) * off, size * (1 + 0.15 * math.sin(t * 0.9 + self.seed))]


class Pair:
    def __init__(self):
        self.e = 0.0      # вытянутость 0..1 (1 - кончики встретились)
        self.ev = 0.0
        self.conn = False
        self.cool = 0.0
        self.neck = R_BLOB
        self.gap = 1e9


class Sim:
    def __init__(self):
        self.wins = {}
        self.blobs = {}
        self.pairs = {}
        self.drops = []   # [pos, vel, r, age]
        self.t = 0.0
        self.next_poke = 1.0
        self.shape = {"b": [], "m": [], "d": []}

    def center(self, k):
        x, y, w, h = self.wins[k]["rect"]
        return np.array([x + w / 2, y + h / 2])

    def set_window(self, k, rect, vis):
        self.wins[k] = {"rect": rect, "vis": vis}
        if k not in self.blobs:
            self.blobs[k] = Blob(self.center(k))

    def drop_window(self, k):
        self.wins.pop(k, None)
        self.blobs.pop(k, None)
        for p in [p for p in self.pairs if k in p]:
            self.pairs.pop(p)

    def wobble(self, k, mode, amount, ang):
        b = self.blobs[k]
        b.av[mode] += amount
        b.ph[mode] = ang

    def snap(self, a, b, pr, m, axis):
        pr.conn = False
        pr.cool = self.t + 1.0
        pr.ev = -3.5                                   # щёлк - вытяжки отдёргиваются
        ang = math.atan2(axis[1], axis[0])
        for k in (a, b):
            self.wobble(k, 0, 1.5, ang)
        perp = np.array([-axis[1], axis[0]])
        for sgn in (-1, 1, -1, 1):
            r = random.uniform(10, 17)
            v = axis * sgn * random.uniform(150, 380) + perp * random.uniform(-90, 90)
            self.drops.append([m + axis * sgn * random.uniform(5, 30), v, r, 0.0])

    def step(self):
        self.t += DT
        dt = DT
        keys = [k for k in self.wins if self.wins[k]["vis"]] or list(self.wins)

        # --- пары: тянуться / слиплись / порвались ---
        live = []
        for i, a in enumerate(sorted(keys)):
            for b in sorted(keys)[i + 1:]:
                pr = self.pairs.setdefault((a, b), Pair())
                gap = rect_gap(self.wins[a]["rect"], self.wins[b]["rect"])
                pr.gap = gap
                if pr.conn or (gap < CONNECT and self.t > pr.cool):
                    tgt = 1.0
                else:   # ещё далеко - капли только клонятся и вытягиваются навстречу
                    tgt = 0.45 * max(0.0, min(1.0, (LEAN - gap) / (LEAN - CONNECT)))
                pr.ev += (K_E * (tgt - pr.e) - C_E * pr.ev) * dt
                pr.e += pr.ev * dt
                if pr.e < -0.25:
                    pr.e, pr.ev = -0.25, 0.0
                if not pr.conn and tgt and pr.e > 0.97:
                    pr.conn = True
                    ax = self.blobs[b].c - self.blobs[a].c
                    ang = math.atan2(ax[1], ax[0])
                    self.wobble(a, 0, 1.2, ang)
                    self.wobble(b, 0, 1.2, ang)
                if pr.e > 0.01 or pr.conn:
                    live.append((a, b, pr))
        for p in list(self.pairs):
            if p[0] not in self.wins or p[1] not in self.wins:
                self.pairs.pop(p)

        # --- тела догоняют свои окна (сдвинуты к соседям) ---
        for k in keys:
            bl = self.blobs[k]
            anc = self.center(k)
            for a, b, pr in live:
                if k in (a, b):
                    o = b if k == a else a
                    edge = clamp_to_rect(self.center(o), self.wins[k]["rect"])
                    anc = anc + (edge - self.center(k)) * (0.08 + 0.4 * max(0.0, 1 - pr.gap / CONNECT) * pr.conn) * max(0, min(1, pr.e))
            anc = clamp_to_rect(anc, self.wins[k]["rect"], inset=R_BLOB * 0.8)
            acc = K_C * (anc - bl.c) - C_C * bl.v
            bl.v += acc * dt
            bl.c += bl.v * dt
            # дрожь: при движении тело вытягивается вдоль скорости
            sp = float(np.linalg.norm(bl.v))
            tgt2 = min(0.28, sp / 2200)
            if sp > 30:
                ang = math.atan2(bl.v[1], bl.v[0])
                d = (ang - bl.ph[0] + math.pi) % (2 * math.pi) - math.pi
                bl.ph[0] += d * min(1, 6 * dt)
            for i, (w, tg) in enumerate(((W2, tgt2), (W3, 0.0), (W2 * 1.3, 0.0))):
                bl.av[i] += (-w * w * (bl.a[i] - tg) - WG * bl.av[i]) * dt
                bl.a[i] += bl.av[i] * dt

        if self.t > self.next_poke and keys:
            self.next_poke = self.t + random.uniform(0.8, 2.2)
            self.wobble(random.choice(keys), random.choice((1, 2)), random.uniform(-0.9, 0.9),
                        random.uniform(0, 2 * math.pi))

        # --- вытяжки: масса из тела, профиль, шейка ---
        frac = {k: 0.0 for k in keys}
        tents = []
        for a, b, pr in live:
            ca, cb = self.blobs[a].c, self.blobs[b].c
            axis = cb - ca
            D = max(1.0, float(np.linalg.norm(axis)))
            axis = axis / D
            m = (ca + cb) / 2
            L = D / 2
            e = max(0.0, min(1.0, pr.e))
            phi = min(0.38, 0.14 + L / 2500) * e          # доля массы, ушедшая в вытяжку
            frac[a] += phi
            frac[b] += phi
            tents.append((a, b, pr, ca, cb, axis, m, L, e, phi))
        for k in keys:
            self.blobs[k].rb = R_BLOB * math.sqrt(max(0.18, 1 - frac[k]))
        shape_t = []
        for a, b, pr, ca, cb, axis, m, L, e, phi in tents:
            necks = []
            segs = []
            for me, c, sgn in ((a, ca, 1), (b, cb, -1)):
                rb = self.blobs[me].rb
                Lp = max(10.0, L - rb * 0.5)
                base = c + axis * sgn * rb * 0.5          # вытяжка растёт из тела
                # шейка тоньшает с растяжением; основание - из сохранения массы:
                # ∫2r dx = phi·M  при  r = r1 + (r0-r1)(1-x/L')^p
                r1 = NECK0 * (L_REF / max(L, 1.0)) ** 1.5
                r0 = r1 + (phi * MASS / (2 * Lp) - r1) * (PROF + 1)
                r0 = max(r1, min(r0, rb * 0.95))
                necks.append(r1)
                tip = base + axis * sgn * Lp * e
                if not pr.conn:
                    r1 = max(18.0, min(r1, 0.32 * rb))      # круглый носик навстречу
                    r0 = max(r0, r1 * 1.8)
                segs.append([base[0], base[1], tip[0], tip[1], r0, max(r1, 0.5), PROF])
            pr.neck = min(necks)
            if pr.conn and pr.neck < R_MIN:
                self.snap(a, b, pr, m, axis)
                continue
            # вытяжка = цепочка шаров-метаболов (поля складываются → плавная перемычка);
            # лёгкое провисание и рябь - общие для всего пролёта, чтобы половинки сходились
            D = 2 * L
            perp = np.array([-axis[1], axis[0]])
            sway = min(segs[0][4], 30) * 0.35 * math.sin(self.t * 1.3 + a * 1.7 + b) * e
            for (bx0, by0, tx, ty, r0, r1, pp), c, sgn in zip(segs, (ca, cb), (1, -1)):
                base = np.array([bx0, by0])
                ln = float(np.hypot(tx - bx0, ty - by0))
                d0 = float(np.linalg.norm(base - c))
                x = 0.0
                while x <= ln:
                    f = x / max(ln, 1e-6)
                    r = r1 + (r0 - r1) * (1 - f) ** pp
                    g = (d0 + x) / D if sgn > 0 else 1 - (d0 + x) / D
                    r *= 1 + 0.07 * math.sin(g * 18 - self.t * 3.5)
                    pos = base + axis * sgn * x + perp * sway * math.sin(math.pi * g)
                    rk = r / UT
                    ds = max(2.5, 0.35 * r)
                    shape_t.append([float(pos[0]), float(pos[1]), rk, ds / (0.914 * rk)])
                    x += ds

        # --- брызги ---
        alive = []
        for d in self.drops:
            p, v, r, age = d
            best, bd = None, 1e9
            for k in keys:
                dist = float(np.linalg.norm(self.blobs[k].c - p))
                if dist < bd:
                    best, bd = k, dist
            if best is not None:
                to = self.blobs[best].c - p
                v += to / max(bd, 1) * 900 * dt
                if bd < self.blobs[best].rb * 0.7:
                    self.wobble(best, 1, 0.5, math.atan2(-to[1], -to[0]))
                    continue
            v *= math.exp(-1.5 * dt)
            p += v * dt
            d[3] += dt
            if d[3] < 4:
                alive.append(d)
        self.drops = alive

        self.shape = {
            "b": [[float(self.blobs[k].c[0]), float(self.blobs[k].c[1]),
                   self.blobs[k].rb * (1 + 0.03 * math.sin(self.t * 1.7 + k * 2.1)),   # дыхание
                   *map(float, np.clip(self.blobs[k].a, -0.26, 0.26)), *map(float, self.blobs[k].ph),
                   *self.blobs[k].contour(self.t)] for k in keys],
            "m": shape_t,
            "d": [[float(d[0][0]), float(d[0][1]), d[2]] for d in self.drops],
        }

    def state(self):
        return dict(self.shape, n=len(self.wins), c=sum(p.conn for p in self.pairs.values()))


def server():
    lockf = open(LOCK, "w")
    fcntl.flock(lockf, fcntl.LOCK_EX)
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            s.connect(SOCK)
            return  # уже работает
        except OSError:
            pass
        s.close()
        try:
            os.unlink(SOCK)
        except FileNotFoundError:
            pass
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(SOCK)
        srv.listen(16)
    finally:
        fcntl.flock(lockf, fcntl.LOCK_UN)
    srv.setblocking(False)
    sim = Sim()
    conns = {}   # sock -> dict(buf, key)
    nextkey = 1
    empty_since = time.monotonic()
    next_tick = time.monotonic()
    frame = 0

    def drop(s):
        sim.drop_window(conns[s]["key"])
        conns.pop(s)
        s.close()

    while True:
        timeout = max(0.0, next_tick - time.monotonic())
        rl, _, _ = select.select([srv] + list(conns), [], [], timeout)
        for s in rl:
            if s is srv:
                try:
                    c, _ = srv.accept()
                    c.setblocking(False)
                    conns[c] = {"buf": b"", "key": nextkey}
                    nextkey += 1
                except OSError:
                    pass
                continue
            info = conns[s]
            try:
                data = s.recv(65536)
            except (BlockingIOError, InterruptedError):
                continue
            except OSError:
                data = b""
            if not data:
                drop(s)
                continue
            info["buf"] += data
            while b"\n" in info["buf"]:
                line, info["buf"] = info["buf"].split(b"\n", 1)
                try:
                    m = json.loads(line)
                    sim.set_window(info["key"], m["rect"], bool(m.get("vis", True)))
                except Exception:
                    pass
        now = time.monotonic()
        if now >= next_tick:
            steps = 0
            while now >= next_tick and steps < 4:
                sim.step()
                next_tick += DT
                steps += 1
            if now > next_tick:
                next_tick = now + DT
            frame += 1
            if sim.wins:
                msg = (json.dumps(sim.state()) + "\n").encode()
                for s, info in list(conns.items()):
                    if info["key"] not in sim.wins:
                        continue
                    try:
                        s.send(msg)
                    except (BlockingIOError, InterruptedError):
                        pass  # клиент не успевает - пропустит кадр
                    except OSError:
                        drop(s)
        if conns:
            empty_since = None
        elif empty_since is None:
            empty_since = time.monotonic()
        elif time.monotonic() - empty_since > 1.5:
            break
    try:
        srv.close()
        os.unlink(SOCK)
    except OSError:
        pass


def connect():
    for attempt in range(60):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            s.connect(SOCK)
            return s
        except OSError:
            s.close()
        if attempt in (0, 30):
            subprocess.Popen([sys.executable, os.path.abspath(__file__), "--server"],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=open(os.path.join(RUN, "kaplya.log"), "a"),
                             start_new_session=True, close_fds=True)
        time.sleep(0.05)
    raise SystemExit("kaplya: не удалось запустить сервер")


# ---------------------------------------------------------------- hyprland
def hypr(cmd):
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        return None
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.5)
    try:
        s.connect(os.path.join(RUN, "hypr", sig, ".socket.sock"))
        s.sendall(cmd.encode())
        out = b""
        while True:
            b = s.recv(65536)
            if not b:
                break
            out += b
        return json.loads(out)
    except Exception:
        return None
    finally:
        s.close()


def hypr_events():
    """Сокет событий Hyprland (socket2): будит клиента при движении окон."""
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        return None
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(os.path.join(RUN, "hypr", sig, ".socket2.sock"))
        s.setblocking(False)
        return s
    except OSError:
        s.close()
        return None


def find_window(tag):
    for _ in range(60):
        for c in hypr("j/clients") or []:
            if tag in c.get("title", ""):
                return c["address"]
        time.sleep(0.05)
    aw = hypr("j/activewindow")
    return aw.get("address") if aw else None


def window_state(addr):
    cl = hypr("j/clients")
    mons = hypr("j/monitors")
    if cl is None:
        return None
    for c in cl:
        if c["address"] == addr:
            vis = True
            if mons:
                act = set()
                for m in mons:
                    act.add(m["activeWorkspace"]["id"])
                    sw = m.get("specialWorkspace", {})
                    if sw.get("id"):
                        act.add(sw["id"])
                vis = c["workspace"]["id"] in act and not c.get("hidden", False)
            return c["at"], c["size"], vis
    return None


# ---------------------------------------------------------------- render
def accent():
    try:
        h = json.load(open(SETTINGS)).get("accent", "#aad2ee").lstrip("#")
        return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float) / 255
    except Exception:
        return np.array([0.67, 0.82, 0.93])




def blur(img, r):
    """Box-размытие по обеим осям через накопленные суммы."""
    out = img
    for ax in (0, 1):
        n = out.shape[ax]
        c = np.cumsum(np.pad(out, [(r + 1, r) if a == ax else (0, 0) for a in (0, 1)], mode="edge"), axis=ax)
        out = (np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=ax) - np.take(c, np.arange(n), axis=ax)) / (2 * r + 1)
    return out


class Renderer:
    T = 0.42                       # порог поверхности
    UT = math.sqrt(1 - 0.42 ** (1 / 3))   # ядро (1-u²)³ = T  при  u = UT
    KU = 3.0                       # мягкое объединение (p-норма)

    def __init__(self, col):
        self.col = col

    def field(self, st, gx, gy, sx, sy, W, H):
        """Поле метаболов (суммой) в сетке W×H с шагом sx×sy от (gx, gy)."""
        F = np.zeros((H, W), np.float32)
        ut = self.UT

        def patch(cx, cy, R):
            x0 = max(0, int((cx - R - gx) / sx)); x1 = min(W, int((cx + R - gx) / sx) + 2)
            y0 = max(0, int((cy - R - gy) / sy)); y1 = min(H, int((cy + R - gy) / sy) + 2)
            if x0 >= x1 or y0 >= y1:
                return None
            xs = gx + (np.arange(x0, x1, dtype=np.float32) + 0.5) * sx - cx
            ys = gy + (np.arange(y0, y1, dtype=np.float32) + 0.5) * sy - cy
            return (slice(y0, y1), slice(x0, x1)), xs[None, :], ys[:, None]

        def ball(cx, cy, Rk, w=1.0):
            pt = patch(cx, cy, Rk)
            if pt:
                sl, dx, dy = pt
                q = np.clip(1 - (dx * dx + dy * dy) / (Rk * Rk), 0, None)
                F[sl] += w * q * q * q

        for cx, cy, rb, a2, a3, a4, p2, p3, p4, *form in st.get("b", []):
            pt = patch(cx, cy, rb * 1.6 / ut)
            if pt:
                sl, dx, dy = pt
                th = np.arctan2(dy, dx)
                k = 1 + a2 * np.cos(2 * (th - p2)) + a3 * np.cos(3 * (th - p3)) * 0.5 \
                    + a4 * np.cos(4 * (th - p4)) * 0.3
                if form:                               # своя неровная форма капли
                    harm = form[0]
                    for i in range(0, len(harm), 3):
                        k = k + harm[i + 1] * np.cos(harm[i] * th - harm[i + 2])
                q = np.clip(1 - (dx * dx + dy * dy) / (rb * k / ut) ** 2, 0, None)
                F[sl] += q * q * q
            if form:
                lx, ly, ls = form[1]
                ball(cx + lx * rb, cy + ly * rb, ls * rb * 0.85 / ut)
        for cx, cy, Rk, w in st.get("m", []):
            ball(cx, cy, Rk, w)
        for cx, cy, r in st.get("d", []):
            ball(cx, cy, r / ut)
        return F

    def visible(self, st, gx, gy, gw, gh):
        m = 2 * R_BLOB
        for cx, cy, *_ in st.get("b", []):
            if gx - m < cx < gx + gw + m and gy - m < cy < gy + gh + m:
                return True
        return bool(st.get("m")) or bool(st.get("d"))

    def bbox(self, st):
        """Глобальный прямоугольник, куда может попасть капля."""
        xs, ys = [], []
        for cx, cy, rb, *_ in st.get("b", []):
            R = rb * 1.75 / self.UT
            xs += [cx - R, cx + R]; ys += [cy - R, cy + R]
        for cx, cy, Rk, w in st.get("m", []):
            xs += [cx - Rk, cx + Rk]; ys += [cy - Rk, cy + Rk]
        for cx, cy, r in st.get("d", []):
            R = r / self.UT
            xs += [cx - R, cx + R]; ys += [cy - R, cy + R]
        return (min(xs), min(ys), max(xs), max(ys)) if xs else None

    def pixels(self, st, gx, gy, cw, ch, cols, rows, t):
        """Для полублоков: cols × 2·rows пикселей, 2×2 выборки на пиксель."""
        return self.image(st, gx, gy, cw, ch / 2, cols, rows * 2, 2)

    def image(self, st, gx, gy, sx, sy, W, H, ss=1):
        """Цвет и непрозрачность сетки W×H (пиксель sx×sy px, начало gx, gy)."""
        F2 = self.field(st, gx, gy, sx / ss, sy / ss, W * ss, H * ss)
        T = self.T
        c2 = np.clip((F2 - T * 0.95) / (T * 0.1), 0, 1)          # мягкий порог
        c2 = c2 * c2 * (3 - 2 * c2)
        a = c2.reshape(H, ss, W, ss).mean((1, 3)) if ss > 1 else c2   # сглаженный край
        # объём: купол из размытой маски (расстояние до края)
        r = max(1, int(round(26 / sx)))
        dome = np.sqrt(np.clip(blur(blur(a, r), r), 0, 1)) * a
        hgt = dome * (80.0 / sx)
        gyy, gxx = np.gradient(hgt)
        nz = 1 / np.sqrt(1 + gxx * gxx + gyy * gyy)
        nx, ny = -gxx * nz, -gyy * nz
        L = np.array([-0.45, -0.62, 0.64])
        L /= np.linalg.norm(L)
        ndl = nx * L[0] + ny * L[1] + nz * L[2]
        diff = np.clip(ndl, 0, 1)
        Hh = L + np.array([0, 0, 1.0])
        Hh /= np.linalg.norm(Hh)
        spec = np.clip(nx * Hh[0] + ny * Hh[1] + nz * Hh[2], 0, 1) ** 18
        rim = np.clip(1 - nz, 0, 1) ** 0.8
        # мягкий блик-пятно сверху слева внутри тела
        o = max(1, int(round(10 / sx)))
        ab = blur(a, max(1, int(round(6 / sx))))
        sh = np.zeros_like(ab)
        sh[o:, o:] = ab[:-o, :-o]
        gloss = np.clip((ab - 0.8) * 5, 0, 1) * np.clip(1 - sh * 1.1, 0, 1)
        gloss = blur(gloss, 1)
        base = self.col[None, None, :]
        body = base * (0.55 + 0.55 * diff[..., None])                  # светлее к свету
        body = body * (1 - 0.42 * rim[..., None])                      # тёмный ободок
        shadow = np.clip(-ndl + 0.25, 0, 1)                            # теневая сторона снизу справа
        body = body * (1 - 0.35 * shadow[..., None])
        # чуть насыщеннее в глубине, как у желе
        depth = np.clip(dome, 0, 1)[..., None]
        body = body * (0.9 + 0.15 * depth)
        rgb = body + (spec[..., None] * 0.75 + gloss[..., None] * 0.55) * (0.6 + 0.4 * base)
        rgb = np.clip(rgb, 0, 1)
        return rgb, a


# ---------------------------------------------------------------- client
class Term:
    def __init__(self):
        self.fd = sys.stdout.fileno()
        self.inp = sys.stdin.fileno()
        self.old = termios.tcgetattr(self.inp) if sys.stdin.isatty() else None

    def w(self, s):
        mv = memoryview(s.encode() if isinstance(s, str) else s)
        while mv:
            try:
                mv = mv[os.write(self.fd, mv):]
            except BlockingIOError:
                select.select([], [self.fd], [], 0.1)
            except InterruptedError:
                pass

    def enter(self, tag):
        if self.old:
            new = termios.tcgetattr(self.inp)
            new[3] &= ~(termios.ECHO | termios.ICANON)
            new[6][termios.VMIN] = 0
            new[6][termios.VTIME] = 0
            termios.tcsetattr(self.inp, termios.TCSANOW, new)
        self.w(f"\x1b[22;2t\x1b[?1049h\x1b[?25l\x1b[?7l\x1b[2J\x1b]2;{tag}\x07")
        self.bg = self.query_bg()
        self.img_on = False
        self.graphics = "--halfblock" not in sys.argv and (
            os.environ.get("TERM") == "xterm-kitty" or "KITTY_WINDOW_ID" in os.environ)

    def query_bg(self):
        """Цвет фона терминала (OSC 11) - для мягкого края."""
        fallback = np.array([0.06, 0.07, 0.09])
        if not self.old:
            return fallback
        self.w("\x1b]11;?\x1b\\")
        buf = b""
        end = time.monotonic() + 0.3
        while time.monotonic() < end:
            r, _, _ = select.select([self.inp], [], [], 0.05)
            if r:
                buf += os.read(self.inp, 256)
                m = re.search(rb"rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+)", buf)
                if m:
                    return np.array([int(g, 16) / (16 ** len(g) - 1) for g in m.groups()])
        return fallback

    def leave(self):
        self.w(f"\x1b_Ga=d,d=I,i={IMG_ID},q=2\x1b\\\x1b[0m\x1b[2J\x1b[?7h\x1b[?25h\x1b[?1049l\x1b[23;2t")
        if self.old:
            termios.tcsetattr(self.inp, termios.TCSANOW, self.old)

    def size(self):
        rows, cols, xp, yp = struct.unpack("HHHH", fcntl.ioctl(self.fd, termios.TIOCGWINSZ, b"\0" * 8))
        return rows, cols, xp, yp


IMG_ID = 7171


def draw_image(term, rend, st, rect, cols, rows):
    """Гладкая капля картинкой kitty graphics protocol (2 px экрана на пиксель)."""
    gx, gy, gw, gh = rect
    s = 2.0
    W, H = int(math.ceil(gw / s)), int(math.ceil(gh / s))
    bb = rend.bbox(st)
    x0 = y0 = x1 = y1 = 0
    if bb:
        x0 = max(0, int((bb[0] - gx) / s)); x1 = min(W, int(math.ceil((bb[2] - gx) / s)))
        y0 = max(0, int((bb[1] - gy) / s)); y1 = min(H, int(math.ceil((bb[3] - gy) / s)))
    if x1 <= x0 or y1 <= y0:
        if term.img_on:
            term.w(f"\x1b_Ga=d,d=I,i={IMG_ID},q=2\x1b\\")
            term.img_on = False
        return
    rgb, a = rend.image(st, gx + x0 * s, gy + y0 * s, s, s, x1 - x0, y1 - y0)
    img = np.zeros((H, W, 4), np.uint8)
    img[y0:y1, x0:x1, :3] = (rgb * 255).astype(np.uint8)
    img[y0:y1, x0:x1, 3] = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    payload = base64.b64encode(zlib.compress(img.tobytes(), 1))
    chunks = [payload[i:i + 4096] for i in range(0, len(payload), 4096)] or [b""]
    out = [b"\x1b7\x1b[1;1H"]
    for i, chn in enumerate(chunks):
        more = 1 if i < len(chunks) - 1 else 0
        hdr = (f"a=T,f=32,o=z,s={W},v={H},i={IMG_ID},p=1,c={cols},r={rows},C=1,z=-1,q=2,m={more}"
               if i == 0 else f"m={more}")
        out.append(b"\x1b_G" + hdr.encode() + b";" + chn + b"\x1b\\")
    out.append(b"\x1b8")
    term.w(b"".join(out))
    term.img_on = True


def client():
    tag = f"kaplya·{os.getpid()}"
    term = Term()
    term.enter(tag)
    resized = [True]

    def bye(*a):
        raise KeyboardInterrupt
    signal.signal(signal.SIGWINCH, lambda *a: resized.__setitem__(0, True))
    signal.signal(signal.SIGTERM, bye)
    signal.signal(signal.SIGHUP, bye)
    sock = None
    try:
        addr = find_window(tag)
        term.w("\x1b]2;капля\x07")
        sock = connect()
        sock.setblocking(False)
        ev = hypr_events()
        rend = Renderer(accent())
        buf = b""
        st = None
        rect = None
        sent = None
        last_geo = 0.0
        geo_now = True
        last_frame = 0.0
        last_acc = time.monotonic()
        prev_lines = []
        rows = cols = xp = yp = 0
        t0 = time.monotonic()
        moved = 0.0
        while True:
            now = time.monotonic()
            if resized[0]:
                resized[0] = False
                rows, cols, xp, yp = term.size()
                term.w("\x1b[0m\x1b[2J")
                prev_lines = []
                geo_now = True
            # геометрия: сразу по событию Hyprland, иначе 20 раз/с (ловит перетаскивание мышью)
            if geo_now or now - last_geo > 0.012:
                geo_now = False
                last_geo = now
                ws = window_state(addr) if addr else None
                if ws:
                    (wx, wy), (ww, wh), vis = ws
                    gw = xp or cols * 9
                    gh = yp or rows * 19
                    rect = [wx + (ww - gw) / 2, wy + (wh - gh) / 2, gw, gh]
                    if (rect, vis) != sent:
                        moved = now
                        sent = (rect, vis)
                        try:
                            sock.sendall((json.dumps({"rect": rect, "vis": vis}) + "\n").encode())
                        except BlockingIOError:
                            pass
                        except OSError:
                            sock = connect()
                            sock.setblocking(False)
                            sent = None
            if now - last_acc > 3:
                last_acc = now
                rend.col = accent()

            rl = [sock, sys.stdin] + ([ev] if ev else [])
            r, _, _ = select.select(rl, [], [], 1 / 120)
            if sys.stdin in r:
                k = os.read(sys.stdin.fileno(), 64)
                if b"q" in k or k == b"\x1b":
                    break
            if ev and ev in r:
                try:
                    e = ev.recv(65536)
                    if not e:
                        ev.close()
                        ev = None
                    elif b"movewindow" in e or b"resizewindow" in e or b"workspace" in e or b"changefloatingmode" in e:
                        geo_now = True
                except BlockingIOError:
                    pass
                except OSError:
                    ev = None
            if sock in r:
                try:
                    data = sock.recv(1 << 20)
                except BlockingIOError:
                    data = None
                except OSError:
                    data = b""
                if data == b"":
                    sock.close()
                    sock = connect()
                    sock.setblocking(False)
                    sent = None
                    buf = b""
                    continue
                if data:
                    buf += data
                    lines = buf.split(b"\n")
                    buf = lines[-1]
                    for ln in reversed(lines[:-1]):
                        try:
                            st = json.loads(ln)
                            break
                        except Exception:
                            continue
            if st is None or rect is None or rows < 2:
                continue
            if time.monotonic() - last_frame < (1 / 50 if now - moved < 0.6 else 1 / 30):
                continue
            last_frame = time.monotonic()

            gx, gy, gw, gh = rect
            cw, ch = gw / cols, gh / rows
            drows = rows
            t = time.monotonic() - t0
            if term.graphics:
                draw_image(term, rend, st, rect, cols, rows)
                continue
            if rend.visible(st, gx, gy, gw, gh):
                rgb, al = rend.pixels(st, gx, gy, cw, ch, cols, drows, t)
                bg = term.bg[None, None, :]
                # край сглаживаем смешиванием с цветом фона терминала
                mix = np.clip(rgb * al[..., None] + bg * (1 - al[..., None]), 0, 1)
                q = (mix * 255).astype(np.int32) & ~3
                on = al > 0.04
            else:
                on = np.zeros((drows * 2, cols), bool)
            out = []
            lines = []
            for y in range(drows):
                to, bo = on[2 * y], on[2 * y + 1]
                if not (to.any() or bo.any()):
                    line = ""
                else:
                    parts = []
                    last = None
                    tq, bq = q[2 * y], q[2 * y + 1]
                    for x in range(cols):
                        tt, bb = to[x], bo[x]
                        if tt and bb:
                            key = ("tb", tq[x, 0], tq[x, 1], tq[x, 2], bq[x, 0], bq[x, 1], bq[x, 2])
                            code = f"[38;2;{tq[x,0]};{tq[x,1]};{tq[x,2]};48;2;{bq[x,0]};{bq[x,1]};{bq[x,2]}m"
                            chr_ = "▀"
                        elif tt:
                            key = ("t", tq[x, 0], tq[x, 1], tq[x, 2])
                            code = f"[49;38;2;{tq[x,0]};{tq[x,1]};{tq[x,2]}m"
                            chr_ = "▀"
                        elif bb:
                            key = ("b", bq[x, 0], bq[x, 1], bq[x, 2])
                            code = f"[49;38;2;{bq[x,0]};{bq[x,1]};{bq[x,2]}m"
                            chr_ = "▄"
                        else:
                            key, code, chr_ = "sp", "[0m", " "
                        if key != last:
                            parts.append(code)
                            last = key
                        parts.append(chr_)
                    line = "".join(parts)
                lines.append(line)
                if y >= len(prev_lines) or prev_lines[y] != line:
                    out.append(f"[{y + 1};1H[0m[2K{line}[0m")
            prev_lines = lines
            if out:
                term.w("".join(out))
    except KeyboardInterrupt:
        pass
    finally:
        term.leave()
        if sock:
            sock.close()


def main():
    a = sys.argv[1:]
    if "--server" in a:
        server()
    else:
        if not sys.stdout.isatty():
            raise SystemExit("kaplya: нужен терминал")
        client()


if __name__ == "__main__":
    main()
