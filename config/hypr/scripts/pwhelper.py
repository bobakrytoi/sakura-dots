#!/usr/bin/env python3
"""sakura mono - Password helper backend (port of the Windows "Password helper", C#/WPF).

Runs as a long-lived child of quickshell (PwVault.qml) and talks JSON lines over stdin/stdout:
  in : {"id": n, "cmd": "...", ...}          out: {"re": n, "ok": true|false, ...}
  out (events): {"ev": "state" | "history" | "toast", ...}

Vault  ~/.local/share/sakura/vault.dat (+ .bak):
  b"SKVAULT" | ver(1) | sha256(nonce+ct+tag)(32) | nonce(12) | ct | tag(16)
  AES-256-GCM through the system libcrypto (ctypes, no extra packages). The SHA-256 is checked BEFORE decrypting.
  The 256-bit key lives in the login keyring through the Secret Service (secret-tool: gnome-keyring or KWallet),
  so it opens together with the login - no master password (like DPAPI on Windows).
  Writes are atomic (tmp + fsync + rename) and keep a .bak. A vault that does not open is NEVER emptied silently:
  the UI offers restore backup / start new (bad file moved aside) / leave it.
Clipboard: copies go through wl-copy; passwords with --sensitive (x-kde-passwordManagerHint=secret), so history
  managers skip them. Optional auto-clear only if the clipboard still holds exactly our value.
  History: in memory only, from `wl-paste --watch` (events, no polling); sensitive offers and copies made while a
  password-manager window is focused are ignored.
Never logs secrets: stderr gets fixed status lines only.

Tests only: SAKURA_VAULT_DIR + SAKURA_VAULT_TESTKEY (hex) together replace the data dir and the keyring.
"""
import base64, ctypes, ctypes.util, hashlib, json, os, secrets, shutil, signal, struct, subprocess, sys, threading, time, uuid

_LIBC = ctypes.CDLL(None, use_errno=True)


def die_with_parent():
    """PR_SET_PDEATHSIG: get SIGTERM when the parent goes away (no orphaned helper / wl-paste watchers)."""
    try: _LIBC.prctl(1, signal.SIGTERM, 0, 0, 0)
    except Exception: pass

# ── paths ─────────────────────────────────────────────────────────────
TEST_DIR = os.environ.get("SAKURA_VAULT_DIR", "")
TEST_KEY = os.environ.get("SAKURA_VAULT_TESTKEY", "")
TESTING = bool(TEST_DIR and TEST_KEY)
DATA_DIR = TEST_DIR if TESTING else os.path.join(os.path.expanduser("~"), ".local/share/sakura")
VAULT = os.path.join(DATA_DIR, "vault.dat")
BAK = VAULT + ".bak"
TMP = VAULT + ".tmp"
MAGIC = b"SKVAULT"
VER = 1
KEY_ATTRS = ["service", "sakura-vault", "account", "vault-key"]


def log(msg):            # fixed messages only - never secrets
    try:
        sys.stderr.write("pwhelper: " + msg + "\n"); sys.stderr.flush()
    except Exception:
        pass


