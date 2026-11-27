#!/usr/bin/env python3
"""Sakura Sound backend.

QML runs this as a long-lived process. Protocol: one JSON object per line.
  stdin  ← commands  {"cmd": "search", "q": "…", "id": 7}
  stdout → events    {"ev": "reply", "id": 7, ...} | state | track | queue | wave | auth | error | log

Owns mpv (--idle --no-video, JSON IPC socket). mpv-mpris exposes it on D-Bus, so
the shell's notch / Media tab / lock screen / widgets pick the player up.
Metadata for MPRIS is passed through an in-memory EDL (`!global_tags`) and the
cover through `cover-art-files`.
"""
import json, math, os, random, re, sqlite3, sys, threading, time, traceback
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mpv_ipc import Mpv, MpvError
from sc_api import SC, ApiError, fetch
import extras
try:
    from mpris import Mpris
except Exception:      # no python-gobject → no MPRIS, the player still works
    Mpris = None

HOME = os.path.expanduser("~")
CONF = os.path.join(HOME, ".config/sakura-sound")
CACHE = os.path.join(HOME, ".cache/sakura-sound")
RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "sakura-sound")
STATE_FILE = os.path.join(CONF, "state.json")
SETTINGS_FILE = os.path.join(CONF, "settings.json")
PREFETCH_S = 20
TEST = "--test" in sys.argv

_out = threading.Lock()


def emit(ev, **kw):
    kw["ev"] = ev
    line = json.dumps(kw, ensure_ascii=False, separators=(",", ":"))
    with _out:
        try:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
        except BrokenPipeError:
            os._exit(0)


def log(*a):
    emit("log", msg=" ".join(str(x) for x in a))


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


def esc(s):
    s = str(s)
    return "%%%d%%%s" % (len(s.encode()), s)


def mpris_meta(t):
    """What the shell's notch shows: SoundCloud titles are often "Artist - Track" → split them,
    so the notch says "Track - Artist" instead of "Artist - Track - uploader"."""
    title, artist = t.get("title", "") or "", t.get("artist", "") or ""
    m = re.match(r"^\s*(.+?)\s+[---]\s+(.+?)\s*$", title)
    if m and len(m.group(1)) <= 60:
        return m.group(2), m.group(1)
    return title, artist


