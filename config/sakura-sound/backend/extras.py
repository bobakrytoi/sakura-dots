"""Backend helpers used by bundled plugins: lyrics (LRCLIB), Last.fm, Discord RPC."""
import hashlib, json, os, re, socket, struct, threading, time, urllib.parse, urllib.request, uuid

UA = "SakuraSound/1.0 (+local)"


def _get(url, timeout=8, data=None):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


# ── lyrics ─────────────────────────────────────────────────────
_JUNK = re.compile(r"\s*[\(\[\{][^\)\]\}]*(prod|feat|ft\.|remix|snippet|slowed|sped|speed|free|official|audio|video|lyric|clip|bass|edit|mix|version|cover)[^\)\]\}]*[\)\]\}]", re.I)


def clean_title(title, artist):
    t = title or ""
    t = _JUNK.sub("", t)
    t = re.sub(r"\s*(prod\.?|prod by|ft\.?|feat\.?)\s.*$", "", t, flags=re.I)
    t = re.sub(r"[#@]\S+", "", t)
    a = artist or ""
    # "Artist - Title" / "Artist - Title" inside the title
    m = re.match(r"^\s*(.+?)\s+[---]\s+(.+)$", t)
    if m:
        a, t = m.group(1), m.group(2)
    t = re.sub(r"\s*\+\S.*$", "", t)              # "title +someone"
    t = re.sub(r"[^\w\s'’&.,!?-]", " ", t, flags=re.U)
    return re.sub(r"\s+", " ", t).strip(), re.sub(r"\s+", " ", a).strip()


def parse_lrc(raw):
    out = []
    for line in (raw or "").splitlines():
        stamps = re.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", line)
        text = re.sub(r"\[[^\]]*\]", "", line).strip()
        for m, s in stamps:
            out.append({"t": int(m) * 60 + float(s), "text": text})
    out.sort(key=lambda x: x["t"])
    return out


def lyrics(track, cache_dir):
    tid = track.get("id")
    p = os.path.join(cache_dir, "%s.json" % tid)
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        pass
    title, artist = clean_title(track.get("title"), track.get("artist"))
    dur = track.get("full") or track.get("dur") or 0
    res = {"synced": [], "plain": "", "q": "%s - %s" % (artist, title)}
    hit = None
    try:
        q = {"track_name": title, "artist_name": artist}
        if dur:
            q["duration"] = int(dur)
        hit = _get("https://lrclib.net/api/get?" + urllib.parse.urlencode(q))
    except Exception:
        hit = None
    if not hit or not (hit.get("syncedLyrics") or hit.get("plainLyrics")):
        try:
            found = _get("https://lrclib.net/api/search?" + urllib.parse.urlencode({"q": (artist + " " + title).strip()}))
            best = None
            for f in found or []:
                if not (f.get("syncedLyrics") or f.get("plainLyrics")):
                    continue
                d = abs((f.get("duration") or 0) - dur) if dur else 0
                if dur and d > 12:
                    continue
                score = (2 if f.get("syncedLyrics") else 0) - d / 10
                if best is None or score > best[0]:
                    best = (score, f)
            hit = best[1] if best else None
        except Exception:
            hit = None
    if hit:
        res["synced"] = parse_lrc(hit.get("syncedLyrics") or "")
        res["plain"] = hit.get("plainLyrics") or ""
    try:
        os.makedirs(cache_dir, exist_ok=True)
        with open(p, "w") as f:
            json.dump(res, f, ensure_ascii=False)
    except Exception:
        pass
    return res


# ── Last.fm ────────────────────────────────────────────────────
def lastfm(method, params, key, secret, sk=None, post=False):
    p = dict(params or {})
    p.update({"method": method, "api_key": key})
    if sk:
        p["sk"] = sk
    if secret:
        sig = "".join(k + str(p[k]) for k in sorted(p)) + secret
        p["api_sig"] = hashlib.md5(sig.encode("utf-8")).hexdigest()
    p["format"] = "json"
    body = urllib.parse.urlencode(p).encode()
    url = "https://ws.audioscrobbler.com/2.0/"
    if post:
        return _get(url, data=body)
    return _get(url + "?" + body.decode())


# ── Discord Rich Presence (local IPC socket) ───────────────────
class Discord:
    def __init__(self, log):
        self.log = log
        self.sock = None
        self.client_id = None
        self.lock = threading.Lock()

    def _path(self):
        base = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
        for sub in ("", "app/com.discordapp.Discord/", "snap.discord/"):
            for i in range(10):
                p = os.path.join(base, sub, "discord-ipc-%d" % i)
                if os.path.exists(p):
                    return p
        return None

    def _send(self, op, payload):
        data = json.dumps(payload).encode()
        self.sock.sendall(struct.pack("<II", op, len(data)) + data)
        hdr = self.sock.recv(8)
        if len(hdr) < 8:
            raise OSError("discord closed")
        _, n = struct.unpack("<II", hdr)
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                break
            buf += chunk
        return json.loads(buf or b"{}")

    def _connect(self, client_id):
        p = self._path()
        if not p:
            raise OSError("Discord is not running")
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(4)
        s.connect(p)
        self.sock = s
        self._send(0, {"v": 1, "client_id": str(client_id)})
        self.client_id = client_id

    def set(self, client_id, activity):
        with self.lock:
            for attempt in range(2):
                try:
                    if not self.sock or self.client_id != client_id:
                        self.close()
                        self._connect(client_id)
                    return self._send(1, {"cmd": "SET_ACTIVITY", "nonce": str(uuid.uuid4()),
                                          "args": {"pid": os.getpid(), "activity": activity}})
                except OSError as e:
                    self.close()
                    if attempt:
                        raise
            return None

    def close(self):
        try:
            if self.sock:
                self.sock.close()
        except OSError:
            pass
        self.sock = None