# ── AES-256-GCM via libcrypto ─────────────────────────────────────────
class Gcm:
    def __init__(self):
        lib = None
        for name in ("libcrypto.so.3", "libcrypto.so.4", ctypes.util.find_library("crypto") or ""):
            if not name:
                continue
            try:
                lib = ctypes.CDLL(name); break
            except OSError:
                pass
        if lib is None:
            raise RuntimeError("libcrypto not found")
        self.l = lib
        lib.EVP_CIPHER_CTX_new.restype = ctypes.c_void_p
        lib.EVP_CIPHER_CTX_free.argtypes = [ctypes.c_void_p]
        lib.EVP_aes_256_gcm.restype = ctypes.c_void_p
        for f in ("EVP_EncryptInit_ex", "EVP_DecryptInit_ex"):
            getattr(lib, f).argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
        for f in ("EVP_EncryptUpdate", "EVP_DecryptUpdate"):
            getattr(lib, f).argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_int), ctypes.c_char_p, ctypes.c_int]
        for f in ("EVP_EncryptFinal_ex", "EVP_DecryptFinal_ex"):
            getattr(lib, f).argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
        lib.EVP_CIPHER_CTX_ctrl.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_void_p]

    def encrypt(self, key, plain, aad=b""):
        l = self.l
        nonce = secrets.token_bytes(12)
        ctx = l.EVP_CIPHER_CTX_new()
        try:
            n = ctypes.c_int(0)
            assert l.EVP_EncryptInit_ex(ctx, l.EVP_aes_256_gcm(), None, None, None) == 1
            assert l.EVP_CIPHER_CTX_ctrl(ctx, 0x9, 12, None) == 1           # SET_IVLEN
            assert l.EVP_EncryptInit_ex(ctx, None, None, key, nonce) == 1
            if aad:
                assert l.EVP_EncryptUpdate(ctx, None, ctypes.byref(n), aad, len(aad)) == 1
            out = ctypes.create_string_buffer(len(plain) + 16)
            assert l.EVP_EncryptUpdate(ctx, out, ctypes.byref(n), plain, len(plain)) == 1
            total = n.value
            fin = ctypes.create_string_buffer(16)
            assert l.EVP_EncryptFinal_ex(ctx, fin, ctypes.byref(n)) == 1
            tag = ctypes.create_string_buffer(16)
            assert l.EVP_CIPHER_CTX_ctrl(ctx, 0x10, 16, tag) == 1           # GET_TAG
            ct = out.raw[:total] + fin.raw[:n.value]
            ctypes.memset(out, 0, len(out))
            return nonce + ct + tag.raw
        finally:
            l.EVP_CIPHER_CTX_free(ctx)

    def decrypt(self, key, blob, aad=b""):
        l = self.l
        if len(blob) < 28:
            raise ValueError("short")
        nonce, ct, tag = blob[:12], blob[12:-16], blob[-16:]
        ctx = l.EVP_CIPHER_CTX_new()
        try:
            n = ctypes.c_int(0)
            assert l.EVP_DecryptInit_ex(ctx, l.EVP_aes_256_gcm(), None, None, None) == 1
            assert l.EVP_CIPHER_CTX_ctrl(ctx, 0x9, 12, None) == 1
            assert l.EVP_DecryptInit_ex(ctx, None, None, key, nonce) == 1
            if aad:
                assert l.EVP_DecryptUpdate(ctx, None, ctypes.byref(n), aad, len(aad)) == 1
            out = ctypes.create_string_buffer(len(ct) + 16)
            assert l.EVP_DecryptUpdate(ctx, out, ctypes.byref(n), ct, len(ct)) == 1
            total = n.value
            tbuf = ctypes.create_string_buffer(tag, 16)
            assert l.EVP_CIPHER_CTX_ctrl(ctx, 0x11, 16, tbuf) == 1          # SET_TAG
            fin = ctypes.create_string_buffer(16)
            if l.EVP_DecryptFinal_ex(ctx, fin, ctypes.byref(n)) != 1:
                ctypes.memset(out, 0, len(out))
                raise ValueError("auth")
            plain = out.raw[:total] + fin.raw[:n.value]
            ctypes.memset(out, 0, len(out))
            return plain
        finally:
            l.EVP_CIPHER_CTX_free(ctx)


GCM = Gcm()


# ── vault file format ─────────────────────────────────────────────────
def pack(key, payload: bytes) -> bytes:
    blob = GCM.encrypt(key, payload, MAGIC + bytes([VER]))
    return MAGIC + bytes([VER]) + hashlib.sha256(blob).digest() + blob


class VaultError(Exception):
    def __init__(self, code, msg):
        super().__init__(msg); self.code = code; self.msg = msg


