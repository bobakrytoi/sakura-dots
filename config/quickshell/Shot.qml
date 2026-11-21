// sakura mono - screenshot editor in the HolyScreen / Lightshot style:
// the screen freezes, you drag an area (or click a window / F for the monitor), annotate it right there, then copy or save.
//   qs ipc call shot open region|screen "<layout json>"   (hypr/scripts/screenshot.sh does this; grabs land in $XDG_RUNTIME_DIR/shot-<monitor>.ppm)
// Before selecting: drag = area · click = window under the pointer · F / Ctrl+A = monitor · R = previous area · C = pick a colour · Esc / right-click = close
// After:  A R E L P M T N X U B = arrow, rectangle, ellipse, line, pencil, marker, text, step, pixelate, blur, redact
//         Enter / Ctrl+C / double-click = copy · Ctrl+S = save · Ctrl+P = pin · Ctrl+T = copy text (OCR) · Ctrl+B = beautify
//         Ctrl+Z / Ctrl+Y = undo / redo · Del = remove · arrows = move area (Ctrl = resize, Shift ×10) · wheel / [ ] = size · 1…0 = colours
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects

Scope {
    id: sh

    // ── state ─────────────────────────────────────────────
    property bool shown: false          // the session is live (drives the fade)
    property bool mapped: false         // the layer surfaces exist (stay a moment after closing for the fade-out)
    property int rev: 0                 // busts the image cache: every capture is a new file
    property string act: ""             // monitor that owns the session (keyboard + selection)
    property string phase: "select"     // select | edit | pick
    property var sel: null              // {x,y,w,h} in the active monitor's pixels
    property var layout: ({ mons: [], wins: [] })
    property var anns: []               // annotations, never mutated in place (undo keeps old arrays)
    property var undoStack: []
    property var redoStack: []
    property int selIdx: -1             // selected annotation
    property var draft: null            // annotation being drawn
    property var editing: null          // text being typed: {idx, x, y, c, fs, t}
    property string tool: ""
    property color color: "#ff3b30"
    property real stroke: 4
    property real fontSize: 26
    property bool beauty: false
    property bool dragging: false       // a drag that moves geometry (no glide animations meanwhile)
    property real mx: -100              // pointer on the active monitor
    property real my: -100
    property color pix: "#000000"       // colour under the pointer
    property string toast: ""
    property var last: null             // previous area {sn,x,y,w,h}
    property var pins: []
    property int pinSeq: 0
    property bool busy: false
    property bool passive: false        // test mode: no keyboard grab (qs ipc call shot test …)
    // file mode (hypr/scripts/convert.py edit crop|edit|redact FILE): the "screen" is a picture prepared by convert.py,
    // the area starts on it; Enter / Ctrl+S / Ctrl+C save next to the original (convert.py editdone puts the drawing
    // back onto the full-size original). {mon, x, y, w, h, mode, tool, lay}
    property var fileJob: null
    property bool hideAnns: false       // a clean render of the area, for convert.py to tell the drawing apart

    readonly property string home: Quickshell.env("HOME")
    readonly property string run: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string script: home + "/.config/hypr/scripts/screenshot.sh"
    readonly property string memPath: home + "/.cache/sakura-shot.json"

    readonly property color cFg:    "#eceef4"
    readonly property color cMuted: "#8a8fa3"
    readonly property color cHover: "#22ffffff"
    readonly property string fUi:   Cfg.fontUi
    readonly property string fIcon: "Symbols Nerd Font"

    readonly property var palette: [Cfg.accent, "#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#30b0c7", "#0a84ff", "#af52de", "#ffffff", "#1c1c1e"]
    readonly property var sizes: [2, 4, 8]
    // id, icon, rotation, label, key
    readonly property var tools: [
        ["arrow",   "", -45, "Arrow",         "A"],
        ["rect",    "", 0,   "Rectangle",     "R"],
        ["ellipse", "", 0,   "Ellipse",       "E"],
        ["line",    "", -45, "Line",          "L"],
        ["pen",     "", 0,   "Pencil",        "P"],
        ["marker",  "", 0,   "Marker",        "M"],
        ["text",    "", 0,   "Text",          "T"],
        ["step",    "",       0,   "Numbered step", "N"],
        ["pixel",   "", 0,   "Pixelate",      "X"],
        ["blur",    "", 0,   "Blur",          "U"],
        ["redact",  "", 0,   "Redact",        "B"]
    ]
    readonly property var vector: ({ arrow: 1, line: 1, rect: 1, ellipse: 1, pen: 1, marker: 1, redact: 1 })
    readonly property var boxy: ({ rect: 1, ellipse: 1, pixel: 1, blur: 1, redact: 1 })
    readonly property var twoPt: ({ arrow: 1, line: 1 })

    property var wins: ({})              // monitor name → window (filled by the windows themselves)
    function win() { return wins[act] || null; }
    function tr(s) { return Cfg.tr(s); }

    // ── memory: colour, sizes, previous area (not settings.json - only Settings.qml writes that) ──
    FileView {
        id: mem
        path: sh.memPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (d.c) sh.color = d.c;
                if (d.w) sh.stroke = d.w;
                if (d.fs) sh.fontSize = d.fs;
                if (d.last) sh.last = d.last;
            } catch (e) {}
        }
    }
    function remember() {
        mem.setText(JSON.stringify({ c: String(color), w: stroke, fs: fontSize, last: last }));
    }

    IpcHandler {
        target: "shot"
        function open(mode: string, layout: string): void { sh.open(mode, layout); }
        function close(): void { sh.close(); }
        function test(mode: string, layout: string): void { sh.open(mode, layout, true); }
        function openFile(req: string): void { sh.openFile(req, false); }
        function testFile(req: string): void { sh.openFile(req, true); }
        function copy(): void { sh.finish("copy", false); }
        function save(): void { sh.finish("save", false); }
        function pin(): void { sh.finish("pin", false); }
        function ocr(): void { sh.finish("ocr", false); }
        function tool(t: string): void { sh.setTool(t); }
        function select(x: int, y: int, w: int, h: int): void { if (sh.shown) { sh.sel = { x: x, y: y, w: w, h: h }; sh.confirm(); } }
        function selectAnn(i: int): void { sh.selIdx = i; }
        function beautify(): void { sh.beauty = !sh.beauty; }
        function unpinAll(): void { sh.pins = []; }
        function palette(): void { const w = sh.win(); if (w) w.togglePalette(); }
        function hoverAt(x: int, y: int): void { const w = sh.win(); if (w) { sh.mx = x; sh.my = y; sh.hoverAt(w, x, y); } }
        // a sample of every tool, for checking the look (qs ipc call shot demo)
        function demo(): void {
            if (!sh.shown || !sh.sel) return;
            const s = sh.sel, X = v => s.x + s.w * v, Y = v => s.y + s.h * v;
            const pen = [], mk = [];
            for (let i = 0; i <= 40; i++) { pen.push(X(0.06 + i * 0.006), Y(0.78 + Math.sin(i / 5) * 0.04)); mk.push(X(0.05 + i * 0.008), Y(0.08)); }
            sh.commit(sh.anns.concat([
                { k: "marker", c: "#ffcc00", w: 5, pts: mk },
                { k: "rect", c: "#ff3b30", w: 4, x1: X(0.05), y1: Y(0.18), x2: X(0.32), y2: Y(0.42) },
                { k: "step", c: "#ff3b30", w: 4, x: X(0.05), y: Y(0.18), n: 1 },
                { k: "ellipse", c: String(Cfg.accent), w: 4, x1: X(0.38), y1: Y(0.18), x2: X(0.6), y2: Y(0.4) },
                { k: "arrow", c: "#ff3b30", w: 5, x1: X(0.45), y1: Y(0.7), x2: X(0.68), y2: Y(0.5) },
                { k: "line", c: "#30b0c7", w: 3, x1: X(0.7), y1: Y(0.2), x2: X(0.95), y2: Y(0.2) },
                { k: "text", c: "#ff3b30", fs: 30, x: X(0.24), y: Y(0.6), t: "Record day!", tw: 5.6, th: 1.25 },
                { k: "step", c: "#ff3b30", w: 4, x: X(0.21), y: Y(0.63), n: 2 },
                { k: "pen", c: "#34c759", w: 4, pts: pen },
                { k: "pixel", x1: X(0.7), y1: Y(0.3), x2: X(0.95), y2: Y(0.45), b: 12 },
                { k: "blur", x1: X(0.7), y1: Y(0.5), x2: X(0.95), y2: Y(0.65) },
                { k: "redact", c: "#1c1c1e", w: 4, x1: X(0.7), y1: Y(0.72), x2: X(0.95), y2: Y(0.78) },
                { k: "step", c: "#ff3b30", w: 4, x: X(0.68), y: Y(0.3), n: 3 }
            ]));
        }
    }

    // ── open / close ──────────────────────────────────────
    function open(mode, lay, passive) {
        if (shown || busy) return;
        sh.passive = passive === true;
        try { layout = JSON.parse(lay || "{}"); } catch (e) { layout = { mons: [], wins: [] }; }
        if (!layout.mons) layout = { mons: [], wins: [] };
        const fm = Hyprland.focusedMonitor;
        act = fm ? fm.name : (Quickshell.screens[0] ? Quickshell.screens[0].name : "");
        rev++;
        anns = []; undoStack = []; redoStack = []; selIdx = -1; draft = null; editing = null;
        tool = ""; beauty = false; dragging = false; toast = ""; mx = -100; my = -100; hover = null; hoverShown = false;
        sel = null; phase = "select";
        if (mode === "screen") {
            const s = Quickshell.screens.find(x => x.name === act);
            if (s) { sel = { x: 0, y: 0, w: s.width, h: s.height }; phase = "edit"; }
        }
        mapped = true; shown = true;
    }
    function openFile(req, passive) {
        let r = null;
        try { r = JSON.parse(req); } catch (e) { return; }
        if (shown || busy || !r) return;
        open("region", JSON.stringify(r.lay || {}), passive);
        fileJob = r;
        if (r.mon) act = r.mon;
        sel = { x: r.x, y: r.y, w: r.w, h: r.h };
        phase = "edit";
        if (r.tool) setTool(r.tool);
        say(r.mode === "crop" ? tr("Drag the frame's edges · Enter saves") : tr("Enter saves next to the original"));
    }
    function close() {
        if (!shown) return;
        fileJob = null;
        shown = false;
        unmapT.restart();
    }
    Timer { id: unmapT; interval: 190; onTriggered: { if (!sh.shown) { sh.mapped = false; sh.anns = []; sh.undoStack = []; sh.redoStack = []; } } }

    function say(s) { toast = s; toastT.restart(); }
    Timer { id: toastT; interval: 1100; onTriggered: sh.toast = "" }

    // ── geometry helpers ──────────────────────────────────
    function clamp(v, a, b) { return b < a ? a : Math.max(a, Math.min(b, v)); }
    function norm(x1, y1, x2, y2) { return { x: Math.min(x1, x2), y: Math.min(y1, y2), w: Math.abs(x2 - x1), h: Math.abs(y2 - y1) }; }
    function inRect(r, x, y) { return r && x >= r.x && y >= r.y && x <= r.x + r.w && y <= r.y + r.h; }
    function segDist(px, py, x1, y1, x2, y2) {
        const dx = x2 - x1, dy = y2 - y1, l = dx * dx + dy * dy;
        let t = l > 0 ? ((px - x1) * dx + (py - y1) * dy) / l : 0;
        t = Math.max(0, Math.min(1, t));
        return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
    }
    function stepR(a) { return 12 + a.w * 1.6; }
    function headLen(a) { return Math.max(16, a.w * 4.2); }
    function luma(c) { const q = Qt.color(c); return 0.2126 * q.r + 0.7152 * q.g + 0.0722 * q.b; }

    function bounds(a) {
        if (!a) return { x: 0, y: 0, w: 0, h: 0 };
        if (a.k === "pen" || a.k === "marker") {
            let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
            for (let i = 0; i < a.pts.length; i += 2) {
                x0 = Math.min(x0, a.pts[i]); x1 = Math.max(x1, a.pts[i]);
                y0 = Math.min(y0, a.pts[i + 1]); y1 = Math.max(y1, a.pts[i + 1]);
            }
            return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
        }
        if (a.k === "text") return { x: a.x, y: a.y, w: (a.tw || 1) * a.fs, h: (a.th || 1.3) * a.fs };
        if (a.k === "step") { const r = stepR(a); return { x: a.x - r, y: a.y - r, w: 2 * r, h: 2 * r }; }
        return norm(a.x1, a.y1, a.x2, a.y2);
    }
    function pad(a) {
        if (!a) return 0;
        const w = a.k === "marker" ? markerW(a) : a.w;
        return (a.k === "arrow" ? headLen(a) : 0) + w * 1.5 + 12;
    }
    function markerW(a) { return Math.max(12, a.w * 4); }

    function hit(a, x, y) {
        const tol = 6;
        switch (a.k) {
        case "arrow": case "line": return segDist(x, y, a.x1, a.y1, a.x2, a.y2) <= a.w / 2 + tol + (a.k === "arrow" ? 4 : 0);
        case "rect": {
            const r = norm(a.x1, a.y1, a.x2, a.y2), e = a.w / 2 + tol;
            const inO = x >= r.x - e && x <= r.x + r.w + e && y >= r.y - e && y <= r.y + r.h + e;
            const inI = x > r.x + e && x < r.x + r.w - e && y > r.y + e && y < r.y + r.h - e;
            return inO && !inI;
        }
        case "ellipse": {
            const r = norm(a.x1, a.y1, a.x2, a.y2), rx = r.w / 2, ry = r.h / 2;
            if (rx < 1 || ry < 1) return false;
            const nx = (x - r.x - rx) / rx, ny = (y - r.y - ry) / ry, d = Math.sqrt(nx * nx + ny * ny);
            return Math.abs(d - 1) * Math.min(rx, ry) <= a.w / 2 + tol;
        }
        case "pixel": case "blur": case "redact": return inRect(norm(a.x1, a.y1, a.x2, a.y2), x, y);
        case "pen": case "marker": {
            const w = (a.k === "marker" ? markerW(a) : a.w) / 2 + tol;
            if (a.pts.length === 2) return Math.hypot(x - a.pts[0], y - a.pts[1]) <= w;
            for (let i = 0; i + 3 < a.pts.length; i += 2)
                if (segDist(x, y, a.pts[i], a.pts[i + 1], a.pts[i + 2], a.pts[i + 3]) <= w) return true;
            return false;
        }
        case "text": { const b = bounds(a); return x >= b.x - 4 && y >= b.y - 4 && x <= b.x + b.w + 4 && y <= b.y + b.h + 4; }
        case "step": return Math.hypot(x - a.x, y - a.y) <= stepR(a) + 3;
        }
        return false;
    }
    function hitTest(x, y) {
        for (let i = anns.length - 1; i >= 0; i--) if (hit(anns[i], x, y)) return i;
        return -1;
    }
    function handles(a) {
        if (!a) return [];
        if (twoPt[a.k]) return [[a.x1, a.y1], [a.x2, a.y2]];
        if (boxy[a.k]) return [[a.x1, a.y1], [a.x2, a.y1], [a.x2, a.y2], [a.x1, a.y2]];
        return [];
    }
    function handleAt(a, x, y) {
        const h = handles(a);
        for (let i = 0; i < h.length; i++) if (Math.hypot(x - h[i][0], y - h[i][1]) <= 9) return i;
        return -1;
    }
    function dragHandle(o, i, x, y) {
        const a = Object.assign({}, o);
        if (twoPt[a.k]) { if (i === 0) { a.x1 = x; a.y1 = y; } else { a.x2 = x; a.y2 = y; } }
        else {
            if (i === 0 || i === 3) a.x1 = x; else a.x2 = x;
            if (i === 0 || i === 1) a.y1 = y; else a.y2 = y;
        }
        return a;
    }
    function offset(o, dx, dy) {
        const a = Object.assign({}, o);
        if (a.pts) a.pts = a.pts.map((v, i) => v + (i % 2 ? dy : dx));
        if (a.x1 !== undefined) { a.x1 += dx; a.y1 += dy; a.x2 += dx; a.y2 += dy; }
        if (a.x !== undefined) { a.x += dx; a.y += dy; }
        return a;
    }
    function constrain(k, x0, y0, x, y) {
        if (twoPt[k]) {
            const ang = Math.round(Math.atan2(y - y0, x - x0) / (Math.PI / 4)) * (Math.PI / 4), l = Math.hypot(x - x0, y - y0);
            return [x0 + Math.cos(ang) * l, y0 + Math.sin(ang) * l];
        }
        const s = Math.max(Math.abs(x - x0), Math.abs(y - y0));
        return [x0 + (x >= x0 ? s : -s), y0 + (y >= y0 ? s : -s)];
    }

    // selection frame: 8 handles tl, t, tr, r, br, b, bl, l
    function frameHandles(s) {
        if (!s) return [];
        const x = s.x, y = s.y, r = s.x + s.w, b = s.y + s.h, cx = x + s.w / 2, cy = y + s.h / 2;
        return [[x, y], [cx, y], [r, y], [r, cy], [r, b], [cx, b], [x, b], [x, cy]];
    }
    function frameHandleAt(x, y) {
        const h = frameHandles(sel);
        for (let i = 0; i < h.length; i++) if (Math.abs(x - h[i][0]) <= 9 && Math.abs(y - h[i][1]) <= 9) return i;
        return -1;
    }
    function frameResize(o, i, dx, dy, sw, shh) {
        let l = o.x, t = o.y, r = o.x + o.w, b = o.y + o.h;
        if (i === 0 || i === 6 || i === 7) l += dx;
        if (i === 2 || i === 3 || i === 4) r += dx;
        if (i === 0 || i === 1 || i === 2) t += dy;
        if (i === 4 || i === 5 || i === 6) b += dy;
        const n = norm(clamp(l, 0, sw), clamp(t, 0, shh), clamp(r, 0, sw), clamp(b, 0, shh));
        return { x: Math.round(n.x), y: Math.round(n.y), w: Math.max(1, Math.round(n.w)), h: Math.max(1, Math.round(n.h)) };
    }
    readonly property var frameCursors: [Qt.SizeFDiagCursor, Qt.SizeVerCursor, Qt.SizeBDiagCursor, Qt.SizeHorCursor,
                                         Qt.SizeFDiagCursor, Qt.SizeVerCursor, Qt.SizeBDiagCursor, Qt.SizeHorCursor]

    // windows of one monitor, in its local pixels, topmost first
    function winsFor(sn) {
        const m = (layout.mons || []).find(q => q.name === sn);
        if (!m) return [];
        const out = [];
        for (const w of (layout.wins || [])) {
            const x0 = Math.max(w.x, m.x), y0 = Math.max(w.y, m.y), x1 = Math.min(w.x + w.w, m.x + m.w), y1 = Math.min(w.y + w.h, m.y + m.h);
            if (x1 - x0 < 8 || y1 - y0 < 8) continue;
            out.push({ x: x0 - m.x, y: y0 - m.y, w: x1 - x0, h: y1 - y0, title: w.title || w.cls || "" });
        }
        return out;
    }

    // ── history ───────────────────────────────────────────
    function commit(next, base) {
        undoStack = undoStack.concat([base !== undefined ? base : anns]);
        redoStack = [];
        anns = next;
    }
    function undo() {
        commitText();
        if (!undoStack.length) return;
        redoStack = redoStack.concat([anns]);
        anns = undoStack[undoStack.length - 1];
        undoStack = undoStack.slice(0, -1);
        selIdx = -1;
    }
    function redo() {
        commitText();
        if (!redoStack.length) return;
        undoStack = undoStack.concat([anns]);
        anns = redoStack[redoStack.length - 1];
        redoStack = redoStack.slice(0, -1);
        selIdx = -1;
    }
    function replaceAt(i, a) { const n = anns.slice(); n[i] = a; return n; }
    function removeSelected() {
        if (selIdx < 0) return false;
        const n = anns.slice(); n.splice(selIdx, 1);
        selIdx = -1; commit(n);
        return true;
    }
    function nextStep() { let n = 0; for (const a of anns) if (a.k === "step") n = Math.max(n, a.n); return n + 1; }

    // ── tools, colour, size ───────────────────────────────
    function setTool(t) {
        commitText();
        tool = tool === t ? "" : t;
        selIdx = -1;
        const d = tools.find(x => x[0] === t);
        if (d) say(tool ? tr(d[3]) : tr("Move"));
    }
    function setColor(c) {
        color = c; remember();
        if (editing) { editing = Object.assign({}, editing, { c: String(c) }); return; }
        if (selIdx >= 0 && anns[selIdx].c !== undefined) commit(replaceAt(selIdx, Object.assign({}, anns[selIdx], { c: String(c) })));
    }
    function setStroke(w) {
        stroke = clamp(w, 1, 40); remember();
        const a = selIdx >= 0 ? anns[selIdx] : null;
        if (a && a.w !== undefined && a.k !== "text") commit(replaceAt(selIdx, Object.assign({}, a, { w: stroke })));
        say(tr("Size") + " " + Math.round(stroke));
    }
    function bump(d) {
        const a = selIdx >= 0 ? anns[selIdx] : null;
        if (editing || tool === "text" || (a && a.k === "text")) {
            fontSize = clamp(fontSize + 2 * d, 10, 120); remember();
            if (editing) editing = Object.assign({}, editing, { fs: fontSize });
            else if (a && a.k === "text") commit(replaceAt(selIdx, Object.assign({}, a, { fs: fontSize })));
            say(tr("Text") + " " + fontSize);
        } else if (a && a.k === "pixel") {
            commit(replaceAt(selIdx, Object.assign({}, a, { b: clamp(a.b + 2 * d, 4, 64) })));
            say(tr("Blocks") + " " + clamp(a.b + 2 * d, 4, 64));
        } else setStroke(stroke + d);
    }

    // ── text ──────────────────────────────────────────────
    function startText(idx, x, y) {
        const a = idx >= 0 ? anns[idx] : null;
        editing = a ? { idx: idx, x: a.x, y: a.y, c: a.c, fs: a.fs, t: a.t }
                    : { idx: -1, x: x, y: y - fontSize * 0.65, c: String(color), fs: fontSize, t: "" };
        if (a) fontSize = a.fs;
        selIdx = -1;
        const w = win(); if (w) Qt.callLater(w.focusText);
    }
    function commitText() {
        if (!editing) return;
        const w = win(), e = editing;
        editing = null;
        const t = w ? w.textValue().replace(/\s+$/, "") : "";
        const m = w ? w.textSize() : { w: 1, h: 1.3 };
        if (w) w.focusKeys();
        if (t === "") {
            if (e.idx >= 0) { const n = anns.slice(); n.splice(e.idx, 1); commit(n); }
            return;
        }
        const a = { k: "text", c: e.c, fs: e.fs, x: e.x, y: e.y, t: t, tw: m.w / e.fs, th: m.h / e.fs };
        if (e.idx >= 0) commit(replaceAt(e.idx, a)); else commit(anns.concat([a]));
    }

    // ── pointer ───────────────────────────────────────────
    property string mode: ""            // new | draw | annMove | annHandle | frame | moveSel
    property var press: null            // {x,y}
    property var orig: null             // annotation / frame at press
    property var base: null             // anns at press
    property int hIdx: -1
    property bool moved: false
    property var hover: null            // window rect under the pointer (select phase)
    property bool hoverShown: false     // …lit up after the pointer rests a moment
    Timer { id: hoverT; interval: 380; onTriggered: sh.hoverShown = true }
    property int cursor: Qt.CrossCursor

    function pressAt(w, x, y, btn, mods) {
        if (btn === Qt.RightButton) {
            if (editing) { commitText(); return; }
            if (phase === "edit" && selIdx >= 0) { selIdx = -1; return; }
            if (phase === "edit" && tool) { tool = ""; return; }
            close(); return;
        }
        if (w.sn !== act) { if (phase === "edit") return; act = w.sn; }
        press = { x: x, y: y }; moved = false; mode = "";
        if (phase === "pick") { pickColor(mods & Qt.ShiftModifier); return; }
        if (phase === "select") { mode = "new"; return; }
        if (editing) { commitText(); return; }

        if (selIdx >= 0) {
            const h = handleAt(anns[selIdx], x, y);
            if (h >= 0) { mode = "annHandle"; hIdx = h; orig = anns[selIdx]; base = anns; return; }
        }
        const fh = frameHandleAt(x, y);
        if (fh >= 0) { mode = "frame"; hIdx = fh; orig = sel; dragging = true; return; }

        const hi = (mods & Qt.ControlModifier) && tool ? -1 : hitTest(x, y);
        if (hi >= 0) { selIdx = hi; mode = "annMove"; orig = anns[hi]; base = anns; return; }
        selIdx = -1;

        const inside = inRect(sel, x, y);
        if (tool && inside) {
            const c = String(color);
            if (tool === "step") { commit(anns.concat([{ k: "step", c: c, w: stroke, x: x, y: y, n: nextStep() }])); return; }
            if (tool === "text") { startText(-1, x, y); return; }
            if (tool === "pen" || tool === "marker") draft = { k: tool, c: c, w: stroke, pts: [x, y] };
            else draft = { k: tool, c: c, w: stroke, x1: x, y1: y, x2: x, y2: y, b: Math.round(6 + stroke * 1.5) };
            mode = "draw";
            return;
        }
        if (inside) { mode = "moveSel"; orig = sel; dragging = true; return; }
        if (!anns.length) { phase = "select"; sel = null; mode = "new"; hoverAt(w, x, y); }
    }

    function moveTo(w, x, y, mods, pressed) {
        if (w.sn !== act) {
            if (!pressed && phase !== "edit") act = w.sn;
            else return;
        }
        mx = x; my = y;
        const sw = w.width, shh = w.height;
        if (!pressed || !press) { hoverAt(w, x, y); return; }
        const dx = x - press.x, dy = y - press.y;
        if (!moved && Math.abs(dx) < 3 && Math.abs(dy) < 3) return;
        moved = true;
        switch (mode) {
        case "new": {
            dragging = true;
            const n = norm(press.x, press.y, clamp(x, 0, sw), clamp(y, 0, shh));
            sel = { x: Math.round(n.x), y: Math.round(n.y), w: Math.max(1, Math.round(n.w)), h: Math.max(1, Math.round(n.h)) };
            break;
        }
        case "draw": {
            const d = Object.assign({}, draft);
            if (d.pts) {
                const lx = d.pts[d.pts.length - 2], ly = d.pts[d.pts.length - 1];
                if (Math.hypot(x - lx, y - ly) >= 1.5) d.pts = d.pts.concat([x, y]);
            } else {
                let e = [x, y];
                if (mods & Qt.ShiftModifier) e = constrain(d.k, d.x1, d.y1, x, y);
                d.x2 = e[0]; d.y2 = e[1];
            }
            draft = d;
            break;
        }
        case "annMove": anns = replaceAt(selIdx, offset(orig, dx, dy)); break;
        case "annHandle": {
            let e = [x, y];
            if (mods & Qt.ShiftModifier) {
                const h = handles(orig), o = h[twoPt[orig.k] ? 1 - hIdx : (hIdx + 2) % 4];
                e = constrain(orig.k, o[0], o[1], x, y);
            }
            anns = replaceAt(selIdx, dragHandle(orig, hIdx, e[0], e[1]));
            break;
        }
        case "frame": sel = frameResize(orig, hIdx, dx, dy, sw, shh); break;
        case "moveSel":
            sel = { x: Math.round(clamp(orig.x + dx, 0, sw - orig.w)), y: Math.round(clamp(orig.y + dy, 0, shh - orig.h)), w: orig.w, h: orig.h };
            break;
        }
    }

    function releaseAt(w, x, y) {
        const m = mode;
        mode = ""; dragging = false;
        if (m === "new") {
            if (!moved || !sel || sel.w < 4 || sel.h < 4) {
                const r = hover || { x: 0, y: 0, w: w.width, h: w.height };
                sel = { x: r.x, y: r.y, w: r.w, h: r.h };
            }
            confirm();
        } else if (m === "draw" && draft) {
            const d = draft, b = bounds(d);
            draft = null;
            const ok = d.pts ? true : (twoPt[d.k] ? Math.hypot(d.x2 - d.x1, d.y2 - d.y1) >= 4 : b.w >= 4 && b.h >= 4);
            if (d.pts && d.pts.length === 2) d.pts = d.pts.concat([d.pts[0] + 0.1, d.pts[1]]);
            if (ok) commit(anns.concat([d]));
        } else if ((m === "annMove" || m === "annHandle") && moved) {
            commit(anns, base);
        }
        press = null;
        hoverAt(w, x, y);
    }

    function doubleAt(w, x, y) {
        if (phase !== "edit") return;
        const hi = hitTest(x, y);
        if (hi >= 0 && anns[hi].k === "text") { startText(hi, 0, 0); return; }
        if (!tool && hi < 0 && inRect(sel, x, y)) finish("copy", false);
    }

    function hoverAt(w, x, y) {
        if (phase === "select") {
            const ws = winsFor(w.sn);
            const f = ws.find(r => inRect(r, x, y));
            const h = f || { x: 0, y: 0, w: w.width, h: w.height, title: "" };
            const same = hover && hover.x === h.x && hover.y === h.y && hover.w === h.w && hover.h === h.h;
            hover = h;
            // the window lights up only once the pointer rests on it - no flashing while you aim for a drag
            if (!same || !hoverShown) { hoverShown = false; hoverT.restart(); }
            cursor = Qt.CrossCursor;
            return;
        }
        if (phase === "pick") { cursor = Qt.CrossCursor; return; }
        if (selIdx >= 0 && handleAt(anns[selIdx], x, y) >= 0) { cursor = Qt.PointingHandCursor; return; }
        const fh = frameHandleAt(x, y);
        if (fh >= 0) { cursor = frameCursors[fh]; return; }
        if (hitTest(x, y) >= 0) { cursor = Qt.SizeAllCursor; return; }
        if (inRect(sel, x, y)) { cursor = tool === "text" ? Qt.IBeamCursor : tool ? Qt.CrossCursor : Qt.SizeAllCursor; return; }
        cursor = Qt.ArrowCursor;
    }

    function confirm() {
        phase = "edit";
        last = { sn: act, x: sel.x, y: sel.y, w: sel.w, h: sel.h };
        remember();
    }
    function selectAll(w) { sel = { x: 0, y: 0, w: w.width, h: w.height }; confirm(); }
    function repeatLast(w) {
        if (!last || last.sn !== w.sn) { say(tr("No previous area")); return; }
        sel = { x: last.x, y: last.y, w: last.w, h: last.h }; confirm();
    }

    function hex2(v) { const s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s; }
    function pickColor(rgb) {
        const c = pix;
        const out = rgb ? "rgb(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ")"
                        : "#" + hex2(c.r) + hex2(c.g) + hex2(c.b);
        Quickshell.execDetached([script, "color", out]);
        close();
    }

    // ── keyboard ──────────────────────────────────────────
    // letters by key code, or by the physical key when another layout (ru) is active
    readonly property var scan: ({ 24: "Q", 25: "W", 26: "E", 27: "R", 28: "T", 29: "Y", 30: "U", 31: "I", 32: "O", 33: "P", 34: "[", 35: "]",
                                   38: "A", 39: "S", 40: "D", 41: "F", 42: "G", 43: "H", 44: "J", 45: "K", 46: "L",
                                   52: "Z", 53: "X", 54: "C", 55: "V", 56: "B", 57: "N", 58: "M" })
    function letter(e) {
        if (e.key >= Qt.Key_A && e.key <= Qt.Key_Z) return String.fromCharCode(e.key);
        if (e.key === Qt.Key_BracketLeft) return "[";
        if (e.key === Qt.Key_BracketRight) return "]";
        return scan[e.nativeScanCode] || "";
    }
    function key(e, w) {
        const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
        const L = letter(e);
        e.accepted = true;
        if (e.key === Qt.Key_Escape) {
            if (phase === "edit" && selIdx >= 0) selIdx = -1;
            else if (phase === "pick") phase = "select";
            else close();
            return;
        }
        if (phase !== "edit") {
            if (L === "F" || (ctrl && L === "A")) selectAll(w);
            else if (L === "R") repeatLast(w);
            else if (L === "C") { phase = phase === "pick" ? "select" : "pick"; say(phase === "pick" ? tr("Pick a colour - Shift for rgb()") : tr("Select an area")); }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (phase === "pick") pickColor(shift); else selectAll(w); }
            else e.accepted = false;
            return;
        }
        if (ctrl) {
            if (L === "Z" && shift) redo();
            else if (L === "Z") undo();
            else if (L === "Y") redo();
            else if (L === "C") finish("copy", shift);
            else if (L === "S") finish("save", shift);
            else if (L === "P") finish("pin", false);
            else if (L === "T") finish("ocr", false);
            else if (L === "B") { beauty = !beauty; say(beauty ? tr("Beautify on") : tr("Beautify off")); }
            else if (L === "A") { sel = { x: 0, y: 0, w: w.width, h: w.height }; }
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Up || e.key === Qt.Key_Down) arrow(e, w, true, shift);
            else e.accepted = false;
            return;
        }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { finish("copy", shift); return; }
        if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) { removeSelected(); return; }
        if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Up || e.key === Qt.Key_Down) { arrow(e, w, false, shift); return; }
        if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) { setColor(palette[(e.key - Qt.Key_0 + 9) % 10]); return; }
        if (L === "[" || e.key === Qt.Key_Minus) { bump(-1); return; }
        if (L === "]" || e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) { bump(1); return; }
        const t = tools.find(x => x[4] === L);
        if (t) { setTool(t[0]); return; }
        e.accepted = false;
    }
    function arrow(e, w, resize, big) {
        const d = big ? 10 : 1;
        const dx = e.key === Qt.Key_Left ? -d : e.key === Qt.Key_Right ? d : 0;
        const dy = e.key === Qt.Key_Up ? -d : e.key === Qt.Key_Down ? d : 0;
        if (!resize && selIdx >= 0) { commit(replaceAt(selIdx, offset(anns[selIdx], dx, dy))); return; }
        if (!sel) return;
        if (resize) sel = { x: sel.x, y: sel.y, w: clamp(sel.w + dx, 4, w.width - sel.x), h: clamp(sel.h + dy, 4, w.height - sel.y) };
        else sel = { x: clamp(sel.x + dx, 0, w.width - sel.w), y: clamp(sel.y + dy, 0, w.height - sel.h), w: sel.w, h: sel.h };
    }

    // ── output ────────────────────────────────────────────
    // kind: copy | save | pin | ocr. keep = Shift held: copy/save without closing.
    function finish(kind, keep) {
        const w = win();
        if (!w || !sel || busy) return;
        commitText();
        selIdx = -1; draft = null;
        busy = true;
        const out = run + "/shot-out-" + kind + (kind === "pin" ? "-" + (++pinSeq) : "") + ".png";
        if (fileJob && (kind === "copy" || kind === "save")) {
            beauty = false;
            const job = fileJob, s = sel, bare = run + "/shot-out-bare.png";
            w.render(out, function (ok) {
                if (!ok) { busy = false; say(tr("Could not render the image")); return; }
                hideAnns = true;
                Qt.callLater(function () {
                    w.render(bare, function (ok2) {
                        hideAnns = false; busy = false;
                        if (!ok2) { say(tr("Could not render the image")); return; }
                        Quickshell.execDetached(["python3", "-I", home + "/.config/hypr/scripts/convert.py", "editdone", out, bare,
                                                 String(s.x), String(s.y), String(s.w), String(s.h)]);
                        close();
                    });
                });
            });
            return;
        }
        w.render(out, function (ok) {
            busy = false;
            if (!ok) { say(tr("Could not render the image")); return; }
            if (kind === "pin") {
                pins = pins.concat([{ id: pinSeq, path: out, sn: act, x: sel.x, y: sel.y, w: sel.w, h: sel.h }]);
                close();
                return;
            }
            Quickshell.execDetached(kind === "ocr" ? [script, "ocr", out] : [script, "done", kind, out]);
            if (keep) say(kind === "copy" ? tr("Copied") : tr("Saved"));
            else close();
        });
    }
    function unpin(id) { pins = pins.filter(p => p.id !== id); }

    // draws one vector annotation (also used for the live draft)
    function paint(ctx, a) {
        const c = a.c;
        ctx.lineCap = "round"; ctx.lineJoin = "round";
        if (a.k !== "marker" && a.k !== "redact") {
            ctx.shadowColor = "#55000000"; ctx.shadowBlur = 5; ctx.shadowOffsetY = 1;
        }
        switch (a.k) {
        case "line":
            ctx.strokeStyle = c; ctx.lineWidth = a.w;
            ctx.beginPath(); ctx.moveTo(a.x1, a.y1); ctx.lineTo(a.x2, a.y2); ctx.stroke();
            break;
        case "arrow": {
            const dx = a.x2 - a.x1, dy = a.y2 - a.y1, L = Math.hypot(dx, dy);
            if (L < 1) break;
            const ux = dx / L, uy = dy / L, px = -uy, py = ux;
            const head = Math.min(headLen(a), L * 0.7), hw = head * 0.5;
            const bx = a.x2 - ux * head * 0.72, by = a.y2 - uy * head * 0.72;
            // tapered shaft: thin at the tail, full width at the head
            const t0 = Math.max(1, a.w * 0.35), t1 = a.w * 0.6;
            ctx.fillStyle = c;
            ctx.beginPath();
            ctx.moveTo(a.x1 + px * t0, a.y1 + py * t0);
            ctx.lineTo(bx + px * t1, by + py * t1);
            ctx.lineTo(a.x2 - ux * head + px * hw, a.y2 - uy * head + py * hw);
            ctx.lineTo(a.x2, a.y2);
            ctx.lineTo(a.x2 - ux * head - px * hw, a.y2 - uy * head - py * hw);
            ctx.lineTo(bx - px * t1, by - py * t1);
            ctx.lineTo(a.x1 - px * t0, a.y1 - py * t0);
            ctx.closePath();
            ctx.fill();
            break;
        }
        case "rect": {
            const r = norm(a.x1, a.y1, a.x2, a.y2), rr = Math.min(3 + a.w * 0.6, r.w / 2, r.h / 2);
            ctx.strokeStyle = c; ctx.lineWidth = a.w;
            ctx.beginPath(); ctx.roundedRect(r.x, r.y, r.w, r.h, rr, rr); ctx.stroke();
            break;
        }
        case "ellipse": {
            const r = norm(a.x1, a.y1, a.x2, a.y2);
            ctx.strokeStyle = c; ctx.lineWidth = a.w;
            ctx.beginPath(); ctx.ellipse(r.x, r.y, r.w, r.h); ctx.stroke();
            break;
        }
        case "redact": {
            const r = norm(a.x1, a.y1, a.x2, a.y2);
            ctx.fillStyle = c;
            ctx.beginPath(); ctx.roundedRect(r.x, r.y, r.w, r.h, 3, 3); ctx.fill();
            break;
        }
        case "pen": case "marker": {
            const p = a.pts;
            ctx.strokeStyle = c;
            ctx.lineWidth = a.k === "marker" ? markerW(a) : a.w;
            if (a.k === "marker") { ctx.globalAlpha = 0.42; ctx.lineCap = "square"; ctx.lineJoin = "round"; }
            ctx.beginPath();
            ctx.moveTo(p[0], p[1]);
            if (p.length <= 4) ctx.lineTo(p[p.length - 2], p[p.length - 1]);
            for (let i = 2; i + 2 < p.length; i += 2) {
                // smooth through midpoints
                const mx = (p[i] + p[i + 2]) / 2, my = (p[i + 1] + p[i + 3]) / 2;
                ctx.quadraticCurveTo(p[i], p[i + 1], mx, my);
            }
            if (p.length > 4) ctx.lineTo(p[p.length - 2], p[p.length - 1]);
            ctx.stroke();
            ctx.globalAlpha = 1;
            break;
        }
        }
    }

    // ── pieces ────────────────────────────────────────────

    // frosted glass cut from the blurred frozen frame of the window (the layer is opaque, so the compositor can't blur for us)
    component Glass: Item {
        id: gl
        property Item bsrc: null
        property real radius: 16
        property real tint: 0.55
        Item {
            id: gwrap
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: gmask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: gl.bsrc
                sourceRect: Qt.rect(gl.x, gl.y, gl.width, gl.height)
            }
        }
        Item {
            id: gmask
            anchors.fill: parent
            layer.enabled: true
            visible: false
            Rectangle { anchors.fill: parent; radius: gl.radius; color: "black" }
        }
        Rectangle {
            anchors.fill: parent; radius: gl.radius
            color: Qt.rgba(15 / 255, 17 / 255, 25 / 255, gl.tint)
            border.width: 1; border.color: "#1fffffff"
        }
    }

    // one toolbar button
    component TB: Item {
        id: tb
        property string icon: ""
        property real rot: 0
        property string tip: ""
        property string keyHint: ""
        property bool on: false
        property bool enabledB: true
        property bool step: false
        property string side: "left"
        signal clicked()
        width: 38; height: 38
        opacity: enabledB ? 1 : 0.35
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Rectangle {
            anchors.fill: parent; radius: 11
            color: tb.on ? Cfg.acc(0.24) : tma.containsMouse && tb.enabledB ? sh.cHover : "transparent"
            border.width: tb.on ? 1 : 0; border.color: Cfg.acc(0.55)
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Text {
            visible: !tb.step
            anchors.centerIn: parent
            text: tb.icon; rotation: tb.rot
            font.family: sh.fIcon; font.pixelSize: 15
            color: tb.on ? Cfg.accent : sh.cFg
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Rectangle {           // the numbered-step icon: a ringed 1
            visible: tb.step
            anchors.centerIn: parent
            width: 18; height: 18; radius: 9
            color: "transparent"; border.width: 1.6; border.color: tb.on ? Cfg.accent : sh.cFg
            Text { anchors.centerIn: parent; text: "1"; font.family: sh.fUi; font.pixelSize: 10; font.weight: Font.Bold; color: tb.on ? Cfg.accent : sh.cFg }
        }
        scale: tma.pressed && tb.enabledB ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        MouseArea {
            id: tma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: tb.enabledB ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (tb.enabledB) tb.clicked()
            onContainsMouseChanged: {
                const w = sh.win();
                if (!w) return;
                if (containsMouse && tb.tip) w.showTip(tb, sh.tr(tb.tip) + (tb.keyHint ? "   " + tb.keyHint : ""), tb.side);
                else w.hideTip(tb);
            }
        }
    }

    component Sep: Rectangle {
        property bool vertical: true
        width: vertical ? 22 : 1; height: vertical ? 1 : 22
        color: "#26ffffff"
        anchors.horizontalCenter: vertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: vertical ? undefined : parent.verticalCenter
    }

    // one annotation as drawn on the frozen frame
    component Ann: Item {
        id: an
        property var a: null
        property int idx: -1
        property Item src: null       // the frozen image
        property Item bsrc: null      // its blurred copy
        readonly property string k: a ? a.k : ""
        readonly property var bb: sh.bounds(a)
        visible: a !== null && !(sh.editing && sh.editing.idx === idx && idx >= 0)
        onAChanged: cv.requestPaint()

        Canvas {
            id: cv
            visible: !!sh.vector[an.k]
            readonly property real pd: sh.pad(an.a)
            x: Math.floor(an.bb.x - pd); y: Math.floor(an.bb.y - pd)
            width: visible ? Math.ceil(an.bb.w + 2 * pd) + 1 : 1
            height: visible ? Math.ceil(an.bb.h + 2 * pd) + 1 : 1
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                if (!an.a || !visible) return;
                ctx.translate(-x, -y);
                sh.paint(ctx, an.a);
            }
        }
        Text {
            visible: an.k === "text"
            x: an.a && an.k === "text" ? an.a.x : 0; y: an.a && an.k === "text" ? an.a.y : 0
            text: an.a && an.k === "text" ? an.a.t : ""
            color: an.a && an.a.c ? an.a.c : "white"
            font.family: sh.fUi; font.pixelSize: an.a && an.a.fs ? an.a.fs : 20; font.weight: Font.Bold
            textFormat: Text.PlainText
            style: Text.Raised; styleColor: "#40000000"
        }
        Rectangle {
            visible: an.k === "step"
            readonly property real r: an.a && an.k === "step" ? sh.stepR(an.a) : 0
            x: an.a && an.k === "step" ? an.a.x - r : 0; y: an.a && an.k === "step" ? an.a.y - r : 0
            width: 2 * r; height: 2 * r; radius: r
            color: an.a && an.a.c ? an.a.c : "red"
            border.width: Math.max(1.5, r * 0.1); border.color: "#e6ffffff"
            Text {
                anchors.centerIn: parent
                text: an.a && an.k === "step" ? an.a.n : ""
                font.family: sh.fUi; font.pixelSize: parent.r * 1.05; font.weight: Font.Bold
                color: an.a && an.a.c && sh.luma(an.a.c) > 0.6 ? "#1a121a" : "white"
            }
        }
        ShaderEffectSource {          // pixelate: the original pixels squeezed into a few texels, drawn back without smoothing
            visible: an.k === "pixel" && an.bb.w > 0 && an.bb.h > 0
            x: an.bb.x; y: an.bb.y; width: an.bb.w; height: an.bb.h
            sourceItem: visible ? an.src : null
            sourceRect: Qt.rect(an.bb.x, an.bb.y, Math.max(1, an.bb.w), Math.max(1, an.bb.h))
            readonly property real blk: an.a && an.a.b ? an.a.b : 12
            textureSize: Qt.size(Math.max(1, Math.ceil(an.bb.w / blk)), Math.max(1, Math.ceil(an.bb.h / blk)))
            smooth: false
        }
        ShaderEffectSource {          // blur: a piece of the blurred frame
            visible: an.k === "blur" && an.bb.w > 0 && an.bb.h > 0
            x: an.bb.x; y: an.bb.y; width: an.bb.w; height: an.bb.h
            sourceItem: visible ? an.bsrc : null
            sourceRect: Qt.rect(an.bb.x, an.bb.y, Math.max(1, an.bb.w), Math.max(1, an.bb.h))
        }
    }

    // ── the frozen screen, one per monitor ────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: w
            required property var modelData
            screen: modelData
            readonly property string sn: modelData.name
            readonly property bool act: sh.act === sn
            readonly property bool editing: act && sh.phase === "edit"
            visible: sh.mapped
            color: "transparent"
            anchors { top: true; left: true; right: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "shot"
            WlrLayershell.keyboardFocus: sh.shown && act && !sh.passive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Component.onCompleted: { const m = Object.assign({}, sh.wins); m[sn] = w; sh.wins = m; }
            onActChanged: if (act && sh.shown) focusKeys()
            onVisibleChanged: if (visible && act) Qt.callLater(focusKeys)

            function focusKeys() { keys.forceActiveFocus(); }
            function togglePalette() { paletteP.pinned = !paletteP.pinned; }
            function focusText() { tedit.text = sh.editing ? sh.editing.t : ""; tedit.forceActiveFocus(); tedit.cursorPosition = tedit.text.length; }
            function textValue() { return tedit.text; }
            function textSize() { return { w: Math.max(4, tedit.contentWidth), h: Math.max(4, tedit.contentHeight) }; }

            // render the area (with beautify, if on) into a PNG, then cb(ok)
            function render(path, cb) {
                const after = function (ok) { cb(ok); };
                cropper.grabToImage(function (r) {
                    if (!sh.beauty) { after(r.saveToFile(path)); return; }
                    const tmp = sh.run + "/shot-raw.png";
                    if (!r.saveToFile(tmp)) { after(false); return; }
                    beautyImg.source = "";
                    beautyImg.source = "file://" + tmp + "?b=" + Date.now();
                    Qt.callLater(function () {
                        beautyCard.grabToImage(function (r2) { after(r2.saveToFile(path)); });
                    });
                });
            }

            property Item tipFor: null
            property string tipText: ""
            property string tipSide: "left"
            function showTip(it, t, side) { tipFor = it; tipText = t; tipSide = side; }
            function hideTip(it) { if (tipFor === it) tipFor = null; }

            Item {
                id: root
                anchors.fill: parent
                opacity: sh.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: sh.shown ? 60 : 170; easing.type: Easing.OutCubic } }

                // blurred copy of the frame, hidden under it: source for the glass and the blur tool
                MultiEffect {
                    id: blurFull
                    anchors.fill: frozen
                    source: frozen
                    visible: w.act && sh.mapped && frozen.status === Image.Ready     // else it peeks out while the new frame loads
                    blurEnabled: true; blur: 1.0; blurMax: 64; blurMultiplier: 0.6
                    autoPaddingEnabled: false
                }
                Image {
                    id: frozen
                    anchors.fill: parent
                    source: sh.mapped ? "file://" + sh.run + "/shot-" + w.sn + ".ppm?r=" + sh.rev : ""
                    cache: false
                    asynchronous: false
                    smooth: false
                    fillMode: Image.Stretch
                }

                // everything outside the area is dimmed
                Rectangle {
                    anchors.fill: parent
                    color: "#05060a"
                    opacity: !sh.shown ? 0 : sh.phase === "pick" ? 0.12 : w.act ? 0.5 : 0.62
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                // the bright area: hovered window (glides), the drag, or the selection - and the drawing on it
                readonly property var area: !w.act ? null
                    : sh.phase === "edit" || (sh.phase === "select" && sh.dragging && sh.sel) ? sh.sel
                    : sh.phase === "select" && sh.hoverShown ? sh.hover : null
                readonly property bool glide: sh.phase === "select" && !sh.dragging
                Item {
                    id: cropper
                    readonly property var r: root.area || ({ x: sh.mx, y: sh.my, w: 0, h: 0 })
                    x: r.x; y: r.y; width: r.w; height: r.h
                    opacity: root.area ? 1 : 0
                    clip: true
                    Behavior on x { enabled: root.glide; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: root.glide; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                    Behavior on width { enabled: root.glide; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                    Behavior on height { enabled: root.glide; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 140 } }

                    ShaderEffectSource {
                        anchors.fill: parent
                        sourceItem: frozen
                        sourceRect: Qt.rect(cropper.x, cropper.y, Math.max(1, cropper.width), Math.max(1, cropper.height))
                    }
                    Item {
                        x: -cropper.x; y: -cropper.y; width: w.width; height: w.height
                        visible: w.act && !sh.hideAnns
                        Repeater {
                            model: w.act ? sh.anns.length : 0
                            Ann { required property int index; idx: index; a: sh.anns[index] || null; src: frozen; bsrc: blurFull }
                        }
                        Ann { a: w.act ? sh.draft : null; src: frozen; bsrc: blurFull }
                    }
                }

                // pointer
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: w.act ? sh.cursor : Qt.ArrowCursor
                    onPressed: m => sh.pressAt(w, m.x, m.y, m.button, m.modifiers)
                    onPositionChanged: m => sh.moveTo(w, m.x, m.y, m.modifiers, pressed)
                    onReleased: m => { if (m.button === Qt.LeftButton) sh.releaseAt(w, m.x, m.y); }
                    onDoubleClicked: m => { if (m.button === Qt.LeftButton) sh.doubleAt(w, m.x, m.y); }
                    onWheel: wh => { if (sh.phase === "edit") sh.bump(wh.angleDelta.y > 0 ? 1 : -1); }
                }

                // selection frame + handles
                Rectangle {
                    visible: root.area !== null && root.area !== undefined && sh.phase !== "pick"
                    x: cropper.x - 1; y: cropper.y - 1; width: cropper.width + 2; height: cropper.height + 2
                    color: "transparent"
                    border.width: 1.5; border.color: sh.phase === "edit" || sh.dragging ? Cfg.accent : Cfg.acc(0.8)
                    opacity: cropper.opacity
                }
                Repeater {
                    model: w.editing ? 8 : 0
                    Rectangle {
                        required property int index
                        readonly property var p: sh.frameHandles(sh.sel)[index] || [0, 0]
                        x: p[0] - 5; y: p[1] - 5; width: 10; height: 10; radius: 5
                        color: "white"; border.width: 1.5; border.color: Cfg.accent
                        scale: sh.shown ? 1 : 0
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    }
                }

                // size / window label above the area
                Glass {
                    id: sizeTag
                    bsrc: blurFull
                    visible: w.act && root.area && sh.phase !== "pick" && (sh.phase === "edit" || sh.dragging || (root.area && root.area.title !== undefined))
                    readonly property string label: !root.area ? "" : (Math.round(root.area.w) + " × " + Math.round(root.area.h))
                        + (sh.phase === "select" && !sh.dragging && root.area && root.area.title ? "   " + root.area.title : "")
                    width: Math.min(420, stxt.implicitWidth + 22); height: 26; radius: 13
                    x: Math.round(sh.clamp(cropper.x, 6, w.width - width - 6))
                    y: Math.round(cropper.y - height - 8 < 6 ? cropper.y + 8 : cropper.y - height - 8)
                    Text {
                        id: stxt
                        anchors.centerIn: parent; width: Math.min(implicitWidth, 398); elide: Text.ElideRight
                        text: sizeTag.label
                        font.family: sh.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: sh.cFg
                    }
                }

                // selected annotation: outline + handles
                Item {
                    visible: w.editing && sh.selIdx >= 0 && sh.selIdx < sh.anns.length
                    readonly property var a: visible ? sh.anns[sh.selIdx] : null
                    readonly property var b: sh.bounds(a)
                    readonly property real e: a ? (a.k === "marker" ? sh.markerW(a) : (a.w || 0)) / 2 + 5 : 0
                    Rectangle {
                        visible: parent.a && !sh.twoPt[parent.a.k]
                        x: parent.b.x - parent.e; y: parent.b.y - parent.e; width: parent.b.w + 2 * parent.e; height: parent.b.h + 2 * parent.e
                        radius: 6; color: Cfg.acc(0.06); border.width: 1; border.color: Cfg.acc(0.9)
                    }
                    Repeater {
                        model: parent.visible ? sh.handles(parent.a).length : 0
                        Rectangle {
                            required property int index
                            readonly property var p: sh.handles(parent.a)[index] || [0, 0]
                            x: p[0] - 6; y: p[1] - 6; width: 12; height: 12; radius: 6
                            color: Cfg.accent; border.width: 2; border.color: "white"
                        }
                    }
                }

                // text being typed - same font as the result, so nothing jumps on commit
                Rectangle {
                    visible: w.act && !!sh.editing
                    x: tedit.x - 6; y: tedit.y - 3; width: Math.max(40, tedit.contentWidth) + 12; height: tedit.contentHeight + 6
                    radius: 6; color: "#14ffffff"; border.width: 1; border.color: Cfg.acc(0.7)
                }
                TextEdit {
                    id: tedit
                    visible: w.act && !!sh.editing
                    x: sh.editing ? sh.editing.x : 0; y: sh.editing ? sh.editing.y : 0
                    color: sh.editing ? sh.editing.c : "white"
                    font.family: sh.fUi; font.pixelSize: sh.editing ? sh.editing.fs : 20; font.weight: Font.Bold
                    textFormat: TextEdit.PlainText
                    selectByMouse: true
                    selectionColor: Cfg.acc(0.45)
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape || ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier))) {
                            e.accepted = true; sh.commitText();
                        }
                    }
                }

                // ── toolbars (Lightshot «L»: actions under the area, tools beside it, palette slides out) ──
                readonly property var lay: {
                    const s = sh.sel;
                    if (!w.editing || !s) return null;
                    const Wd = w.width, Hd = w.height, G = 10, M = 8;
                    const aw = actions.width, ah = actions.height, tw = toolsP.width, th = toolsP.height, pw = paletteP.width, ph = paletteP.height;
                    let ax = s.x + s.w - aw, ay = s.y + s.h + G;
                    if (ay + ah > Hd - M) { ay = s.y - G - ah; if (ay < M) ay = s.y + s.h - G - ah; }
                    ax = sh.clamp(ax, M, Wd - aw - M); ay = sh.clamp(ay, M, Hd - ah - M);
                    let tx = s.x + s.w + G, right = true;
                    if (tx + tw > Wd - M) { right = false; tx = s.x - G - tw; if (tx < M) tx = s.x + s.w - G - tw; }
                    let ty = s.y + s.h - th;
                    tx = sh.clamp(tx, M, Wd - tw - M); ty = sh.clamp(ty, M, Hd - th - M);
                    const meet = (x1, y1, w1, h1, x2, y2, w2, h2) => x1 < x2 + w2 && x2 < x1 + w1 && y1 < y2 + h2 && y2 < y1 + h1;
                    if (meet(tx, ty, tw, th, ax, ay, aw, ah)) {
                        ty = sh.clamp(ay - G - th, M, Hd - th - M);
                        if (meet(tx, ty, tw, th, ax, ay, aw, ah)) tx = sh.clamp(ax - G - tw, M, Wd - tw - M);
                    }
                    let px = right ? tx + tw + G : tx - G - pw;
                    if (px + pw > Wd - M || px < M) px = right ? tx - G - pw : tx + tw + G;
                    const py = sh.clamp(ty + th - ph, M, Hd - ph - M);
                    return { ax: Math.round(ax), ay: Math.round(ay), tx: Math.round(tx), ty: Math.round(ty), px: Math.round(sh.clamp(px, M, Wd - pw - M)), py: Math.round(py), right: right };
                }
                // panels appear in place (fade + scale); they glide only once they are already standing there -
                // otherwise they flew in from wherever they were last time (previous capture, the corner)
                readonly property bool shownLay: !!lay && !sh.dragging
                property bool settled: false
                onShownLayChanged: { settled = false; if (shownLay) settleT.restart(); else settleT.stop(); }
                Timer { id: settleT; interval: 320; onTriggered: root.settled = true }
                readonly property bool slide: settled && !sh.dragging

                Glass {
                    id: toolsP
                    bsrc: blurFull
                    width: 48; height: tcol.implicitHeight + 10; radius: 16
                    x: root.lay ? root.lay.tx : (sh.sel ? sh.sel.x + sh.sel.w + 10 : 0)
                    y: root.lay ? root.lay.ty : (sh.sel ? sh.sel.y + sh.sel.h - height : 0)
                    visible: opacity > 0 && w.editing && !!sh.sel     // never fade out at the (0,0) fallback of a new capture
                    opacity: root.lay && !sh.dragging ? 1 : 0
                    scale: root.lay ? 1 : 0.92
                    transformOrigin: Item.BottomLeft
                    Behavior on x { enabled: root.slide; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: root.slide; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    Column {
                        id: tcol
                        x: 5; y: 5; spacing: 2
                        Repeater {
                            model: sh.tools
                            TB {
                                required property var modelData
                                icon: modelData[1]; rot: modelData[2]; tip: modelData[3]; keyHint: modelData[4]
                                step: modelData[0] === "step"
                                on: sh.tool === modelData[0]
                                side: root.lay && !root.lay.right ? "right" : "left"
                                onClicked: sh.setTool(modelData[0])
                            }
                        }
                        Item { width: 38; height: 9; Sep { anchors.centerIn: parent } }
                        Item {     // colour swatch: hover opens the palette
                            id: swatch
                            width: 38; height: 38
                            Rectangle {
                                anchors.fill: parent; radius: 11
                                color: swma.containsMouse || paletteP.open ? sh.cHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 20; height: 20; radius: 10
                                color: sh.color
                                border.width: 2; border.color: "white"
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Rectangle {   // stroke size dot
                                anchors { right: parent.right; bottom: parent.bottom; margins: 3 }
                                width: 13; height: 13; radius: 6.5; color: "#cc0f1119"; border.width: 1; border.color: "#33ffffff"
                                Text { anchors.centerIn: parent; text: sh.tool === "text" ? Math.round(sh.fontSize) : Math.round(sh.stroke)
                                       font.family: sh.fUi; font.pixelSize: 7; font.weight: Font.Bold; color: sh.cFg }
                            }
                            MouseArea {
                                id: swma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: if (containsMouse) { paletteP.pinned = false; paletteP.hold(); }
                                onClicked: { paletteP.pinned = !paletteP.pinned; paletteP.hold(); }
                                onWheel: wh => sh.bump(wh.angleDelta.y > 0 ? 1 : -1)
                            }
                        }
                    }
                }

                Glass {
                    id: paletteP
                    bsrc: blurFull
                    property bool pinned: false
                    property bool hovered: false
                    readonly property bool open: (pinned || hovered) && !!root.lay && !sh.dragging
                    function hold() { hovered = true; closeT.stop(); }
                    Timer { id: closeT; interval: 420; onTriggered: paletteP.hovered = false }
                    Connections {
                        target: swma
                        function onContainsMouseChanged() { if (!swma.containsMouse && !pma.containsMouse) closeT.restart(); }
                    }
                    width: prow.implicitWidth + 12; height: 48; radius: 16
                    x: root.lay ? root.lay.px + (open ? 0 : (root.lay.right ? -14 : 14)) : 0
                    y: root.lay ? root.lay.py : 0
                    visible: opacity > 0 && w.editing && !!sh.sel
                    opacity: open ? 1 : 0
                    Behavior on x { enabled: root.slide; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    MouseArea {
                        id: pma
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: if (containsMouse) paletteP.hold(); else if (!swma.containsMouse) closeT.restart()
                        onWheel: wh => sh.bump(wh.angleDelta.y > 0 ? 1 : -1)
                    }
                    Row {
                        id: prow
                        x: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 0
                        Repeater {
                            model: sh.palette
                            Item {
                                required property var modelData
                                required property int index
                                readonly property bool on: Qt.colorEqual(sh.color, modelData)
                                width: 30; height: 36
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.on ? 22 : 18; height: width; radius: width / 2
                                    color: modelData
                                    border.width: parent.on ? 2.5 : 1; border.color: parent.on ? "white" : "#55ffffff"
                                    scale: cma.containsMouse ? 1.15 : 1
                                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                }
                                MouseArea {
                                    id: cma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: if (containsMouse) paletteP.hold(); else if (!swma.containsMouse) closeT.restart()
                                    onClicked: sh.setColor(modelData)
                                }
                            }
                        }
                        Item { width: 9; height: 36; Sep { vertical: false; anchors.centerIn: parent } }
                        Repeater {
                            model: sh.sizes
                            Item {
                                required property var modelData
                                readonly property bool on: Math.abs(sh.stroke - modelData) < 0.01
                                width: 30; height: 36
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 4 + modelData * 1.4; height: width; radius: width / 2
                                    color: parent.on ? Cfg.accent : sh.cFg
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: if (containsMouse) paletteP.hold(); else if (!swma.containsMouse) closeT.restart()
                                    onClicked: sh.setStroke(modelData)
                                }
                            }
                        }
                    }
                }

                Glass {
                    id: actions
                    bsrc: blurFull
                    width: arow.implicitWidth + 10; height: 48; radius: 16
                    x: root.lay ? root.lay.ax : (sh.sel ? sh.sel.x + sh.sel.w - width : 0)
                    y: root.lay ? root.lay.ay : (sh.sel ? sh.sel.y + sh.sel.h + 10 : 0)
                    visible: opacity > 0 && w.editing && !!sh.sel     // never fade out at the (0,0) fallback of a new capture
                    opacity: root.lay && !sh.dragging ? 1 : 0
                    scale: root.lay ? 1 : 0.92
                    transformOrigin: Item.TopRight
                    Behavior on x { enabled: root.slide; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: root.slide; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    Row {
                        id: arow
                        x: 5; y: 5; spacing: 2
                        TB { icon: ""; tip: "Undo"; keyHint: "Ctrl+Z"; side: "top"; enabledB: sh.undoStack.length > 0; onClicked: sh.undo() }
                        TB { icon: ""; tip: "Redo"; keyHint: "Ctrl+Y"; side: "top"; enabledB: sh.redoStack.length > 0; onClicked: sh.redo() }
                        Item { width: 9; height: 38; Sep { vertical: false; anchors.centerIn: parent } }
                        TB { icon: ""; tip: "Pin to screen"; keyHint: "Ctrl+P"; side: "top"; onClicked: sh.finish("pin", false) }
                        TB { icon: ""; tip: "Copy text (OCR)"; keyHint: "Ctrl+T"; side: "top"; onClicked: sh.finish("ocr", false) }
                        TB { icon: ""; tip: "Beautify"; keyHint: "Ctrl+B"; side: "top"; on: sh.beauty
                             onClicked: { sh.beauty = !sh.beauty; sh.say(sh.beauty ? sh.tr("Beautify on") : sh.tr("Beautify off")); } }
                        Item { width: 9; height: 38; Sep { vertical: false; anchors.centerIn: parent } }
                        TB { icon: ""; tip: "Save"; keyHint: "Ctrl+S"; side: "top"; onClicked: sh.finish("save", false) }
                        TB { icon: ""; tip: "Copy"; keyHint: "Enter"; side: "top"; onClicked: sh.finish("copy", false) }
                        Item { width: 9; height: 38; Sep { vertical: false; anchors.centerIn: parent } }
                        TB { icon: ""; tip: "Close"; keyHint: "Esc"; side: "top"; onClicked: sh.close() }
                    }
                }

                // tooltip
                Glass {
                    id: tipG
                    bsrc: blurFull
                    readonly property var at: w.tipFor ? w.tipFor.mapToItem(root, 0, 0) : null
                    opacity: w.tipFor && !sh.dragging ? 1 : 0
                    visible: opacity > 0 && w.editing
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    width: ttxt.implicitWidth + 20; height: 28; radius: 10; tint: 0.8
                    x: !at ? x : w.tipSide === "top" ? sh.clamp(at.x + 19 - width / 2, 6, w.width - width - 6)
                       : w.tipSide === "right" ? at.x + 38 + 14 : at.x - width - 14
                    y: !at ? y : w.tipSide === "top" ? (at.y - height - 12 < 6 ? at.y + 38 + 12 : at.y - height - 12) : at.y + 5
                    Text { id: ttxt; anchors.centerIn: parent; text: w.tipText; font.family: sh.fUi; font.pixelSize: 12; font.weight: Font.Medium; color: sh.cFg }
                }

                // toast (size, tool, copied…)
                Glass {
                    id: toastG
                    bsrc: blurFull
                    readonly property var c: sh.sel && sh.phase === "edit" ? sh.sel : { x: 0, y: 0, w: w.width, h: w.height }
                    opacity: w.act && sh.toast !== "" ? 1 : 0
                    visible: opacity > 0
                    scale: sh.toast !== "" ? 1 : 0.9
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                    width: tst.implicitWidth + 28; height: 32; radius: 16; tint: 0.7
                    x: Math.round(sh.clamp(c.x + c.w / 2 - width / 2, 6, w.width - width - 6))
                    y: Math.round(sh.clamp(c.y + 14, 6, w.height - height - 6))
                    Text { id: tst; anchors.centerIn: parent; text: sh.toast; font.family: sh.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: sh.cFg }
                }

                // magnifier with the colour under the pointer (before selecting, and in colour-pick mode)
                Item {
                    id: mag
                    visible: w.act && sh.phase !== "edit" && ma.containsMouse && !(sh.dragging && false)
                    readonly property int n: 15        // pixels across
                    readonly property int zm: 8
                    width: n * zm + 8; height: n * zm + 8 + 30
                    x: sh.mx + 24 + width > w.width ? sh.mx - 24 - width : sh.mx + 24
                    y: sh.my + 24 + height > w.height ? sh.my - 24 - height : sh.my + 24
                    Glass { anchors.fill: parent; bsrc: blurFull; radius: 18; tint: 0.7 }
                    Item {
                        id: lens
                        x: 4; y: 4; width: mag.n * mag.zm; height: width
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: lensMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        ShaderEffectSource {
                            anchors.fill: parent
                            sourceItem: mag.visible ? frozen : null
                            sourceRect: Qt.rect(Math.floor(sh.mx) - (mag.n - 1) / 2, Math.floor(sh.my) - (mag.n - 1) / 2, mag.n, mag.n)
                            smooth: false
                        }
                        Rectangle {     // the centre pixel
                            x: (mag.n - 1) / 2 * mag.zm; y: x; width: mag.zm; height: mag.zm
                            color: "transparent"; border.width: 1.5; border.color: "white"
                        }
                        Rectangle { x: 0; y: (mag.n - 1) / 2 * mag.zm + mag.zm / 2; width: (mag.n - 1) / 2 * mag.zm; height: 1; color: "#66ffffff" }
                        Rectangle { x: (mag.n + 1) / 2 * mag.zm; y: (mag.n - 1) / 2 * mag.zm + mag.zm / 2; width: (mag.n - 1) / 2 * mag.zm; height: 1; color: "#66ffffff" }
                        Rectangle { y: 0; x: (mag.n - 1) / 2 * mag.zm + mag.zm / 2; height: (mag.n - 1) / 2 * mag.zm; width: 1; color: "#66ffffff" }
                        Rectangle { y: (mag.n + 1) / 2 * mag.zm; x: (mag.n - 1) / 2 * mag.zm + mag.zm / 2; height: (mag.n - 1) / 2 * mag.zm; width: 1; color: "#66ffffff" }
                    }
                    Item {
                        id: lensMask
                        x: 4; y: 4; width: lens.width; height: lens.height
                        layer.enabled: true; visible: false
                        Rectangle { anchors.fill: parent; radius: 14 }
                    }
                    Row {
                        x: 10; y: lens.y + lens.height + 7; spacing: 8
                        Rectangle { width: 16; height: 16; radius: 5; color: sh.pix; border.width: 1; border.color: "#55ffffff"; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ("#" + sh.hex2(sh.pix.r) + sh.hex2(sh.pix.g) + sh.hex2(sh.pix.b)).toUpperCase() + "   " + Math.round(sh.mx) + ", " + Math.round(sh.my)
                            font.family: sh.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: sh.cFg
                        }
                    }
                }

                // 1-pixel sampler for the colour under the pointer
                Canvas {
                    id: sampler
                    width: 1; height: 1; opacity: 0
                    property string url: frozen.source.toString()
                    property bool ready: false
                    onUrlChanged: { ready = false; if (url !== "") loadImage(url); }
                    onImageLoaded: { ready = true; requestPaint(); }
                    Connections {
                        target: sh
                        enabled: w.act && sh.phase !== "edit"
                        function onMxChanged() { sampler.requestPaint(); }
                        function onMyChanged() { sampler.requestPaint(); }
                    }
                    onPaint: {
                        if (!ready || !w.act || sh.mx < 0 || sh.my < 0 || sh.mx >= w.width || sh.my >= w.height) return;
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, 1, 1);
                        ctx.drawImage(url, Math.floor(sh.mx), Math.floor(sh.my), 1, 1, 0, 0, 1, 1);
                        const d = ctx.getImageData(0, 0, 1, 1).data;
                        sh.pix = Qt.rgba(d[0] / 255, d[1] / 255, d[2] / 255, 1);
                    }
                }

                // beautify: the picture on an accent gradient, rounded, with a shadow (rendered off-screen for export)
                Item {
                    id: beautyCard
                    readonly property real pad: Math.round(Math.max(40, Math.min(96, Math.max(beautyImg.width, beautyImg.height) * 0.07)))
                    x: -width - 50; y: 0
                    width: beautyImg.width + 2 * pad; height: beautyImg.height + 2 * pad
                    visible: sh.beauty && w.act
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0; color: Qt.lighter(Cfg.accent, 1.05) }
                            GradientStop { position: 0.55; color: Qt.darker(Cfg.accent, 1.9) }
                            GradientStop { position: 1; color: "#1a1626" }
                        }
                    }
                    Rectangle {
                        x: beautyCard.pad; y: beautyCard.pad + 10; width: beautyImg.width; height: beautyImg.height; radius: 14
                        color: "#000000"
                        layer.enabled: true
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 40; opacity: 0.55 }
                    }
                    Item {
                        x: beautyCard.pad; y: beautyCard.pad; width: beautyImg.width; height: beautyImg.height
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: bMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        Image { id: beautyImg; cache: false; asynchronous: false; smooth: false }
                    }
                    Item {
                        id: bMask
                        x: beautyCard.pad; y: beautyCard.pad; width: beautyImg.width; height: beautyImg.height
                        layer.enabled: true; visible: false
                        Rectangle { anchors.fill: parent; radius: 14 }
                    }
                }

                Item {
                    id: keys
                    focus: true
                    Keys.onPressed: e => sh.key(e, w)
                }
            }
        }
    }

    // ── pinned captures: always on top, drag to move, wheel = zoom, Ctrl+wheel = fade, double-click / Esc = close ──
    Variants {
        model: sh.pins
        PanelWindow {
            id: pw
            required property var modelData
            readonly property var p: modelData
            property real zoom: 1
            property real fade: 1
            property real px: p.x - 12
            property real py: p.y - 12
            screen: Quickshell.screens.find(s => s.name === p.sn) || Quickshell.screens[0]
            // the layer covers the whole monitor but only takes input over the picture (mask), and the picture moves
            // inside it - moving the layer itself (margins) made the pointer coordinates chase the surface and jitter
            anchors { top: true; left: true; right: true; bottom: true }
            mask: Region { item: pc }
            readonly property real iw: pimg.implicitWidth > 0 ? pimg.implicitWidth : p.w     // beautified pins are bigger than the area
            readonly property real ih: pimg.implicitHeight > 0 ? pimg.implicitHeight : p.h
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "shot-pin"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            Item {
                id: pc
                x: Math.round(pw.px); y: Math.round(pw.py)
                width: Math.round(pw.iw * pw.zoom) + 24; height: Math.round(pw.ih * pw.zoom) + 24
                opacity: 0
                scale: 0.94
                Component.onCompleted: { opacity = Qt.binding(() => pw.fade); scale = 1; pk.forceActiveFocus(); }
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                Rectangle {     // soft shadow
                    x: 12; y: 15; width: parent.width - 24; height: parent.height - 24; radius: 10; color: "black"
                    layer.enabled: true
                    layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 16; opacity: 0.5 }
                }
                Item {
                    x: 12; y: 12; width: parent.width - 24; height: parent.height - 24
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: pmask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                    Image { id: pimg; anchors.fill: parent; source: "file://" + pw.p.path; cache: false; smooth: pw.zoom !== 1; mipmap: pw.zoom < 1 }
                }
                Item {
                    id: pmask
                    x: 12; y: 12; width: parent.width - 24; height: parent.height - 24
                    layer.enabled: true; visible: false
                    Rectangle { anchors.fill: parent; radius: 8 }
                }
                Rectangle {
                    x: 12; y: 12; width: parent.width - 24; height: parent.height - 24; radius: 8
                    color: "transparent"; border.width: pma2.containsMouse ? 1.5 : 1
                    border.color: pma2.containsMouse ? Cfg.acc(0.85) : "#33ffffff"
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                }
                Rectangle {     // zoom / fade label
                    id: ptag
                    anchors { right: parent.right; bottom: parent.bottom; margins: 20 }
                    width: ptt.implicitWidth + 16; height: 22; radius: 11; color: "#cc0f1119"
                    opacity: 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Text { id: ptt; anchors.centerIn: parent; font.family: sh.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: sh.cFg }
                    Timer { id: ptagT; interval: 900; onTriggered: ptag.opacity = 0 }
                    function show(t) { ptt.text = t; opacity = 1; ptagT.restart(); }
                }
                Item {
                    id: pk
                    focus: true
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) sh.unpin(pw.p.id);
                        else if ((e.modifiers & Qt.ControlModifier) && sh.letter(e) === "C") Quickshell.execDetached([sh.script, "done", "copy", pw.p.path]);
                    }
                }
            MouseArea {
                id: pma2
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real ox: 0       // pointer in monitor coordinates at the press
                property real oy: 0
                property real sx: 0       // picture position at the press
                property real sy: 0
                onPressed: m => { ox = pc.x + m.x; oy = pc.y + m.y; sx = pw.px; sy = pw.py; pk.forceActiveFocus(); }
                onPositionChanged: m => {
                    if (!pressed || !(m.buttons & Qt.LeftButton)) return;
                    pw.px = sh.clamp(sx + pc.x + m.x - ox, -pc.width + 60, pw.width - 60);
                    pw.py = sh.clamp(sy + pc.y + m.y - oy, -pc.height + 60, pw.height - 60);
                }
                onClicked: m => {
                    if (m.button === Qt.MiddleButton) { Quickshell.execDetached([sh.script, "done", "copy", pw.p.path]); ptag.show(sh.tr("Copied")); }
                    else if (m.button === Qt.RightButton) sh.unpin(pw.p.id);
                }
                onDoubleClicked: sh.unpin(pw.p.id)
                onWheel: wh => {
                    const d = wh.angleDelta.y > 0 ? 1 : -1;
                    if (wh.modifiers & Qt.ControlModifier) { pw.fade = sh.clamp(pw.fade + d * 0.1, 0.2, 1); ptag.show(Math.round(pw.fade * 100) + "%"); }
                    else { pw.zoom = sh.clamp(pw.zoom * (d > 0 ? 1.1 : 1 / 1.1), 0.2, 4); ptag.show(Math.round(pw.zoom * 100) + "%"); }
                }
            }
            }
        }
    }
}
