#!/usr/bin/env python3
# sakura mono - file converter behind the radial menu (quickshell Convert.qml), DragShift-style.
#   convert.py run OP FILE…        → do OP on every file; result next to the original (unique name), original untouched
#   convert.py ui FILE…            → open the radial menu for these files (Dolphin right-click → Convert…)
#   convert.py cancel JOB          → stop a running job (the × on its progress card)
#   convert.py edit MODE FILE      → crop | edit | redact in the screenshot editor (Shot.qml, file mode)
#   convert.py editdone ANN BARE X Y W H   → Shot.qml saved: put the drawing back onto the full-size original
#   convert.py duration FILE       → seconds (for the trim dialog)
# OPs: to:<fmt> (png jpg webp avif heic gif ico bmp tiff pdf · mp4 webm mkv gif mp3 ogg flac wav opus m4a · audio = extract as is)
#      info strip compress:normal|strong resize:50|25|1080|720|480 rotate:cw|ccw|180|flipx|flipy rmbg bg:accent|white|black
#      vcompress:normal|strong vresize:1080|720|480|50 vrotate:cw|ccw|180 trim:S:E mute speed:2|0.5 frame
#      acompress:128|64 normalize silence
# Done → a notification "2.4 MB → 610 KB · 75% smaller" with Open / Show in folder / Undo (Undo = gio trash).
# Long jobs report progress to the menu's progress card: qs ipc call convert progress JOB PCT TITLE SUB.
# Tools: magick (imagemagick + libheif + ghostscript), ffmpeg/ffprobe, gio, rembg (optional, Remove BG).
import json, os, re, shutil, signal, subprocess, sys, tempfile, time

HOME = os.path.expanduser("~")
RUN = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
STATE = os.path.join(RUN, "sakura-convert")
os.makedirs(STATE, exist_ok=True)
APP = "Converter"

try:
    _set = json.load(open(os.path.join(HOME, ".config/sakura/settings.json")))
except Exception:
    _set = {}
LANG = _set.get("lang", "en")
RU = {
    "Converter": "Конвертер", "smaller": "меньше", "larger": "больше", "same size": "тот же размер",
    "Open": "Открыть", "Show in folder": "В папке", "Undo": "Отменить", "Details": "Подробно", "Remove EXIF": "Удалить EXIF",
    "files": "файлов", "Failed": "Не вышло", "Cancelled": "Отменено", "Moved to trash": "Перемещено в корзину", "Deleted": "Удалено",
    "Converting": "Конвертация", "Working": "Обработка", "pages": "стр.", "first 30 s": "первые 30 с",
    "Remove BG needs rembg": "Для «Убрать фон» нужен rembg",
    "Install it (no sudo):": "Установить (без sudo):",
    "Not for this file": "Не для этого файла", "No metadata": "Нет метаданных", "Metadata": "Метаданные",
    "Metadata removed": "Метаданные удалены", "Edited": "Отредактировано", "Cropped": "Обрезано",
    "Location": "Геометка", "yes": "есть", "Camera": "Камера", "Taken": "Снято", "Size": "Размер", "Duration": "Длительность",
    "Video": "Видео", "Audio": "Звук", "Background removed": "Фон убран", "Background added": "Фон добавлен",
    "Trimmed": "Обрезано", "Sound removed": "Звук убран", "Frame saved": "Кадр сохранён", "Done": "Готово",
    "Normalized": "Громкость выровнена", "Silence trimmed": "Тишина обрезана", "Rotated": "Повёрнуто", "Flipped": "Отражено",
    "Resized": "Размер изменён", "already as small as it gets": "меньше уже не сжать", "Compressed": "Сжато", "combined": "в один", "The editor isn't available": "Редактор недоступен",
}
def tr(s): return RU.get(s, s) if LANG == "ru" else s