def unpack(key, data: bytes) -> bytes:
    if len(data) < len(MAGIC) + 1 + 32 + 28 or not data.startswith(MAGIC):
        raise VaultError("format", "The vault file is not recognised or is truncated.")
    ver = data[len(MAGIC)]
    if ver != VER:
        raise VaultError("version", "The vault was written by a newer version.")
    off = len(MAGIC) + 1
    digest, blob = data[off:off + 32], data[off + 32:]
    if hashlib.sha256(blob).digest() != digest:        # integrity first, before any decryption
        raise VaultError("integrity", "The vault file is damaged (integrity check failed).")
    try:
        return GCM.decrypt(key, blob, MAGIC + bytes([ver]))
    except Exception:
        raise VaultError("decrypt", "The vault could not be decrypted with the key from the keyring.")


def read_file(path):
    with open(path, "rb") as f:
        return f.read()


def fsync_dir(d):
    try:
        fd = os.open(d, os.O_RDONLY | os.O_DIRECTORY)
        try: os.fsync(fd)
        finally: os.close(fd)
    except OSError:
        pass


def atomic_write(path, data: bytes, keep_bak=True):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, data); os.fsync(fd)
    finally:
        os.close(fd)
    if keep_bak and os.path.exists(path):
        shutil.copy2(path, path + ".bak"); os.chmod(path + ".bak", 0o600)
    os.replace(tmp, path)
    fsync_dir(os.path.dirname(path))


