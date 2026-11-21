// sakura mono - sketch pad: a little tab on the left edge of the main monitor; click it and a
// drawing panel slides out. Click outside / Esc hides it.
//   layers: paper + pictures at the bottom, the drawing on top (the eraser only erases the drawing)
//   view:   zoom (Ctrl+wheel, + / −, fit), scroll (wheel, Shift+wheel), pan (middle mouse, Space+drag, H)
//   page:   any size - drag the corner of the page, or pick a preset / "fit to picture"
//   color:  palette, hue strip, eyedropper (I) on the page, or pick any color from the screen
// The drawing is kept in ~/.local/share/sakura/sketch/ (objects as JSON + imported pictures).
// Save -> ~/Pictures/Sketches/*.png (2x, sharp at any zoom), Copy -> clipboard.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

Scope {
    id: sk

    readonly property color cBg:     "#8c0f1119"
    readonly property color cCard:   "#14ffffff"
    readonly property color cCard2:  "#1fffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    "Inter"
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string home:   Quickshell.env("HOME")
    readonly property string dir:    home + "/.local/share/sakura/sketch"
    function t(s) { return Cfg.tr(s); }

    // viewport (the visible drawing area inside the panel) - the page itself can be any size
    readonly property int vpW: 1000
    readonly property int vpH: 640

    // ── state ───────────────────────────────────────────────
    property bool shown: false
    property real closedAt: 0
    onShownChanged: if (!shown) { closedAt = Date.now(); commitText(); sizeMenu = false; }
    property string tool: "brush"          // select | brush | eraser | line | arrow | rect | ellipse | text | picker | hand
    property string lastTool: "brush"
    property color color: "#1a121a"
    property int size: 6
    property bool fill: false
    property string paper: "#ffffff"
    property int pageW: 1000
    property int pageH: 640
    property var objs: []                  // committed objects, bottom -> top (pictures are always drawn under the drawing)
    property var undoStack: []
    property var redoStack: []
    property var cur: null                 // object being drawn
    property int sel: -1                   // selected object (select tool)
    property int imgSeq: 0

    // view transform: screen = page * zoom - (cx, cy)
    property real zoom: 1
    property real cx: 0
    property real cy: 0
    property bool spaceDown: false

    IpcHandler {
        target: "sketch"
        function toggle(): void { sk.shown = !sk.shown; }
        function open(): void { sk.shown = true; }
        function close(): void { sk.shown = false; }
    }

    // ── persistence ─────────────────────────────────────────
    FileView {
        id: store
        path: sk.dir + "/sketch.json"
        blockLoading: true
        onLoaded: {
            try {
                const j = JSON.parse(text());
                sk.objs = j.objs || []; sk.paper = j.paper || "#ffffff"; sk.imgSeq = j.imgSeq || 0;
                if (j.color) sk.color = j.color; if (j.size) sk.size = j.size;
                if (j.w) sk.pageW = j.w; if (j.h) sk.pageH = j.h;
                if (j.zoom) sk.zoom = j.zoom;
            } catch (e) {}
            sk.clampView(); sk.loadImages();
        }
        onLoadFailed: sk.fitView()
    }
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", dir])
    Timer { id: saveT; interval: 700
        onTriggered: store.setText(JSON.stringify({ objs: sk.objs, paper: sk.paper, imgSeq: sk.imgSeq, color: String(sk.color), size: sk.size,
                                                    w: sk.pageW, h: sk.pageH, zoom: sk.zoom })) }

    function repaint() { under.requestPaint(); over.requestPaint(); live.requestPaint(); }
    function commit(list) {
        undoStack = undoStack.concat([{ objs: objs, w: pageW, h: pageH }]).slice(-80);
        redoStack = [];
        objs = list;
        saveT.restart(); repaint();
    }
    function add(o) { commit(objs.concat([o])); }
    function restoreSnap(s) { objs = s.objs; if (s.w) { pageW = s.w; pageH = s.h; } sel = -1; saveT.restart(); clampView(); loadImages(); }
    function undo() { if (!undoStack.length) return; redoStack = redoStack.concat([{ objs: objs, w: pageW, h: pageH }]); const s = undoStack[undoStack.length - 1]; undoStack = undoStack.slice(0, -1); restoreSnap(s); }
    function redo() { if (!redoStack.length) return; undoStack = undoStack.concat([{ objs: objs, w: pageW, h: pageH }]); const s = redoStack[redoStack.length - 1]; redoStack = redoStack.slice(0, -1); restoreSnap(s); }
    function clearAll() { if (objs.length) { commit([]); sel = -1; } }
    function removeSel() { if (sel < 0) return; const l = objs.slice(); l.splice(sel, 1); sel = -1; commit(l); }
    function setPage(w, h) {
        w = Math.max(50, Math.min(8000, Math.round(w))); h = Math.max(50, Math.min(8000, Math.round(h)));
        if (w === pageW && h === pageH) return;
        undoStack = undoStack.concat([{ objs: objs, w: pageW, h: pageH }]).slice(-80); redoStack = [];
        pageW = w; pageH = h; saveT.restart(); clampView(); repaint();
    }

    // ── view ────────────────────────────────────────────────
    function clampAxis(c, page, vp) {
        const m = 60;
        if (page <= vp - 2 * 12) return -(vp - page) / 2;        // smaller than the view: centred
        return Math.max(-m, Math.min(page - vp + m, c));
    }
    function clampView() {
        cx = clampAxis(cx, pageW * zoom, vpW); cy = clampAxis(cy, pageH * zoom, vpH);
        repaint();
    }
    function zoomAt(nz, mx, my) {
        nz = Math.max(0.1, Math.min(8, nz));
        const px = (mx + cx) / zoom, py = (my + cy) / zoom;
        zoom = nz; cx = px * nz - mx; cy = py * nz - my;
        clampView(); saveT.restart();
    }
    function fitView() {
        zoom = Math.max(0.1, Math.min(4, Math.min((vpW - 40) / pageW, (vpH - 40) / pageH)));
        cx = -(vpW - pageW * zoom) / 2; cy = -(vpH - pageH * zoom) / 2;
        clampView(); saveT.restart();
    }
    function toPage(mx, my) { return { x: (mx + cx) / zoom, y: (my + cy) / zoom }; }
    onPageWChanged: repaint()
    onPageHChanged: repaint()

    // ── images ──────────────────────────────────────────────
    // every imported picture is copied next to the drawing, so it is still there after a reboot
    function loadImages() {
        for (const o of objs) if (o.type === "img") { if (!under.isImageLoaded(o.src)) under.loadImage(o.src); }
        repaint();
    }
    Process { id: imgProc; property var after: null
        stdout: StdioCollector { onStreamFinished: { const f = imgProc.after; imgProc.after = null; if (f) f(this.text.trim()); } } }
    function importFile(path) {
        if (!path) return;
        imgSeq++;
        const dst = dir + "/img-" + Date.now() + "-" + imgSeq;
        imgProc.after = out => { if (out.startsWith("OK ")) placeImage("file://" + out.slice(3)); };
        imgProc.command = ["sh", "-c", "mkdir -p \"$(dirname \"$2\")\" && ext=$(printf '%s' \"$1\" | sed 's/.*\\.//' | tr A-Z a-z) && cp -- \"$1\" \"$2.$ext\" && echo \"OK $2.$ext\"", "sh", path, dst];
        imgProc.running = true;
    }
    function pasteClipboard() {
        imgSeq++;
        const dst = dir + "/img-" + Date.now() + "-" + imgSeq + ".png";
        imgProc.after = out => { if (out.startsWith("OK ")) placeImage("file://" + out.slice(3)); else if (out.startsWith("PATH ")) importFile(out.slice(5)); };
        // an image in the clipboard, or a copied file (from the file manager)
        imgProc.command = ["sh", "-c",
            "if wl-paste -l 2>/dev/null | grep -q '^image/'; then wl-paste -t image/png > \"$1\" 2>/dev/null || wl-paste -t \"$(wl-paste -l | grep '^image/' | head -1)\" > \"$1\"; [ -s \"$1\" ] && echo \"OK $1\"; " +
            "else u=$(wl-paste -t text/uri-list 2>/dev/null | grep -m1 '^file://' | sed 's#^file://##' | tr -d '\\r'); [ -n \"$u\" ] && echo \"PATH $(printf '%b' \"${u//%/\\\\x}\")\"; fi", "sh", dst];
        imgProc.running = true;
    }
    property bool picking: false
    Process { id: pickProc
        stdout: StdioCollector { onStreamFinished: { sk.picking = false; sk.shown = true; const f = this.text.trim(); if (f) sk.importFile(f); } } }
    function pickFile() {
        picking = true; shown = false;   // the file dialog is a normal window: hide the panel while it is open
        pickProc.command = ["zenity", "--file-selection", "--title=" + t("Choose a picture"),
                            "--file-filter=" + t("Images") + " | *.png *.jpg *.jpeg *.webp *.gif *.bmp *.PNG *.JPG *.JPEG",
                            "--filename=" + home + "/Pictures/"];
        pickProc.running = true;
    }
    // color from anywhere on the screen (hyprpicker): the panel steps aside while you pick
    Process { id: screenPick
        stdout: StdioCollector { onStreamFinished: { const c = this.text.trim(); sk.picking = false; sk.shown = true;
            if (/^#[0-9a-fA-F]{6}$/.test(c)) { sk.color = c.toLowerCase(); sk.backToDrawing(); } } } }
    function pickScreenColor() {
        picking = true; shown = false;
        screenPick.command = ["sh", "-c", "sleep 0.3; hyprpicker -f hex -n 2>/dev/null | tail -1"];
        screenPick.running = true;
    }
    function backToDrawing() { if (tool === "eraser" || tool === "select" || tool === "picker" || tool === "hand") tool = lastTool === "eraser" ? "brush" : lastTool; }

    function placeImage(url) { probe.pending = url; probe.source = url; }
    Image {
        id: probe; visible: false; property string pending: ""
        asynchronous: false
        onStatusChanged: {
            if (status !== Image.Ready || !pending) return;
            const k = Math.min(1, sk.pageW * 0.8 / implicitWidth, sk.pageH * 0.8 / implicitHeight);
            const w = Math.round(implicitWidth * k), h = Math.round(implicitHeight * k);
            const o = { type: "img", src: pending, x: Math.round((sk.pageW - w) / 2), y: Math.round((sk.pageH - h) / 2), w: w, h: h,
                        nw: implicitWidth, nh: implicitHeight };
            pending = ""; source = "";
            sk.add(o); sk.tool = "select"; sk.sel = sk.objs.length - 1; sk.loadImages();
        }
    }
    // page = exactly the selected (or the first) picture at its own size
    function fitPageToImage() {
        let i = sel >= 0 && objs[sel] && objs[sel].type === "img" ? sel : objs.findIndex(o => o.type === "img");
        if (i < 0) { say(t("No picture on the page")); return; }
        const o = objs[i], w = o.nw || o.w, h = o.nh || o.h;
        const l = objs.slice(); l[i] = Object.assign({}, o, { x: 0, y: 0, w: w, h: h });
        undoStack = undoStack.concat([{ objs: objs, w: pageW, h: pageH }]).slice(-80); redoStack = [];
        objs = l; pageW = w; pageH = h; saveT.restart(); fitView();
    }

    // ── export (separate canvas at 2x the page, so it is sharp at any zoom) ──
    property string toast: ""
    Timer { id: toastT; interval: 2200; onTriggered: sk.toast = "" }
    function say(s) { toast = s; toastT.restart(); }
    property var exportJob: null
    function exportPng(copy) {
        commitText();
        const name = "sketch-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".png";
        Quickshell.execDetached(["mkdir", "-p", home + "/Pictures/Sketches"]);
        exportJob = { copy: copy, out: copy ? dir + "/clipboard.png" : home + "/Pictures/Sketches/" + name };
        exp.start();
    }
    function finishExport(ok) {
        const j = exportJob; exportJob = null;
        if (!j) return;
        if (!ok) { say(t("Could not save")); return; }
        if (j.copy) { Quickshell.execDetached(["sh", "-c", "wl-copy -t image/png < \"$1\"", "sh", j.out]); say(t("Copied - paste it anywhere")); }
        else say(t("Saved to") + " ~/Pictures/Sketches");
    }

    // ── geometry helpers (page coordinates) ─────────────────
    function bbox(o) {
        if (o.type === "img" || o.type === "rect" || o.type === "ellipse") {
            const x = Math.min(o.x, o.x + o.w), y = Math.min(o.y, o.y + o.h);
            return { x: x, y: y, w: Math.abs(o.w), h: Math.abs(o.h) };
        }
        if (o.type === "text") {
            metrics.font.pixelSize = o.size; metrics.font.family = fUi; metrics.font.weight = Font.DemiBold;
            const lines = o.text.split("\n"); let w = 0;
            for (const l of lines) { metrics.text = l; w = Math.max(w, metrics.width); }
            return { x: o.x, y: o.y, w: w, h: lines.length * o.size * 1.25 };
        }
        const p = o.pts || [o.x1, o.y1, o.x2, o.y2];
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
        for (let i = 0; i < p.length; i += 2) { x0 = Math.min(x0, p[i]); x1 = Math.max(x1, p[i]); y0 = Math.min(y0, p[i + 1]); y1 = Math.max(y1, p[i + 1]); }
        const r = (o.size || 2) / 2 + 3;
        return { x: x0 - r, y: y0 - r, w: x1 - x0 + 2 * r, h: y1 - y0 + 2 * r };
    }
    TextMetrics { id: metrics }
    function hit(px, py) {
        // the drawing lies above the pictures, so it wins
        for (const wantImg of [false, true])
            for (let i = objs.length - 1; i >= 0; i--) {
                const o = objs[i]; if (o.type === "eraser" || (o.type === "img") !== wantImg) continue;
                const b = bbox(o);
                if (px >= b.x && px <= b.x + b.w && py >= b.y && py <= b.y + b.h) return i;
            }
        return -1;
    }
    function moved(o, dx, dy) {
        const n = Object.assign({}, o);
        if (n.pts) n.pts = n.pts.map((v, i) => v + (i % 2 ? dy : dx));
        if (n.x1 !== undefined) { n.x1 += dx; n.y1 += dy; n.x2 += dx; n.y2 += dy; }
        if (n.x !== undefined) { n.x += dx; n.y += dy; }
        return n;
    }

    // ── painting ────────────────────────────────────────────
    function paintObj(ctx, o, cv) {
        ctx.save();
        ctx.lineCap = "round"; ctx.lineJoin = "round";
        if (o.type === "eraser") ctx.globalCompositeOperation = "destination-out";
        ctx.strokeStyle = o.color || "#000"; ctx.fillStyle = o.color || "#000"; ctx.lineWidth = o.size || 2;
        if (o.type === "brush" || o.type === "eraser") {
            const p = o.pts;
            ctx.beginPath();
            if (p.length <= 2) { ctx.arc(p[0], p[1], ctx.lineWidth / 2, 0, Math.PI * 2); ctx.fill(); ctx.restore(); return; }
            ctx.moveTo(p[0], p[1]);
            for (let i = 2; i < p.length - 2; i += 2) {
                const mx = (p[i] + p[i + 2]) / 2, my = (p[i + 1] + p[i + 3]) / 2;
                ctx.quadraticCurveTo(p[i], p[i + 1], mx, my);
            }
            ctx.lineTo(p[p.length - 2], p[p.length - 1]);
            ctx.stroke();
        } else if (o.type === "line" || o.type === "arrow") {
            ctx.beginPath(); ctx.moveTo(o.x1, o.y1); ctx.lineTo(o.x2, o.y2); ctx.stroke();
            if (o.type === "arrow") {
                const a = Math.atan2(o.y2 - o.y1, o.x2 - o.x1), L = 10 + o.size * 2.2;
                ctx.beginPath();
                ctx.moveTo(o.x2, o.y2); ctx.lineTo(o.x2 - L * Math.cos(a - 0.45), o.y2 - L * Math.sin(a - 0.45));
                ctx.moveTo(o.x2, o.y2); ctx.lineTo(o.x2 - L * Math.cos(a + 0.45), o.y2 - L * Math.sin(a + 0.45));
                ctx.stroke();
            }
        } else if (o.type === "rect") {
            if (o.fill) ctx.fillRect(o.x, o.y, o.w, o.h); else ctx.strokeRect(o.x, o.y, o.w, o.h);
        } else if (o.type === "ellipse") {
            ctx.beginPath(); ctx.ellipse(Math.min(o.x, o.x + o.w), Math.min(o.y, o.y + o.h), Math.abs(o.w), Math.abs(o.h));
            if (o.fill) ctx.fill(); else ctx.stroke();
        } else if (o.type === "text") {
            ctx.font = "600 " + o.size + "px \"" + fUi + "\"";
            ctx.textBaseline = "top";
            o.text.split("\n").forEach((l, i) => ctx.fillText(l, o.x, o.y + i * o.size * 1.25));
        } else if (o.type === "img") {
            if (cv.isImageLoaded(o.src)) ctx.drawImage(o.src, o.x, o.y, o.w, o.h);
        }
        ctx.restore();
    }
    // bottom layer: paper + pictures
    function paintUnder(ctx, cv, s, ox, oy) {
        ctx.save();
        ctx.setTransform(s, 0, 0, s, -ox, -oy);
        ctx.beginPath(); ctx.rect(0, 0, pageW, pageH); ctx.clip();
        if (paper === "#00000000") {
            if (cv !== exp) {     // checkerboard only on screen; the exported PNG stays transparent
                const q = 12 / s;
                for (let y = 0, r = 0; y < pageH; y += q, r++)
                    for (let x = (r % 2) * q; x < pageW; x += 2 * q) { ctx.fillStyle = "#2a2e40"; ctx.fillRect(x, y, q, q); }
            }
        } else { ctx.fillStyle = paper; ctx.fillRect(0, 0, pageW, pageH); }
        for (const o of objs) if (o.type === "img") paintObj(ctx, o, cv);
        ctx.restore();
    }
    // top layer: the drawing (strokes, shapes, text, eraser)
    function paintOver(ctx, cv, s, ox, oy, withCur) {
        ctx.save();
        ctx.setTransform(s, 0, 0, s, -ox, -oy);
        ctx.beginPath(); ctx.rect(0, 0, pageW, pageH); ctx.clip();
        for (const o of objs) if (o.type !== "img") paintObj(ctx, o, cv);
        if (withCur && cur && cur.type === "eraser") paintObj(ctx, cur, cv);   // erase live while dragging
        ctx.restore();
    }

    // ── eyedropper ──────────────────────────────────────────
    property color hoverColor: "transparent"
    function sampleAt(mx, my) {
        const a = over.getContext("2d").getImageData(Math.round(mx), Math.round(my), 1, 1).data;
        const b = under.getContext("2d").getImageData(Math.round(mx), Math.round(my), 1, 1).data;
        const k = a[3] / 255;
        let r = a[0] * k + b[0] * (1 - k), g = a[1] * k + b[1] * (1 - k), bl = a[2] * k + b[2] * (1 - k);
        if (a[3] === 0 && b[3] === 0) return null;
        const h = n => ("0" + Math.round(n).toString(16)).slice(-2);
        return "#" + h(r) + h(g) + h(bl);
    }

    // ── text tool ───────────────────────────────────────────
    property var textAt: null              // { x, y } in page coordinates while typing
    function commitText() {
        if (!textAt) return;
        const s = textEdit.text.replace(/\s+$/, "");
        const at = textAt; textAt = null; textEdit.text = "";
        if (s !== "") add({ type: "text", x: at.x, y: at.y, text: s, color: String(color), size: Math.max(14, size * 4) });
    }

    // (the tab on the left edge that opens this lives in EdgeTab.qml)

    // ── the panel ───────────────────────────────────────────
    property bool sizeMenu: false
    PanelWindow {
        id: win
        screen: Cfg.mainScreen
        visible: sk.shown || panel.x > -panel.width + 2 || sk.exportJob !== null
        anchors.left: true
        implicitWidth: sk.vpW + 2 * 18 + 64 + 16
        implicitHeight: sk.vpH + 60 + 48
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "sketch"
        WlrLayershell.keyboardFocus: sk.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        HyprlandFocusGrab { windows: [ win ]; active: sk.shown && !sk.picking; onCleared: sk.shown = false }

        // export canvas: the page at 2x, rendered off to the side and saved straight to a file
        Canvas {
            id: exp
            x: 0; y: 0; z: -10
            width: sk.exportJob ? sk.pageW * 2 : 1; height: sk.exportJob ? sk.pageH * 2 : 1
            opacity: 0
            renderTarget: Canvas.Image
            property int waiting: 0
            function start() {
                waiting = 0;
                for (const o of sk.objs) if (o.type === "img" && !isImageLoaded(o.src)) { waiting++; loadImage(o.src); }
                if (waiting === 0) Qt.callLater(requestPaint);
            }
            onImageLoaded: { waiting--; if (waiting <= 0 && sk.exportJob) requestPaint(); }
            onPaint: {
                if (!sk.exportJob) return;
                const ctx = getContext("2d");
                ctx.reset();
                sk.paintUnder(ctx, exp, 2, 0, 0);
                sk.paintOver(ctx, exp, 2, 0, 0, false);
            }
            onPainted: if (sk.exportJob) { const ok = save(sk.exportJob.out); sk.finishExport(ok); }
        }

        Rectangle {
            id: panel
            x: sk.shown ? 8 : -width - 10
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            width: parent.width - 16; height: parent.height
            radius: 22; color: sk.cBg; border.width: 1; border.color: sk.cBorder

            focus: sk.shown
            Keys.onReleased: e => { if (e.key === Qt.Key_Space && !e.isAutoRepeat) { sk.spaceDown = false; e.accepted = true; } }
            Keys.onPressed: e => {
                const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
                if (sk.textAt) return;
                if (e.key === Qt.Key_Space) { sk.spaceDown = true; e.accepted = true; return; }
                if (e.key === Qt.Key_Escape) { if (sk.sizeMenu) sk.sizeMenu = false; else if (sk.sel >= 0) sk.sel = -1; else sk.shown = false; }
                else if (ctrl && e.key === Qt.Key_Z) shift ? sk.redo() : sk.undo();
                else if (ctrl && e.key === Qt.Key_Y) sk.redo();
                else if (ctrl && e.key === Qt.Key_V) sk.pasteClipboard();
                else if (ctrl && e.key === Qt.Key_S) sk.exportPng(false);
                else if (ctrl && e.key === Qt.Key_C) sk.exportPng(true);
                else if (ctrl && e.key === Qt.Key_O) sk.pickFile();
                else if (ctrl && (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal)) sk.zoomAt(sk.zoom * 1.25, sk.vpW / 2, sk.vpH / 2);
                else if (ctrl && e.key === Qt.Key_Minus) sk.zoomAt(sk.zoom / 1.25, sk.vpW / 2, sk.vpH / 2);
                else if (ctrl && e.key === Qt.Key_0) sk.fitView();
                else if (ctrl && e.key === Qt.Key_1) sk.zoomAt(1, sk.vpW / 2, sk.vpH / 2);
                else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) sk.removeSel();
                else if (!ctrl) {
                    const k = { "B": "brush", "E": "eraser", "L": "line", "A": "arrow", "R": "rect", "O": "ellipse", "T": "text", "V": "select", "I": "picker", "H": "hand" }[e.text.toUpperCase()];
                    if (k) sk.setTool(k);
                    else if (e.text === "[") sk.size = Math.max(1, sk.size - 1);
                    else if (e.text === "]") sk.size = Math.min(60, sk.size + 1);
                    else return;
                } else return;
                e.accepted = true;
            }

            // ── toolbar (left column) ──
            Column {
                id: tools
                x: 12; y: 16; spacing: 3
                property var tipItem: null
                property string tipText: ""
                component ToolBtn: Rectangle {
                    id: tb
                    property string icon: ""
                    property string tip: ""
                    property bool on: false
                    signal clicked()
                    width: 44; height: 38; radius: 12
                    color: on ? sk.cAccent : (tba.containsMouse ? sk.cCard2 : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: tb.icon; font.family: sk.fIcon; font.pixelSize: 15; color: tb.on ? sk.cAccFg : sk.cFg }
                    MouseArea { id: tba; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked()
                        // one shared tooltip (toolTip below) - drawn above everything, never over the top row
                        onContainsMouseChanged: { if (containsMouse) { tools.tipItem = tb; tools.tipText = tb.tip; } else if (tools.tipItem === tb) tools.tipText = ""; } }
                }
                Repeater {
                    model: [ { k: "select", i: "", t: "Select / move (V)" }, { k: "hand", i: "", t: "Move the view (H, Space or middle mouse)" },
                             { k: "brush", i: "", t: "Brush (B)" }, { k: "eraser", i: "", t: "Eraser (E) - pictures stay" },
                             { k: "line", i: "", t: "Line (L)" }, { k: "arrow", i: "", t: "Arrow (A)" }, { k: "rect", i: "", t: "Rectangle (R)" },
                             { k: "ellipse", i: "", t: "Ellipse (O)" }, { k: "text", i: "", t: "Text (T)" }, { k: "picker", i: "", t: "Eyedropper (I)" } ]
                    ToolBtn { required property var modelData; icon: modelData.i; tip: sk.t(modelData.t); on: sk.tool === modelData.k
                              onClicked: sk.setTool(modelData.k) }
                }
                Rectangle { width: 44; height: 1; color: sk.cBorder }
                ToolBtn { icon: ""; tip: sk.t("Import picture (Ctrl+O, or Ctrl+V / drop a file)"); onClicked: sk.pickFile() }
                ToolBtn { icon: ""; tip: sk.t("Undo (Ctrl+Z)"); opacity: sk.undoStack.length ? 1 : 0.4; onClicked: sk.undo() }
                ToolBtn { icon: ""; tip: sk.t("Redo (Ctrl+Shift+Z)"); opacity: sk.redoStack.length ? 1 : 0.4; onClicked: sk.redo() }
                ToolBtn { icon: ""; tip: sk.t("Clear (undo brings it back)"); onClicked: sk.clearAll() }
            }

            Rectangle {   // tooltip of the tool under the mouse
                id: toolTip
                z: 1000
                visible: tools.tipText !== "" && tools.tipItem !== null
                readonly property bool below: !!tools.tipItem && tools.tipItem.parent === topRow
                readonly property point p: !tools.tipItem ? Qt.point(0, 0)
                    : below ? tools.tipItem.mapToItem(parent, tools.tipItem.width / 2, tools.tipItem.height)
                            : tools.tipItem.mapToItem(parent, tools.tipItem.width + 10, tools.tipItem.height / 2)
                x: below ? Math.max(8, p.x - width / 2) : p.x
                y: below ? topRow.y + topRow.height + 8 : Math.max(topRow.y + topRow.height + 8, p.y - height / 2)
                width: toolTipT.implicitWidth + 18; height: 28; radius: 9
                color: "#f20f1119"; border.width: 1; border.color: sk.cBorder
                Text { id: toolTipT; anchors.centerIn: parent; text: tools.tipText; color: sk.cFg; font.family: sk.fUi; font.pixelSize: 11 }
            }

            // ── top bar: colors, size, fill, paper, save/copy ──
            Row {
                id: topRow
                x: view.x; y: 12; spacing: 7; height: 36
                // current color (+ what the eyedropper is pointing at)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34; radius: 11; color: sk.color
                    border.width: 2; border.color: "#55ffffff"
                    Rectangle { visible: sk.tool === "picker" && sk.hoverColor.a > 0
                        anchors { right: parent.right; bottom: parent.bottom; margins: -5 } width: 18; height: 18; radius: 9
                        color: sk.hoverColor; border.width: 2; border.color: "#ffffff" }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; radius: 9
                    color: scrMa.containsMouse ? sk.cCard2 : "transparent"
                    Text { anchors.centerIn: parent; text: ""; font.family: sk.fIcon; font.pixelSize: 13; color: sk.cFg }
                    MouseArea { id: scrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sk.pickScreenColor()
                        onContainsMouseChanged: { if (containsMouse) { tools.tipItem = parent; tools.tipText = sk.t("Pick a color anywhere on the screen"); } else if (tools.tipItem === parent) tools.tipText = ""; } }
                }
                Repeater {
                    model: [ "#1a121a", "#ffffff", "#f2b8d0", "#ff4f7a", "#ff9f43", "#ffd93d", "#4cd97b", "#3fb6ff", "#6c63ff", "#b48cff", "#8a8fa3" ]
                    Rectangle {
                        required property string modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 11; color: modelData
                        border.width: String(sk.color) === modelData ? 3 : 1
                        border.color: String(sk.color) === modelData ? sk.cAccent : "#44ffffff"
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { sk.color = modelData; sk.backToDrawing(); } }
                    }
                }
                // custom color strip
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 80; height: 14; radius: 7
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#ff0000" } GradientStop { position: 0.17; color: "#ffff00" } GradientStop { position: 0.33; color: "#00ff00" }
                        GradientStop { position: 0.5; color: "#00ffff" } GradientStop { position: 0.67; color: "#0000ff" } GradientStop { position: 0.83; color: "#ff00ff" }
                        GradientStop { position: 1.0; color: "#ff0000" } }
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.CrossCursor
                        function pick(mx) { sk.color = Qt.hsva(Math.max(0, Math.min(0.999, mx / width)), 0.85, 1, 1).toString(); sk.backToDrawing(); }
                        onPressed: m => pick(m.x); onPositionChanged: m => { if (pressed) pick(m.x); } }
                }
                Rectangle { width: 1; height: 24; color: sk.cBorder; anchors.verticalCenter: parent.verticalCenter }
                // size
                Item {
                    anchors.verticalCenter: parent.verticalCenter; width: 110; height: 24
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: "#33ffffff" }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * (sk.size - 1) / 59; height: 4; radius: 2; color: sk.cAccent }
                    Rectangle { x: (parent.width - 16) * (sk.size - 1) / 59; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: "#ffffff" }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        function at(mx) { sk.size = Math.round(1 + Math.max(0, Math.min(1, mx / width)) * 59); }
                        onPressed: m => at(m.x); onPositionChanged: m => { if (pressed) at(m.x); } }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; width: 40; leftPadding: 4; text: sk.size + "px"; color: sk.cMuted; font.family: sk.fUi; font.pixelSize: 11 }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; radius: 9
                    color: sk.fill ? sk.cAccent : (fma.containsMouse ? sk.cCard2 : "transparent")
                    Text { anchors.centerIn: parent; text: sk.fill ? "" : ""; font.family: sk.fIcon; font.pixelSize: 14; color: sk.fill ? sk.cAccFg : sk.cFg }
                    MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sk.fill = !sk.fill }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; radius: 9
                    color: pma.containsMouse ? sk.cCard2 : "transparent"
                    Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 4; color: sk.paper; border.width: 1; border.color: "#66ffffff" }
                    MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { const l = ["#ffffff", "#0f1119", "#fdf6e9", "#00000000"]; sk.paper = l[(l.indexOf(sk.paper) + 1) % l.length]; saveT.restart(); sk.repaint(); } }
                }
            }
            Row {
                anchors { right: parent.right; rightMargin: 18; verticalCenter: topRow.verticalCenter }
                spacing: 8
                component PillBtn: Rectangle {
                    id: pb
                    property string text: ""
                    property string icon: ""
                    property bool primary: false
                    signal clicked()
                    width: pbr.implicitWidth + 22; height: 32; radius: 11
                    color: primary ? (pba.containsMouse ? "#ffffff" : sk.cAccent) : (pba.containsMouse ? sk.cCard2 : "#14ffffff")
                    Row { id: pbr; anchors.centerIn: parent; spacing: 7
                        Text { visible: pb.icon !== ""; text: pb.icon; font.family: sk.fIcon; font.pixelSize: 12; color: pb.primary ? sk.cAccFg : sk.cAccent; anchors.verticalCenter: parent.verticalCenter }
                        Text { visible: pb.text !== ""; text: pb.text; font.family: sk.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: pb.primary ? sk.cAccFg : sk.cFg; anchors.verticalCenter: parent.verticalCenter } }
                    MouseArea { id: pba; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
                }
                PillBtn { icon: ""; text: sk.t("Copy"); onClicked: sk.exportPng(true) }
                PillBtn { icon: ""; text: sk.t("Save"); primary: true; onClicked: sk.exportPng(false) }
            }

            // ── the view: paper + pictures, drawing, live stroke, ui ──
            Rectangle {
                id: view
                x: 72; y: 56; width: sk.vpW; height: sk.vpH
                radius: 12; color: "#14ffffff"; clip: true
                border.width: 1; border.color: sk.cBorder

                Canvas { id: under; anchors.fill: parent; renderStrategy: Canvas.Cooperative
                    onImageLoaded: requestPaint()
                    onPaint: { const ctx = getContext("2d"); ctx.reset(); sk.paintUnder(ctx, under, sk.zoom, sk.cx, sk.cy); } }
                Canvas { id: over; anchors.fill: parent; renderStrategy: Canvas.Cooperative
                    onPaint: { const ctx = getContext("2d"); ctx.reset(); sk.paintOver(ctx, over, sk.zoom, sk.cx, sk.cy, true); } }
                Canvas { id: live; anchors.fill: parent; renderStrategy: Canvas.Cooperative
                    onPaint: {
                        const ctx = getContext("2d"); ctx.reset();
                        if (!sk.cur || sk.cur.type === "eraser") return;
                        ctx.save(); ctx.setTransform(sk.zoom, 0, 0, sk.zoom, -sk.cx, -sk.cy);
                        ctx.beginPath(); ctx.rect(0, 0, sk.pageW, sk.pageH); ctx.clip();
                        sk.paintObj(ctx, sk.cur, live); ctx.restore();
                    } }
                // page outline
                Rectangle {
                    x: -sk.cx - 1; y: -sk.cy - 1; width: sk.pageW * sk.zoom + 2; height: sk.pageH * sk.zoom + 2
                    color: "transparent"; border.width: 1; border.color: "#33ffffff"
                }
                // selection box + resize handle
                Rectangle {
                    id: selBox
                    readonly property var b: sk.sel >= 0 && sk.sel < sk.objs.length ? sk.bbox(sk.objs[sk.sel]) : null
                    visible: b !== null
                    x: b ? b.x * sk.zoom - sk.cx - 3 : 0; y: b ? b.y * sk.zoom - sk.cy - 3 : 0
                    width: b ? b.w * sk.zoom + 6 : 0; height: b ? b.h * sk.zoom + 6 : 0
                    color: "transparent"; border.width: 2; border.color: sk.cAccent; radius: 4
                    Rectangle {
                        readonly property bool can: sk.sel >= 0 && sk.sel < sk.objs.length && ["img", "rect", "ellipse"].indexOf(sk.objs[sk.sel].type) >= 0
                        visible: can
                        x: parent.width - 8; y: parent.height - 8; width: 14; height: 14; radius: 7; color: sk.cAccent; border.width: 2; border.color: "#ffffff"
                    }
                }
                // typing text
                TextEdit {
                    id: textEdit
                    visible: sk.textAt !== null
                    x: sk.textAt ? sk.textAt.x * sk.zoom - sk.cx : 0; y: sk.textAt ? sk.textAt.y * sk.zoom - sk.cy : 0
                    width: Math.max(40, sk.vpW - x - 10)
                    color: sk.color; font.family: sk.fUi; font.weight: Font.DemiBold; font.pixelSize: Math.max(4, Math.round(Math.max(14, sk.size * 4) * sk.zoom))
                    wrapMode: TextEdit.NoWrap; selectionColor: sk.cAccent
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) { sk.textAt = null; text = ""; panel.forceActiveFocus(); e.accepted = true; }
                        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) { sk.commitText(); panel.forceActiveFocus(); e.accepted = true; }
                    }
                    Rectangle { anchors.fill: parent; anchors.margins: -4; color: "transparent"; border.width: 1; border.color: sk.cAccent; radius: 4; z: -1 }
                }

                MouseArea {
                    id: drawMa
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    readonly property bool panMode: sk.tool === "hand" || sk.spaceDown
                    cursorShape: panning ? Qt.ClosedHandCursor : panMode ? Qt.OpenHandCursor
                               : sk.tool === "select" ? (sk.hit(sk.toPage(mouseX, mouseY).x, sk.toPage(mouseX, mouseY).y) >= 0 ? Qt.SizeAllCursor : Qt.ArrowCursor)
                               : sk.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
                    property real sx: 0
                    property real sy: 0
                    property var orig: null
                    property bool resizing: false
                    property bool panning: false
                    property real pcx: 0
                    property real pcy: 0
                    onWheel: w => {
                        if (w.modifiers & Qt.ControlModifier) sk.zoomAt(sk.zoom * Math.pow(1.0015, w.angleDelta.y), w.x, w.y);
                        else if (w.modifiers & Qt.ShiftModifier) { sk.cx -= w.angleDelta.y; sk.clampView(); }
                        else { sk.cx -= w.angleDelta.x; sk.cy -= w.angleDelta.y; sk.clampView(); }
                    }
                    onPressed: m => {
                        panel.forceActiveFocus(); sk.sizeMenu = false;
                        if (m.button === Qt.MiddleButton || panMode) { panning = true; sx = m.x; sy = m.y; pcx = sk.cx; pcy = sk.cy; return; }
                        const p = sk.toPage(m.x, m.y), x = p.x, y = p.y; sx = x; sy = y;
                        if (sk.tool === "picker") {
                            const c = sk.sampleAt(m.x, m.y);
                            if (c) { sk.color = c; sk.backToDrawing(); }
                            return;
                        }
                        if (sk.tool === "text") { sk.commitText(); sk.textAt = { x: x, y: y - Math.max(14, sk.size * 4) * 0.6 }; textEdit.forceActiveFocus(); return; }
                        sk.commitText();
                        if (sk.tool === "select") {
                            const b = sk.sel >= 0 ? sk.bbox(sk.objs[sk.sel]) : null;
                            const hr = 14 / sk.zoom;
                            resizing = !!b && ["img", "rect", "ellipse"].indexOf(sk.objs[sk.sel].type) >= 0 && Math.abs(x - (b.x + b.w)) < hr && Math.abs(y - (b.y + b.h)) < hr;
                            if (!resizing) sk.sel = sk.hit(x, y);
                            orig = sk.sel >= 0 ? sk.objs[sk.sel] : null;
                            if (orig) sk.undoStack = sk.undoStack.concat([{ objs: sk.objs, w: sk.pageW, h: sk.pageH }]).slice(-80);
                            return;
                        }
                        const c = String(sk.color), s = sk.size;
                        if (sk.tool === "brush" || sk.tool === "eraser") sk.cur = { type: sk.tool, pts: [x, y], color: c, size: sk.tool === "eraser" ? s * 3 : s };
                        else if (sk.tool === "line" || sk.tool === "arrow") sk.cur = { type: sk.tool, x1: x, y1: y, x2: x, y2: y, color: c, size: s };
                        else sk.cur = { type: sk.tool, x: x, y: y, w: 0, h: 0, color: c, size: s, fill: sk.fill };
                        live.requestPaint();
                    }
                    onPositionChanged: m => {
                        if (sk.tool === "picker" && !pressed) { const c = sk.sampleAt(m.x, m.y); sk.hoverColor = c ? c : "transparent"; return; }
                        if (!pressed) return;
                        if (panning) { sk.cx = pcx - (m.x - sx); sk.cy = pcy - (m.y - sy); sk.clampView(); return; }
                        const p = sk.toPage(m.x, m.y), x = p.x, y = p.y;
                        if (sk.tool === "select") {
                            if (!orig) return;
                            const l = sk.objs.slice();
                            if (resizing) {
                                const n = Object.assign({}, orig);
                                if (n.type === "img") { const k = Math.max(0.02, (n.w + x - sx) / n.w); n.w = Math.round(orig.w * k); n.h = Math.round(orig.h * k); }
                                else { n.w = orig.w + x - sx; n.h = orig.h + y - sy; }
                                l[sk.sel] = n;
                            } else l[sk.sel] = sk.moved(orig, x - sx, y - sy);
                            sk.objs = l; sk.repaint();
                            return;
                        }
                        if (!sk.cur) return;
                        const o = Object.assign({}, sk.cur);
                        if (o.pts) {
                            const pp = o.pts, lx = pp[pp.length - 2], ly = pp[pp.length - 1];
                            if (Math.abs(x - lx) + Math.abs(y - ly) < 1.2 / sk.zoom) return;
                            o.pts = pp.concat([x, y]);
                        } else if (o.x1 !== undefined) {
                            let dx = x - o.x1, dy = y - o.y1;
                            if (m.modifiers & Qt.ShiftModifier) { const a = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * Math.PI / 4, r = Math.hypot(dx, dy); dx = r * Math.cos(a); dy = r * Math.sin(a); }
                            o.x2 = o.x1 + dx; o.y2 = o.y1 + dy;
                        } else {
                            o.w = x - o.x; o.h = y - o.y;
                            if (m.modifiers & Qt.ShiftModifier) { const d = Math.max(Math.abs(o.w), Math.abs(o.h)); o.w = Math.sign(o.w || 1) * d; o.h = Math.sign(o.h || 1) * d; }
                        }
                        sk.cur = o;
                        if (o.type === "eraser") over.requestPaint(); else live.requestPaint();
                    }
                    onExited: sk.hoverColor = "transparent"
                    onReleased: {
                        if (panning) { panning = false; saveT.restart(); return; }
                        if (sk.tool === "select") {
                            if (orig) { sk.redoStack = []; saveT.restart(); }
                            orig = null; resizing = false;
                            return;
                        }
                        if (!sk.cur) return;
                        const o = sk.cur; sk.cur = null; live.requestPaint();
                        if ((o.type === "rect" || o.type === "ellipse") && Math.abs(o.w) < 2 && Math.abs(o.h) < 2) return;
                        if (o.type === "rect" || o.type === "ellipse") { if (o.w < 0) { o.x += o.w; o.w = -o.w; } if (o.h < 0) { o.y += o.h; o.h = -o.h; } }
                        sk.add(o);
                    }
                }
                // drag the bottom-right corner of the page to resize it
                Rectangle {
                    id: pageGrip
                    x: sk.pageW * sk.zoom - sk.cx - 9; y: sk.pageH * sk.zoom - sk.cy - 9
                    width: 18; height: 18; radius: 5
                    color: gripMa.containsMouse || gripMa.pressed ? sk.cAccent : "#f20f1119"
                    border.width: 1; border.color: "#88ffffff"
                    Text { anchors.centerIn: parent; text: ""; rotation: 90; font.family: sk.fIcon; font.pixelSize: 9
                           color: gripMa.containsMouse || gripMa.pressed ? sk.cAccFg : sk.cFg }
                    MouseArea {
                        id: gripMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; preventStealing: true
                        cursorShape: Qt.SizeFDiagCursor
                        property real w0: 0
                        property real h0: 0
                        property point p0
                        onPressed: m => { const g = mapToItem(view, m.x, m.y); p0 = g; w0 = sk.pageW; h0 = sk.pageH; sk.sizeMenu = false; }
                        onPositionChanged: m => {
                            if (!pressed) return;
                            const g = mapToItem(view, m.x, m.y);
                            const snap = v => Math.round(v / 10) * 10;
                            sk.pageW = Math.max(50, snap(w0 + (g.x - p0.x) / sk.zoom)); sk.pageH = Math.max(50, snap(h0 + (g.y - p0.y) / sk.zoom));
                        }
                        onReleased: { if (sk.pageW !== w0 || sk.pageH !== h0) {
                                          sk.undoStack = sk.undoStack.concat([{ objs: sk.objs, w: w0, h: h0 }]).slice(-80); sk.redoStack = []; saveT.restart(); }
                                      sk.clampView(); }
                    }
                    Rectangle {   // live size label while dragging
                        visible: gripMa.pressed
                        x: -width - 6; y: -height - 6; width: szT.implicitWidth + 14; height: 24; radius: 8; color: "#f20f1119"
                        Text { id: szT; anchors.centerIn: parent; text: sk.pageW + " × " + sk.pageH; color: sk.cFg; font.family: sk.fUi; font.pixelSize: 11 }
                    }
                }
                // drop image files onto the page
                DropArea {
                    anchors.fill: parent
                    onDropped: d => {
                        const u = (d.urls || []).map(String).find(x => /\.(png|jpe?g|webp|gif|bmp)$/i.test(x));
                        if (u) sk.importFile(decodeURIComponent(u.replace(/^file:\/\//, "")));
                    }
                }
            }

            // ── bottom bar: page size, zoom, messages ──
            Row {
                id: bottomRow
                x: view.x; y: view.y + view.height + 8; spacing: 6; height: 30
                PillBtn { icon: ""; text: sk.pageW + " × " + sk.pageH; onClicked: sk.sizeMenu = !sk.sizeMenu }
                Rectangle { width: 1; height: 20; color: sk.cBorder; anchors.verticalCenter: parent.verticalCenter }
                PillBtn { icon: ""; onClicked: sk.zoomAt(sk.zoom / 1.25, sk.vpW / 2, sk.vpH / 2) }
                PillBtn { text: Math.round(sk.zoom * 100) + "%"; width: 64; onClicked: sk.zoomAt(1, sk.vpW / 2, sk.vpH / 2) }
                PillBtn { icon: ""; onClicked: sk.zoomAt(sk.zoom * 1.25, sk.vpW / 2, sk.vpH / 2) }
                PillBtn { icon: ""; text: sk.t("Fit"); onClicked: sk.fitView() }
                Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: 10; text: sk.toast; visible: sk.toast !== ""
                       color: sk.cAccent; font.family: sk.fUi; font.pixelSize: 12 }
            }
            // page size menu
            Rectangle {
                id: sizePop
                visible: sk.sizeMenu
                x: bottomRow.x; y: bottomRow.y - height - 8; z: 50
                width: 300; height: spCol.implicitHeight + 24; radius: 16
                color: "#f20f1119"; border.width: 1; border.color: sk.cBorder
                Column {
                    id: spCol; x: 12; y: 12; width: parent.width - 24; spacing: 6
                    Text { text: sk.t("Page size"); color: sk.cFg; font.family: sk.fUi; font.pixelSize: 13; font.weight: Font.Bold }
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: [ [800, 600], [1000, 640], [1280, 720], [1920, 1080], [1080, 1080], [1080, 1920], [1240, 1754] ]
                            PillBtn { required property var modelData
                                      text: modelData[0] + "×" + modelData[1] + (modelData[0] === 1240 ? " A4" : "")
                                      primary: sk.pageW === modelData[0] && sk.pageH === modelData[1]
                                      onClicked: { sk.setPage(modelData[0], modelData[1]); sk.fitView(); } }
                        }
                    }
                    Row {
                        spacing: 6
                        NumField { id: wIn; text: String(sk.pageW); onDone: v => sk.setPage(v, sk.pageH) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "×"; color: sk.cMuted; font.family: sk.fUi; font.pixelSize: 13 }
                        NumField { id: hIn; text: String(sk.pageH); onDone: v => sk.setPage(sk.pageW, v) }
                        PillBtn { text: sk.t("Apply"); onClicked: { sk.setPage(parseInt(wIn.text) || sk.pageW, parseInt(hIn.text) || sk.pageH); sk.fitView(); } }
                    }
                    PillBtn { icon: ""; text: sk.t("Fit the page to the picture"); onClicked: { sk.fitPageToImage(); sk.sizeMenu = false; } }
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: sk.cMuted; font.family: sk.fUi; font.pixelSize: 11
                           text: sk.t("Or drag the corner of the page.") }
                }
            }
        }
    }
    component NumField: Rectangle {
        id: nf
        property alias text: nti.text
        signal done(int v)
        width: 70; height: 30; radius: 9; color: "#14ffffff"; border.width: 1; border.color: nti.activeFocus ? sk.cAccent : sk.cBorder
        TextInput { id: nti; anchors.fill: parent; anchors.margins: 6; verticalAlignment: TextInput.AlignVCenter; horizontalAlignment: TextInput.AlignHCenter
                    color: sk.cFg; font.family: sk.fUi; font.pixelSize: 12; validator: IntValidator { bottom: 50; top: 8000 }
                    selectByMouse: true
                    onAccepted: { nf.done(parseInt(text)); panel.forceActiveFocus(); } }
    }
    function setTool(k) {
        commitText();
        if (k !== "picker" && k !== "hand" && k !== "select") lastTool = k;
        else if (tool !== "picker" && tool !== "hand" && tool !== "select") lastTool = tool;
        tool = k; sel = -1; hoverColor = "transparent";
    }
}