IMG = {"png", "jpg", "jpeg", "webp", "avif", "heic", "heif", "gif", "ico", "bmp", "tif", "tiff", "jxl"}
VID = {"mp4", "webm", "mkv", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg", "ts", "3gp"}
AUD = {"mp3", "ogg", "oga", "flac", "wav", "opus", "m4a", "aac", "wma", "aiff", "alac"}

def ext(p): return os.path.splitext(p)[1][1:].lower()
def kind(p):
    e = ext(p)
    return "image" if e in IMG else "pdf" if e == "pdf" else "video" if e in VID else "audio" if e in AUD else "other"
def stem(p): return os.path.splitext(os.path.basename(p))[0]

def uniq(d, name, e):
    out = os.path.join(d, f"{name}.{e}"); n = 2
    while os.path.exists(out):
        out = os.path.join(d, f"{name} ({n}).{e}"); n += 1
    return out

def human(n):
    n = float(n)
    for u in ("B", "KB", "MB", "GB"):
        if n < 1024 or u == "GB":
            s = f"{n:.0f}" if u in ("B", "KB") or n >= 100 else f"{n:.1f}"
            return f"{s} {u}" if LANG != "ru" else f"{s} " + {"B": "Б", "KB": "КБ", "MB": "МБ", "GB": "ГБ"}[u]
        n /= 1024

def dims(p):
    try:
        o = subprocess.run(["magick", "identify", "-format", "%w %h\n", p + "[0]"], capture_output=True, text=True, timeout=20).stdout.split()
        return int(o[0]), int(o[1])
    except Exception:
        return None

def vdims(p):
    pr = probe(p)
    for s in pr.get("streams", []):
        if s.get("codec_type") == "video" and s.get("width"):
            return int(s["width"]), int(s["height"])
    return None

def probe(p):
    try:
        return json.loads(subprocess.run(["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", p],
                                         capture_output=True, text=True, timeout=20).stdout or "{}")
    except Exception:
        return {}

def duration(p):
    try: return float(probe(p).get("format", {}).get("duration", 0) or 0)
    except Exception: return 0.0

def codecs(p):
    v = a = None
    for s in probe(p).get("streams", []):
        if s.get("codec_type") == "video" and not v and s.get("disposition", {}).get("attached_pic") != 1: v = s.get("codec_name")
        if s.get("codec_type") == "audio" and not a: a = s.get("codec_name")
    return v, a

def frames(p):
    try:
        o = subprocess.run(["magick", "identify", "-format", "%n\n", p], capture_output=True, text=True, timeout=20).stdout.split()
        return int(o[0]) if o else 1
    except Exception:
        return 1

def hasalpha(p):
    try:
        o = subprocess.run(["magick", "identify", "-format", "%[opaque]", p + "[0]"], capture_output=True, text=True, timeout=20).stdout.strip().lower()
        return o == "false"
    except Exception:
        return False

def ipc(*a):
    try: subprocess.run(["qs", "ipc", "call", "convert", *[str(x) for x in a]], capture_output=True, timeout=1.5)
    except Exception: pass

QUIET = os.environ.get("SAKURA_CONVERT_QUIET") == "1"      # tests: print instead of notifying
def note(summary, body="", icon="emblem-synchronizing", image=None, urgency=None):
    if QUIET: print("NOTE:", summary, "|", body.replace("\n", " / ")); return
    cmd = ["notify-send", "-a", tr(APP), "-i", icon]
    if image: cmd += ["-h", f"string:image-path:{image}"]
    if urgency: cmd += ["-u", urgency]
    subprocess.run(cmd + [summary, body], capture_output=True)

def esc(s): return re.sub(r"[&<>]", " ", str(s))

# a notification with buttons; a detached child waits for the click so this script can end
def note_actions(summary, body, actions, handler, icon="emblem-synchronizing", image=None):
    if QUIET: print("NOTE+:", summary, "|", body.replace("\n", " / "), "|", [k for k, _ in actions]); return
    if os.fork() != 0: return
    os.setsid()
    if os.fork() != 0: os._exit(0)
    cmd = ["timeout", "7200", "notify-send", "-a", tr(APP), "-i", icon, "--wait"]
    if image: cmd += ["-h", f"string:image-path:{image}"]
    for k, t in actions: cmd += ["-A", f"{k}={t}"]
    try:
        r = subprocess.run(cmd + [summary, body], capture_output=True, text=True).stdout.strip().splitlines()
        if r: handler(r[-1].strip())
    except Exception:
        pass
    os._exit(0)

def open_file(p): subprocess.Popen(["xdg-open", p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
def show_in_folder(p):
    if shutil.which("dolphin"): subprocess.Popen(["dolphin", "--select", p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    else: open_file(os.path.dirname(p))

def done_note(outs, srcs, title, extra=""):
    outs = [o for o in outs if o and os.path.exists(o)]
    if not outs: return
    a = sum(os.path.getsize(s) for s in srcs if os.path.exists(s)); b = sum(os.path.getsize(o) for o in outs)
    pct = round((1 - b / a) * 100) if a else 0
    sz = f"{human(a)} → {human(b)}"
    if a and abs(pct) >= 1: sz += f" · {abs(pct)}% {tr('smaller') if pct > 0 else tr('larger')}"
    names = esc(", ".join(os.path.basename(o) for o in outs[:3]) + (" …" if len(outs) > 3 else ""))
    summary = sz if not extra else f"{extra} · {sz}"
    img = outs[0] if kind(outs[0]) == "image" and ext(outs[0]) not in ("ico",) else None
    def h(act):
        if act in ("open", "default"): open_file(outs[0])
        elif act == "show": show_in_folder(outs[0])
        elif act == "undo":
            gone = False
            for o in outs:      # to the trash; where there is none (tmpfs, some USB sticks) the new file is just removed
                if subprocess.run(["gio", "trash", "--", o], capture_output=True).returncode != 0:
                    try: os.remove(o); gone = True
                    except Exception: pass
            note(tr("Deleted") if gone else tr("Moved to trash"), esc(", ".join(os.path.basename(o) for o in outs[:3])), "user-trash")
    note_actions(f"{title}", f"{esc(summary)}<br>{names}", [("default", tr("Open")), ("open", tr("Open")), ("show", tr("Show in folder")), ("undo", tr("Undo"))],
                 h, icon="emblem-synchronizing", image=img)

# ── running external tools, cancellable ─────────────────────────────
JOB = None
CHILD = None
PARTIAL = []
def on_term(*_):
    if CHILD and CHILD.poll() is None:
        try: CHILD.terminate(); CHILD.wait(3)
        except Exception: pass
    for p in PARTIAL:
        try: os.remove(p)
        except Exception: pass
    if JOB: ipc("finished", JOB)
    note(tr("Cancelled"), "", "process-stop")
    try: os.remove(os.path.join(STATE, f"{JOB}.pid"))
    except Exception: pass
    os._exit(1)

class Fail(Exception): pass

def sh(cmd, timeout=None):
    global CHILD
    CHILD = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    try: _, err = CHILD.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        CHILD.kill(); raise Fail("timeout")
    if CHILD.returncode != 0:
        raise Fail((err or "").strip().splitlines()[-1][:200] if (err or "").strip() else f"exit {CHILD.returncode}")

LAST_P = 0
def progress(pct, title, sub):
    global LAST_P
    now = time.time()
    if pct not in (-1, 0, 100) and now - LAST_P < 0.3: return
    LAST_P = now
    ipc("progress", JOB, int(pct), title, sub)

def ff(args, out, dur, title, sub):
    """ffmpeg with a progress bar; dur = seconds of output expected"""
    global CHILD
    PARTIAL.append(out)
    cmd = ["ffmpeg", "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats", *args, out]
    CHILD = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    t0 = time.time()
    for line in CHILD.stdout:
        if line.startswith("out_time_us=") or line.startswith("out_time_ms="):
            try: t = int(line.split("=")[1]) / 1e6
            except ValueError: continue
            if dur > 0:
                p = max(0, min(99, t / dur * 100)); el = time.time() - t0
                left = el / (p / 100) - el if p > 2 else 0
                progress(p, title, sub + (f" · ~{int(left // 60)}:{int(left % 60):02d}" if left > 3 else ""))
    err = CHILD.stderr.read()
    CHILD.wait()
    PARTIAL.remove(out)
    if CHILD.returncode != 0:
        try: os.remove(out)
        except Exception: pass
        raise Fail((err or "").strip().splitlines()[-1][:200] if (err or "").strip() else "ffmpeg failed")

def mg(args, out):
    PARTIAL.append(out)
    try: sh(["magick", *args, out], timeout=600)
    except Fail:
        try: os.remove(out)
        except Exception: pass
        raise
    finally:
        if out in PARTIAL: PARTIAL.remove(out)

# ── images ───────────────────────────────────────────────────────────
QUAL = {"jpg": ["-quality", "90"], "webp": ["-quality", "88"], "avif": ["-quality", "60"], "heic": ["-quality", "80"],
        "png": ["-define", "png:compression-level=9"], "tiff": ["-compress", "lzw"], "jxl": ["-quality", "90"]}

def img_out_ext(src):
    e = ext(src)
    return {"jpeg": "jpg", "heif": "heic", "tif": "tiff"}.get(e, e) if e in IMG else "png"

def img_convert(src, fmt):
    d = os.path.dirname(src); fmt = "jpg" if fmt == "jpeg" else fmt
    anim = ext(src) in ("gif", "webp") and frames(src) > 1
    if fmt in ("mp4", "webm"):
        return [vid_convert(src, fmt)]
    out = uniq(d, stem(src), fmt)
    first = src if (anim and fmt in ("gif", "webp")) else src + "[0]"
    a = ["-auto-orient"] if not anim else []
    if fmt == "jpg" or fmt == "bmp": a += ["-background", "white", "-alpha", "remove", "-alpha", "off"]
    if fmt == "ico": a += ["-background", "none", "-resize", "256x256", "-gravity", "center", "-extent", "256x256",
                           "-define", "icon:auto-resize=256,128,64,48,32,16"]
    if fmt == "gif" and not anim: a += ["-colors", "256"]
    if ext(src) == "pdf": first = src
    mg([first, *a, *QUAL.get(fmt, [])], out)
    return [out]

def pdf_pages(src, fmt):
    d = os.path.dirname(src); tmp = tempfile.mkdtemp(dir=STATE)
    try:
        bg = ["-background", "white", "-alpha", "remove", "-alpha", "off"]
        sh(["magick", "-density", "150", src, *bg, *QUAL.get(fmt, []), os.path.join(tmp, f"p-%04d.{fmt}")], timeout=900)
        pages = sorted(os.listdir(tmp)); outs = []
        for i, p in enumerate(pages):
            out = uniq(d, stem(src) if len(pages) == 1 else f"{stem(src)}-{i + 1}", fmt)
            shutil.move(os.path.join(tmp, p), out); outs.append(out)
        return outs
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def srcq(src):
    try: return int(subprocess.run(["magick", "identify", "-format", "%Q", src + "[0]"], capture_output=True, text=True, timeout=20).stdout.strip() or 92)
    except Exception: return 92

def keepq(src, e):
    """re-encode a lossy picture at the quality it already had (no bloat from a rotate / resize)"""
    return ["-quality", str(min(92, srcq(src)))] if e in ("jpg", "webp", "heic", "avif", "jxl") else QUAL.get(e, [])

def img_tool(src, op, arg):
    d = os.path.dirname(src); e = img_out_ext(src); s = stem(src)
    anim = ext(src) in ("gif", "webp") and frames(src) > 1
    inp = src if anim else src + "[0]"
    pre = ["-coalesce"] if anim else ["-auto-orient"]
    if op == "compress":
        out = uniq(d, f"{s}-small", e)
        q = {"normal": {"jpg": "78", "webp": "75", "avif": "50", "heic": "60", "jxl": "75"},
             "strong": {"jpg": "62", "webp": "60", "avif": "38", "heic": "45", "jxl": "60"}}[arg if arg in ("normal", "strong") else "normal"]
        a = ["-strip"]
        if e == "png": a += ["-define", "png:compression-level=9", "-colors", "256" if arg != "strong" else "128", "-dither", "FloydSteinberg"]
        elif e == "gif": a += ["-layers", "Optimize", "-fuzz", "3%" if arg != "strong" else "8%"]
        elif e in q: a += ["-quality", str(min(int(q[e]), srcq(src) - (8 if arg != "strong" else 18)))]
        if arg == "strong" and not anim: a += ["-resize", "2560x2560>"]
        mg([inp, *pre, *a], out)
        if os.path.getsize(out) >= os.path.getsize(src) and e == "png":
            os.remove(out); mg([inp, *pre, "-strip", "-define", "png:compression-level=9", "-define", "png:compression-filter=5"], out)
        if os.path.getsize(out) >= os.path.getsize(src):
            os.remove(out); raise Fail(tr("already as small as it gets"))
        return out
    if op == "resize":
        wh = dims(src) or (0, 0)
        if arg in ("50", "25"): geo = f"{arg}%"; tag = f"{arg}%"
        else:
            n = int(arg); short = min(wh)
            if short and short <= n: raise Fail(f"{wh[0]}×{wh[1]} ≤ {n}p")
            geo = f"x{n}" if wh[0] >= wh[1] else f"{n}x"; tag = f"{n}p"
        out = uniq(d, f"{s}-{tag}", e)
        mg([inp, *pre, "-resize", geo, *keepq(src, e)], out); return out
    if op == "rotate":
        m = {"cw": (["-rotate", "90"], "rotated"), "ccw": (["-rotate", "-90"], "rotated"), "180": (["-rotate", "180"], "rotated"),
             "flipx": (["-flop"], "flipped"), "flipy": (["-flip"], "flipped")}[arg or "cw"]
        out = uniq(d, f"{s}-{m[1]}", e)
        mg([inp, *pre, *m[0], *keepq(src, e)], out); return out
    if op == "strip":
        out = uniq(d, f"{s}-clean", e)
        mg([inp, *pre, "-strip", *keepq(src, e)], out); return out
    if op == "rmbg":
        rb = shutil.which("rembg") or (os.path.join(HOME, ".local/bin/rembg") if os.access(os.path.join(HOME, ".local/bin/rembg"), os.X_OK) else None)
        if not rb: raise Fail("rembg")
        out = uniq(d, f"{s}-nobg", "png")
        tmp = None; srcp = src
        if ext(src) not in ("png", "jpg", "jpeg", "webp", "bmp"):
            tmp = os.path.join(STATE, f"rb-{os.getpid()}.png"); sh(["magick", src + "[0]", "-auto-orient", tmp]); srcp = tmp
        PARTIAL.append(out)
        try: sh([rb, "i", srcp, out], timeout=900)
        finally:
            PARTIAL.remove(out)
            if tmp:
                try: os.remove(tmp)
                except Exception: pass
        return out
    if op == "bg":
        out = uniq(d, f"{s}-bg", "png" if arg == "accent" else ("jpg" if e in ("jpg", "heic", "avif") else "png"))
        if arg in ("white", "black"):
            mg([src + "[0]", "-auto-orient", "-background", arg, "-alpha", "remove", "-alpha", "off"], out); return out
        # accent: the picture on a soft accent gradient card, padded, rounded corners and a shadow
        acc = _set.get("accent") or "#e8a0bf"
        w, h = dims(src) or (1000, 1000)
        pad = max(24, round(max(w, h) * 0.07)); r = max(8, round(min(w, h) * 0.03))
        tmp = os.path.join(STATE, f"bg-{os.getpid()}.png")
        try:
            if hasalpha(src): sh(["magick", src + "[0]", "-auto-orient", tmp])
            else:
                sh(["magick", src + "[0]", "-auto-orient", "-alpha", "set", "(", "+clone", "-alpha", "off", "-fill", "black", "-colorize", "100",
                    "-fill", "white", "-draw", f"roundrectangle 0,0 {w - 1},{h - 1} {r},{r}", ")", "-alpha", "off", "-compose", "CopyOpacity", "-composite", tmp])
            W, H = w + pad * 2, h + pad * 2
            mg(["-size", f"{W}x{H}", f"gradient:{acc}-#1a1420", "-rotate", "0",
                "(", tmp, "-background", "#000000", "-shadow", f"60x{max(6, pad // 4)}+0+{max(4, pad // 8)}", ")", "-gravity", "center", "-compose", "over", "-composite",
                tmp, "-gravity", "center", "-compose", "over", "-composite"], out)
        finally:
            try: os.remove(tmp)
            except Exception: pass
        return out
    raise Fail("unknown tool")

def img_info(src):
    wh = dims(src)
    try:
        raw = subprocess.run(["magick", "identify", "-format", "%[EXIF:*]", src + "[0]"], capture_output=True, text=True, timeout=20).stdout
    except Exception:
        raw = ""
    ex = {}
    for l in raw.splitlines():
        if "=" in l:
            k, v = l.split("=", 1); ex[k.replace("exif:", "")] = v.strip()
    lines = [f"{tr('Size')}: {wh[0]}×{wh[1]} · {human(os.path.getsize(src))} · {ext(src).upper()}" if wh else ""]
    cam = " ".join(x for x in (ex.get("Make", ""), ex.get("Model", "")) if x).strip()
    if cam: lines.append(f"{tr('Camera')}: {cam}")
    if ex.get("DateTimeOriginal"): lines.append(f"{tr('Taken')}: {ex['DateTimeOriginal']}")
    if any(k.startswith("GPS") for k in ex): lines.append(f"{tr('Location')}: {tr('yes')} ⚠")
    lines.append(f"EXIF: {len(ex)}" if ex else tr("No metadata"))
    dump = os.path.join(STATE, f"info-{stem(src)}.txt")
    try:
        with open(dump, "w") as f:
            f.write(subprocess.run(["magick", "identify", "-verbose", src + "[0]"], capture_output=True, text=True, timeout=30).stdout)
    except Exception: pass
    def h(act):
        if act == "details": open_file(dump)
        elif act == "strip":
            subprocess.Popen([sys.executable, "-I", os.path.abspath(__file__), "run", "strip", src], start_new_session=True)
    acts = [("details", tr("Details"))] + ([("strip", tr("Remove EXIF"))] if ex else [])
    note_actions(f"{tr('Metadata')} · {esc(os.path.basename(src))}", esc("\n".join(l for l in lines if l)), acts, h, icon="dialog-information", image=src)

def av_info(src):
    pr = probe(src); fm = pr.get("format", {}); lines = []
    dur = float(fm.get("duration", 0) or 0)
    lines.append(f"{tr('Duration')}: {int(dur // 60)}:{int(dur % 60):02d} · {human(os.path.getsize(src))} · {ext(src).upper()}")
    for s in pr.get("streams", []):
        if s.get("codec_type") == "video" and s.get("disposition", {}).get("attached_pic") != 1:
            fps = s.get("avg_frame_rate", "0/1"); n, dd = (fps.split("/") + ["1"])[:2]
            fr = round(float(n) / float(dd), 2) if float(dd or 0) else 0
            lines.append(f"{tr('Video')}: {s.get('codec_name', '?')} {s.get('width')}×{s.get('height')} · {fr} fps")
        elif s.get("codec_type") == "audio":
            br = int(s.get("bit_rate", 0) or 0) // 1000
            lines.append(f"{tr('Audio')}: {s.get('codec_name', '?')} · {s.get('sample_rate', '?')} Hz · {s.get('channels', '?')} ch" + (f" · {br} kb/s" if br else ""))
    tags = fm.get("tags", {})
    for k in ("title", "artist", "album", "creation_time"):
        if tags.get(k): lines.append(f"{k}: {tags[k]}")
    dump = os.path.join(STATE, f"info-{stem(src)}.txt")
    with open(dump, "w") as f: f.write(json.dumps(pr, indent=2, ensure_ascii=False))
    note_actions(f"{tr('Metadata')} · {esc(os.path.basename(src))}", esc("\n".join(lines)), [("details", tr("Details"))],
                 lambda a: open_file(dump) if a == "details" else None, icon="dialog-information")

# ── video / audio ────────────────────────────────────────────────────
ACODEC = {"mp3": ["-c:a", "libmp3lame", "-q:a", "2"], "ogg": ["-c:a", "libvorbis", "-q:a", "5"], "flac": ["-c:a", "flac", "-sample_fmt", "s16"],
          "wav": ["-c:a", "pcm_s16le"], "opus": ["-c:a", "libopus", "-b:a", "128k"], "m4a": ["-c:a", "aac", "-b:a", "192k"]}
def venc(e, crf=None):
    if e == "webm":
        return ["-c:v", "libvpx-vp9", "-crf", str(crf or 32), "-b:v", "0", "-row-mt", "1", "-deadline", "good", "-cpu-used", "4",
                "-pix_fmt", "yuv420p", "-c:a", "libopus", "-b:a", "128k"]
    a = ["-c:v", "libx264", "-crf", str(crf or 20), "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k"]
    return a + (["-movflags", "+faststart"] if e in ("mp4", "mov", "m4v") else [])

def vid_convert(src, fmt):
    d = os.path.dirname(src); dur = duration(src); title = f"{ext(src).upper()} → {fmt.upper()}"; sub = os.path.basename(src)
    v, a = codecs(src)
    if fmt == "audio":
        e = {"aac": "m4a", "mp3": "mp3", "opus": "opus", "vorbis": "ogg", "flac": "flac", "ac3": "ac3", "pcm_s16le": "wav"}.get(a or "", "mka")
        if not a: raise Fail("no audio")
        out = uniq(d, stem(src), e)
        ff(["-i", src, "-vn", "-map", "0:a:0", "-c:a", "copy"], out, dur, title, sub); return out
    out = uniq(d, stem(src), fmt)
    if fmt in ACODEC:
        if not a: raise Fail("no audio")
        ff(["-i", src, "-vn", "-map", "0:a:0", *ACODEC[fmt]], out, dur, title, sub); return out
    if fmt == "gif":
        cut = min(dur, 30) if dur else 30
        ff(["-t", str(cut), "-i", src, "-vf", "fps=12,scale='min(640,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4",
            "-loop", "0"], out, cut, title, sub)
        return out
    copy = (fmt == "mkv" and v) or (fmt in ("mp4", "mov", "m4v") and v in ("h264", "hevc", "av1") and a in (None, "aac", "mp3", "alac")) \
        or (fmt == "webm" and v in ("vp8", "vp9", "av1") and a in (None, "opus", "vorbis"))
    if copy and ext(src) != "gif":
        try:
            ff(["-i", src, "-map", "0:v:0", "-map", "0:a?", "-c", "copy", *(["-movflags", "+faststart"] if fmt in ("mp4", "mov") else [])], out, dur, title, sub)
            return out
        except Fail: pass
    vf = ["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"] if fmt != "webm" else []
    ff(["-i", src, "-map", "0:v:0", "-map", "0:a?", *vf, *venc(fmt)], out, dur, title, sub)
    return out

def av_tool(src, op, arg):
    d = os.path.dirname(src); e = ext(src); s = stem(src); dur = duration(src); sub = os.path.basename(src)
    isvid = kind(src) == "video"
    ve = e if e in ("mp4", "webm", "mkv", "mov") else "mp4"
    if op == "vcompress":
        strong = arg == "strong"; n = 720 if strong else 1080
        out = uniq(d, f"{s}-small", "mp4")
        vf = f"scale='if(gte(iw,ih),-2,min({n},iw))':'if(gte(iw,ih),min({n},ih),-2)',scale=trunc(iw/2)*2:trunc(ih/2)*2"
        ff(["-i", src, "-map", "0:v:0", "-map", "0:a?", "-vf", vf, "-c:v", "libx264", "-crf", "32" if strong else "28", "-preset", "medium",
            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "96k" if strong else "128k", "-movflags", "+faststart"], out, dur, tr("Compressed"), sub)
        return out
    if op == "vresize":
        if arg == "50": vf = "scale=trunc(iw/4)*2:trunc(ih/4)*2"; tag = "50%"
        else:
            n = int(arg); wh = vdims(src)
            if wh and min(wh) <= n: raise Fail(f"{wh[0]}×{wh[1]} ≤ {n}p")
            vf = f"scale='if(gte(iw,ih),-2,{n})':'if(gte(iw,ih),{n},-2)'"; tag = f"{n}p"
        out = uniq(d, f"{s}-{tag}", ve)
        ff(["-i", src, "-map", "0:v:0", "-map", "0:a?", "-vf", vf, *venc(ve)], out, dur, tr("Resized"), sub); return out
    if op == "vrotate":
        vf = {"cw": "transpose=1", "ccw": "transpose=2", "180": "transpose=1,transpose=1"}[arg or "cw"]
        out = uniq(d, f"{s}-rotated", ve)
        ff(["-i", src, "-map", "0:v:0", "-map", "0:a?", "-vf", vf, *venc(ve)], out, dur, tr("Rotated"), sub); return out
    if op == "mute":
        out = uniq(d, f"{s}-muted", e)
        ff(["-i", src, "-map", "0:v", "-c", "copy", "-an"], out, dur, tr("Sound removed"), sub); return out
    if op == "speed":
        k = float(arg or 2)
        out = uniq(d, f"{s}-{arg}x", ve if isvid else e)
        af = f"atempo={k}" if 0.5 <= k <= 2 else f"atempo={k ** 0.5},atempo={k ** 0.5}"
        args = ["-i", src, "-filter:a", af]
        if isvid: args = ["-i", src, "-map", "0:v:0", "-map", "0:a?", "-filter:v", f"setpts={1 / k}*PTS", "-filter:a", af, *venc(ve)]
        else: args += ACODEC.get(e, [])
        ff(args, out, dur / k, f"{arg}×", sub); return out
    if op == "frame":
        out = uniq(d, f"{s}-frame", "png")
        ff(["-ss", f"{dur / 2:.2f}", "-i", src, "-frames:v", "1"], out, 0, tr("Frame saved"), sub); return out
    if op == "trim":
        a, b = [float(x) for x in arg.split(":")]
        if b <= a: raise Fail("end ≤ start")
        out = uniq(d, f"{s}-trim", ve if isvid else e)
        codec = venc(ve) if isvid else ACODEC.get(e, [])
        maps = ["-map", "0:v:0", "-map", "0:a?"] if isvid else ["-map", "0:a:0"]
        ff(["-ss", f"{a:.3f}", "-i", src, "-t", f"{b - a:.3f}", *maps, *codec], out, b - a, tr("Trimmed"), sub); return out
    if op == "acompress":
        out = uniq(d, f"{s}-small", "mp3")
        ff(["-i", src, "-vn", "-map", "0:a:0", "-c:a", "libmp3lame", "-b:a", f"{arg or 128}k"], out, dur, tr("Compressed"), sub); return out
    if op == "normalize":
        out = uniq(d, f"{s}-loud", e if e in ACODEC else "m4a")
        ff(["-i", src, "-vn", "-map", "0:a:0", "-af", "loudnorm=I=-14:TP=-1.5:LRA=11", "-ar", str(next((x.get("sample_rate") for x in probe(src).get("streams", []) if x.get("codec_type") == "audio"), "48000")), *ACODEC.get(e if e in ACODEC else "m4a")], out, dur, tr("Normalized"), sub)
        return out
    if op == "silence":
        out = uniq(d, f"{s}-trim", e if e in ACODEC else "m4a")
        f = "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1"
        ff(["-i", src, "-vn", "-map", "0:a:0", "-af", f"{f},areverse,{f},areverse", *ACODEC.get(e if e in ACODEC else "m4a")], out, dur, tr("Silence trimmed"), sub)
        return out
    raise Fail("unknown tool")

TITLES = {"compress": "Compressed", "vcompress": "Compressed", "acompress": "Compressed", "resize": "Resized", "vresize": "Resized",
          "rotate": "Rotated", "vrotate": "Rotated", "strip": "Metadata removed", "rmbg": "Background removed", "bg": "Background added",
          "trim": "Trimmed", "mute": "Sound removed", "frame": "Frame saved", "normalize": "Normalized", "silence": "Silence trimmed", "speed": "Done"}

def run(op, files):
    global JOB
    files = [os.path.abspath(f) for f in files if os.path.isfile(f)]
    if not files: return
    JOB = f"j{os.getpid()}"
    with open(os.path.join(STATE, f"{JOB}.pid"), "w") as f: f.write(str(os.getpid()))
    signal.signal(signal.SIGTERM, on_term)
    name, _, arg = op.partition(":")
    outs, srcs, errs = [], [], []
    n = len(files)
    try:
        if name == "info":
            for f in files[:3]: img_info(f) if kind(f) == "image" else av_info(f) if kind(f) in ("video", "audio") else None
            return
        if name == "rmbg" and not (shutil.which("rembg") or os.access(os.path.join(HOME, ".local/bin/rembg"), os.X_OK)):
            note(tr("Remove BG needs rembg"), tr("Install it (no sudo):") + "\nuv tool install --python 3.12 \"rembg[cpu,cli]\"", "dialog-information")
            return
        # several pictures → one PDF
        if name == "to" and arg == "pdf" and n > 1 and all(kind(f) == "image" for f in files):
            out = uniq(os.path.dirname(files[0]), f"{stem(files[0])} +{n - 1}", "pdf")
            progress(-1, f"{n} → PDF", os.path.basename(out))
            mg([*[f + "[0]" for f in files], "-auto-orient", "-background", "white", "-alpha", "remove", "-alpha", "off"], out)
            done_note([out], files, f"{n} {tr('files')} → PDF · {tr('combined')}"); return
        for i, f in enumerate(files):
            k = kind(f); title = f"{ext(f).upper()} → {arg.upper()}" if name == "to" else tr(TITLES.get(name, "Working"))
            sub = (f"{i + 1}/{n} · " if n > 1 else "") + os.path.basename(f)
            progress(-1 if k in ("image", "pdf") else 0, title, sub)
            try:
                if name == "to":
                    if k == "image": outs += img_convert(f, arg)
                    elif k == "pdf": outs += pdf_pages(f, arg) if arg in ("png", "jpg", "webp", "tiff") else []
                    elif k in ("video", "audio"): outs.append(vid_convert(f, arg))
                    else: raise Fail(tr("Not for this file"))
                elif k in ("image",) and name in ("compress", "resize", "rotate", "strip", "rmbg", "bg"):
                    outs.append(img_tool(f, name, arg))
                elif k in ("video", "audio") and name in ("vcompress", "vresize", "vrotate", "mute", "speed", "frame", "trim", "acompress", "normalize", "silence"):
                    outs.append(av_tool(f, name, arg))
                elif k == "image" and name in ("vcompress",):
                    outs.append(img_tool(f, "compress", "normal"))
                else:
                    raise Fail(tr("Not for this file"))
                srcs.append(f)
            except Fail as ex:
                errs.append(f"{os.path.basename(f)}: {ex}")
        if outs:
            extra = ""
            if name in ("resize", "vresize", "rotate", "vrotate", "rmbg", "bg") or (name == "to" and n == 1 and kind(files[0]) == "image"):
                a = dims(srcs[0]) if kind(srcs[0]) == "image" else vdims(srcs[0])
                b = dims(outs[0]) if kind(outs[0]) == "image" else vdims(outs[0])
                if a and b and a != b: extra = f"{a[0]}×{a[1]} → {b[0]}×{b[1]}"
            if name == "to" and kind(files[0]) == "pdf" and len(outs) > 1: extra = f"{len(outs)} {tr('pages')}"
            if name == "to" and arg == "gif" and kind(files[0]) == "video" and duration(files[0]) > 30: extra = tr("first 30 s")
            if name == "to":
                title = f"{n} {tr('files')} → {arg.upper()}" if n > 1 else f"{ext(files[0]).upper()} → {('AUDIO' if arg == 'audio' else arg.upper())}"
            else:
                title = f"{arg}×" if name == "speed" else tr("Flipped" if arg in ("flipx", "flipy") else TITLES.get(name, "Done")) + (f" · {len(outs)} {tr('files')}" if len(outs) > 1 else "")
            done_note(outs, srcs, title, extra)
        if errs:
            note(tr("Failed"), esc("\n".join(errs[:4])), "dialog-error")
    finally:
        ipc("finished", JOB)
        try: os.remove(os.path.join(STATE, f"{JOB}.pid"))
        except Exception: pass

# ── editing in the screenshot editor (Shot.qml file mode) ───────────
def edit(mode, src):
    src = os.path.abspath(src)
    mons = json.loads(subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True).stdout or "[]")
    if not mons: return
    m = next((x for x in mons if x.get("focused")), mons[0])
    sc = m.get("scale", 1) or 1; W, H = round(m["width"] / sc), round(m["height"] / sc)
    wh = dims(src)
    if not wh: note(tr("Failed"), esc(os.path.basename(src)), "dialog-error"); return
    iw, ih = wh
    k = min(1.0, (W - 160) / iw, (H - 220) / ih)
    dw, dh = max(1, round(iw * k)), max(1, round(ih * k))
    x, y = (W - dw) // 2, (H - dh) // 2 + 10
    run_ = RUN
    frame = os.path.join(run_, f"shot-{m['name']}.ppm")
    # the frozen "screen": the picture on a blurred, darkened copy of itself
    sh(["magick", "(", src + "[0]", "-auto-orient", "-resize", f"{W}x{H}^", "-gravity", "center", "-extent", f"{W}x{H}", "-blur", "0x28",
        "-fill", "#0c0d12", "-colorize", "62%", ")", "(", src + "[0]", "-auto-orient", "-background", "#202128", "-alpha", "remove",
        "-resize", f"{dw}x{dh}!", ")", "-gravity", "northwest", "-geometry", f"+{x}+{y}", "-composite", "-depth", "8", frame])
    others = [o for o in mons if o["name"] != m["name"]]
    for o in others:
        subprocess.run(["grim", "-t", "ppm", "-o", o["name"], os.path.join(run_, f"shot-{o['name']}.ppm")], capture_output=True)
    with open(os.path.join(STATE, "edit.json"), "w") as f:
        json.dump({"src": src, "x": x, "y": y, "w": dw, "h": dh, "iw": iw, "ih": ih, "mode": mode}, f)
    lay = {"mons": [{"name": o["name"], "x": o["x"], "y": o["y"], "w": round(o["width"] / (o.get("scale", 1) or 1)),
                     "h": round(o["height"] / (o.get("scale", 1) or 1))} for o in mons], "wins": []}
    req = {"mon": m["name"], "x": x, "y": y, "w": dw, "h": dh, "mode": mode, "lay": lay,
           "tool": {"edit": "arrow", "redact": "redact", "crop": ""}.get(mode, "")}
    fn = "testFile" if os.environ.get("SHOT_TEST") else "openFile"     # SHOT_TEST=1: no keyboard grab
    r = subprocess.run(["qs", "ipc", "call", "shot", fn, json.dumps(req)], capture_output=True, text=True, timeout=3)
    if r.returncode != 0: note(tr("The editor isn't available"), esc(r.stderr.strip()[:120]), "dialog-error")

def editdone(ann, bare, sx, sy, sw, shh):
    st = json.load(open(os.path.join(STATE, "edit.json")))
    src = st["src"]; k = st["w"] / st["iw"]
    sx, sy, sw, shh = float(sx), float(sy), float(sw), float(shh)
    # the frame in the original's pixels (clamped to the picture)
    x0 = max(0, (sx - st["x"]) / k); y0 = max(0, (sy - st["y"]) / k)
    x1 = min(st["iw"], (sx + sw - st["x"]) / k); y1 = min(st["ih"], (sy + shh - st["y"]) / k)
    cw, ch = max(1, round(x1 - x0)), max(1, round(y1 - y0)); cx, cy = round(x0), round(y0)
    # the frame may hang over the picture: cut the drawing to the part that lies on it
    ox, oy = round(max(0, st["x"] - sx)), round(max(0, st["y"] - sy))
    pw, ph = round(cw * k), round(ch * k)
    e = img_out_ext(src)
    if e in ("gif", "ico", "bmp"): e = "png"
    mode = st.get("mode", "edit")
    out = uniq(os.path.dirname(src), f"{stem(src)}-{'cropped' if mode == 'crop' else 'edited'}", e)
    crop = ["-crop", f"{pw}x{ph}+{ox}+{oy}", "+repage"]
    if k >= 0.999:
        mg([ann, *crop, "-resize", f"{cw}x{ch}!", *QUAL.get(e, [])], out)
    else:
        # the drawing was made on a shrunk copy: keep the original's pixels wherever nothing was drawn
        t = os.path.join(STATE, f"ed-{os.getpid()}")
        sh(["magick", ann, *crop, "-filter", "Lanczos", "-resize", f"{cw}x{ch}!", t + "-a.png"])
        sh(["magick", bare, *crop, "-filter", "Lanczos", "-resize", f"{cw}x{ch}!", t + "-b.png"])
        sh(["magick", t + "-a.png", t + "-b.png", "-compose", "difference", "-composite", "-colorspace", "gray", "-threshold", "4%",
            "-morphology", "dilate", "disk:2", "-blur", "0x1.2", t + "-m.png"])
        mg([src + "[0]", "-auto-orient", "-crop", f"{cw}x{ch}+{cx}+{cy}", "+repage", t + "-a.png", t + "-m.png", "-compose", "over", "-composite", *QUAL.get(e, [])], out)
        for s in ("-a.png", "-b.png", "-m.png"):
            try: os.remove(t + s)
            except Exception: pass
    a = (st["iw"], st["ih"]); b = dims(out)
    done_note([out], [src], tr("Cropped") if mode == "crop" else tr("Edited"), f"{a[0]}×{a[1]} → {b[0]}×{b[1]}" if b and b != a else "")

def main():
    a = sys.argv[1:]
    if not a: print(__doc__ or "usage: convert.py run|ui|cancel|edit|editdone|duration"); return
    c = a[0]
    if c == "run" and len(a) >= 3: run(a[1], a[2:])
    elif c == "ui":
        files = "\n".join(os.path.abspath(f) for f in a[1:])
        r = subprocess.run(["qs", "ipc", "call", "convert", "open", files], capture_output=True)
        if r.returncode != 0: note(tr("Converter"), "The shell isn't running", "dialog-error")
    elif c == "cancel" and len(a) >= 2:
        try: os.kill(int(open(os.path.join(STATE, f"{a[1]}.pid")).read()), signal.SIGTERM)
        except Exception: ipc("finished", a[1])
    elif c == "edit" and len(a) >= 3:
        try: edit(a[1], a[2])
        except Fail as ex: note(tr("Failed"), esc(ex), "dialog-error")
    elif c == "editdone" and len(a) >= 7:
        try: editdone(*a[1:7])
        except Fail as ex: note(tr("Failed"), esc(ex), "dialog-error")
    elif c == "duration" and len(a) >= 2: print(f"{duration(a[1]):.3f}")
    else: print("usage: convert.py run OP FILE… | ui FILE… | cancel JOB | edit MODE FILE | duration FILE")

if __name__ == "__main__":
    main()