# ── keyring (Secret Service via secret-tool) ──────────────────────────
def keyring_available():
    if TESTING:
        return True
    try:
        out = subprocess.run(["busctl", "--user", "--no-pager", "--no-legend", "list"], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return False
    return any(line.split()[:1] == ["org.freedesktop.secrets"] for line in out.splitlines() if line.strip())


def default_collection():
    """'open' | 'locked' | 'missing' - the login keyring behind the "default" alias. Checked before every keyring call:
    we must never make the keyring ask for a NEW keyring password (that would be a master password)."""
    try:
        r = subprocess.run(["busctl", "--user", "get-property", "org.freedesktop.secrets", "/org/freedesktop/secrets/aliases/default",
                            "org.freedesktop.Secret.Collection", "Locked"], capture_output=True, text=True, timeout=10)
    except Exception:
        return "missing"
    if r.returncode != 0:
        return "missing"
    return "locked" if "true" in r.stdout else "open"


def key_lookup(interactive=False):
    """-> bytes | None (no key stored) ; raises VaultError('keyring') when the keyring is not reachable.
    interactive=False never lets the keyring show a prompt; True (the user pressed Unlock) allows its unlock prompt."""
    if TESTING:
        return bytes.fromhex(TEST_KEY)
    if not keyring_available():
        raise VaultError("keyring", "No keyring (Secret Service) is running.")
    col = default_collection()
    if col == "missing":
        raise VaultError("keyring", "The login keyring does not exist yet - log out and back in once.")
    if col == "locked" and not interactive:
        raise VaultError("keyring", "The login keyring is locked.")
    try:
        r = subprocess.run(["secret-tool", "lookup"] + KEY_ATTRS, capture_output=True, timeout=180)
    except Exception:
        raise VaultError("keyring", "The keyring did not answer.")
    s = r.stdout.strip()
    if r.returncode != 0 or not s:
        return None
    try:
        k = base64.b64decode(s, validate=True)
    except Exception:
        raise VaultError("keyring", "The key in the keyring is malformed.")
    return k if len(k) == 32 else None


def key_store(k):
    if TESTING:
        return
    r = subprocess.run(["secret-tool", "store", "--label=Sakura password vault key"] + KEY_ATTRS,
                       input=base64.b64encode(k), capture_output=True, timeout=180)
    if r.returncode != 0 or key_lookup() != k:
        raise VaultError("keyring", "Could not save the vault key in the keyring.")


def key_clear():
    if TESTING:
        return
    subprocess.run(["secret-tool", "clear"] + KEY_ATTRS, capture_output=True, timeout=60)


# ── output ────────────────────────────────────────────────────────────
OUT = threading.Lock()


def send(obj):
    with OUT:
        try:
            sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n"); sys.stdout.flush()
        except (BrokenPipeError, ValueError):       # quickshell went away: nothing left to talk to
            try: C.stop_watch()
            except Exception: pass
            os._exit(0)


# ── the vault ─────────────────────────────────────────────────────────
class Vault:
    """state: loading | ready | locked | nokeyring | corrupt"""

    def __init__(self):
        self.state = "loading"
        self.problem = ""
        self.code = ""
        self.key = None
        self.mem = secrets.token_bytes(32)   # session key: passwords stay encrypted in memory, decrypted per use
        self.entries = []                    # dicts; "pw" = encrypted with self.mem
        self.has_bak = False
        self.last_use = time.monotonic()
        self.lock = threading.RLock()

    # passwords in memory
    def seal(self, pw: str) -> bytes: return GCM.encrypt(self.mem, pw.encode("utf-8"))
    def open_pw(self, e) -> str: return GCM.decrypt(self.mem, e["pw"]).decode("utf-8")

    def public(self):
        return [{k: e.get(k, "") for k in ("id", "title", "username", "url", "notes", "pinned", "created", "modified")} for e in self.entries]

    def emit(self):
        send({"ev": "state", "state": self.state, "problem": self.problem, "code": self.code,
              "hasBak": self.has_bak, "entries": self.public() if self.state == "ready" else []})

    def touch(self): self.last_use = time.monotonic()

    def _fail(self, state, err):
        self.state, self.code, self.problem = state, err.code, err.msg
        self.entries, self.key = [], None
        self.has_bak = os.path.exists(BAK)

    def load(self, interactive=False):
        with self.lock:
            self.state, self.problem, self.code = "loading", "", ""
            try:
                key = key_lookup(interactive)
            except VaultError as e:
                self._fail("nokeyring", e); return
            # an interrupted save: the main file is gone but the finished tmp is there
            if not os.path.exists(VAULT) and os.path.exists(TMP) and key:
                try:
                    unpack(key, read_file(TMP)); os.replace(TMP, VAULT); log("recovered an interrupted save")
                except Exception:
                    pass
            if not os.path.exists(VAULT):
                if key is None:
                    if os.path.exists(BAK):
                        self._fail("corrupt", VaultError("nokey", "The vault key is missing from the keyring.")); return
                    key = secrets.token_bytes(32)
                    try:
                        key_store(key)
                    except VaultError as e:
                        self._fail("nokeyring", e); return
                self.key = key
                self.entries = []
                self._save()
                self.state = "ready"; self.has_bak = os.path.exists(BAK)
                log("new vault created"); return
            if key is None:
                self._fail("corrupt", VaultError("nokey", "The vault key is missing from the keyring.")); return
            try:
                payload = json.loads(unpack(key, read_file(VAULT)).decode("utf-8"))
            except VaultError as e:
                self._fail("corrupt", e); log("vault did not open: " + e.code); return
            except Exception:
                self._fail("corrupt", VaultError("payload", "The vault contents are not readable.")); return
            self.key = key
            self.entries = [self._from_disk(e) for e in payload.get("entries", []) if isinstance(e, dict)]
            self.state = "ready"; self.has_bak = os.path.exists(BAK)
            self.touch()

    def _from_disk(self, e):
        d = {k: str(e.get(k, "")) for k in ("id", "title", "username", "url", "notes", "created", "modified")}
        d["id"] = d["id"] or str(uuid.uuid4())
        d["pinned"] = bool(e.get("pinned", False))
        d["pw"] = self.seal(str(e.get("password", "")))
        return d

    def _save(self):
        items = []
        for e in self.entries:
            d = {k: e.get(k, "") for k in ("id", "title", "username", "url", "notes", "pinned", "created", "modified")}
            d["password"] = self.open_pw(e)
            items.append(d)
        raw = json.dumps({"version": 1, "entries": items}, ensure_ascii=False).encode("utf-8")
        data = pack(self.key, raw)
        # never back up a file that does not open with our key (keeps the .bak a good copy)
        keep = False
        if os.path.exists(VAULT):
            try: unpack(self.key, read_file(VAULT)); keep = True
            except Exception: keep = False
        atomic_write(VAULT, data, keep_bak=keep)
        self.has_bak = os.path.exists(BAK)

    def need_ready(self):
        if self.state != "ready":
            raise VaultError("state", {"locked": "The vault is locked.", "nokeyring": "The keyring is not available."}.get(self.state, self.problem or "The vault is not available."))

    def find(self, eid):
        for e in self.entries:
            if e["id"] == eid: return e
        raise VaultError("missing", "That password is not available.")

    def add(self, x):
        with self.lock:
            self.need_ready(); self.touch()
            title = str(x.get("title", "")).strip()[:80]
            pw = str(x.get("password", ""))
            if not title: raise VaultError("input", "Enter a title.")
            if not pw: raise VaultError("input", "Enter a password.")
            now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            e = {"id": str(uuid.uuid4()), "title": title, "username": str(x.get("username", ""))[:200],
                 "url": str(x.get("url", ""))[:500], "notes": str(x.get("notes", ""))[:2000],
                 "pinned": bool(x.get("pinned", False)), "created": now, "modified": now, "pw": self.seal(pw)}
            old = list(self.entries)
            self.entries.append(e)
            try: self._save()
            except Exception:
                self.entries = old; raise VaultError("io", "Could not save the vault.")
            return e["id"]

    def update(self, eid, x, replace_pw):
        with self.lock:
            self.need_ready(); self.touch()
            cur = self.find(eid)
            title = str(x.get("title", "")).strip()[:80]
            if not title: raise VaultError("input", "Enter a title.")
            n = dict(cur)
            n.update({"title": title, "username": str(x.get("username", ""))[:200], "url": str(x.get("url", ""))[:500],
                      "notes": str(x.get("notes", ""))[:2000], "pinned": bool(x.get("pinned", False)),
                      "modified": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
            if replace_pw:
                pw = str(x.get("password", ""))
                if not pw: raise VaultError("input", "Enter a password.")
                n["pw"] = self.seal(pw)
            old = list(self.entries)
            self.entries = [n if e["id"] == eid else e for e in self.entries]
            try: self._save()
            except Exception:
                self.entries = old; raise VaultError("io", "Could not save the vault.")

    def delete(self, eid):
        with self.lock:
            self.need_ready(); self.touch()
            self.find(eid)
            old = list(self.entries)
            self.entries = [e for e in self.entries if e["id"] != eid]
            try: self._save()
            except Exception:
                self.entries = old; raise VaultError("io", "Could not save the vault.")

    def reveal(self, eid):
        with self.lock:
            self.need_ready(); self.touch()
            return self.open_pw(self.find(eid))

    def lock_now(self):
        with self.lock:
            if self.state == "ready":
                self.entries, self.key = [], None
                self.mem = secrets.token_bytes(32)
                self.state = "locked"; self.problem = ""

    def recover(self, action):
        with self.lock:
            if self.state != "corrupt":
                return
            stamp = time.strftime("%Y%m%d-%H%M%S")
            if action == "restore":
                key = key_lookup()
                if not key or not os.path.exists(BAK):
                    raise VaultError("restore", "There is no usable backup.")
                try:
                    unpack(key, read_file(BAK))
                except VaultError:
                    raise VaultError("restore", "The backup does not open either.")
                if os.path.exists(VAULT):
                    os.replace(VAULT, VAULT + ".broken-" + stamp)
                shutil.copy2(BAK, VAULT)
                log("restored from backup")
                self.load()
            elif action == "new":
                for p in (VAULT, BAK):         # keep the bad files aside, never delete them here
                    if os.path.exists(p):
                        os.replace(p, p + ".broken-" + stamp)
                if self.code == "nokey" or key_lookup() is None:
                    key_clear()
                log("started a new vault (old files kept as .broken-*)")
                self.load()
            # "leave": nothing changes; the vault stays unavailable until restored

    def wipe(self):
        with self.lock:
            for p in os.listdir(DATA_DIR) if os.path.isdir(DATA_DIR) else []:
                if p.startswith("vault.dat"):
                    try: os.remove(os.path.join(DATA_DIR, p))
                    except OSError: pass
            key_clear()
            self.entries, self.key = [], None
            self.mem = secrets.token_bytes(32)
            log("all password data deleted")
            self.load()


# ── password generator (port of PasswordGenerator.cs) ─────────────────
UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
LOWER = "abcdefghijklmnopqrstuvwxyz"
DIGITS = "0123456789"
DEFAULT_SYMBOLS = "!@#$%^&*()-_=+[]{};:,.?"
AMBIGUOUS = "Il1|O0o"


def sanitize_symbols(s):
    out = ""
    for c in str(s or ""):
        if " " < c < "\x7f" and not c.isalnum() and c not in out:
            out += c
    return out


def classes(p):
    res = []
    def add(on, chars):
        if not on: return
        f = "".join(c for c in chars if c not in AMBIGUOUS) if p.get("excludeAmbiguous") else chars
        if f: res.append(f)
    add(p.get("upper", True), UPPER)
    add(p.get("lower", True), LOWER)
    add(p.get("digits", True), DIGITS)
    add(p.get("symbols", True), sanitize_symbols(p.get("symbolSet", DEFAULT_SYMBOLS)))
    return res


def validate(p):
    n = int(p.get("length", 32))
    if n < 4 or n > 256: return "Password length must be between 4 and 256 characters."
    c = classes(p)
    if not c: return "Enable at least one character group."
    if n < len(c): return "The password is too short to contain every enabled character group."
    return None


def generate(p):
    if validate(p):
        p = {"length": 32}
    cl = classes(p)
    alphabet = "".join(cl)
    n = int(p.get("length", 32))
    for _ in range(100000):
        # secrets.choice → randbelow: rejection sampling, no modulo bias. Whole candidates missing a class are
        # redrawn, which keeps the result uniform over all valid passwords.
        cand = "".join(secrets.choice(alphabet) for _ in range(n))
        if all(any(ch in c for ch in cand) for c in cl):
            return cand
    raise RuntimeError("generator")


def entropy_bits(p):
    import math
    a = sum(len(c) for c in classes(p))
    return 0.0 if a <= 1 else int(p.get("length", 32)) * math.log2(a)


# ── clipboard ─────────────────────────────────────────────────────────
class Clip:
    TEXT_TYPES = ("text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "TEXT", "STRING")

    def __init__(self):
        self.cfg = {"history": True, "limit": 20, "clearAfter": 90,
                    "ignored": ["keepassxc", "org.keepassxc.keepassxc", "bitwarden", "1password", "proton-pass", "proton pass",
                                "enpass", "nordpass", "kwalletmanager5", "org.kde.kwalletmanager5", "seahorse", "org.gnome.seahorse.application",
                                "secrets", "org.gnome.world.secrets", "gnome-passwords"]}
        self.items = []          # [{id, text, ts}] newest first - memory only
        self.ours = None         # sha256 of the last sensitive value we put on the clipboard
        self.timer = None
        self.watch = None
        self.lk = threading.Lock()

    def copy(self, text, sensitive):
        args = ["wl-copy", "--type", "text/plain;charset=utf-8"] + (["--sensitive"] if sensitive else [])
        try:
            # wl-copy forks a server that inherits stdout/stderr: never capture them or run() waits for it
            r = subprocess.run(args, input=text.encode("utf-8"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        except Exception:
            return False
        if r.returncode != 0:
            return False
        if sensitive:
            self.ours = hashlib.sha256(text.encode("utf-8")).digest()
            self.arm()
        return True

    def arm(self):
        if self.timer: self.timer.cancel(); self.timer = None
        sec = int(self.cfg.get("clearAfter", 0) or 0)
        if sec > 0 and self.ours:
            self.timer = threading.Timer(sec, self.autoclear); self.timer.daemon = True; self.timer.start()

    def autoclear(self):
        h = self.ours
        if not h: return
        try:
            cur = subprocess.run(["wl-paste", "--no-newline"], capture_output=True, timeout=5).stdout
        except Exception:
            return
        if hashlib.sha256(cur).digest() == h:     # still exactly our value → clear; anything else is left alone
            subprocess.run(["wl-copy", "--clear"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            send({"ev": "toast", "text": "Clipboard cleared", "icon": "clear"})
        self.ours = None

    # history ───────────────────────────────────────────
    def start_watch(self):
        if self.watch and self.watch.poll() is None: return
        try:
            self.watch = subprocess.Popen(["wl-paste", "--watch", "sh", "-c", "cat >/dev/null; echo x"],
                                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                                          preexec_fn=die_with_parent)
        except Exception:
            log("wl-paste --watch could not start"); return
        threading.Thread(target=self._loop, args=(self.watch,), daemon=True).start()

    def stop_watch(self):
        if self.watch and self.watch.poll() is None:
            self.watch.terminate()
        self.watch = None

    def _loop(self, proc):
        for _ in proc.stdout:
            try: self.on_change()
            except Exception: log("history event failed")

    def on_change(self):
        if not self.cfg.get("history", True): return
        try:
            types = subprocess.run(["wl-paste", "--list-types"], capture_output=True, text=True, timeout=5).stdout.split("\n")
        except Exception:
            return
        if "x-kde-passwordManagerHint" in types:
            try:
                hint = subprocess.run(["wl-paste", "-t", "x-kde-passwordManagerHint"], capture_output=True, text=True, timeout=5).stdout.strip()
            except Exception:
                hint = "secret"
            if hint == "secret": return
        t = next((x for x in self.TEXT_TYPES if x in types), None)
        if not t: return
        if self.ignored_focus(): return
        try:
            raw = subprocess.run(["wl-paste", "--no-newline", "-t", t], capture_output=True, timeout=5).stdout
        except Exception:
            return
        if not raw or len(raw) > 100000: return
        if self.ours and hashlib.sha256(raw).digest() == self.ours: return
        text = raw.decode("utf-8", "replace")
        if not text.strip(): return
        with self.lk:
            self.items = [i for i in self.items if i["text"] != text]
            self.items.insert(0, {"id": str(uuid.uuid4()), "text": text, "ts": int(time.time())})
            del self.items[max(5, int(self.cfg.get("limit", 20))):]
        self.emit()

    def ignored_focus(self):
        try:
            w = json.loads(subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True, timeout=3).stdout or "{}")
        except Exception:
            return False
        names = {str(w.get("class", "")).lower(), str(w.get("initialClass", "")).lower()}
        ign = {str(a).strip().lower() for a in self.cfg.get("ignored", []) if str(a).strip()}
        return bool(names & ign)

    def emit(self):
        with self.lk:
            send({"ev": "history", "items": list(self.items)})

    def remove(self, hid):
        with self.lk: self.items = [i for i in self.items if i["id"] != hid]
        self.emit()

    def clear(self):
        with self.lk: self.items = []
        self.emit()

    def get(self, hid):
        with self.lk:
            for i in self.items:
                if i["id"] == hid: return i["text"]
        return None


# ── main loop ─────────────────────────────────────────────────────────
V = Vault()
C = Clip()
AUTOLOCK = {"min": 0}


def autolock_loop():
    while True:
        time.sleep(20)
        m = AUTOLOCK["min"]
        if m > 0 and V.state == "ready" and time.monotonic() - V.last_use > m * 60:
            V.lock_now(); V.emit(); log("auto-locked")


def handle(m):
    cmd = m.get("cmd")
    if cmd == "status":
        V.emit(); C.emit(); return {}
    if cmd == "config":
        c = m.get("clip") or {}
        C.cfg.update({k: c[k] for k in ("history", "limit", "clearAfter", "ignored") if k in c})
        AUTOLOCK["min"] = int(m.get("autoLock", 0) or 0)
        if C.cfg.get("history", True): C.start_watch()
        else: C.stop_watch(); C.clear()
        with C.lk: del C.items[max(5, int(C.cfg.get("limit", 20))):]
        C.emit(); return {}
    if cmd == "unlock":
        if V.state in ("locked", "nokeyring", "loading"): V.load(interactive=True)
        V.emit(); return {}
    if cmd == "lock":
        V.lock_now(); V.emit(); return {}
    if cmd == "add":
        eid = V.add(m.get("entry") or {}); V.emit(); return {"entryId": eid}
    if cmd == "update":
        V.update(m.get("entryId", ""), m.get("entry") or {}, bool(m.get("replacePassword"))); V.emit(); return {}
    if cmd == "delete":
        V.delete(m.get("entryId", "")); V.emit(); return {}
    if cmd == "reveal":
        return {"password": V.reveal(m.get("entryId", ""))}
    if cmd == "copy":                    # field: password | username
        e_id, field = m.get("entryId", ""), m.get("field", "password")
        with V.lock:
            V.need_ready(); V.touch()
            e = V.find(e_id)
            val = V.open_pw(e) if field == "password" else e.get("username", "")
        if not val: raise VaultError("empty", "Nothing to copy.")
        if not C.copy(val, field == "password"): raise VaultError("clip", "Could not access the clipboard.")
        return {}
    if cmd == "generate":
        p = m.get("policy") or {}
        pw = generate(p)
        if m.get("copy"):
            if not C.copy(pw, True): raise VaultError("clip", "Could not access the clipboard.")
            return {"bits": entropy_bits(p) if not validate(p) else entropy_bits({"length": 32})}
        return {"password": pw, "bits": entropy_bits(p), "problem": validate(p) or ""}
    if cmd == "policyInfo":
        p = m.get("policy") or {}
        return {"bits": entropy_bits(p), "problem": validate(p) or ""}
    if cmd == "copyText":                # editor / details: copy a value the UI already has
        if not C.copy(str(m.get("text", "")), bool(m.get("sensitive"))): raise VaultError("clip", "Could not access the clipboard.")
        return {}
    if cmd == "copyHistory":
        t = C.get(m.get("histId", ""))
        if t is None: raise VaultError("missing", "That item is gone.")
        if not C.copy(t, False): raise VaultError("clip", "Could not access the clipboard.")
        return {}
    if cmd == "histRemove":
        C.remove(m.get("histId", "")); return {}
    if cmd == "histClear":
        C.clear(); return {}
    if cmd == "recover":
        V.recover(m.get("action", "leave")); V.emit(); return {}
    if cmd == "wipe":
        V.wipe(); C.clear(); V.emit(); return {}
    raise VaultError("cmd", "Unknown command.")


def main():
    die_with_parent()
    signal.signal(signal.SIGTERM, lambda *_: (C.stop_watch(), os._exit(0)))
    threading.Thread(target=autolock_loop, daemon=True).start()
    V.load(); V.emit(); C.emit()
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        rid = m.get("id")
        try:
            r = handle(m) or {}
            r.update({"re": rid, "ok": True})
        except VaultError as e:
            r = {"re": rid, "ok": False, "error": e.msg}
        except Exception as e:
            log("command failed: " + type(e).__name__)
            r = {"re": rid, "ok": False, "error": "Something went wrong."}
        send(r)
    C.stop_watch()


if __name__ == "__main__":
    try:
        main()
    finally:
        C.stop_watch()
