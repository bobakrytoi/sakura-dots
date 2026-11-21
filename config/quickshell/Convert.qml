// sakura mono - file converter with a radial menu (DragShift-style), backend hypr/scripts/convert.py.
// Drag files from Dolphin to the outer left / right edge of the screens (a 2 px invisible catcher, away from the bar,
// the dock, the hot corners and the edge tab) → a glass flower opens in an empty spot of that screen (no window
// under it; if there is none - next to the pointer). Every petal is a drop target: drop the files on one → done.
// Rings: Convert ↔ Tools - hold the drag on the centre (the ring around it fills), or on the tab under the flower.
// Petals with more options (Resize, Rotate, …) open an outer ring of them when you rest on them.
// Leaving the screen / cancelling the drag (Esc in Dolphin) closes it; dropping on an empty spot does nothing.
// Also: Dolphin right-click → Convert… (servicemenus/sakura-convert.desktop → convert.py ui) opens it for clicking.
//   qs ipc call convert open "<paths, one per line>" | test "<paths>" <convert|tools> <petal> <sub> | close
//   qs ipc call convert progress JOB PCT TITLE SUB | finished JOB        (convert.py reports long jobs here)
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Shapes

Scope {
    id: cv

    // ── state ─────────────────────────────────────────────
    property bool shown: false
    property bool dragMode: false            // opened by a drag (petals are drop targets) or by a click (petals are buttons)
    property bool passive: false             // test: no keyboard, no focus grab
    property var files: []
    property string ring: "convert"          // convert | tools
    property var screen0: Quickshell.screens[0]
    property real fx: 400                    // flower centre, in screen0's coordinates
    property real fy: 400
    property int hov: -1                     // petal under the pointer / the drag
    property int subHov: -1
    property int subOpen: -1                 // petal whose outer ring is open
    property string zone: ""                 // "center" | "tab-convert" | "tab-tools" | "" (what else is under it)
    property bool hasRembg: false
    // a hot corner set to "File converter" (Settings > Taskbar > Hot corners) replaces the edge catchers
    readonly property bool cornerMode: Object.values(Cfg.data.corners || {}).includes("convert")
    // progress cards, updated in place (a new array would rebuild the cards and restart their spinners)
    ListModel { id: jobs }
    // trim dialog
    property bool trimming: false
    property real dur: 0
    property real tA: 0
    property real tB: 0

    readonly property real r0: 74            // petals: inner / outer radius, gap between them
    readonly property real r1: 186
    readonly property real rc: 64            // the centre disc
    readonly property real gap: 5
    readonly property real s0: r1 + 9        // outer ring of options
    readonly property real s1: r1 + 62
    readonly property real box: 2 * (s1 + 14)

    readonly property color cFg:    "#eceef4"
    readonly property color cMuted: "#8a8fa3"
    readonly property string fUi:   Cfg.fontUi
    readonly property string fIcon: "Symbols Nerd Font"
    readonly property string py:    Quickshell.env("HOME") + "/.config/hypr/scripts/convert.py"
    function tr(s) { return Cfg.tr(s); }

    // ── what the files are ───────────────────────────────
    readonly property var extKind: ({
        png: "image", jpg: "image", jpeg: "image", webp: "image", avif: "image", heic: "image", heif: "image", gif: "image",
        ico: "image", bmp: "image", tif: "image", tiff: "image", jxl: "image", pdf: "pdf",
        mp4: "video", webm: "video", mkv: "video", mov: "video", avi: "video", m4v: "video", wmv: "video", flv: "video", mpg: "video", mpeg: "video", ts: "video", "3gp": "video",
        mp3: "audio", ogg: "audio", oga: "audio", flac: "audio", wav: "audio", opus: "audio", m4a: "audio", aac: "audio", wma: "audio", aiff: "audio"
    })
    function ext(p) { const m = String(p).toLowerCase().match(/\.([a-z0-9]+)$/); return m ? m[1] : ""; }
    function base(p) { return String(p).split("/").pop(); }
    readonly property string kind: {
        const c = {};
        for (const f of files) { const k = extKind[ext(f)] || "other"; c[k] = (c[k] || 0) + 1; }
        let best = "other", n = 0;
        for (const k in c) if (k !== "other" && c[k] > n) { best = k; n = c[k]; }
        return best;
    }
    readonly property string ext0: files.length ? ext(files[0]) : ""
    readonly property bool multi: files.length > 1

    // ── the petals ───────────────────────────────────────
    // {label, icon, op, desc, subs: [{label, op, desc}]}
    function fm(id, desc, icon) { return { label: id.toUpperCase(), icon: icon || "", op: "to:" + id, desc: desc }; }
    readonly property var imgFormats: [
        fm("png", "Lossless, keeps transparency"), fm("jpg", "Photos, opens everywhere"), fm("webp", "Small, made for the web"),
        fm("avif", "Smallest, modern"), fm("heic", "The iPhone photo format"), fm("gif", "Animation, 256 colours"),
        fm("ico", "Windows icon"), fm("bmp", "Plain bitmap, no compression"), fm("tiff", "Lossless, for print"), fm("pdf", "Document")
    ]
    readonly property var vidFormats: [
        fm("mp4", "Plays everywhere (H.264)"), fm("webm", "Open web video (VP9)"), fm("mkv", "Repack, no quality loss"),
        fm("gif", "Animated GIF · first 30 s"), fm("mp3", "Just the sound · MP3"), fm("ogg", "Just the sound · Vorbis"),
        fm("flac", "Just the sound · lossless"), fm("wav", "Just the sound · uncompressed"),
        { label: "AUDIO", icon: "\uf001", op: "to:audio", desc: "Extract the sound as it is" }
    ]
    readonly property var audFormats: [
        fm("mp3", "Plays everywhere"), fm("ogg", "Open format (Vorbis)"), fm("flac", "Lossless"), fm("wav", "Uncompressed"),
        fm("opus", "Smallest, great quality"), fm("m4a", "AAC, Apple-friendly")
    ]
    readonly property var pdfFormats: [ fm("png", "One picture per page"), fm("jpg", "One picture per page"), fm("webp", "One picture per page"), fm("tiff", "One picture per page") ]

    readonly property var imgTools: [
        { label: "Info", icon: "\uf05a", op: "info", desc: "Camera, date, location, size",
          subs: [ { label: "View", op: "info", desc: "Show the metadata" }, { label: "Remove", op: "strip", desc: "Strip EXIF and location" } ] },
        { label: "Compress", icon: "\uf066", op: "compress:normal", desc: "Smaller file, same look",
          subs: [ { label: "Light", op: "compress:normal", desc: "Barely visible" }, { label: "Strong", op: "compress:strong", desc: "Much smaller, max 2560 px" } ] },
        { label: "Resize", icon: "\uf065", op: "resize:50", desc: "Make the picture smaller",
          subs: [ { label: "50%", op: "resize:50", desc: "Half the size" }, { label: "1080p", op: "resize:1080", desc: "Short side 1080 px" },
                  { label: "720p", op: "resize:720", desc: "Short side 720 px" }, { label: "480p", op: "resize:480", desc: "Short side 480 px" },
                  { label: "25%", op: "resize:25", desc: "A quarter" } ] },
        { label: "Crop", icon: "\uf125", op: "crop", desc: "Drag the frame's edges · Enter saves" },
        { label: "Rotate", icon: "\uf01e", op: "rotate:cw", desc: "Turn or mirror",
          subs: [ { label: "90°", icon: "\uf01e", op: "rotate:cw", desc: "Clockwise" }, { label: "−90°", icon: "\uf0e2", op: "rotate:ccw", desc: "Counter-clockwise" },
                  { label: "180°", op: "rotate:180", desc: "Upside down" }, { label: "↔", op: "rotate:flipx", desc: "Mirror left-right" },
                  { label: "↕", op: "rotate:flipy", desc: "Mirror top-bottom" } ] },
        { label: "No BG", icon: "\uf0d0", op: "rmbg", desc: "Cut the background out", need: "rembg" },
        { label: "Add BG", icon: "\uf1fc", op: "bg:accent", desc: "Put it on a background",
          subs: [ { label: "Accent", op: "bg:accent", desc: "Soft accent card with a shadow" }, { label: "White", op: "bg:white", desc: "Fill transparency with white" },
                  { label: "Black", op: "bg:black", desc: "Fill transparency with black" } ] },
        { label: "Edit", icon: "\uf040", op: "edit", desc: "Arrows, text, steps, marker" },
        { label: "Redact", icon: "\uf070", op: "redact", desc: "Black out, blur or pixelate" }
    ]
    readonly property var vidTools: [
        { label: "Info", icon: "\uf05a", op: "info", desc: "Codecs, resolution, length" },
        { label: "Compress", icon: "\uf066", op: "vcompress:normal", desc: "Smaller MP4 for sharing",
          subs: [ { label: "Medium", op: "vcompress:normal", desc: "Up to 1080p" }, { label: "Strong", op: "vcompress:strong", desc: "Up to 720p, tiny" } ] },
        { label: "Resize", icon: "\uf065", op: "vresize:720", desc: "Lower the resolution",
          subs: [ { label: "1080p", op: "vresize:1080", desc: "Full HD" }, { label: "720p", op: "vresize:720", desc: "HD" },
                  { label: "480p", op: "vresize:480", desc: "SD" }, { label: "50%", op: "vresize:50", desc: "Half the size" } ] },
        { label: "Trim", icon: "\uf0c4", op: "trim", desc: "Cut a piece out by time" },
        { label: "Mute", icon: "\uf026", op: "mute", desc: "Remove the sound (no re-encode)" },
        { label: "Rotate", icon: "\uf01e", op: "vrotate:cw", desc: "Turn the video",
          subs: [ { label: "90°", op: "vrotate:cw", desc: "Clockwise" }, { label: "−90°", op: "vrotate:ccw", desc: "Counter-clockwise" }, { label: "180°", op: "vrotate:180", desc: "Upside down" } ] },
        { label: "Speed", icon: "\uf04e", op: "speed:2", desc: "Faster or slower",
          subs: [ { label: "2×", op: "speed:2", desc: "Twice as fast" }, { label: "1.5×", op: "speed:1.5", desc: "A bit faster" }, { label: "0.5×", op: "speed:0.5", desc: "Slow motion" } ] },
        { label: "Frame", icon: "\uf030", op: "frame", desc: "Save the middle frame as PNG" }
    ]
    readonly property var audTools: [
        { label: "Info", icon: "\uf05a", op: "info", desc: "Codec, bitrate, tags" },
        { label: "Trim", icon: "\uf0c4", op: "trim", desc: "Cut a piece out by time" },
        { label: "Compress", icon: "\uf066", op: "acompress:128", desc: "Smaller MP3",
          subs: [ { label: "128k", op: "acompress:128", desc: "Good for music" }, { label: "64k", op: "acompress:64", desc: "Voice, podcasts" } ] },
        { label: "Louder", icon: "\uf028", op: "normalize", desc: "Even out the loudness (−14 LUFS)" },
        { label: "Silence", icon: "\uf1de", op: "silence", desc: "Cut silence at the start and end" },
        { label: "Speed", icon: "\uf04e", op: "speed:1.5", desc: "Faster or slower",
          subs: [ { label: "2×", op: "speed:2", desc: "Twice as fast" }, { label: "1.5×", op: "speed:1.5", desc: "A bit faster" }, { label: "0.75×", op: "speed:0.75", desc: "Slower" } ] }
    ]

    readonly property var petals: {
        const own = { jpeg: "jpg", tif: "tiff", heif: "heic" }[ext0] || ext0;
        const drop = l => l.filter(p => p.op !== "to:" + own || multi);
        if (ring === "tools") {
            if (kind === "image") return ext0 === "gif" || ext0 === "ico" ? imgTools.filter(p => !["rmbg", "edit", "redact", "crop"].includes(p.op)) : imgTools;
            if (kind === "video") return vidTools;
            if (kind === "audio") return audTools;
            return [];
        }
        if (kind === "image") {
            let l = imgFormats.slice();
            if (own === "gif") l = l.filter(p => p.op !== "to:bmp" && p.op !== "to:ico").concat([fm("mp4", "Video, much smaller"), fm("webm", "Web video")]);
            if (multi) l = l.map(p => p.op === "to:pdf" ? Object.assign({}, p, { desc: "All of them into one PDF" }) : p);
            return drop(l);
        }
        if (kind === "video") return drop(vidFormats);
        if (kind === "audio") return drop(audFormats);
        if (kind === "pdf") return pdfFormats;
        return [];
    }
    readonly property bool hasTools: kind === "image" || kind === "video" || kind === "audio"
    readonly property var curPetal: hov >= 0 && hov < petals.length ? petals[hov] : null
    readonly property var curSubs: subOpen >= 0 && subOpen < petals.length ? (petals[subOpen].subs || []) : []
    readonly property var curSub: subHov >= 0 && subHov < curSubs.length ? curSubs[subHov] : null
    function needsMissing(p) { return p && p.need === "rembg" && !hasRembg; }

    // ── geometry ─────────────────────────────────────────
    readonly property real step: petals.length ? 360 / petals.length : 360
    function ang(i) { return i * step; }                                   // start of petal i, degrees from the top, clockwise
    function pol(r, deg) { const a = (deg - 90) * Math.PI / 180; return [r * Math.cos(a), r * Math.sin(a)]; }
    // an annular sector with straight, evenly wide gaps and rounded corners, as an SVG path around (c, c)
    function sector(a0, a1, ri, ro, g, cr, c) {
        const off = (r) => Math.asin(Math.min(0.99, g / 2 / r)) * 180 / Math.PI;
        const P = (r, d) => { const p = pol(r, d); return (c + p[0]).toFixed(2) + " " + (c + p[1]).toFixed(2); };
        const oo = off(ro), oi = off(ri);
        const A0o = a0 + oo, A1o = a1 - oo, A0i = a0 + oi, A1i = a1 - oi;
        const dco = cr / ro * 180 / Math.PI, dci = cr / ri * 180 / Math.PI;
        const large = (A1o - A0o - 2 * dco) > 180 ? 1 : 0, largeI = (A1i - A0i - 2 * dci) > 180 ? 1 : 0;
        const rad = (r, d, o) => { const p = pol(r, d), q = pol(1, d + 90); return (c + p[0] + q[0] * o).toFixed(2) + " " + (c + p[1] + q[1] * o).toFixed(2); };
        return "M " + P(ro, A0o + dco)
            + " A " + ro + " " + ro + " 0 " + large + " 1 " + P(ro, A1o - dco)
            + " Q " + P(ro, A1o) + " " + rad(ro - cr, a1, -g / 2)
            + " L " + rad(ri + cr, a1, -g / 2)
            + " Q " + P(ri, A1i) + " " + P(ri, A1i - dci)
            + " A " + ri + " " + ri + " 0 " + largeI + " 0 " + P(ri, A0i + dci)
            + " Q " + P(ri, A0i) + " " + rad(ri + cr, a0, g / 2)
            + " L " + rad(ro - cr, a0, g / 2)
            + " Q " + P(ro, A0o) + " " + P(ro, A0o + dco) + " Z";
    }
    readonly property real subStep: 25
    function subStart() { return subOpen < 0 ? 0 : ang(subOpen) + step / 2 - curSubs.length * subStep / 2; }

    // what is at (x, y) relative to the flower's centre
    function hitAt(x, y) {
        const d = Math.hypot(x, y);
        let deg = Math.atan2(y, x) * 180 / Math.PI + 90; if (deg < 0) deg += 360;
        // tabs under the flower
        const ty = y - (r1 + 34);
        if (hasTools && Math.abs(ty) < 18 && Math.abs(x) < 120) return { z: x < 0 ? "tab-convert" : "tab-tools", p: -1, s: -1 };
        if (d < rc + 4) return { z: "center", p: -1, s: -1 };
        if (subOpen >= 0 && d >= s0 - 4 && d <= s1 + 6) {
            let rel = deg - subStart(); rel = ((rel % 360) + 360) % 360;
            const k = Math.floor(rel / subStep);
            if (k >= 0 && k < curSubs.length) return { z: "", p: subOpen, s: k };
        }
        if (d >= r0 - 4 && d <= r1 + 6 && petals.length) return { z: "", p: Math.floor(deg / step) % petals.length, s: -1 };
        // between the petals and their outer ring: keep the open one
        if (subOpen >= 0 && d > r1 && d < s0) return { z: "", p: subOpen, s: -1 };
        return { z: "", p: -1, s: -1 };
    }
    function hoverAt(x, y) {
        const h = hitAt(x, y);
        if (h.p !== hov) { hov = h.p; if (h.p >= 0 && (petals[h.p].subs || []).length && h.p !== subOpen) subT.restart(); else subT.stop(); }
        if (h.p >= 0 && h.p !== subOpen && !(petals[h.p].subs || []).length) subOpen = -1;
        subHov = h.s;
        if (h.z !== zone) {
            zone = h.z;
            dwellT.stop(); tabT.stop(); dwell = 0;
            if (zone === "center" && hasTools) dwellT.restart();
            if (zone === "tab-convert" && ring !== "convert") tabT.restart();
            if (zone === "tab-tools" && ring !== "tools") tabT.restart();
        }
    }
    function clearHover() { hov = -1; subHov = -1; zone = ""; dwellT.stop(); tabT.stop(); dwell = 0; subT.stop(); }
    Timer { id: subT; interval: 260; onTriggered: if (cv.hov >= 0) cv.subOpen = cv.hov }
    // resting on the centre fills a ring around it, then the other ring of petals comes in
    property real dwell: 0
    Behavior on dwell { NumberAnimation { duration: cv.dwell > 0 ? 650 : 120 } }
    Timer { id: dwellT; interval: 40; onTriggered: { cv.dwell = 1; flipT.restart(); } }
    Timer { id: flipT; interval: 660; onTriggered: if (cv.zone === "center") cv.flip() }
    Timer { id: tabT; interval: 220; onTriggered: { if (cv.zone === "tab-convert") cv.setRing("convert"); else if (cv.zone === "tab-tools") cv.setRing("tools"); } }
    onZoneChanged: if (zone !== "center") flipT.stop()
    function flip() { setRing(ring === "convert" ? "tools" : "convert"); dwell = 0; }
    function setRing(r) { if (r === ring || (r === "tools" && !hasTools)) return; ring = r; hov = -1; subOpen = -1; subHov = -1; swapAnim.restart(); }

    // ── open / close ─────────────────────────────────────
    function parse(list) { return String(list).split("\n").map(s => s.trim()).filter(s => s !== ""); }
    function fromUrls(urls) {
        const out = [];
        for (let i = 0; i < urls.length; i++) {
            const u = String(urls[i]);
            if (u.startsWith("file://")) out.push(decodeURIComponent(u.slice(7)));
        }
        return out;
    }
    property var pending: null              // {screen, ex, ey, side}
    function openOn(scr, list, ex, ey, side, byDrag, pas) {
        if (!list.length) return;
        if (shown && byDrag && dragMode && screen0 === scr) return;
        files = list; dragMode = byDrag; passive = pas === true; trimming = false;
        ring = "convert";
        if (!petals.length && hasTools) ring = "tools";
        if (!petals.length) { Quickshell.execDetached(["notify-send", "-a", tr("Converter"), "-i", "dialog-information", tr("Nothing to convert"), tr("Pictures, PDF, video and audio only")]); return; }
        hov = -1; subOpen = -1; subHov = -1; zone = ""; dwell = 0;
        pending = { screen: scr, ex: ex, ey: ey, side: side };
        place.running = false; place.running = true;
    }
    // find an empty spot for the flower: no window of that screen's workspace under it, near where the drag came in
    Process {
        id: place
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector { onStreamFinished: cv.placeWith(this.text) }
    }
    function placeWith(txt) {
        const p = pending; if (!p) return;
        const s = p.screen, W = s.width, H = s.height;
        let cl = [];
        try { cl = JSON.parse(txt); } catch (e) {}
        const hm = Hyprland.monitorFor(s);
        const ws = hm && hm.activeWorkspace ? hm.activeWorkspace.id : -999;
        const rects = cl.filter(c => c.mapped !== false && !c.hidden && c.workspace && c.workspace.id === ws)
                        .map(c => ({ x: c.at[0] - s.x, y: c.at[1] - s.y, w: c.size[0], h: c.size[1] }));
        const R = r1 + 22, top = 58 + R, bot = H - 100 - R - 40, lft = 16 + R, rgt = W - 16 - R;
        let best = null;
        for (let y = top; y <= bot; y += 20) for (let x = lft; x <= rgt; x += 20) {
            let ov = 0;
            for (const r of rects) {
                const ix = Math.max(0, Math.min(x + R, r.x + r.w) - Math.max(x - R, r.x));
                const iy = Math.max(0, Math.min(y + R + 40, r.y + r.h) - Math.max(y - R, r.y));
                ov += ix * iy;
            }
            const dist = Math.hypot(x - p.ex, y - p.ey);
            const sc = ov * 50 + dist;
            if (!best || sc < best.sc) best = { x: x, y: y, sc: sc, ov: ov };
        }
        if (!best || best.ov > 0) {      // no empty place: right by the pointer, off the edge it came from
            const x = p.side === "right" ? W - R - 30 : p.side === "left" ? R + 30 : p.ex;
            best = { x: Math.max(lft, Math.min(rgt, x)), y: Math.max(top, Math.min(Math.max(top, bot), p.ey)) };
        }
        screen0 = s; fx = best.x; fy = best.y;
        shown = true;
        pending = null;
    }
    function close() { shown = false; trimming = false; clearHover(); subOpen = -1; closeT.stop(); }
    Timer { id: closeT; interval: 450; onTriggered: cv.close() }

    // ── doing it ─────────────────────────────────────────
    function act(p, s) {
        const it = s || p; if (!it) return;
        const op = it.op;
        if (op === "trim") { startTrim(); return; }
        if (op === "crop" || op === "edit" || op === "redact") {
            Quickshell.execDetached(["python3", "-I", py, "edit", op, files[0]]);
            close(); return;
        }
        Quickshell.execDetached(["python3", "-I", py, "run", op].concat(files));
        close();
    }
    Process { id: rembgCheck; running: true; command: ["sh", "-c", "command -v rembg || test -x \"$HOME/.local/bin/rembg\""]; onExited: code => cv.hasRembg = code === 0 }
    onShownChanged: if (shown) { rembgCheck.running = false; rembgCheck.running = true; }

    // trim: the flower turns into a small panel with a two-handle range
    Process {
        id: durP
        stdout: StdioCollector { onStreamFinished: { const d = parseFloat(this.text); cv.dur = isNaN(d) ? 0 : d; cv.tA = 0; cv.tB = cv.dur; } }
    }
    function startTrim() {
        dur = 0; tA = 0; tB = 0; trimming = true; dragMode = false; clearHover();
        durP.command = ["python3", "-I", py, "duration", files[0]]; durP.running = true;
    }
    function doTrim() {
        if (dur <= 0 || tB - tA < 0.2) return;
        Quickshell.execDetached(["python3", "-I", py, "run", "trim:" + tA.toFixed(2) + ":" + tB.toFixed(2)].concat(files));
        close();
    }
    function ts(t) { const m = Math.floor(t / 60), s = t - m * 60; return m + ":" + (s < 10 ? "0" : "") + s.toFixed(1); }

    IpcHandler {
        target: "convert"
        function open(paths: string): void {
            const fm = Hyprland.focusedMonitor;
            const s = (fm && Quickshell.screens.find(x => x.name === fm.name)) || Cfg.mainScreen || Quickshell.screens[0];
            cv.openOn(s, cv.parse(paths), s.width / 2, s.height / 2, "", false, false);
        }
        // for screenshots: no keyboard / focus grab; ring convert|tools, a petal and its option highlighted
        function test(paths: string, ring: string, petal: int, sub: int): void {
            const s = Cfg.mainScreen || Quickshell.screens[0];
            cv.openOn(s, cv.parse(paths), s.width / 2, s.height / 2, "", false, true);
            cv.testHover = { ring: ring, petal: petal, sub: sub };
            testT.restart();
        }
        function close(): void { cv.close(); }
        function pick(petal: int, sub: int): void {      // = a click on a petal (tests)
            if (!cv.shown || petal < 0 || petal >= cv.petals.length) return;
            const p = cv.petals[petal]; cv.act(p, sub >= 0 ? (p.subs || [])[sub] : null);
        }
        // where the flower is (screen coords) and its petals - for tests
        function state(): string {
            return JSON.stringify({ shown: cv.shown, drag: cv.dragMode, ring: cv.ring, screen: cv.screen0 ? cv.screen0.name : "",
                                    x: cv.screen0 ? cv.screen0.x + cv.fx : cv.fx, y: cv.screen0 ? cv.screen0.y + cv.fy : cv.fy,
                                    step: cv.step, r: (cv.r0 + cv.r1) / 2, petals: cv.petals.map(p => p.label), files: cv.files });
        }
        function progress(id: string, pct: int, title: string, sub: string): void { cv.setJob(id, pct, title, sub); }
        function finished(id: string): void { for (let i = jobs.count - 1; i >= 0; i--) if (jobs.get(i).jid === id) jobs.remove(i); }
    }
    property var testHover: null
    Timer { id: testT; interval: 250; onTriggered: { const t = cv.testHover; if (!t) return; if (t.ring === "tools") cv.setRing("tools");
            cv.hov = t.petal; if (t.sub >= 0) { cv.subOpen = t.petal; cv.subHov = t.sub; } } }
    function setJob(id, pct, title, sub) {
        for (let i = 0; i < jobs.count; i++)
            if (jobs.get(i).jid === id) { jobs.setProperty(i, "pct", pct); jobs.setProperty(i, "title", title); jobs.setProperty(i, "sub", sub); return; }
        jobs.append({ jid: id, pct: pct, title: title, sub: sub });
    }

    // ── catchers on the outer screen edges ───────────────
    Variants {
        model: Quickshell.screens
        Scope {
            id: es
            required property var modelData
            readonly property var hmon: Hyprland.monitorFor(modelData)
            readonly property bool fs: hmon && hmon.activeWorkspace ? hmon.activeWorkspace.hasFullscreen === true : false
            readonly property bool openL: !Quickshell.screens.some(o => o !== modelData && o.x + o.width === modelData.x && o.y < modelData.y + modelData.height && o.y + o.height > modelData.y)
            readonly property bool openR: !Quickshell.screens.some(o => o !== modelData && o.x === modelData.x + modelData.width && o.y < modelData.y + modelData.height && o.y + o.height > modelData.y)
            readonly property bool tab: modelData === Cfg.mainScreen        // the edge tab (sketch / notes) sits mid-left there
            readonly property int h: modelData.height
            readonly property int mid: Math.round(h / 2)
            // left edge: whole (or, on the main screen, above and below the edge tab); right edge: whole
            ConvertEdge { host: cv; side: "left"; scr: es.modelData; want: es.openL && !es.fs && !cv.cornerMode; mTop: 90; mBottom: es.tab ? es.mid + 95 : 110 }
            ConvertEdge { host: cv; side: "left"; scr: es.modelData; want: es.openL && !es.fs && es.tab && !cv.cornerMode; mTop: es.mid + 95; mBottom: 110 }
            ConvertEdge { host: cv; side: "right"; scr: es.modelData; want: es.openR && !es.fs && !cv.cornerMode; mTop: 90; mBottom: 110 }
        }
    }
    // ── the flower ───────────────────────────────────────
    PanelWindow {
        id: win
        screen: cv.screen0
        visible: cv.shown || flower.opacity > 0.01
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "convert"
        WlrLayershell.keyboardFocus: cv.shown && !cv.passive && !cv.dragMode ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        // a drag: the whole screen listens (to know when it leaves / is dropped elsewhere); a click: only the flower
        mask: Region { item: cv.dragMode || !cv.shown ? catchAll : flowerHit }
        Item { id: catchAll; anchors.fill: parent }
        Item { id: flowerHit; x: cv.fx - cv.box / 2; y: cv.fy - cv.box / 2; width: cv.box; height: cv.box + 30 }
        HyprlandFocusGrab { windows: [ win ]; active: cv.shown && !cv.passive && !cv.dragMode; onCleared: cv.close() }

        DropArea {
            anchors.fill: parent
            enabled: cv.shown && cv.dragMode
            onEntered: drag => { closeT.stop(); drag.accept(Qt.CopyAction); cv.hoverAt(drag.x - cv.fx, drag.y - cv.fy); }
            onPositionChanged: drag => { closeT.stop(); cv.hoverAt(drag.x - cv.fx, drag.y - cv.fy); }
            onExited: { cv.clearHover(); closeT.restart(); }
            onDropped: drop => {
                const h = cv.hitAt(drop.x - cv.fx, drop.y - cv.fy);
                const l = cv.fromUrls(drop.urls || []);
                if (l.length) cv.files = l;
                if (h.p >= 0) {
                    drop.accept(Qt.CopyAction);
                    const p = cv.petals[h.p], s = h.s >= 0 ? (p.subs || [])[h.s] : null;
                    cv.act(p, s);
                } else {
                    drop.accepted = false;          // dropped on the centre / an empty spot: nothing happens
                    cv.close();
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: cv.shown && !cv.dragMode && !cv.trimming
            hoverEnabled: true
            onPositionChanged: mouse => cv.hoverAt(mouse.x - cv.fx, mouse.y - cv.fy)
            onExited: cv.clearHover()
            onClicked: mouse => {
                const h = cv.hitAt(mouse.x - cv.fx, mouse.y - cv.fy);
                if (h.z === "center") cv.flip();
                else if (h.z === "tab-convert") cv.setRing("convert");
                else if (h.z === "tab-tools") cv.setRing("tools");
                else if (h.p >= 0) { const p = cv.petals[h.p]; cv.act(p, h.s >= 0 ? (p.subs || [])[h.s] : null); }
                else cv.close();
            }
        }
        Item {
            anchors.fill: parent; focus: cv.shown
            Keys.onEscapePressed: cv.close()
            Keys.onTabPressed: cv.flip()
        }

        Item {
            id: flower
            x: cv.fx - cv.box / 2; y: cv.fy - cv.box / 2
            width: cv.box; height: cv.box
            visible: !cv.trimming || opacity > 0.01
            opacity: cv.shown && !cv.trimming ? 1 : 0
            scale: cv.shown && !cv.trimming ? 1 : 0.72
            Behavior on opacity { NumberAnimation { duration: cv.shown ? 160 : 140 } }
            Behavior on scale { NumberAnimation { duration: cv.shown ? 340 * Cfg.anim : 150; easing.type: cv.shown ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.25 } }
            readonly property real c: width / 2

            // petals (swap: the ring turns in when it changes)
            Item {
                id: petalLayer
                anchors.fill: parent
                SequentialAnimation {
                    id: swapAnim
                    ParallelAnimation {
                        NumberAnimation { target: petalLayer; property: "rotation"; from: -24; to: 0; duration: 380 * Cfg.anim; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                        NumberAnimation { target: petalLayer; property: "opacity"; from: 0.15; to: 1; duration: 240 }
                        NumberAnimation { target: petalLayer; property: "scale"; from: 0.9; to: 1; duration: 340 * Cfg.anim; easing.type: Easing.OutCubic }
                    }
                }
                Repeater {
                    model: cv.petals
                    Item {
                        id: pt
                        required property var modelData
                        required property int index
                        readonly property bool on: cv.hov === index
                        readonly property bool off: cv.needsMissing(modelData)
                        readonly property real mid: cv.ang(index) + cv.step / 2
                        readonly property var push: cv.pol(on ? 7 : 0, mid)
                        width: flower.width; height: flower.height
                        x: push[0]; y: push[1]
                        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        opacity: off && !on ? 0.5 : 1
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                fillColor: pt.on ? (pt.off ? "#55ff9f43" : Cfg.acc(0.34)) : Cfg.glass
                                strokeColor: pt.on ? Cfg.acc(0.85) : "#2effffff"
                                strokeWidth: 1.2
                                Behavior on fillColor { ColorAnimation { duration: 140 } }
                                PathSvg { path: cv.sector(cv.ang(pt.index), cv.ang(pt.index) + cv.step, cv.r0, cv.r1, cv.gap, 14, flower.c) }
                            }
                        }
                        Column {
                            readonly property var p: cv.pol((cv.r0 + cv.r1) / 2 + 4, pt.mid)
                            x: flower.c + p[0] - width / 2; y: flower.c + p[1] - height / 2
                            spacing: 3
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: text !== ""
                                text: pt.modelData.icon || ""
                                font.family: cv.fIcon; font.pixelSize: 17
                                color: pt.on ? Cfg.accent : "#c9ccd8"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: cv.ring === "tools" ? cv.tr(pt.modelData.label) : pt.modelData.label
                                font.family: cv.fUi; font.pixelSize: cv.ring === "tools" ? 12 : 15; font.weight: Font.Bold
                                font.letterSpacing: cv.ring === "tools" ? 0 : 0.8
                                color: pt.on ? "#ffffff" : cv.cFg
                            }
                            Rectangle {     // a dot under petals that have more options
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: (pt.modelData.subs || []).length > 0
                                width: 14; height: 3; radius: 1.5
                                color: pt.on ? Cfg.accent : "#40ffffff"
                            }
                        }
                    }
                }
            }

            // the outer ring of options of the petal you rest on
            Repeater {
                model: cv.curSubs
                Item {
                    id: sp
                    required property var modelData
                    required property int index
                    readonly property bool on: cv.subHov === index
                    readonly property real a0: cv.subStart() + index * cv.subStep
                    width: flower.width; height: flower.height
                    opacity: 0; scale: 0.92
                    Component.onCompleted: { opacity = 1; scale = 1; }
                    Behavior on opacity { NumberAnimation { duration: 150 + sp.index * 30 } }
                    Behavior on scale { NumberAnimation { duration: 220 + sp.index * 30; easing.type: Easing.OutCubic } }
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: sp.on ? Cfg.accent : Cfg.glass
                            strokeColor: sp.on ? Cfg.accent : Cfg.acc(0.4)
                            strokeWidth: 1.2
                            PathSvg { path: cv.sector(sp.a0, sp.a0 + cv.subStep, cv.s0, cv.s1, 4, 10, flower.c) }
                        }
                    }
                    Text {
                        readonly property var p: cv.pol((cv.s0 + cv.s1) / 2, sp.a0 + cv.subStep / 2)
                        x: flower.c + p[0] - width / 2; y: flower.c + p[1] - height / 2
                        text: cv.tr(sp.modelData.label)
                        font.family: cv.fUi; font.pixelSize: 12; font.weight: Font.Bold
                        color: sp.on ? Cfg.accFg : cv.cFg
                    }
                }
            }

            // centre: what is under the pointer and what it does
            Rectangle {
                id: center
                anchors.centerIn: parent
                width: cv.rc * 2; height: width; radius: width / 2
                color: Qt.rgba(15 / 255, 17 / 255, 25 / 255, Math.min(0.92, Cfg.glassAlpha + 0.2))
                border.width: 1.2; border.color: cv.zone === "center" ? Cfg.acc(0.7) : "#30ffffff"
                scale: cv.zone === "center" ? 1.05 : 1
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                // ring switch progress
                Shape {
                    anchors.fill: parent
                    visible: cv.dwell > 0.01
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"; strokeColor: Cfg.accent; strokeWidth: 3; capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: cv.rc; centerY: cv.rc; radiusX: cv.rc - 3; radiusY: cv.rc - 3; startAngle: -90; sweepAngle: 360 * cv.dwell }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 18
                    spacing: 2
                    readonly property var it: cv.curSub || cv.curPetal
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: parent.it ? (cv.ring === "tools" || cv.curSub ? cv.tr(parent.it.label) : parent.it.label)
                                        : cv.zone === "center" && cv.hasTools ? cv.tr(cv.ring === "convert" ? "Tools" : "Convert")
                                        : cv.tr(cv.ring === "convert" ? "Convert" : "Tools")
                        font.family: cv.fUi; font.pixelSize: parent.it && cv.ring !== "tools" && !cv.curSub ? 21 : 15; font.weight: Font.Bold
                        color: parent.it ? Cfg.accent : cv.cFg
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: cv.needsMissing(parent.it) ? cv.tr("Needs rembg - drop for the install command")
                              : parent.it ? cv.tr(parent.it.desc)
                              : cv.zone === "center" && cv.hasTools ? cv.tr("hold…")
                              : cv.multi ? cv.files.length + " " + cv.tr("files") : cv.base(cv.files[0] || "")
                        font.family: cv.fUi; font.pixelSize: 10; color: cv.cMuted
                        wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                        lineHeight: 0.95
                    }
                }
            }

            // tabs under it: Convert | Tools (rest the drag on one, or click)
            Rectangle {
                visible: cv.hasTools
                anchors.horizontalCenter: parent.horizontalCenter
                y: flower.c + cv.r1 + 34 - height / 2
                width: 232; height: 32; radius: 16
                color: Cfg.glass; border.width: 1; border.color: "#26ffffff"
                Rectangle {
                    x: cv.ring === "convert" ? 3 : parent.width / 2; y: 3
                    width: parent.width / 2 - 3; height: parent.height - 6; radius: 13
                    color: Cfg.accent
                    Behavior on x { NumberAnimation { duration: 220 * Cfg.anim; easing.type: Easing.OutCubic } }
                }
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: [["convert", "\uf021", "Convert"], ["tools", "\uf0ad", "Tools"]]
                        Item {
                            required property var modelData
                            width: 116; height: 32
                            readonly property bool sel: cv.ring === modelData[0]
                            readonly property bool hot: cv.zone === "tab-" + modelData[0]
                            Row {
                                anchors.centerIn: parent; spacing: 6
                                Text { text: modelData[1]; font.family: cv.fIcon; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
                                       color: parent.parent.sel ? Cfg.accFg : parent.parent.hot ? Cfg.accent : cv.cMuted }
                                Text { text: cv.tr(modelData[2]); font.family: cv.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter
                                       color: parent.parent.sel ? Cfg.accFg : parent.parent.hot ? Cfg.accent : cv.cFg }
                            }
                        }
                    }
                }
            }
        }

        // trim panel
        Rectangle {
            id: trimBox
            visible: opacity > 0.01
            opacity: cv.shown && cv.trimming ? 1 : 0
            scale: cv.shown && cv.trimming ? 1 : 0.9
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 260 * Cfg.anim; easing.type: Easing.OutBack } }
            width: 460; height: tcol.implicitHeight + 40
            x: Math.max(16, Math.min(win.width - width - 16, cv.fx - width / 2)); y: cv.fy - height / 2
            radius: 24; color: Cfg.glass; border.width: 1; border.color: "#1affffff"
            MouseArea { anchors.fill: parent }      // keep clicks inside
            Column {
                id: tcol
                x: 20; y: 20; width: parent.width - 40; spacing: 16
                Row {
                    spacing: 12; width: parent.width
                    Rectangle { width: 40; height: 40; radius: 13; color: Cfg.acc(0.16); border.width: 1; border.color: Cfg.acc(0.3)
                        Text { anchors.centerIn: parent; text: "\uf0c4"; font.family: cv.fIcon; font.pixelSize: 16; color: Cfg.accent } }
                    Column {
                        width: parent.width - 52; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: cv.tr("Trim"); font.family: cv.fUi; font.pixelSize: 15; font.weight: Font.Bold; color: cv.cFg }
                        Text { width: parent.width; elide: Text.ElideMiddle; text: cv.base(cv.files[0] || "") + (cv.multi ? "  +" + (cv.files.length - 1) : "")
                               font.family: cv.fUi; font.pixelSize: 11; color: cv.cMuted }
                    }
                }
                // the range
                Item {
                    id: rng
                    width: parent.width; height: 36
                    readonly property real k: cv.dur > 0 ? width / cv.dur : 0
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 8; radius: 4; color: "#22ffffff" }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; x: cv.tA * rng.k; width: (cv.tB - cv.tA) * rng.k; height: 8; radius: 4; color: Cfg.accent }
                    Repeater {
                        model: 2
                        Rectangle {
                            required property int index
                            readonly property real t: index === 0 ? cv.tA : cv.tB
                            x: t * rng.k - width / 2; anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 28; radius: 7
                            color: hma.pressed || hma.containsMouse ? "#ffffff" : cv.cFg
                            border.width: 2; border.color: Cfg.accent
                            MouseArea {
                                id: hma; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.SizeHorCursor
                                onPositionChanged: mouse => {
                                    if (!pressed || rng.k <= 0) return;
                                    const t = Math.max(0, Math.min(cv.dur, mapToItem(rng, mouse.x, mouse.y).x / rng.k));
                                    if (index === 0) cv.tA = Math.min(t, cv.tB - 0.2); else cv.tB = Math.max(t, cv.tA + 0.2);
                                }
                            }
                        }
                    }
                }
                Row {
                    width: parent.width
                    Text { width: parent.width / 3; text: cv.ts(cv.tA); font.family: cv.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: cv.cFg }
                    Text { width: parent.width / 3; horizontalAlignment: Text.AlignHCenter; text: cv.dur > 0 ? "= " + cv.ts(cv.tB - cv.tA) : "…"
                           font.family: cv.fUi; font.pixelSize: 13; color: Cfg.accent }
                    Text { width: parent.width / 3; horizontalAlignment: Text.AlignRight; text: cv.ts(cv.tB); font.family: cv.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: cv.cFg }
                }
                Item {
                    width: parent.width; height: 38
                    Row {
                        anchors.right: parent.right; spacing: 8
                        Repeater {
                            model: [["Cancel", false], ["Trim", true]]
                            Rectangle {
                                required property var modelData
                                width: bt.implicitWidth + 36; height: 38; radius: 12
                                color: modelData[1] ? (bm.containsMouse ? Qt.lighter(Cfg.accent, 1.08) : Cfg.accent) : (bm.containsMouse ? "#24ffffff" : "#14ffffff")
                                Text { id: bt; anchors.centerIn: parent; text: cv.tr(parent.modelData[0]); font.family: cv.fUi; font.pixelSize: 13; font.weight: Font.DemiBold
                                       color: parent.modelData[1] ? Cfg.accFg : cv.cFg }
                                MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: parent.modelData[1] ? cv.doTrim() : cv.close() }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── progress cards (long videos, batches) ────────────
    PanelWindow {
        id: progWin
        screen: Cfg.mainScreen || Quickshell.screens[0]
        visible: jobs.count > 0
        anchors { bottom: true; right: true }
        margins { bottom: 90; right: 14 }
        implicitWidth: 320; implicitHeight: Math.max(1, pcol.implicitHeight)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "convert-progress"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Column {
            id: pcol
            width: parent.width; spacing: 8
            Repeater {
                model: jobs
                Rectangle {
                    id: card
                    required property string jid
                    required property int pct
                    required property string title
                    required property string sub
                    width: pcol.width; height: 64; radius: 18
                    color: Cfg.glass; border.width: 1; border.color: "#1affffff"
                    Rectangle {
                        x: 12; anchors.verticalCenter: parent.verticalCenter; width: 38; height: 38; radius: 12; color: Cfg.acc(0.16)
                        // a square box right in the middle with the glyph centred in it: turns around its own centre, no wobble
                        Text {
                            anchors.centerIn: parent
                            width: 20; height: 20
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: "\uf021"; font.family: cv.fIcon; font.pixelSize: 15; color: Cfg.accent
                            antialiasing: true
                            RotationAnimator on rotation { from: 0; to: 360; duration: 1400; loops: Animation.Infinite; easing.type: Easing.Linear; running: progWin.visible }
                        }
                    }
                    Column {
                        x: 60; y: 11; width: parent.width - 60 - 40; spacing: 3
                        Row {
                            width: parent.width
                            Text { width: parent.width - pc.implicitWidth; text: card.title; elide: Text.ElideRight
                                   font.family: cv.fUi; font.pixelSize: 13; font.weight: Font.Bold; color: cv.cFg }
                            Text { id: pc; text: card.pct >= 0 ? card.pct + "%" : ""; font.family: cv.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: Cfg.accent }
                        }
                        Text { width: parent.width; text: card.sub; elide: Text.ElideMiddle; font.family: cv.fUi; font.pixelSize: 11; color: cv.cMuted }
                        Rectangle {
                            width: parent.width; height: 4; radius: 2; color: "#22ffffff"; clip: true
                            Rectangle {
                                id: bar
                                height: parent.height; radius: 2; color: Cfg.accent
                                width: card.pct >= 0 ? parent.width * card.pct / 100 : parent.width * 0.3
                                Behavior on width { NumberAnimation { duration: 250 } }
                                SequentialAnimation on x {      // indeterminate: a sliding piece
                                    running: card.pct < 0 && progWin.visible; loops: Animation.Infinite
                                    NumberAnimation { from: -bar.width; to: bar.parent.width; duration: 1100; easing.type: Easing.InOutQuad }
                                }
                                onWidthChanged: if (card.pct >= 0) x = 0
                            }
                        }
                    }
                    Rectangle {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 24; height: 24; radius: 12
                        color: xm.containsMouse ? Cfg.acc(0.3) : "#1affffff"
                        Text { anchors.centerIn: parent; text: "\uf00d"; font.family: cv.fIcon; font.pixelSize: 11; color: cv.cFg }
                        MouseArea { id: xm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["python3", "-I", cv.py, "cancel", card.jid]) }
                    }
                }
            }
        }
    }
}
