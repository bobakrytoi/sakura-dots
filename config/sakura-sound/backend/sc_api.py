"""Unofficial SoundCloud web API (api-v2) - the same calls the website makes.

Auth: the public web client_id (yt-dlp extracts it from the site's JS) plus
the user's `oauth_token` cookie read from Brave by yt-dlp. Nothing is stored:
cookies are re-read from the browser when needed.

All network calls: timeout, retry with backoff on 429/5xx, a global limit of
4 parallel requests.
"""
import json, threading, time, urllib.request, urllib.parse, urllib.error

API = "https://api-v2.soundcloud.com"
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0 Safari/537.36"



# ── browser cookies: Chromium browsers keep the cookie key in the Secret Service (gnome-keyring) once one runs.
# yt-dlp can't detect that under Hyprland (it guesses BASICTEXT → v11 cookies undecryptable → guest), and its
# GNOMEKEYRING path needs python-secretstorage. So: pick GNOMEKEYRING when the browser's key is there, and read
# the key with `secret-tool` if secretstorage is missing.
def _keyring_key(browser):
    import subprocess
    try:
        r = subprocess.run(["secret-tool", "lookup", "application", browser.split(":")[0].lower()],
                           capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None
    except Exception:
        return None


def _patch_ytdlp_gnome():
    import yt_dlp.cookies as yc
    if getattr(yc, "_sakura_patched", False):
        return
    orig = yc._get_gnome_keyring_password

    def get(browser_keyring_name, logger):
        if getattr(yc, "SECRETSTORAGE_AVAILABLE", False):
            return orig(browser_keyring_name, logger)
        name = str(browser_keyring_name).lower()
        for app in ("brave", "chromium", "chrome", "vivaldi", "opera", "edge"):
            if app in name:
                k = _keyring_key(app)
                if k:
                    return k.encode()
        return b""
    yc._get_gnome_keyring_password = get
    yc._sakura_patched = True


def cookie_opt(browser):
    """yt-dlp `cookiesfrombrowser` tuple for this browser."""
    if not browser:
        return None
    b = browser.split(":")[0].lower()
    if b in ("brave", "chromium", "chrome", "vivaldi", "opera", "edge") and _keyring_key(b):
        _patch_ytdlp_gnome()
        return (b, None, "GNOMEKEYRING", None)
    return (browser,)

class ApiError(Exception):
    def __init__(self, msg, status=0):
        super().__init__(msg)
        self.status = status


class SC:
    def __init__(self, browser="brave", log=lambda *a: None):
        self.browser = browser
        self.log = log
        self.client_id = None
        self.token = None
        self.me = None
        self._ydl = None
        self._ie = None
        self._lock = threading.Lock()
        self._sem = threading.Semaphore(4)
        self._cookies_at = 0
        self.browser_failed = None

    # ── credentials ────────────────────────────────────────────
    def _ytdlp(self):
        import yt_dlp
        if self._ydl is None:
            opts = {"quiet": True, "no_warnings": True, "skip_download": True}
            if self.browser:
                opts["cookiesfrombrowser"] = cookie_opt(self.browser)
            self._ydl = yt_dlp.YoutubeDL(opts)
            self._ie = self._ydl.get_info_extractor("Soundcloud")
        return self._ydl, self._ie

    def init(self, force=False):
        """(Re)load client_id and the oauth token. Safe to call often."""
        with self._lock:
            # signed in: re-read cookies every 30 min; guest: retry every minute (the keyring may not be ready at login)
            if not force and self.client_id and time.time() - self._cookies_at < (1800 if self.token else 60):
                return
            if force:
                self._ydl = None
            ydl, ie = self._ytdlp()
            try:
                ie.initialize()
            except Exception as e:  # cookies unreadable → guest
                self.log("ytdlp init: %s" % e)
                self._ydl = None
                self.browser_failed = str(e)
                ydl, ie = self._ytdlp()
            self.client_id = getattr(ie, "_CLIENT_ID", None) or ydl.cache.load("soundcloud", "client_id")
            if not self.client_id:
                try:
                    ie._update_client_id()
                    self.client_id = ie._CLIENT_ID
                except Exception as e:
                    raise ApiError("no client_id: %s" % e)
            tok = None
            self.browser_failed = None
            try:
                for c in ydl.cookiejar:            # yt-dlp reads the browser's cookies here (may fail: no such browser…)
                    if c.name == "oauth_token" and "soundcloud.com" in c.domain:
                        tok = c.value
            except Exception as e:
                self.browser_failed = str(e).replace("ERROR: ", "")
                self.log("cookies: %s" % self.browser_failed)
                self._ydl = None                  # next call starts clean
            self.token = tok
            if not tok:
                self._ydl = None                  # rebuild next time: cookie_opt() picks the keyring once it answers
            self._cookies_at = time.time()

    def refresh_client_id(self):
        with self._lock:
            ydl, ie = self._ytdlp()
            try:
                ie._update_client_id()
                self.client_id = ie._CLIENT_ID
            except Exception as e:
                self.log("client_id refresh failed: %s" % e)

    # ── http ───────────────────────────────────────────────────
    def get(self, path, params=None, auth=True, absolute=False, tries=4):
        if not self.client_id:
            self.init()
        params = dict(params or {})
        if absolute:
            u = urllib.parse.urlsplit(path)
            q = dict(urllib.parse.parse_qsl(u.query))
            q.update(params)
            q["client_id"] = self.client_id
            url = urllib.parse.urlunsplit((u.scheme, u.netloc, u.path, urllib.parse.urlencode(q), ""))
        else:
            params["client_id"] = self.client_id
            url = API + path + "?" + urllib.parse.urlencode(params)
        headers = {"User-Agent": UA, "Accept": "application/json", "Origin": "https://soundcloud.com",
                   "Referer": "https://soundcloud.com/"}
        if auth and self.token:
            headers["Authorization"] = "OAuth " + self.token
        delay = 1.0
        for attempt in range(tries):
            req = urllib.request.Request(url, headers=headers)
            try:
                with self._sem:
                    with urllib.request.urlopen(req, timeout=12) as r:
                        return json.load(r)
            except urllib.error.HTTPError as e:
                if e.code == 429 or e.code >= 500:
                    time.sleep(delay); delay *= 2
                    continue
                if e.code == 401 and attempt == 0:
                    # stale client_id or token: refresh both once
                    if "Authorization" in headers:
                        self.init(force=True)
                        if self.token:
                            headers["Authorization"] = "OAuth " + self.token
                        else:
                            headers.pop("Authorization", None)
                    else:
                        self.refresh_client_id()
                    url = _swap_cid(url, self.client_id)
                    continue
                raise ApiError("HTTP %d %s" % (e.code, path), e.code)
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                if attempt == tries - 1:
                    raise ApiError("network: %s" % e)
                time.sleep(delay); delay *= 2
        raise ApiError("too many retries: %s" % path, 429)

    def write(self, method, path):
        """PUT/POST/DELETE as the signed-in user (like, follow). Returns HTTP status."""
        if not self.token:
            raise ApiError("not signed in", 401)
        url = API + path + "?" + urllib.parse.urlencode({"client_id": self.client_id})
        headers = {"User-Agent": UA, "Accept": "application/json", "Origin": "https://soundcloud.com",
                   "Referer": "https://soundcloud.com/", "Authorization": "OAuth " + self.token,
                   "Content-Type": "application/json"}
        req = urllib.request.Request(url, data=b"" if method in ("PUT", "POST") else None, headers=headers, method=method)
        try:
            with self._sem:
                with urllib.request.urlopen(req, timeout=12) as r:
                    return r.status
        except urllib.error.HTTPError as e:
            if e.code in (404,) and method == "DELETE":
                return e.code      # already not liked / not followed
            raise ApiError("HTTP %d %s %s" % (e.code, method, path), e.code)

    def page(self, path_or_next, params=None, limit=30):
        """One page of a collection → (items, next_href)."""
        if path_or_next.startswith("http"):
            d = self.get(path_or_next, absolute=True)
        else:
            p = {"limit": limit, "linked_partitioning": 1}
            p.update(params or {})
            d = self.get(path_or_next, p)
        if isinstance(d, list):
            return d, None
        return d.get("collection") or [], d.get("next_href")

    # ── account ────────────────────────────────────────────────
    def whoami(self):
        self.init()
        if not self.token:
            self.me = None
            return None
        try:
            self.me = self.get("/me")
        except ApiError as e:
            if e.status in (401, 403):
                self.me = None
                return None
            raise
        return self.me

    # ── streams ────────────────────────────────────────────────
    def stream_url(self, track):
        """Fast path: resolve a playable URL from a full track object (api-v2).
        Returns (url, protocol, is_snippet) or raises ApiError."""
        media = (track.get("media") or {}).get("transcodings") or []
        if not media:
            raise ApiError("no transcodings")
        def score(t):
            f = t.get("format") or {}
            proto, mime = f.get("protocol", ""), f.get("mime_type", "")
            s = 0
            if proto == "hls": s += 10
            if "aac" in mime or "mp4" in mime: s += 5
            elif "mpeg" in mime: s += 3
            elif "opus" in mime or "ogg" in mime: s += 2
            if "encrypted" in proto or "ctr" in proto or "cbc" in proto: s -= 100
            if t.get("snipped"): s -= 1
            return s
        best = sorted(media, key=score, reverse=True)[0]
        if score(best) < 0:
            raise ApiError("only encrypted streams")
        params = {}
        if track.get("track_authorization"):
            params["track_authorization"] = track["track_authorization"]
        d = self.get(best["url"], params, absolute=True)
        if not d.get("url"):
            raise ApiError("empty stream url")
        return d["url"], best["format"]["protocol"], bool(best.get("snipped"))

    def stream_url_ytdlp(self, permalink):
        """Slow but robust fallback through yt-dlp."""
        import yt_dlp
        opts = {"quiet": True, "no_warnings": True, "skip_download": True,
                "format": "bestaudio[protocol^=m3u8]/bestaudio"}
        if self.browser:
            opts["cookiesfrombrowser"] = cookie_opt(self.browser)
        info = yt_dlp.YoutubeDL(opts).extract_info(permalink, download=False)
        return info["url"], info.get("protocol", ""), False


def _swap_cid(url, cid):
    u = urllib.parse.urlsplit(url)
    q = dict(urllib.parse.parse_qsl(u.query))
    q["client_id"] = cid
    return urllib.parse.urlunsplit((u.scheme, u.netloc, u.path, urllib.parse.urlencode(q), ""))


def fetch(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()
