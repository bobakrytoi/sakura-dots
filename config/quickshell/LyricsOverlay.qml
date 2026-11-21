// sakura mono - floating lyrics: the words of the current line pop up one by one in liquid-glass pills
// settings: ~/.config/sakura/lyrics.json (Settings > Floating Lyrics) · preview: qs ipc call lyrics demo
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects

Scope {
    id: ov
    readonly property string home: Quickshell.env("HOME")

    // ── settings ────────────────────────────────────────────
    property var cfg: ({ enabled: true, style: "pop", size: "m", position: "top", speed: 1.0, highlight: true, offset: 0.0, layout: "scatter" })
    FileView {
        id: lyrFile
        path: ov.home + "/.config/sakura/lyrics.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { ov.cfg = Object.assign({}, ov.cfg, JSON.parse(text())); } catch (e) {} }
    }
    readonly property real fs: cfg.size === "s" ? 15 : cfg.size === "l" ? 25 : 19
    function dur(base) { return Math.round(base / Math.max(0.25, cfg.speed || 1)); }

    // ── player ──────────────────────────────────────────────
    readonly property var player: Players.player && Players.player.isPlaying ? Players.player : null
    readonly property string trackKey: player ? (player.trackArtist + "|" + player.trackTitle) : ""
    property string loadedKey: ""
    property var lines: []
    onTrackKeyChanged: { lines = []; curIdx = -1; slotA.lineIdx = -1; slotB.lineIdx = -1; fetchDelay.restart(); }
    Timer { id: fetchDelay; interval: 450; onTriggered: ov.fetch() }
    function fetch() {
        if (!player || trackKey === loadedKey) return;
        loadedKey = trackKey;
        const q = "artist_name=" + encodeURIComponent(player.trackArtist || "") + "&track_name=" + encodeURIComponent(player.trackTitle || "");
        lrc.running = false;
        lrc.command = ["curl", "-s", "--max-time", "6", "-A", "sakura-lyrics", "https://lrclib.net/api/get?" + q];
        lrc.running = true;
    }
    Process {
        id: lrc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null; try { d = JSON.parse(this.text); } catch (e) {}
                if (!ov.demo) ov.lines = ov.parse(d && d.syncedLyrics ? d.syncedLyrics : "");
            }
        }
    }

    // LRC -> [{ t, end, words: [{ w, t }] }]. Word times: real ones for word-timed (<mm:ss>) lyrics,
    // otherwise spread across the line by word length.
    function parse(raw) {
        const rows = [];
        raw.split("\n").forEach(l => {
            const m = l.match(/^\[(\d+):(\d+(?:\.\d+)?)\](.*)$/);
            if (m) rows.push({ t: parseInt(m[1]) * 60 + parseFloat(m[2]), text: m[3].trim() });
        });
        const out = [];
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i], next = i + 1 < rows.length ? rows[i + 1].t : r.t + 6;
            const words = [];
            const tag = /<(\d+):(\d+(?:\.\d+)?)>\s*([^<]*)/g;
            let m, timed = false;
            while ((m = tag.exec(r.text)) !== null) {
                timed = true;
                const t0 = parseInt(m[1]) * 60 + parseFloat(m[2]);
                m[3].trim().split(/\s+/).filter(x => x).forEach((x, j) => words.push({ w: x, t: t0 + j * 0.12 }));
            }
            if (!timed) {
                const toks = r.text.replace(/<[^>]*>/g, "").split(/\s+/).filter(x => x);
                const chars = toks.reduce((a, x) => a + x.length + 1, 0);
                const span = Math.max(0.4, Math.min((next - r.t) * 0.8, chars * 0.075));
                let acc = 0;
                toks.forEach(x => { words.push({ w: x, t: r.t + span * acc / Math.max(1, chars) }); acc += x.length + 1; });
            }
            const last = words.length ? words[words.length - 1].t : r.t;
            out.push({ t: r.t, end: words.length ? Math.min(next, last + 3.5) : r.t, words: words });
        }
        return out;
    }

    // ── preview (Settings button) ───────────────────────────
    property bool demo: false
    property real demoStart: 0
    readonly property string demoLrc: "[00:00.40] i use arch btw\n[00:03.10] sakura petals falling on my screen\n[00:06.60] liquid glass words for you\n[00:10.20] "
    IpcHandler {
        target: "lyrics"
        function toggle(): void { const c = Object.assign({}, ov.cfg); c.enabled = !c.enabled; ov.cfg = c; lyrFile.setText(JSON.stringify(c, null, 2)); }
        function demo(): void { ov.demo = true; ov.demoStart = Date.now(); ov.curIdx = -1; slotA.lineIdx = -1; slotB.lineIdx = -1; ov.lines = ov.parse(ov.demoLrc); demoEnd.restart(); }
    }
    Timer { id: demoEnd; interval: 11500; onTriggered: { ov.demo = false; ov.lines = []; ov.loadedKey = ""; ov.fetch(); } }

    // ── clock ───────────────────────────────────────────────
    property real pos: 0
    property int curIdx: -1
    readonly property bool hasWords: lines.length > 0
    Timer {
        interval: 40; repeat: true
        running: ov.cfg.enabled && ov.hasWords && (ov.demo || ov.player !== null)
        onTriggered: {
            if (ov.demo) ov.pos = (Date.now() - ov.demoStart) / 1000;
            else { ov.player.positionChanged(); ov.pos = ov.player.position + (ov.cfg.offset || 0); }
            let i = -1;
            for (let k = 0; k < ov.lines.length; k++) { if (ov.lines[k].t <= ov.pos) i = k; else break; }
            if (i !== ov.curIdx) {
                ov.curIdx = i;
                if (i >= 0 && ov.lines[i].words.length) {
                    if (ov.useA) { ov.assign(slotB, slotA, i); ov.useA = false; } else { ov.assign(slotA, slotB, i); ov.useA = true; }
                }
            }
        }
    }
    property bool useA: false
    function assign(slot, other, i) {
        slot.rects = ov.layoutLine(ov.lines[i].words, other.active ? other.rects : [], ov.hash(ov.trackKey + "#" + i));
        slot.lineIdx = i;
    }
    FontMetrics { id: fm; font.family: "Inter"; font.pixelSize: ov.fs; font.weight: Font.Bold }
    function hash(str) { let h = 2166136261; for (let k = 0; k < str.length; k++) { h ^= str.charCodeAt(k); h = Math.imul(h, 16777619); } return h >>> 0; }
    function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
    // where each word of a line goes: scattered at random spots without overlapping (also avoids the line that is leaving), or one centered row
    function layoutLine(words, avoid, seed) {
        const W = stage.width, H = stage.height, gap = ov.fs * 0.45, out = [];
        const size = w => ({ w: fm.advanceWidth(w) + ov.fs * 1.5, h: fm.height + ov.fs * 0.85 });
        if (ov.cfg.layout === "row") {
            const sz = words.map(x => size(x.w));
            const total = sz.reduce((a, r) => a + r.w, 0) + gap * Math.max(0, sz.length - 1);
            const k = Math.min(1, (W - 80) / Math.max(1, total));
            let x = (W - total * k) / 2;
            sz.forEach(r => { out.push({ x: x, y: (H - r.h) / 2, w: r.w, h: r.h }); x += (r.w + gap) * k; });
            return out;
        }
        const rand = ov.rng(seed), placed = avoid.slice(), pad = 14;
        words.forEach(x => {
            const r = size(x.w);
            let best = null, score = 1e12;
            for (let t = 0; t < 60 && score > 0; t++) {
                const cx = 50 + rand() * Math.max(1, W - 100 - r.w), cy = 6 + rand() * Math.max(1, H - 12 - r.h);
                let o = 0;
                placed.forEach(q => {
                    const ix = Math.max(0, Math.min(cx + r.w + pad, q.x + q.w) - Math.max(cx - pad, q.x));
                    const iy = Math.max(0, Math.min(cy + r.h + pad, q.y + q.h) - Math.max(cy - pad, q.y));
                    o += ix * iy;
                });
                if (o < score) { score = o; best = { x: cx, y: cy, w: r.w, h: r.h }; }
            }
            out.push(best); placed.push(best);
        });
        return out;
    }

    // hidden in fullscreen (games, F11 video), when paused or with nothing playing
    readonly property var activeTop: ToplevelManager.activeToplevel
    readonly property bool blocked: !cfg.enabled || (!demo && (player === null || (activeTop !== null && activeTop.fullscreen)))

    // continuous phase for the "wave" style
    property real phase: 0
    NumberAnimation on phase { from: 0; to: Math.PI * 2; duration: 2400; loops: Animation.Infinite; running: ov.cfg.style === "wave" && ov.hasWords }

    // ── one line of pills (two slots: the old line leaves while the new one comes in) ──
    component Slot: Item {
        id: slot
        anchors.fill: parent
        property int lineIdx: -1
        property var rects: []
        readonly property var line: lineIdx >= 0 && lineIdx < ov.lines.length ? ov.lines[lineIdx] : null
        readonly property bool active: !ov.blocked && line !== null && lineIdx === ov.curIdx && ov.pos < line.end
        readonly property int newest: {
            if (!line) return -1;
            let n = -1; for (let i = 0; i < line.words.length; i++) if (line.words[i].t <= ov.pos) n = i;
            return n;
        }
        Repeater {
            model: slot.line ? slot.line.words : []
            delegate: Item {
                id: pill
                required property var modelData
                required property int index
                readonly property var r: slot.rects[index] || { x: 0, y: 0, w: 10, h: 10 }
                x: r.x; y: r.y; width: r.w; height: r.h
                property bool seen: false
                readonly property bool revealed: slot.active && ov.pos >= modelData.t
                onRevealedChanged: if (revealed) seen = true
                property real e: seen ? 1 : 0                       // enter 0 -> 1 (may overshoot)
                property real l: (seen && !slot.active) ? 1 : 0     // leave 0 -> 1
                Behavior on e { NumberAnimation {
                    duration: ov.dur(ov.cfg.style === "fade" ? 380 : 560)
                    easing.type: (ov.cfg.style === "pop" || ov.cfg.style === "wave") ? Easing.OutBack : Easing.OutCubic
                    easing.overshoot: 2.2 } }
                Behavior on l { NumberAnimation { duration: ov.dur(480); easing.type: Easing.InCubic } }

                readonly property real ein: Math.max(0, Math.min(1, e))
                readonly property int st: ov.cfg.style === "pop" ? 0 : ov.cfg.style === "slide" ? 1 : ov.cfg.style === "wave" ? 2 : 3
                opacity: ein * (1 - l)
                scale: (st === 0 ? 0.45 + 0.55 * e : st === 2 ? 0.8 + 0.2 * e : 1) * (1 + 0.1 * l)
                transform: Translate {
                    y: (pill.st === 1 || pill.st === 2 ? 22 * (1 - pill.ein) : 0)
                       - (pill.st === 3 ? 6 : 18) * pill.l
                       + (pill.st === 2 && pill.seen ? Math.sin(ov.phase + pill.index * 0.8) * 4 * (1 - pill.l) : 0)
                }
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 40
                    blur: pill.st === 0 ? Math.min(1, (1 - pill.ein) * 1.2 + pill.l)
                        : pill.st === 3 ? pill.l * 0.4
                        : Math.min(1, (1 - pill.ein) * 0.5 + pill.l * 0.7)
                    shadowEnabled: false        // a shadow would show through the clear glass and make it muddy
                    brightness: 0.04
                }

                // pink tint on the word being sung
                Rectangle {
                    anchors.fill: parent; radius: height / 2
                    color: Cfg.accent
                    opacity: ov.cfg.highlight && pill.index === slot.newest && slot.active ? 0.30 : 0
                    Behavior on opacity { NumberAnimation { duration: ov.dur(320) } }
                }
                // liquid glass (the compositor blurs what is behind; this draws the glass itself)
                Canvas {
                    anchors.fill: parent
                    antialiasing: true
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d"); c.reset();
                        const w = width, h = height, R = h / 2;
                        function rr(x, y, ww, hh, rad) {
                            rad = Math.max(0.5, Math.min(rad, hh / 2, ww / 2));
                            c.beginPath(); c.moveTo(x + rad, y);
                            c.arcTo(x + ww, y, x + ww, y + hh, rad); c.arcTo(x + ww, y + hh, x, y + hh, rad);
                            c.arcTo(x, y + hh, x, y, rad); c.arcTo(x, y, x + ww, y, rad); c.closePath();
                        }
                        // body: barely-there frost
                        rr(0.5, 0.5, w - 1, h - 1, R);
                        let g = c.createLinearGradient(0, 0, 0, h);
                        g.addColorStop(0, "rgba(255,255,255,0.20)"); g.addColorStop(0.5, "rgba(255,255,255,0.07)"); g.addColorStop(1, "rgba(255,255,255,0.14)");
                        c.fillStyle = g; c.fill();
                        // edge lensing: light gathers along the inner rim
                        for (let i = 0; i < 6; i++) {
                            rr(1 + i, 1 + i, w - 2 - 2 * i, h - 2 - 2 * i, R - 1 - i);
                            c.lineWidth = 1; c.strokeStyle = "rgba(255,255,255," + (0.16 * Math.pow(1 - i / 6, 2)) + ")"; c.stroke();
                        }
                        // rim light: bright top-left and bottom-right, dim sides
                        rr(0.6, 0.6, w - 1.2, h - 1.2, R);
                        let s2 = c.createLinearGradient(0, 0, w, h);
                        s2.addColorStop(0, "rgba(255,255,255,0.95)"); s2.addColorStop(0.3, "rgba(255,255,255,0.22)");
                        s2.addColorStop(0.65, "rgba(255,255,255,0.10)"); s2.addColorStop(1, "rgba(255,255,255,0.70)");
                        c.lineWidth = 1.3; c.strokeStyle = s2; c.stroke();
                        // specular highlight + warm caustic at the bottom
                        c.save(); rr(0.5, 0.5, w - 1, h - 1, R); c.clip();
                        let hg = c.createLinearGradient(0, 0, 0, h * 0.5);
                        hg.addColorStop(0, "rgba(255,255,255,0.55)"); hg.addColorStop(1, "rgba(255,255,255,0)");
                        c.fillStyle = hg; rr(h * 0.32, 1.6, w - h * 0.64, h * 0.42, h * 0.21); c.fill();
                        let bg = c.createLinearGradient(0, h * 0.62, 0, h);
                        bg.addColorStop(0, "rgba(255,225,238,0)"); bg.addColorStop(1, "rgba(255,225,238,0.20)");
                        c.fillStyle = bg; c.fillRect(0, h * 0.62, w, h * 0.38);
                        c.restore();
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: pill.modelData.w
                    color: "#ffffff"
                    style: Text.Raised; styleColor: "#40000000"
                    font.family: "Inter"; font.pixelSize: ov.fs; font.weight: Font.Bold
                }
            }
        }
    }

    PanelWindow {
        visible: ov.cfg.enabled
        screen: Cfg.mainScreen
        anchors { left: true; right: true; top: ov.cfg.position !== "bottom"; bottom: ov.cfg.position === "bottom" }
        margins { top: 50; bottom: 78 }
        implicitHeight: ov.cfg.layout === "row" ? ov.fs * 4 + 20 : ov.fs * 7 + 30
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "lyrics"
        mask: Region {}                                   // never takes the mouse

        Item {
            id: stage
            anchors.fill: parent
            Slot { id: slotA }
            Slot { id: slotB }
        }
    }
}