def iso_ts(s):
    from datetime import datetime
    try:
        return datetime.fromisoformat((s or "").replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def big_art(url):
    return url.replace("-large.", "-t500x500.") if url else ""


# ── normalisation ──────────────────────────────────────────────
def n_user(u):
    if not u:
        return None
    return {"type": "user", "id": u.get("id"), "name": u.get("username") or "",
            "link": u.get("permalink") or "", "url": u.get("permalink_url") or "",
            "avatar": big_art(u.get("avatar_url") or ""), "followers": u.get("followers_count") or 0,
            "tracks": u.get("track_count") or 0, "city": u.get("city") or "",
            "verified": bool(u.get("verified")), "full": u.get("full_name") or "",
            "desc": u.get("description") or "",
            "banner": ((u.get("visuals") or {}).get("visuals") or [{}])[0].get("visual_url", "") if u.get("visuals") else ""}


def n_track(t, repost_by=None):
    if not t or t.get("kind") not in (None, "track"):
        return None
    u = t.get("user") or {}
    pub = t.get("publisher_metadata") or {}
    return {"type": "track", "id": t.get("id"), "title": t.get("title") or "",
            "artist": u.get("username") or "",
            "artistId": u.get("id"), "artistLink": u.get("permalink") or "",
            "art": big_art(t.get("artwork_url") or u.get("avatar_url") or ""),
            "dur": (t.get("duration") or 0) / 1000.0, "full": (t.get("full_duration") or 0) / 1000.0,
            "snip": t.get("policy") == "SNIP", "block": t.get("policy") == "BLOCK",
            "wave": t.get("waveform_url") or "", "url": t.get("permalink_url") or "",
            "plays": t.get("playback_count") or 0, "likes": t.get("likes_count") or 0,
            "genre": t.get("genre") or "", "created": t.get("created_at") or "",
            "repost": repost_by or "", "stub": "title" not in t,
            # only encrypted streams (DRM): can't be played outside SoundCloud's own apps
            "drm": bool(t.get("media")) and all("encrypted" in ((x.get("format") or {}).get("protocol") or "")
                                                for x in (t.get("media") or {}).get("transcodings") or [])}


def n_playlist(p, repost_by=None):
    if not p:
        return None
    u = p.get("user") or {}
    art = p.get("artwork_url") or p.get("calculated_artwork_url") or ""
    if not art:
        for t in p.get("tracks") or []:
            if t.get("artwork_url"):
                art = t["artwork_url"]; break
    return {"type": "playlist", "id": p.get("id") or p.get("urn"), "urn": p.get("urn") or "",
            "title": p.get("title") or p.get("short_title") or "", "artist": u.get("username") or "",
            "artistId": u.get("id"), "art": big_art(art or u.get("avatar_url") or ""),
            "count": p.get("track_count") or len(p.get("tracks") or []),
            "album": bool(p.get("is_album")) or p.get("set_type") in ("album", "ep", "single"),
            "dur": (p.get("duration") or 0) / 1000.0, "url": p.get("permalink_url") or "",
            "likes": p.get("likes_count") or 0, "repost": repost_by or "",
            "system": p.get("kind") == "system-playlist"}


def n_item(x):
    """Any collection entry → normalised item (or None)."""
    if not isinstance(x, dict):
        return None
    if "context_urn" in x:            # play-history contexts
        for key in ("playlist", "station"):
            if x.get(key):
                return n_playlist(x[key])
        return n_user(x.get("user")) if x.get("user") else None
    k = x.get("kind")
    if k == "track":
        return n_track(x)
    if k in ("playlist", "system-playlist"):
        return n_playlist(x)
    if k == "user":
        return n_user(x)
    # wrappers: likes, history, stream, library
    by = (x.get("user") or {}).get("username") if str(x.get("type", "")).endswith("repost") else None
    if x.get("track"):
        return n_track(x["track"], by)
    if x.get("playlist"):
        return n_playlist(x["playlist"], by)
    if x.get("system_playlist"):
        return n_playlist(x["system_playlist"])
    return None


# ── cache (sqlite) ─────────────────────────────────────────────
class Store:
    def __init__(self, path):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.lock = threading.Lock()
        with self.lock:
            self.db.executescript("""
                create table if not exists tracks(id integer primary key, json text, ts real);
                create table if not exists history(id integer, ts real, secs real);
                create index if not exists hist_ts on history(ts);
                create table if not exists local(kind text, id integer, ts real, json text, primary key(kind, id));
                create table if not exists hidden(kind text, id integer, primary key(kind, id));
            """)
            self.db.commit()

    def put(self, raw_tracks):
        rows = [(t["id"], json.dumps(t, ensure_ascii=False), time.time())
                for t in raw_tracks if t and t.get("id") and "title" in t]
        if not rows:
            return
        with self.lock:
            self.db.executemany("insert or replace into tracks values(?,?,?)", rows)
            self.db.commit()

    def get(self, tid, max_age=6 * 3600):
        with self.lock:
            r = self.db.execute("select json, ts from tracks where id=?", (tid,)).fetchone()
        if r and time.time() - r[1] < max_age:
            return json.loads(r[0])
        return None

    def played(self, tid, secs):
        with self.lock:
            self.db.execute("insert into history values(?,?,?)", (tid, time.time(), secs))
            self.db.commit()

    # local likes / follows (SoundCloud refuses writes from outside the website)
    def local_set(self, kind, item, on):
        with self.lock:
            if on:
                self.db.execute("insert or replace into local values(?,?,?,?)", (kind, item["id"], time.time(), json.dumps(item, ensure_ascii=False)))
                self.db.execute("delete from hidden where kind=? and id=?", (kind, item["id"]))
            else:
                self.db.execute("delete from local where kind=? and id=?", (kind, item["id"]))
                self.db.execute("insert or replace into hidden values(?,?)", (kind, item["id"]))
            self.db.commit()

    def local_items(self, kind):
        with self.lock:
            rows = self.db.execute("select ts, json from local where kind=? order by ts desc", (kind,)).fetchall()
        return [(ts, json.loads(js)) for ts, js in rows]

    def hidden_ids(self, kind):
        with self.lock:
            return {r[0] for r in self.db.execute("select id from hidden where kind=?", (kind,)).fetchall()}

    def stats(self, days=7):
        since = time.time() - days * 86400
        with self.lock:
            rows = self.db.execute(
                "select h.id, count(*), sum(h.secs), t.json from history h left join tracks t on t.id=h.id "
                "where h.ts>? group by h.id order by count(*) desc", (since,)).fetchall()
        return rows


# ── backend ────────────────────────────────────────────────────
class Backend:
    def __init__(self):
        for d in (CONF, CACHE, RUN, os.path.join(CACHE, "covers"), os.path.join(CACHE, "waveforms")):
            os.makedirs(d, exist_ok=True)
        self.settings = read_json(SETTINGS_FILE, {})
        self.sc = SC(browser=self.settings.get("browser", "brave") or None, log=log)
        self.store = Store(os.path.join(CACHE, "meta.sqlite"))
        self.pool = ThreadPoolExecutor(6)
        self.raw = {}              # track id → full api object (has media + track_authorization)
        self.pages = {}            # paging token → (kind, next_href)
        self.queue = []            # normalised tracks
        self.orig = None           # queue before shuffle
        self.idx = -1
        self.pre_idx = None        # index appended to mpv's playlist (gapless next)
        self.prefetching = False
        self.gen = 0               # bumps on every user-initiated load
        self.shuffle = False
        self.repeat = "off"        # off | all | one
        self.vol = 70.0
        self.muted = False
        self.playing = False
        self.paused = True
        self.idle = True
        self.pos = 0.0
        self.dur = 0.0
        self.buffering = False
        self.started = False       # current file produced audio
        self.loading = False       # a new track was asked for; the old file's time-pos is ignored until it plays
        self.starting = False      # shown as "buffering" from the click until the new track's audio really starts
        self.retries = 0
        self.counted = False       # history written for the current play
        self.lock = threading.RLock()
        self._last_state = None
        self._last_pos_sent = -9
        self._last_save = 0
        self.af = {}               # audio filter chain parts by name (plugins)
        self.discord = extras.Discord(log)
        self.mpris = None
        self._mp_key = None
        self._loaded_gen = -1
        self.ready_cache = {}      # track id → (edl, cover, time): the next track resolved ahead (links live a few minutes)
        # one mpv (a two-mpv crossfade was tried and removed: too fragile); next tracks are gapless
        self.mpvs = [Mpv(os.path.join(RUN, "mpv-test.sock" if TEST else "mpv.sock"), on_event=lambda ev: self.on_mpv(ev, 0))]
        self.ai = 0

    @property
    def mpv(self):
        return self.mpvs[self.ai]

    def af_chain(self, xvol=1.0):
        return ",".join(self.af[k] for k in sorted(self.af))

    def stop_all(self):
        for m in self.mpvs:
            try:
                m.stop()
            except Exception:
                pass

    # ── startup ────────────────────────────────────────────────
    def start(self):
        st = read_json(STATE_FILE, {})
        self.vol = float(st.get("volume", 70))
        self.queue = [t for t in st.get("queue", []) if t and t.get("id")]
        self.idx = min(int(st.get("idx", -1)), len(self.queue) - 1)
        self.pos = float(st.get("pos", 0)) if self.idx >= 0 else 0
        self.shuffle = bool(st.get("shuffle"))
        self.repeat = st.get("repeat", "off")
        if Mpris and not TEST:
            try:
                self.mpris = Mpris(self, log)
            except Exception as e:
                log("mpris:", e)
        for m in self.mpvs:
            m.start()
            for p in ("time-pos", "duration", "pause", "idle-active", "playlist-pos", "volume", "mute",
                      "paused-for-cache", "core-idle"):
                m.observe(p)
            m.set("volume", self.vol)
            m.set("af", self.af_chain())
        self.mpv.set("loop-file", "inf" if self.repeat == "one" else "no")
        emit("ready")
        self.emit_queue()
        if 0 <= self.idx < len(self.queue):
            self.dur = self.queue[self.idx].get("dur", 0)
            emit("track", track=self.queue[self.idx], idx=self.idx)
            # load it paused, so MPRIS (notch, Media card, lock screen) shows title/artist/cover right away
            self.pool.submit(self.play_index, self.idx, self.pos, True)
            self.pool.submit(self.load_wave, self.queue[self.idx])
            self.pool.submit(self.palette, self.queue[self.idx])
        self.emit_state(force=True)
        self.pool.submit(self.check_auth)

    def check_auth(self):
        try:
            me = self.sc.whoami()
        except Exception as e:
            emit("auth", ok=False, user=None, err=str(e), browser=self.sc.browser or "")
            return
        err = getattr(self.sc, "browser_failed", None) or ""
        if me:
            self._auth_retries = 0
            emit("auth", ok=True, browser=self.sc.browser or "",
                 user=n_user(me), go=bool((me.get("consumer_subscription") or {}).get("product")),
                 likes=me.get("likes_count") or 0)
        else:
            emit("auth", ok=False, user=None, browser=self.sc.browser or "", err=err)
            # still a guest: try again in a minute (keyring locked / browser not started yet at login)
            if self.sc.browser and getattr(self, "_auth_retries", 0) < 30:
                self._auth_retries = getattr(self, "_auth_retries", 0) + 1
                threading.Timer(60, lambda: self.pool.submit(self.check_auth)).start()

    # ── state out ──────────────────────────────────────────────
    def emit_state(self, force=False):
        s = {"playing": self.playing, "dur": round(self.dur, 2), "vol": round(self.vol, 1),
             "muted": self.muted, "buffering": self.buffering or self.starting, "shuffle": self.shuffle,
             "repeat": self.repeat, "idx": self.idx}
        if force or s != self._last_state or abs(self.pos - self._last_pos_sent) >= 0.25:
            self._last_state = s
            self._last_pos_sent = self.pos
            emit("state", pos=round(self.pos, 2), **s)
        self.mpris_sync()
        if time.time() - self._last_save > 10:
            self.save()

    def mpris_sync(self):
        if not self.mpris:
            return
        cur = self.cur()
        cid = cur.get("id") if cur else None
        cover = ""
        if cur:
            p = os.path.join(CACHE, "covers", "%s.jpg" % cid)
            if self._mp_key == (cid, True) or os.path.exists(p):
                cover = p
        key = (cid, bool(cover))
        if key != self._mp_key:
            self._mp_key = key
            title, artist = mpris_meta(cur) if cur else ("", "")
            self.mpris.set_track(cur, cover, title, artist)
        self.mpris.changed()

    def emit_queue(self):
        emit("queue", items=self.queue, idx=self.idx)

    def save(self):
        self._last_save = time.time()
        if TEST:
            return
        try:
            write_json(STATE_FILE, {"volume": self.vol, "queue": self.queue[-500:] if len(self.queue) > 500 else self.queue,
                                    "idx": self.idx, "pos": self.pos, "shuffle": self.shuffle, "repeat": self.repeat})
        except Exception as e:
            log("save:", e)

    # ── mpv events ─────────────────────────────────────────────
    def on_mpv(self, ev, src=0):
        e = ev.get("event")
        if src != self.ai:              # the other mpv (idle, or the track fading out) never touches the state
            if e == "mpv-died":
                self.restart_mpv(src)
            return
        if e == "property-change":
            n, v = ev.get("name"), ev.get("data")
            with self.lock:
                if n == "time-pos" and v is not None:
                    if self.loading:
                        return          # still the previous file talking - the timeline stays at the new start
                    self.pos = v
                    if v > 0.3:
                        if self.starting:
                            self.pool.submit(self.warm_next, self.gen)
                        if self.starting and self.mpris:
                            self.mpris.seeked(v)        # MPRIS clients re-sync their clock to the real start
                        self.starting = False           # audio really started
                        self.started = True
                        self.retries = 0
                    if not self.counted and v > 30:
                        self.counted = True
                        cur = self.cur()
                        if cur:
                            self.store.played(cur["id"], v)
                    self.maybe_prefetch()
                elif n == "duration" and v:
                    self.dur = v
                elif n == "pause":
                    self.paused = bool(v)
                    self.playing = not self.paused and not self.idle
                elif n == "core-idle":
                    pass
                elif n == "volume" and v is not None:
                    self.vol = v
                elif n == "mute":
                    self.muted = bool(v)
                elif n == "paused-for-cache":
                    self.buffering = bool(v)
                elif n == "playlist-pos":
                    if v == 1 and self.pre_idx is not None:
                        self.advance_to_prefetched()
                elif n == "idle-active":
                    self.idle = bool(v)
                    self.playing = not self.paused and not self.idle
                    if v:
                        if self.started and not self.prefetching:
                            self.started = False
                            self.pool.submit(self.auto_next)
                self.emit_state()
        elif e == "end-file":
            reason = ev.get("reason")
            if reason == "error":
                with self.lock:
                    if ev.get("playlist_entry_id") is not None and self.pre_idx is not None and self.mpv_count() > 1:
                        pass
                    self.pool.submit(self.on_error, ev.get("file_error", ""))
        elif e == "playback-restart":
            with self.lock:
                if self.loading and self._loaded_gen == self.gen:
                    self.loading = False
                self.buffering = False
                self.emit_state(force=True)
        elif e == "file-loaded":
            with self.lock:
                if self.loading and self._loaded_gen == self.gen:
                    self.loading = False
        elif e == "start-file":
            with self.lock:
                self.counted = False
        elif e == "mpv-died":
            self.restart_mpv(src)
            self.playing = False
            self.emit_state(force=True)

    def restart_mpv(self, i):
        log("mpv %d died, restarting" % i)
        time.sleep(0.5)
        try:
            m = self.mpvs[i]
            m.start()
            m.set("volume", self.vol)
            m.set("af", self.af_chain())
        except Exception as ex:
            emit("error", msg="mpv: %s" % ex)

    def mpv_has_file(self):
        return self.idx >= 0

    def mpv_count(self):
        try:
            return self.mpv.get("playlist-count", 0) or 0
        except Exception:
            return 0

    def cur(self):
        return self.queue[self.idx] if 0 <= self.idx < len(self.queue) else None

    # ── resolving ──────────────────────────────────────────────
    def full_track(self, t, fresh=False):
        tid = t["id"]
        if not fresh:
            raw = self.raw.get(tid)
            if raw and raw.get("media"):
                return raw
        raw = self.sc.get("/tracks/%s" % tid)
        self.raw[tid] = raw
        self.store.put([raw])
        return raw

    def resolve(self, t):
        """→ (edl url, cover path). Tries the fast api path, then yt-dlp."""
        hit = self.ready_cache.pop(t.get("id"), None)
        if hit and time.time() - hit[2] < 240:
            return hit[0], hit[1]
        cover_f = self.pool.submit(self.cover_file, t)
        url = None
        last = None
        for fresh in (False, True):
            try:
                raw = self.full_track(t, fresh=fresh)
                url = self.sc.stream_url(raw)[0]
                break
            except Exception as e:
                last = e
        if not url and "encrypted" in str(last):
            raise ApiError("can't play: DRM-only track")      # yt-dlp would only say the same, slowly
        if not url:
            try:
                url = self.sc.stream_url_ytdlp(t["url"])[0]
            except Exception as e:
                raise ApiError("can't play: %s / %s" % (last, e))
        edl = self.segments_edl(url) or url
        try:
            cover = cover_f.result(8)
        except Exception:
            cover = ""
        return edl, cover

    def warm_next(self, gen):
        """Resolve the next track while this one plays, so "next" only has to start mpv."""
        try:
            n = self.next_index(manual=True)
            if n is None or gen != self.gen:
                return
            t = self.queue[n]
            if t.get("id") in self.ready_cache:
                return
            edl, cover = self.resolve(t)
            self.ready_cache = {k: v for k, v in self.ready_cache.items() if time.time() - v[2] < 240}
            self.ready_cache[t["id"]] = (edl, cover, time.time())
        except Exception as e:
            log("warm:", e)

    def segments_edl(self, url):
        """HLS → an EDL list of its segments (mp4_dash init + fragments with lengths).
        ffmpeg's HLS demuxer probes for ~2.2 s before the first sound; mpv fetching the fragments itself starts in ~0.6 s.
        Any surprise (encryption, no segments) → None, and the plain URL is used."""
        if ".m3u8" not in url:
            return None
        try:
            pl = fetch(url, timeout=6).decode("utf-8", "replace")
        except Exception as e:
            log("playlist:", e)
            return None
        if "#EXT-X-KEY" in pl and "METHOD=NONE" not in pl:
            return None
        init = re.search(r'#EXT-X-MAP:URI="([^"]+)"', pl)
        parts, dur = [], None
        for line in pl.splitlines():
            m = re.match(r"#EXTINF:([\d.]+)", line)
            if m:
                dur = float(m.group(1))
            elif line and not line.startswith("#"):
                seg = line if line.startswith("http") else url.rsplit("/", 1)[0] + "/" + line
                parts.append(esc(seg) + (",length=%s" % dur if dur else ""))
                dur = None
        if not parts:
            return None
        return "edl://" + ("!mp4_dash,init=" + esc(init.group(1)) + ";" if init else "") + ";".join(parts)

    def cover_file(self, t):
        if not t.get("art"):
            return ""
        p = os.path.join(CACHE, "covers", "%s.jpg" % t["id"])
        if not os.path.exists(p):
            data = fetch(t["art"])
            part = "%s.part%d" % (p, threading.get_ident())   # two threads may fetch the same cover
            with open(part, "wb") as f:
                f.write(data)
            os.replace(part, p)
        return p

    def load_opts(self, cover, start=0, pause=False, title=""):
        o = {}
        if title:
            o["force-media-title"] = title   # mpv-mpris xesam:title - never the m3u8 name
        if cover:
            o["cover-art-files"] = cover
        if start:
            o["start"] = "%.2f" % start
        if pause:
            o["pause"] = "yes"
        return o

    # ── playback ───────────────────────────────────────────────
    def play_index(self, i, start=0.0, pause=False):
        with self.lock:
            if not (0 <= i < len(self.queue)):
                return
            self.gen += 1
            gen = self.gen
            self.idx = i
            self.pre_idx = None
            self.started = False
            self.counted = False
            t = self.queue[i]
            self.dur = t.get("dur", 0)
            self.pos = start
            self.buffering = True
            self.loading = True
            self.starting = not pause
            self._loaded_gen = -1
            try:
                if not self.idle:
                    self.mpv.command("set_property", "pause", True, wait=False)   # the old track stops right away
            except MpvError:
                pass
            emit("track", track=t, idx=i)
            emit("queue_idx", idx=i)
            self.emit_state(force=True)
        self.pool.submit(self.load_wave, t)
        self.pool.submit(self.palette, t)
        try:
            edl, cover = self.resolve(t)
        except Exception as e:
            with self.lock:
                if gen != self.gen:
                    return
                self.buffering = False
                self.loading = False
                self.starting = False
            emit("error", msg=str(e), track=t.get("title"))
            # skip unplayable track
            n = self.next_index(manual=False)
            if n is not None and n != i and self.retries < 5:
                self.retries += 1
                self.play_index(n, 0.0, pause)     # keep a paused restore paused
            return
        with self.lock:
            if gen != self.gen:
                return
            try:
                self._loaded_gen = gen
                self.mpv.command("loadfile", edl, "replace", -1, self.load_opts(cover, start, pause, mpris_meta(t)[0]))
                if not pause:
                    self.mpv.set("pause", False)
            except MpvError as e:
                emit("error", msg="mpv: %s" % e)
            self.save()

    def next_index(self, manual=True):
        if not self.queue:
            return None
        if self.repeat == "one" and not manual:
            return self.idx
        n = self.idx + 1
        if n >= len(self.queue):
            return 0 if self.repeat == "all" else None
        return n

    def maybe_prefetch(self):
        if self.prefetching or self.pre_idx is not None or self.repeat == "one":
            return
        if self.dur <= 0 or self.dur - self.pos > PREFETCH_S or not self.started:
            return
        n = self.next_index(manual=False)
        if n is None or n == self.idx:
            return
        self.prefetching = True
        self.pool.submit(self.prefetch, n, self.gen)

    def prefetch(self, n, gen):
        try:
            t = self.queue[n]
            edl, cover = self.resolve(t)
            with self.lock:
                if gen != self.gen or self.queue[n] is not t:
                    return
                if self.mpv.get("idle-active"):
                    return  # current already ended; auto_next will handle it
                self.mpv.command("loadfile", edl, "append", -1, self.load_opts(cover, title=mpris_meta(t)[0]))
                self.pre_idx = n
        except Exception as e:
            log("prefetch failed:", e)
        finally:
            self.prefetching = False

    def advance_to_prefetched(self):
        self.idx = self.pre_idx
        self.pre_idx = None
        self.started = False
        self.counted = False
        t = self.cur()
        self.dur = t.get("dur", 0) if t else 0
        try:
            self.mpv.command("playlist-remove", 0, wait=False)
        except MpvError:
            pass
        emit("track", track=t, idx=self.idx)
        emit("queue_idx", idx=self.idx)
        self.pool.submit(self.load_wave, t)
        self.pool.submit(self.palette, t)

    def drop_prefetch(self):
        if self.pre_idx is not None:
            try:
                if self.mpv_count() > 1:
                    self.mpv.command("playlist-remove", 1)
            except MpvError:
                pass
            self.pre_idx = None

    def auto_next(self):
        time.sleep(0.05)
        with self.lock:
            if self.mpv.get("idle-active") is False:
                return
            n = self.next_index(manual=False)
        if n is None:
            with self.lock:
                self.playing = False
                self.pos = 0
                self.emit_state(force=True)
            emit("ended")
            return
        self.play_index(n)

    def on_error(self, msg):
        with self.lock:
            cur = self.cur()
            pos = self.pos
            if not cur:
                return
            self.retries += 1
            retry = self.retries <= 2
            self.raw.pop(cur["id"], None)   # stream url probably expired
        if retry:
            log("playback error, re-resolving:", msg)
            self.play_index(self.idx, start=pos)
        else:
            emit("error", msg="playback: %s" % msg, track=cur.get("title"))
            n = self.next_index(manual=False)
            if n is not None and n != self.idx:
                self.retries = 0
                self.play_index(n)

    # ── palette (dynamic accent) ───────────────────────────────
    def palette(self, t):
        """Most saturated, not-too-dark tone of the cover → {"ev": "palette"}."""
        import colorsys, subprocess
        try:
            path = self.cover_file(t)
            if not path:
                return
            out = subprocess.run(["magick", path, "-resize", "64x64", "-colors", "8", "-format", "%c", "histogram:info:"],
                                 capture_output=True, text=True, timeout=6).stdout
            best = None
            for line in out.splitlines():
                m = re.search(r"^\s*(\d+):.*#([0-9A-Fa-f]{6})", line)
                if not m:
                    continue
                n, hx = int(m.group(1)), m.group(2)
                r, g, b = (int(hx[i:i + 2], 16) / 255 for i in (0, 2, 4))
                h, l, sat = colorsys.rgb_to_hls(r, g, b)
                score = sat * (0.4 + min(n, 600) / 600) * (1 if 0.15 < l < 0.9 else 0.3)
                if best is None or score > best[0]:
                    best = (score, h, l, sat)
            if not best or best[3] < 0.15:
                emit("palette", id=t["id"], color="")
                return
            _, h, l, sat = best
            l = min(0.78, max(0.62, l))
            sat = min(0.85, max(0.45, sat))
            r, g, b = colorsys.hls_to_rgb(h, l, sat)
            emit("palette", id=t["id"], color="#%02x%02x%02x" % (int(r * 255), int(g * 255), int(b * 255)))
        except Exception as e:
            log("palette:", e)

    # ── waveform ───────────────────────────────────────────────
    def load_wave(self, t, bars=180):
        if not t or not t.get("wave"):
            emit("wave", id=t.get("id") if t else None, samples=[])
            return
        p = os.path.join(CACHE, "waveforms", "%s.json" % t["id"])
        samples = read_json(p, None)
        if samples is None:
            try:
                w = json.loads(fetch(t["wave"]))
                s, h = w.get("samples") or [], float(w.get("height") or 140)
                if s:
                    step = len(s) / bars
                    samples = [round(max(s[int(i * step):max(int(i * step) + 1, int((i + 1) * step))]) / h, 3)
                               for i in range(bars)]
                else:
                    samples = []
                write_json(p, samples)
            except Exception as e:
                log("wave:", e)
                samples = []
        emit("wave", id=t["id"], samples=samples)

    # ── collections ────────────────────────────────────────────
    def endpoint(self, kind, arg):
        if kind in ("likes", "following", "playlist_likes", "my_playlists") and not self.sc.me:
            self.sc.whoami()
        me = (self.sc.me or {}).get("id")
        m = {
            "search": ("/search/tracks", {"q": arg}),
            "search_tracks": ("/search/tracks", {"q": arg}),
            "search_users": ("/search/users", {"q": arg}),
            "search_playlists": ("/search/playlists_without_albums", {"q": arg}),
            "search_albums": ("/search/albums", {"q": arg}),
            "likes": ("/users/%s/track_likes" % me, {}),
            "history": ("/me/play-history/tracks", {}),
            "feed": ("/stream", {"promoted_playlist": "true"}),
            "following": ("/users/%s/followings" % me, {}),
            "library": ("/me/library/all", {}),
            "playlist_likes": ("/users/%s/playlist_likes" % me, {}),
            "my_playlists": ("/users/%s/playlists" % me, {}),
            "contexts": ("/me/play-history/contexts", {}),
            "user_tracks": ("/users/%s/tracks" % arg, {}),
            "user_top": ("/users/%s/toptracks" % arg, {}),
            "user_likes": ("/users/%s/track_likes" % arg, {}),
            "user_playlists": ("/users/%s/playlists_without_albums" % arg, {}),
            "user_albums": ("/users/%s/albums" % arg, {}),
            "user_reposts": ("/stream/users/%s/reposts" % arg, {}),
            "related": ("/tracks/%s/related" % arg, {}),
            "comments": ("/tracks/%s/comments" % arg, {"threaded": 0, "filter_replies": 1, "sort": "timestamp"}),
        }
        if kind not in m:
            raise ApiError("unknown list: %s" % kind)
        if kind in ("likes", "following", "history", "feed", "library", "playlist_likes", "my_playlists", "contexts") and not self.sc.token:
            raise ApiError("not signed in", 401)
        return m[kind]

    def hydrate(self, items):
        """Fill stub tracks ({id, kind}) with full objects via /tracks?ids=."""
        stubs = [x["id"] for x in items if x and x.get("type") == "track" and x.get("stub")]
        if not stubs:
            return [x for x in items if x]
        full = {}
        for tid in stubs:
            c = self.store.get(tid)
            if c:
                full[tid] = c
        need = [t for t in stubs if t not in full]
        for i in range(0, len(need), 50):
            try:
                got = self.sc.get("/tracks", {"ids": ",".join(str(x) for x in need[i:i + 50])})
                self.store.put(got)
                for g in got:
                    full[g["id"]] = g
                    self.raw[g["id"]] = g
            except ApiError as e:
                log("hydrate:", e)
        out = []
        for x in items:
            if x and x.get("type") == "track" and x.get("stub"):
                f = full.get(x["id"])
                x = n_track(f) if f else None
            if x:
                out.append(x)
        return out

    def remember(self, raws):
        tr = []
        for x in raws:
            t = x.get("track") if isinstance(x, dict) and x.get("track") else x
            if isinstance(t, dict) and t.get("kind") == "track" and t.get("media"):
                self.raw[t["id"]] = t
                tr.append(t)
        self.store.put(tr)

    def list_page(self, kind, arg=None, nxt=None, limit=30):
        if nxt:
            raws, nh = self.sc.page(nxt)
        else:
            path, params = self.endpoint(kind, arg)
            raws, nh = self.sc.page(path, params, limit=limit)
        self.remember(raws)
        if kind == "comments":
            items = [{"type": "comment", "t": (c.get("timestamp") or 0) / 1000.0, "body": c.get("body") or "",
                      "user": (c.get("user") or {}).get("username") or "",
                      "avatar": (c.get("user") or {}).get("avatar_url") or ""} for c in raws]
        else:
            items = self.hydrate([n_item(x) for x in raws])
            seen = set()
            out = []
            for x in items:
                k = (x.get("type"), x.get("id"))
                if k in seen or not (x.get("title") or x.get("name")):
                    continue
                seen.add(k)
                out.append(x)
            items = out
        token = None
        if nh:
            token = "p%d" % (len(self.pages) + 1)
            self.pages[token] = (kind, nh)
        return items, token

    def merged_page(self, kind, nh=None, pend=None, first=True, limit=30):
        """Likes / followings = SoundCloud ∪ local (player-only), newest first, minus what was un-liked here."""
        hk = "like" if kind == "likes" else "follow"
        hidden = self.store.hidden_ids(hk)
        if first:
            pend = self.store.local_items(hk)
        sc, nh2 = [], None
        if self.sc.token and (first or nh):
            try:
                if first:
                    path, params = self.endpoint(kind, None)
                    raws, nh2 = self.sc.page(path, params, limit=limit)
                else:
                    raws, nh2 = self.sc.page(nh)
                self.remember(raws)
                for x in raws:
                    it = n_item(x)
                    if it:
                        sc.append((iso_ts(x.get("created_at")) if kind == "likes" else 0, it))
            except ApiError as e:
                log("merged %s: %s" % (kind, e))
        pend = pend or []
        if kind == "likes" and nh2 and sc:
            cut = min(ts for ts, _ in sc)
            take, rest = [p for p in pend if p[0] >= cut], [p for p in pend if p[0] < cut]
        else:
            take, rest = pend, []
        combined = take + sc if kind == "following" else sorted(take + sc, key=lambda p: -p[0])
        seen, items = set(), []
        for _, it in combined:
            if not it or it.get("id") in seen or it.get("id") in hidden:
                continue
            seen.add(it["id"])
            items.append(it)
        token = None
        if nh2 or rest:
            token = "p%d" % (len(self.pages) + 1)
            self.pages[token] = (kind, nh2, rest)
        return items, token

    def playlist(self, pid):
        if isinstance(pid, str) and pid.startswith("soundcloud:system-playlists"):
            p = self.sc.get("/system-playlists/%s" % pid)
        else:
            p = self.sc.get("/playlists/%s" % pid, {"representation": "full"})
        raws = p.get("tracks") or []
        self.remember(raws)
        tracks = self.hydrate([n_track(t) if "title" in t else {"type": "track", "id": t["id"], "stub": True}
                               for t in raws if t.get("id")])
        return n_playlist(p), tracks

    def user(self, uid):
        u = self.sc.get("/users/%s" % uid)
        return n_user(u)

    def resolve_url(self, url):
        d = self.sc.get("/resolve", {"url": url})
        self.remember([d])
        return n_item(d)

    # ── commands ───────────────────────────────────────────────
    def handle(self, c):
        cmd = c.get("cmd")
        rid = c.get("id")
        fn = getattr(self, "c_" + str(cmd), None)
        if not fn:
            emit("error", id=rid, msg="unknown command %s" % cmd)
            return
        try:
            res = fn(c)
            if rid is not None:
                emit("reply", rid=rid, **(res or {}))
        except ApiError as e:
            if e.status == 401:
                self.pool.submit(self.check_auth)
            emit("reply", rid=rid, err=str(e), status=e.status)
        except Exception as e:
            log(traceback.format_exc())
            emit("reply", rid=rid, err=str(e))

    # instant (run on the reader thread)
    INSTANT = {"toggle", "pause", "resume", "seek", "volume", "mute", "shuffle", "repeat", "move", "remove",
               "clear", "state", "af", "speed", "stop", "afcmd", "gapless", "crossfade"}

    def c_state(self, c):
        self.emit_queue()
        cur = self.cur()
        if cur:
            emit("track", track=cur, idx=self.idx)
            self.pool.submit(self.load_wave, cur)
            self.pool.submit(self.palette, cur)
        self.emit_state(force=True)
        self.pool.submit(self.check_auth)

    def c_toggle(self, c):
        if not self.queue:
            return
        idle = self.mpv.get("idle-active")
        if idle and 0 <= self.idx < len(self.queue):
            self.pool.submit(self.play_index, self.idx, self.pos if self.pos < self.dur - 1 else 0)
            return
        self.mpv.set("pause", not self.mpv.get("pause"))

    def c_pause(self, c):
        self.mpv.set("pause", True)

    def c_resume(self, c):
        if self.mpv.get("idle-active"):
            return self.c_toggle(c)
        self.mpv.set("pause", False)

    def c_stop(self, c):
        self.gen += 1
        self.mpv.command("stop")
        self.started = False
        self.starting = False
        self.playing = False
        self.emit_state(force=True)

    def c_seek(self, c):
        t = max(0.0, float(c.get("t", 0)))
        if self.mpv.get("idle-active"):
            if self.cur():
                self.pool.submit(self.play_index, self.idx, t)
            return
        try:
            self.mpv.command("seek", t, "absolute")
        except MpvError:
            return
        if self.mpris:
            self.mpris.seeked(t)
        with self.lock:
            self.pos = t
            if self.pre_idx is not None and self.dur - t > PREFETCH_S:
                self.drop_prefetch()
            self.emit_state(force=True)

    def c_volume(self, c):
        if "v" not in c:
            return {"err": "volume: no value"}
        v = max(0.0, min(130.0, float(c["v"])))
        for m in self.mpvs:
            m.set("volume", v)
        self.vol = v
        self.emit_state(force=True)

    def c_mute(self, c):
        on = not self.mpv.get("mute")
        for m in self.mpvs:
            m.set("mute", on)

    def c_speed(self, c):
        for m in self.mpvs:
            m.set("speed", float(c.get("v", 1.0)))

    def c_crossfade(self, c):
        """Crossfade was removed; kept as a no-op for old plugins."""
        return {}

    def c_af(self, c):
        """Plugins set named audio filters: {"name": "eq", "value": "equalizer=…"} (empty = remove)."""
        name, val = c.get("name"), c.get("value") or ""
        if val:
            self.af[name] = val
        else:
            self.af.pop(name, None)
        chain = self.af_chain()
        try:
            for m in self.mpvs:
                m.set("af", chain)
        except MpvError as e:
            return {"err": "af: %s" % e}
        return {"af": chain}

    def c_afcmd(self, c):
        """Talk to a labelled filter without rebuilding the chain (glitch-free fades)."""
        try:
            args = ["af-command", c["label"], c["op"], str(c["arg"])]
            if c.get("target"):
                args.append(c["target"])   # filter name inside a lavfi=[…] graph
            for m in self.mpvs:
                m.command(*args)
        except MpvError as e:
            return {"err": str(e)}

    def c_gapless(self, c):
        for m in self.mpvs:
            m.set("gapless-audio", c.get("mode", "weak"))

    def c_shuffle(self, c):
        with self.lock:
            self.drop_prefetch()
            on = c.get("on", not self.shuffle)
            cur = self.cur()
            if on and not self.shuffle:
                self.orig = list(self.queue)
                rest = self.queue[self.idx + 1:]
                random.shuffle(rest)
                self.queue = self.queue[:self.idx + 1] + rest
            elif not on and self.shuffle and self.orig is not None:
                ids = {id(t) for t in self.queue}
                base = [t for t in self.orig if id(t) in ids]
                extra = [t for t in self.queue if id(t) not in {id(b) for b in base}]
                self.queue = base + extra
                self.idx = next((i for i, t in enumerate(self.queue) if t is cur), self.idx)
                self.orig = None
            self.shuffle = bool(on)
            self.emit_queue()
            self.emit_state(force=True)

    def c_repeat(self, c):
        with self.lock:
            m = c.get("mode") or {"off": "all", "all": "one", "one": "off"}[self.repeat]
            self.repeat = m
            self.mpv.set("loop-file", "inf" if m == "one" else "no")
            if m == "one":
                self.drop_prefetch()
            self.emit_state(force=True)

    def c_move(self, c):
        a, b = int(c["from"]), int(c["to"])
        with self.lock:
            if not (0 <= a < len(self.queue) and 0 <= b < len(self.queue)) or a == b:
                return
            self.drop_prefetch()
            t = self.queue.pop(a)
            self.queue.insert(b, t)
            if self.idx == a:
                self.idx = b
            elif a < self.idx <= b:
                self.idx -= 1
            elif b <= self.idx < a:
                self.idx += 1
            self.emit_queue()

    def c_remove(self, c):
        i = int(c["i"])
        with self.lock:
            if not (0 <= i < len(self.queue)):
                return
            self.drop_prefetch()
            if i == self.idx:
                self.queue.pop(i)
                if not self.queue:
                    self.idx = -1
                    self.mpv.command("stop")
                else:
                    self.idx = min(i, len(self.queue) - 1)
                    if self.playing:
                        self.pool.submit(self.play_index, self.idx)
                    else:
                        emit("track", track=self.cur(), idx=self.idx)
            else:
                self.queue.pop(i)
                if i < self.idx:
                    self.idx -= 1
            self.emit_queue()

    def c_clear(self, c):
        """Drop everything except the current track."""
        with self.lock:
            self.drop_prefetch()
            cur = self.cur()
            self.queue = [cur] if cur else []
            self.idx = 0 if cur else -1
            self.orig = None
            self.emit_queue()

    # threaded
    def c_play(self, c):
        """{"tracks": [...], "index": i} replaces the queue; {"index": i} jumps inside it."""
        with self.lock:
            if c.get("tracks") is not None:
                self.drop_prefetch()
                self.queue = [t for t in c["tracks"] if t and t.get("type", "track") == "track"]
                self.orig = None
                i = int(c.get("index", 0))
                if self.shuffle and len(self.queue) > 1:
                    self.orig = list(self.queue)
                    first = self.queue.pop(i)
                    random.shuffle(self.queue)
                    self.queue.insert(0, first)
                    i = 0
                self.emit_queue()
            else:
                i = int(c.get("index", 0))
        self.play_index(i)

    def c_enqueue(self, c):
        with self.lock:
            tracks = c.get("tracks") or ([c["track"]] if c.get("track") else [])
            if c.get("next"):
                at = self.idx + 1
                self.drop_prefetch()
                self.queue[at:at] = tracks
            else:
                self.queue.extend(tracks)
            if self.idx < 0 and self.queue:
                self.idx = 0
                emit("track", track=self.cur(), idx=0)
            self.emit_queue()
        return {"n": len(tracks)}

    def c_next(self, c):
        with self.lock:
            n = self.next_index(manual=True)
        if n is not None:
            self.play_index(n)

    def c_prev(self, c):
        if self.pos > 3 and not self.mpv.get("idle-active"):
            try:
                self.mpv.command("seek", 0, "absolute")
                return
            except MpvError:
                pass
        with self.lock:
            p = self.idx - 1
            if p < 0:
                p = len(self.queue) - 1 if self.repeat == "all" else 0
        self.play_index(p)

    def c_list(self, c):
        nxt = None
        if c.get("kind") in ("likes", "following") or (c.get("next") and (self.pages.get(c["next"]) or ("",))[0] in ("likes", "following")):
            if c.get("next"):
                e = self.pages.get(c["next"])
                if not e:
                    return {"items": [], "next": None}
                items, token = self.merged_page(e[0], e[1], e[2] if len(e) > 2 else [], first=False)
                return {"items": items, "next": token, "kind": e[0]}
            items, token = self.merged_page(c["kind"], first=True, limit=int(c.get("limit", 30)))
            return {"items": items, "next": token, "kind": c["kind"]}
        if c.get("next"):
            e = self.pages.get(c["next"], (c.get("kind"), None))
            kind, nxt = e[0], e[1]
            if not nxt:
                return {"items": [], "next": None}
        items, token = self.list_page(c.get("kind"), c.get("arg"), nxt, int(c.get("limit", 30)))
        return {"items": items, "next": token, "kind": c.get("kind")}

    def c_search(self, c):
        return self.c_list({"kind": "search_" + c.get("type", "tracks"), "arg": c.get("q", ""),
                            "next": c.get("next")})

    def c_home(self, c):
        """SoundCloud's own home shelves (/mixed-selections)."""
        raws, _ = self.sc.page("/mixed-selections", limit=12)
        out = []
        for sel in raws:
            col = (sel.get("items") or {}).get("collection") or []
            self.remember(col)
            seen, items = set(), []
            for x in self.hydrate([n_item(y) for y in col]):
                k = (x.get("type"), x.get("id"))
                if k in seen:
                    continue
                seen.add(k)
                items.append(x)
            if items:
                out.append({"title": sel.get("title") or "", "urn": sel.get("urn") or "", "items": items})
        return {"shelves": out}

    def c_playlist(self, c):
        pl, tracks = self.playlist(c["pid"])
        return {"playlist": pl, "items": tracks}

    def c_user(self, c):
        return {"user": self.user(c["uid"])}

    def c_resolve(self, c):
        return {"item": self.resolve_url(c["url"])}

    def c_radio(self, c):
        """Keep the music going like SoundCloud: the track's station (its own autoplay), related as fallback.
        {"tid", "enqueue": bool, "play": bool} - play = the queue already ran out, start right away."""
        tid = c.get("tid") or (self.cur() or {}).get("id")
        if not tid:
            return {"items": []}
        items = []
        try:
            raws, _ = self.sc.page("/stations/soundcloud:track-stations:%s/tracks" % tid, limit=50)
            self.remember(raws)
            items = self.hydrate([n_item(x) for x in raws])
        except ApiError as e:
            log("station:", e)
        if len(items) < 5:
            more, _ = self.list_page("related", tid, limit=c.get("limit", 20))
            items += more
        recent = {t["id"] for t in self.queue[-200:]}
        seen, out = set(), []
        for t in items:
            if t and t.get("type") == "track" and t["id"] != tid and t["id"] not in recent and t["id"] not in seen and not t.get("block") and not t.get("drm"):
                seen.add(t["id"])
                out.append(t)
        out = out[:int(c.get("limit", 25))]
        if out and (c.get("enqueue") or c.get("play")):
            start = len(self.queue)
            self.c_enqueue({"tracks": out})
            if c.get("play"):
                self.play_index(start)
        return {"items": out}

    def c_auth(self, c):
        """Re-read cookies (optionally from another browser) and always answer with an auth event."""
        if c.get("browser") is not None:
            self.sc.browser = c["browser"] or None
            self.settings["browser"] = c["browser"]
            write_json(SETTINGS_FILE, self.settings)
        try:
            self.sc.init(force=True)
        except Exception as e:
            self.sc.browser_failed = str(e)
        self.check_auth()
        return {"ok": bool(self.sc.me)}

    def c_browsers(self, c):
        """Browsers that are actually installed (their profile folders exist)."""
        H = HOME
        found = {"brave": os.path.isdir(H + "/.config/BraveSoftware/Brave-Browser"),
                 "chromium": os.path.isdir(H + "/.config/chromium"),
                 "chrome": os.path.isdir(H + "/.config/google-chrome"),
                 "vivaldi": os.path.isdir(H + "/.config/vivaldi"),
                 "firefox": os.path.isdir(H + "/.mozilla/firefox"),
                 "zen": os.path.isdir(H + "/.zen")}
        return {"browsers": [k for k, v in found.items() if v]}

    def c_stats(self, c):
        rows = self.store.stats(int(c.get("days", 7)))
        tracks, artists = [], {}
        total = 0.0
        for tid, n, secs, js in rows:
            total += secs or 0
            t = n_track(json.loads(js)) if js else None
            if not t:
                continue
            tracks.append({"track": t, "plays": n})
            a = artists.setdefault(t["artist"], {"name": t["artist"], "plays": 0, "art": t["art"], "id": t["artistId"]})
            a["plays"] += n
        return {"tracks": tracks[:50], "artists": sorted(artists.values(), key=lambda a: -a["plays"])[:20],
                "minutes": round(total / 60)}

    # ── account actions (like / follow) ───────────────────────
    def c_mine(self, c):
        """Ids for heart / follow buttons: (SoundCloud ∪ local) − un-liked here."""
        likes, fol = set(), set()
        if self.sc.token:
            try:
                if not self.sc.me:
                    self.sc.whoami()
                d = self.sc.get("/me/track_likes/ids", {"limit": 5000, "linked_partitioning": 1})
                likes = set(d.get("collection") or [])
                nh, path = None, "/users/%s/followings" % self.sc.me["id"]
                for _ in range(10):
                    items, nh = self.sc.page(nh or path, limit=200)
                    fol |= {u.get("id") for u in items if u.get("id")}
                    if not nh:
                        break
            except Exception as e:
                log("mine:", e)
        likes |= {it["id"] for _, it in self.store.local_items("like")}
        fol |= {it["id"] for _, it in self.store.local_items("follow")}
        likes -= self.store.hidden_ids("like")
        fol -= self.store.hidden_ids("follow")
        return {"likes": sorted(likes), "following": sorted(fol)}

    def c_like(self, c):
        """Saved in the player (SoundCloud rejects likes from outside its website)."""
        t = c.get("track") or {"id": int(c["tid"])}
        if "title" not in t:
            t = n_track(self.full_track(t)) or t
        self.store.local_set("like", t, bool(c.get("on", True)))
        return {"tid": t["id"], "on": bool(c.get("on", True))}

    def c_follow(self, c):
        uid = int(c["uid"])
        u = c.get("user") or {"type": "user", "id": uid}
        if c.get("on", True) and "name" not in u:
            try:
                u = n_user(self.sc.get("/users/%s" % uid)) or u
            except ApiError:
                pass
        self.store.local_set("follow", u, bool(c.get("on", True)))
        return {"uid": uid, "on": bool(c.get("on", True))}

    def c_local_feed(self, c):
        """Fresh tracks from artists followed in the player only (the SoundCloud feed doesn't know them)."""
        out = []
        for _, u in self.store.local_items("follow")[:12]:
            try:
                raws, _ = self.sc.page("/users/%s/tracks" % u["id"], limit=6)
                self.remember(raws)
                out += [(iso_ts(x.get("created_at")), n_track(x)) for x in raws if x.get("kind") == "track"]
            except ApiError:
                pass
        out.sort(key=lambda p: -p[0])
        return {"items": [t for _, t in out[:30] if t]}

    # ── plugin helpers ─────────────────────────────────────────
    def c_lyrics(self, c):
        t = c.get("track") or self.cur()
        if not t:
            return {"synced": [], "plain": ""}
        r = extras.lyrics(t, os.path.join(CACHE, "lyrics"))
        r["id"] = t.get("id")
        return r

    def c_lastfm(self, c):
        return {"data": extras.lastfm(c["method"], c.get("params"), c["key"], c.get("secret"), c.get("sk"), c.get("post", False))}

    def c_discord(self, c):
        if not c.get("client_id"):
            return {"err": "no application id"}
        act = c.get("activity")
        try:
            self.discord.set(c["client_id"], act)
        except OSError as e:
            return {"err": str(e)}
        return {}

    def c_plugins(self, c):
        root = os.path.join(CONF, "plugins")
        out = []
        for d in sorted(os.listdir(root)) if os.path.isdir(root) else []:
            m = read_json(os.path.join(root, d, "manifest.json"), None)
            if isinstance(m, dict) and os.path.exists(os.path.join(root, d, m.get("entry", "Plugin.qml"))):
                m.setdefault("id", d)
                m["dir"] = os.path.join(root, d)
                out.append(m)
        return {"plugins": out}

    # ── themes ─────────────────────────────────────────────────
    def c_themes(self, c):
        root = os.path.join(CONF, "themes")
        out = []
        for d in sorted(os.listdir(root)) if os.path.isdir(root) else []:
            j = read_json(os.path.join(root, d, "theme.json"), None)
            if isinstance(j, dict):
                out.append({"id": d, "data": j, "overrides": os.path.exists(os.path.join(root, d, "Overrides.qml"))})
        return {"themes": out}

    def c_theme_save(self, c):
        # "theme", not "id": "id" is the request id of the JSON protocol
        tid = "".join(ch for ch in str(c.get("theme") or "").lower().replace(" ", "-") if ch.isalnum() or ch in "-_") or "custom"
        d = os.path.join(CONF, "themes", tid)
        os.makedirs(d, exist_ok=True)
        write_json(os.path.join(d, "theme.json"), c.get("data") or {})
        return {"id": tid}

    def c_theme_delete(self, c):
        import shutil
        tid = str(c.get("theme") or "")
        if tid in ("sakura", "vinyl", "paper") or not tid or "/" in tid:
            return {"err": "built-in"}
        shutil.rmtree(os.path.join(CONF, "themes", tid), ignore_errors=True)
        return {}

    def c_theme_export(self, c):
        import zipfile
        tid = str(c.get("theme") or "")
        src = os.path.join(CONF, "themes", tid)
        dest_dir = os.path.join(HOME, "Downloads") if os.path.isdir(os.path.join(HOME, "Downloads")) else HOME
        dest = os.path.join(dest_dir, "sakura-sound-theme-%s.zip" % tid)
        with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
            for name in os.listdir(src):
                if name in ("theme.json", "Overrides.qml") or name.endswith((".png", ".jpg", ".svg")):
                    z.write(os.path.join(src, name), os.path.join(tid, name))
        return {"path": dest}

    def c_theme_import(self, c):
        import zipfile
        path = c.get("path") or ""
        with zipfile.ZipFile(path) as z:
            names = [n for n in z.namelist() if not n.startswith("/") and ".." not in n]
            tj = [n for n in names if n.endswith("theme.json")]
            if not tj:
                return {"err": "no theme.json in zip"}
            prefix = tj[0][:-len("theme.json")]
            tid = (prefix.strip("/").split("/")[-1] or os.path.splitext(os.path.basename(path))[0]).replace("sakura-sound-theme-", "")
            tid = "".join(ch for ch in tid.lower() if ch.isalnum() or ch in "-_") or "imported"
            d = os.path.join(CONF, "themes", tid)
            os.makedirs(d, exist_ok=True)
            for n in names:
                if n.startswith(prefix) and not n.endswith("/"):
                    base = os.path.basename(n)
                    if base == "theme.json" or base == "Overrides.qml" or base.endswith((".png", ".jpg", ".svg")):
                        with open(os.path.join(d, base), "wb") as f:
                            f.write(z.read(n))
        return {"id": tid}

    def c_quit(self, c):
        self.save()
        self.stop_all()
        os._exit(0)

    # ── main loop ──────────────────────────────────────────────
    def run(self):
        try:
            self.start()
        except Exception as e:
            emit("error", msg="start: %s" % e, fatal=True)
            log(traceback.format_exc())
            sys.exit(1)
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                c = json.loads(line)
            except ValueError:
                continue
            if c.get("cmd") in self.INSTANT:
                self.handle(c)
            else:
                self.pool.submit(self.handle, c)
        # stdin closed → window gone
        self.save()
        self.stop_all()


if __name__ == "__main__":
    import signal
    b = Backend()

    def _bye(*_):
        try:
            b.save()
            b.stop_all()
        finally:
            os._exit(0)
    signal.signal(signal.SIGTERM, _bye)
    signal.signal(signal.SIGHUP, _bye)
    b.run()
