// sakura mono - dashboard (click the clock on the top bar)
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import QtQuick

Scope {
    id: db

    // palette
    readonly property color cBg:     Cfg.glass
    readonly property color cCard:   "#14ffffff"
    readonly property color cCard2:  "#1fffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccDim: Cfg.acc(0.33)
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string home:   Quickshell.env("HOME")
    readonly property string scripts: home + "/.config/hypr/scripts"

    property bool shown: false
    // floating lyrics on/off (button next to prev)
    property bool lyricsOn: true
    FileView { path: Quickshell.env("HOME") + "/.config/sakura/lyrics.json"; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { db.lyricsOn = JSON.parse(text()).enabled !== false; } catch (e) {} } }

    // shared "repeat track" flag (Repeat.qml does the looping for players that can't)
    property bool fakeRepeat: false
    FileView { path: Quickshell.env("HOME") + "/.cache/sakura-repeat"; watchChanges: true; onFileChanged: reload()
        onLoaded: db.fakeRepeat = text().trim() === "1"; onLoadFailed: db.fakeRepeat = false }
    function toggleRepeat(p) {
        if (p && p.loopSupported) p.loopState = p.loopState === MprisLoopState.None ? MprisLoopState.Track : MprisLoopState.None;
        else { db.fakeRepeat = !db.fakeRepeat; Quickshell.execDetached(["qs", "ipc", "call", "repeat", "toggle"]); }
    }
    function repeatLit(p) { return p !== null && (p.loopSupported ? p.loopState !== MprisLoopState.None : db.fakeRepeat); }
    property string tab: "dashboard"
    readonly property var tabIds: ["dashboard", "media", "performance", "weather", "timers"]
    readonly property int tabIndex: Math.max(0, tabIds.indexOf(tab))
    property var screen0: Quickshell.screens[0]
    // the bar can sit next to the dock (barpos.sh) - then open above it instead of under the top bar
    property bool barDown: false
    FileView { path: Quickshell.env("HOME") + "/.config/sakura/barpos"; watchChanges: true; onFileChanged: reload()
        onLoaded: db.barDown = text().trim() === "bottom"; onLoadFailed: db.barDown = false }
    readonly property bool atBottom: barDown && !!screen0 && screen0.name === Cfg.mainName
    // with the bar at the top, the dashboard IS the top bar morphed: it takes the bar's shape over (TopBar.drawShape)
    // and turns it into its own box hanging from the top edge - and back into the collapsed bar when it closes.
    // Meanwhile TopBar hides itself on this screen (covering), so only one shape is ever on screen.
    property var topBar: null
    readonly property int dropW: 920
    property var fromGeo: null                      // the bar's shape it starts from / ends in
    onShownChanged: if (topBar && !atBottom && screen0) fromGeo = shown ? topBar.geoFor(screen0.name) : topBar.restGeoFor(screen0.name)
    readonly property string covering: win.visible && !atBottom && screen0 ? screen0.name : ""

    function toggle() {
        if (!shown) {
            const m = Hyprland.focusedMonitor;
            const sc = m ? Quickshell.screens.find(s => s.name === m.name) : null;
            if (sc) screen0 = sc;
            calMonth = new Date(); now = new Date();
            perfProc.running = true;
            if (Date.now() - weatherAt > 15 * 60 * 1000) weatherFetch.running = true; else weatherRead.running = true;
        }
        shown = !shown;
    }
    IpcHandler {
        target: "dashboard"
        function toggle(): void { db.toggle(); }
        function open(tab: string): void { if (tab !== "") db.tab = tab; if (!db.shown) db.toggle(); }
    }

    // ── time / calendar ─────────────────────────────────────
    property var now: new Date()
    Timer { interval: 1000; running: db.shown; repeat: true; onTriggered: db.now = new Date() }
    property var calMonth: new Date()
    readonly property var monthNames: ["January","February","March","April","May","June","July","August","September","October","November","December"]
    function calDays() {
        const y = calMonth.getFullYear(), m = calMonth.getMonth();
        const first = new Date(y, m, 1);
        const shift = (first.getDay() + 6) % 7;                 // Monday first
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(y, m, 1 - shift + i);
            out.push({ day: d.getDate(), inMonth: d.getMonth() === m,
                       today: d.toDateString() === new Date().toDateString() });
        }
        return out;
    }
    function pad(n) { return String(n).padStart(2, "0"); }

    // ── system stats ────────────────────────────────────────
    property var perf: ({ cpu: 0, cpuName: "", cpuTemp: null, memUsed: 0, memTotal: 1, gpu: null, disks: [], down: 0, up: 0, rxTotal: 0, txTotal: 0, uptime: 0 })
    Process {
        id: perfProc
        command: [db.scripts + "/perf.sh"]
        stdout: StdioCollector { onStreamFinished: { try { db.perf = JSON.parse(this.text); } catch (e) {} } }
    }
    Timer { interval: 1500; running: db.shown; repeat: true; onTriggered: perfProc.running = true }
    function gb(b) { return (b / 1073741824).toFixed(1); }
    function rate(b) { return b > 1048576 ? (b / 1048576).toFixed(1) + " MB/s" : (b / 1024).toFixed(0) + " KB/s"; }
    function bytes(b) { return b > 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : (b / 1048576).toFixed(0) + " MB"; }
    function upText(s) { const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return (h > 0 ? h + " h " : "") + m + " min"; }

    // ── weather ─────────────────────────────────────────────
    property var weather: null
    property real weatherAt: 0
    Process { id: weatherFetch; command: [db.scripts + "/weather.sh"]; onExited: weatherRead.running = true }
    Process {
        id: weatherRead
        command: ["cat", db.home + "/.cache/sakura-weather.json"]
        stdout: StdioCollector { onStreamFinished: { try { db.weather = JSON.parse(this.text); db.weatherAt = Date.now(); } catch (e) {} } }
    }
    Timer { interval: 15 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: weatherFetch.running = true }
    function wIcon(code, day) {
        const cp = code === 0 ? (day === 0 ? 0xf0594 : 0xf0599)
                 : code <= 2 ? (day === 0 ? 0xf0f31 : 0xf0595)
                 : code === 3 ? 0xf0590
                 : code <= 48 ? 0xf0591
                 : code <= 67 ? (code >= 63 ? 0xf0596 : 0xf0597)
                 : code <= 77 ? 0xf0598
                 : code <= 82 ? 0xf0596
                 : code <= 86 ? 0xf0598 : 0xf0593;
        return String.fromCodePoint(cp);
    }
    function wText(code) { return Cfg.wText(code); }
    readonly property var cur: weather ? weather.current : null

    // ── media ───────────────────────────────────────────────
    readonly property var players: Players.list
    readonly property var player: Players.player     // the last one that made sound (Players.qml)
    readonly property int pick: players.indexOf(player)
    Timer { interval: 500; running: db.shown && db.player !== null; repeat: true; onTriggered: if (db.player) db.player.positionChanged() }
    // player volume. Native players: their own MPRIS Volume (two-way). Browsers' built-in MPRIS ignores Volume
    // writes, so for them the slider drives the browser's playing PipeWire stream(s) - Chromium opens one per
    // playing tab - and WirePlumber doesn't remember browser volumes (wireplumber.conf.d/90-sakura-browsers.conf),
    // so other tabs / later playback start at 100%. The last value is re-applied when the player opens a new stream.
    readonly property bool isBrowser: player !== null && /mediaplayer2\.(chromium|chrome|brave|vivaldi|opera|edge|yandex|thorium|firefox|librewolf|zen|floorp|waterfox)/.test(String(player.dbusName || "").toLowerCase())
    readonly property bool mprisVol: player !== null && !isBrowser && player.volumeSupported && player.canControl
    readonly property var audioStreams: Pipewire.nodes.values.filter(n => n.audio && n.isStream)
    PwObjectTracker { objects: db.audioStreams }
    function normKey(s) { return String(s || "").toLowerCase().replace(/\.(bin|exe)$/, "").replace(/[^a-z0-9]/g, ""); }
    readonly property var volNodes: {
        const p = player; if (!p || !isBrowser) return [];
        const bus = String(p.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "");
        const keys = [p.identity, p.desktopEntry, bus.split(".")[0]].map(normKey).filter(k => k.length >= 3);
        return audioStreams.filter(n => {
            const q = n.properties || {};
            if ((q["media.class"] || "") !== "Stream/Output/Audio") return false;
            const nk = [q["application.name"], q["application.process.binary"], q["node.name"]].map(normKey).filter(k => k.length >= 3);
            return nk.some(a => keys.some(b => a === b || a.indexOf(b) >= 0 || b.indexOf(a) >= 0));
        });
    }
    readonly property bool volOk: mprisVol || volNodes.length > 0
    readonly property real playerVol: mprisVol ? player.volume : (volNodes.length > 0 && volNodes[0].audio ? volNodes[0].audio.volume : 0)
    property var volMem: ({})          // browser identity -> last slider value
    property var volSeen: ({})         // stream ids that already got it
    function setPlayerVol(v) {
        v = Math.round(Math.max(0, Math.min(1, v)) * 100) / 100;
        if (mprisVol) { player.volume = v; return; }
        if (volNodes.length === 0) return;
        const m = volMem; m[player.identity || "browser"] = v; volMem = m;
        volNodes.forEach(n => { if (n.audio) { n.audio.volume = v; if (n.audio.muted) n.audio.muted = false; } });
    }
    onVolNodesChanged: volApply.restart()
    Timer {
        id: volApply; interval: 300
        onTriggered: {
            if (!db.player) return;
            const v = db.volMem[db.player.identity || "browser"], seen = db.volSeen;
            db.volNodes.forEach(n => { if (!seen[n.id] && n.audio) { seen[n.id] = true; if (v !== undefined) n.audio.volume = v; } });
            db.volSeen = seen;
        }
    }
    function fmt(s) { if (!s || !isFinite(s) || s < 0) return "0:00"; s = Math.floor(s); return Math.floor(s / 60) + ":" + db.pad(s % 60); }

    // audio visualizer (cava)
    property var bars: []
    Process {
        id: cava
        running: db.shown && (db.tab === "media" || db.tab === "dashboard") && db.player !== null && db.player.isPlaying
        command: ["cava", "-p", db.home + "/.config/sakura/cava.conf"]
        stdout: SplitParser { onRead: line => { db.bars = line.split(";").filter(x => x !== "").map(Number); } }
        onRunningChanged: if (!running) db.bars = []
    }
    // Desk.qml rewrites cava.conf with the player's stream as the source - pick it up
    readonly property string vizSrc: Players.stream
    onVizSrcChanged: if (cava.running) { cava.running = false; cavaBack.restart(); }
    Timer { id: cavaBack; interval: 900; onTriggered: cava.running = Qt.binding(() => db.shown && (db.tab === "media" || db.tab === "dashboard") && db.player !== null && db.player.isPlaying) }

    // synced lyrics (lrclib.net)
    property var lyrics: []
    property string lyricsKey: ""
    property string lyricsState: ""
    readonly property string trackKey: player ? (player.trackArtist + "|" + player.trackTitle) : ""
    // fetch on every track change (even while the dashboard is closed), so lyrics are always ready
    onTrackKeyChanged: lyricsDelay.restart()
    Timer { id: lyricsDelay; interval: 400; onTriggered: db.fetchLyrics() }   // title/artist arrive a moment apart
    onTabChanged: if (tab === "media") fetchLyrics()
    function fetchLyrics() {
        if (!player || trackKey === lyricsKey) return;
        lyricsKey = trackKey; lyrics = []; lyricsState = "Loading lyrics…";
        const q = "artist_name=" + encodeURIComponent(player.trackArtist || "") + "&track_name=" + encodeURIComponent(player.trackTitle || "");
        lyricsProc.command = ["curl", "-s", "--max-time", "6", "-A", "sakura-dashboard", "https://lrclib.net/api/get?" + q];
        lyricsProc.running = false;   // cancel a request for the previous track
        lyricsProc.running = true;
    }
    Process {
        id: lyricsProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null; try { d = JSON.parse(this.text); } catch (e) {}
                const raw = d && d.syncedLyrics ? d.syncedLyrics : "";
                const out = [];
                raw.split("\n").forEach(l => {
                    const m = l.match(/^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$/);
                    if (m) out.push({ t: parseInt(m[1]) * 60 + parseFloat(m[2]), text: m[3] || "♪" });
                });
                db.lyrics = out;
                db.lyricsState = out.length ? "" : (d && d.plainLyrics ? "Only unsynced lyrics found" : "No lyrics found");
            }
        }
    }
    readonly property int lyricIdx: {
        if (!player || lyrics.length === 0) return -1;
        const p = player.position; let i = -1;
        for (let k = 0; k < lyrics.length; k++) { if (lyrics[k].t <= p + 0.25) i = k; else break; }
        return i;
    }

    // ── reusable bits ───────────────────────────────────────
    component Card: Rectangle { radius: 22; color: db.cCard; border.width: 1; border.color: db.cBorder }
    component Ring: Item {
        id: ring
        property real value: 0          // 0..100
        property string icon: ""
        property string label: ""
        property int size: 72
        width: size; height: size
        onValueChanged: cv.requestPaint()
        Canvas {
            id: cv
            anchors.fill: parent
            onPaint: {
                const c = getContext("2d"); c.reset();
                const r = width / 2 - 5, cx = width / 2, cy = height / 2, a0 = Math.PI * 0.75, sweep = Math.PI * 1.5;
                c.lineWidth = 6; c.lineCap = "round";
                c.strokeStyle = "#2a2e40"; c.beginPath(); c.arc(cx, cy, r, a0, a0 + sweep); c.stroke();
                c.strokeStyle = String(Cfg.accent); c.beginPath(); c.arc(cx, cy, r, a0, a0 + sweep * Math.max(0.001, Math.min(1, ring.value / 100))); c.stroke();
            }
        }
        Column {
            anchors.centerIn: parent
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: ring.icon; font.family: db.fIcon; font.pixelSize: ring.size * 0.2; color: db.cAccent }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(ring.value) + "%"; font.family: db.fUi; font.pixelSize: ring.size * 0.17; font.weight: Font.Bold; color: db.cFg }
        }
    }
    component Bar: Item {
        id: bar
        property real value: 0          // 0..1
        height: 6
        Rectangle { anchors.fill: parent; radius: 3; color: "#2a2e40" }
        Rectangle { width: parent.width * Math.max(0, Math.min(1, bar.value)); height: parent.height; radius: 3; color: db.cAccent
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } }
    }
    component CtlBtn: Rectangle {
        id: cb
        property string icon: ""
        property bool big: false
        property bool lit: false
        signal clicked()
        width: big ? 54 : 40; height: big ? 40 : 40; radius: 14
        color: big ? db.cAccent : (ma.containsMouse ? db.cCard2 : "transparent")
        scale: ma.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text { anchors.centerIn: parent; text: cb.icon; font.family: db.fIcon; font.pixelSize: cb.big ? 16 : 14
            color: cb.big ? db.cAccFg : (cb.lit ? db.cAccent : db.cFg) }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cb.clicked() }
    }
    // round cover with a live visualizer ring around it; spins like a record while playing
    component Disc: Item {
        id: disc
        property int size: 200
        width: size; height: size
        Repeater {
            model: 48
            delegate: Item {
                required property int index
                anchors.centerIn: parent
                width: 1; height: 1
                rotation: index * 360 / 48
                Rectangle {
                    readonly property real v: db.bars.length > disc.barIndex(index) ? db.bars[disc.barIndex(index)] : 0
                    x: -2; y: -disc.size / 2 + 2
                    width: 4; radius: 2
                    height: 4 + v * disc.size * 0.0011 * 10
                    color: db.cAccent; opacity: 0.35 + Math.min(0.65, v / 100)
                    Behavior on height { NumberAnimation { duration: 60 } }
                }
            }
        }
        function barIndex(i) { return i < 24 ? i : 47 - i; }     // mirrored, low notes at the top
        ClippingRectangle {
            id: cov
            anchors.centerIn: parent
            width: disc.size * 0.72; height: width; radius: width / 2
            color: db.cCard2
            Image { anchors.fill: parent; source: db.player ? (db.player.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            Text { anchors.centerIn: parent; visible: !db.player || !db.player.trackArtUrl; text: ""; font.family: db.fIcon; font.pixelSize: disc.size * 0.18; color: db.cAccent }
            RotationAnimation on rotation { running: db.shown && db.player !== null && db.player.isPlaying; from: 0; to: 360; duration: 24000; loops: Animation.Infinite }
        }
        Rectangle { anchors.centerIn: parent; width: disc.size * 0.08; height: width; radius: width / 2; color: db.cBg; border.width: 2; border.color: db.cAccDim }
    }

    // ── window ──────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: db.shown || grow > 0.001          // stays up while it morphs back into the bar
        screen: db.screen0
        anchors { top: !db.atBottom; bottom: db.atBottom; left: true; right: true }    // the bar's shape is wider than the box
        margins.bottom: 76
        implicitHeight: 480
        mask: Region { item: panel }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dashboard"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        HyprlandFocusGrab { windows: [ win ]; active: db.shown; onCleared: db.shown = false }

        // 0 = the bar's shape, 1 = the whole menu; the content fades in at the end (and out first on close)
        property real grow: db.shown ? 1 : 0
        Behavior on grow { NumberAnimation { duration: 380 * Cfg.anim; easing.type: Easing.OutCubic } }

        Canvas {
            anchors.fill: parent
            readonly property string key: [win.grow, width, height, db.fromGeo ? db.fromGeo.xl : 0, Cfg.glass].join(",")
            onKeyChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                if (!db.atBottom && db.topBar && db.fromGeo) {
                    const box = { xl: panel.x, xr: panel.x + panel.width, x0: db.fromGeo.x0, x1: db.fromGeo.x1, wh: height, d: height, r: 28 };
                    db.topBar.drawShape(ctx, db.topBar.lerpGeo(db.fromGeo, box, win.grow));
                } else {      // above the dock (bar at the bottom): a rounded card growing up from the bottom
                    const h = 40 + (height - 40) * win.grow;
                    ctx.beginPath();
                    ctx.roundedRect(panel.x, height - h, panel.width, h, 28, 28);
                    ctx.fillStyle = db.cBg;
                    ctx.fill();
                }
            }
        }

        Rectangle {
            id: panel
            anchors { top: parent.top; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
            width: db.dropW
            radius: 28
            color: "transparent"
            opacity: Math.max(0, (win.grow - 0.55) / 0.45)
            focus: db.shown
            Keys.onEscapePressed: db.shown = false

            // tabs: one pink pill slides under the selected tab
            Item {
                id: tabs
                anchors { top: parent.top; topMargin: 14; horizontalCenter: parent.horizontalCenter }
                width: tabRow.implicitWidth; height: 38
                Rectangle {
                    id: hilite
                    readonly property var it: tabRep.count > db.tabIndex ? tabRep.itemAt(db.tabIndex) : null
                    x: it ? it.x : 0; width: it ? it.width : 0; height: parent.height; radius: 13
                    color: db.cAccent
                    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                }
                Row {
                    id: tabRow
                    spacing: 6
                    Repeater {
                        id: tabRep
                        model: [ { id: "dashboard",   cp: 0xf056e, t: "Dashboard" },
                                 { id: "media",       cp: 0xf075a, t: "Media" },
                                 { id: "performance", cp: 0xf04c5, t: "Performance" },
                                 { id: "weather",     cp: 0xf0595, t: "Weather" },
                                 { id: "timers",      cp: 0xf051b, t: Cfg.tr("Timers") } ]
                        delegate: Item {
                            required property var modelData
                            readonly property bool sel: db.tab === modelData.id
                            width: tr.implicitWidth + 32; height: 38
                            Rectangle { anchors.fill: parent; radius: 13; color: db.cCard2; opacity: tma.containsMouse && !parent.sel ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } } }
                            Row { id: tr; anchors.centerIn: parent; spacing: 8
                                Text { text: String.fromCodePoint(modelData.cp); font.family: db.fIcon; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter
                                    color: sel ? db.cAccFg : db.cAccent; Behavior on color { ColorAnimation { duration: 220 } }
                                    scale: sel ? 1.12 : 1; Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } } }
                                Text { text: modelData.t; font.family: db.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter
                                    color: sel ? db.cAccFg : db.cFg; Behavior on color { ColorAnimation { duration: 220 } } } }
                            MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: db.tab = modelData.id }
                        }
                    }
                }
            }

            Item {
                id: body
                anchors { top: tabs.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }

                // ═══════════════ DASHBOARD ═══════════════
                Item {
                    anchors.fill: parent
                    // slides in from the side you are moving to, and fades
                    opacity: db.tab === "dashboard" ? 1 : 0
                    visible: opacity > 0.01
                    enabled: db.tab === "dashboard"
                    transform: Translate { x: (0 - db.tabIndex) * 46; Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                    // banner: the current wallpaper (picture or a playing video) with the time, weather and user on top
                    ClippingRectangle {
                        id: banner
                        x: 0; y: 0; width: 608; height: 120; radius: 22; color: db.cCard
                        border.width: 1; border.color: db.cBorder
                        WallThumb { anchors.fill: parent; file: Cfg.data.wallpaper || ""; size: 640; live: db.shown && db.tab === "dashboard" }
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#b30f1119" }
                                GradientStop { position: 0.55; color: "#330f1119" }
                                GradientStop { position: 1.0; color: "#990f1119" }
                            }
                        }
                        Column {
                            anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                            spacing: 0
                            Text { text: Cfg.timeStr(db.now, false); font.family: db.fUi; font.pixelSize: 44; font.weight: Font.ExtraBold; color: "#ffffff"
                                   style: Text.Raised; styleColor: "#40000000" }
                            Text { text: Cfg.dateLong(db.now); font.family: db.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: "#e6ffffff" }
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                            spacing: 16
                            Item {
                                width: wcol.implicitWidth; height: wcol.implicitHeight; anchors.verticalCenter: parent.verticalCenter
                                Column {
                                    id: wcol; spacing: 1
                                    Row { anchors.right: parent.right; spacing: 8
                                        Text { text: db.cur ? db.wIcon(db.cur.weather_code, db.cur.is_day) : ""; font.family: db.fIcon; font.pixelSize: 22; color: db.cAccent; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: db.cur ? Math.round(db.cur.temperature_2m) + "°C" : "--"; font.family: db.fUi; font.pixelSize: 22; font.weight: Font.Bold; color: "#ffffff" } }
                                    Text { anchors.right: parent.right; text: db.cur ? db.wText(db.cur.weather_code) : Cfg.tr("loading…"); font.family: db.fUi; font.pixelSize: 11; color: "#d9ffffff" }
                                    Text { anchors.right: parent.right; text: db.weather ? db.weather.city : ""; font.family: db.fUi; font.pixelSize: 11; color: db.cAccent }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: db.tab = "weather" }
                            }
                            ClippingRectangle { width: 64; height: 64; radius: 32; color: db.cAccent; anchors.verticalCenter: parent.verticalCenter
                                Avatar { anchors.fill: parent; ring: 3; ringColor: "transparent" } }
                        }
                        // uptime pill under the avatar side
                        Rectangle {
                            anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                            width: upT.implicitWidth + 14; height: 18; radius: 9; color: Cfg.glass
                            Text { id: upT; anchors.centerIn: parent; text: Quickshell.env("USER") + " · up " + db.upText(db.perf.uptime); font.family: db.fUi; font.pixelSize: 10; color: "#d9ffffff" }
                        }
                    }
                    // big clock
                    Card {
                        x: 0; y: 132; width: 110; height: parent.height - 132
                        Column { anchors.centerIn: parent; spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: db.pad(db.now.getHours()); font.family: db.fUi; font.pixelSize: 40; font.weight: Font.ExtraBold; color: db.cFg }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "• • •"; font.pixelSize: 12; color: db.cAccent }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: db.pad(db.now.getMinutes()); font.family: db.fUi; font.pixelSize: 40; font.weight: Font.ExtraBold; color: db.cFg } }
                    }
                    // calendar
                    Card {
                        id: cal
                        x: 122; y: 132; width: 360; height: parent.height - 132
                        Row {
                            id: calHead
                            anchors { top: parent.top; topMargin: 12; horizontalCenter: parent.horizontalCenter }
                            spacing: 18
                            Text { text: ""; font.family: db.fIcon; font.pixelSize: 12; color: db.cMuted; anchors.verticalCenter: parent.verticalCenter
                                MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                                    onClicked: db.calMonth = new Date(db.calMonth.getFullYear(), db.calMonth.getMonth() - 1, 1) } }
                            Text { width: 150; horizontalAlignment: Text.AlignHCenter; text: db.monthNames[db.calMonth.getMonth()] + " " + db.calMonth.getFullYear()
                                font.family: db.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: db.cFg
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: db.calMonth = new Date() } }
                            Text { text: ""; font.family: db.fIcon; font.pixelSize: 12; color: db.cMuted; anchors.verticalCenter: parent.verticalCenter
                                MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                                    onClicked: db.calMonth = new Date(db.calMonth.getFullYear(), db.calMonth.getMonth() + 1, 1) } }
                        }
                        Grid {
                            anchors { top: calHead.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
                            columns: 7; columnSpacing: 4; rowSpacing: 1
                            Repeater { model: ["Mo","Tu","We","Th","Fr","Sa","Su"]
                                delegate: Text { required property string modelData; width: 42; height: 20; horizontalAlignment: Text.AlignHCenter
                                    text: modelData; font.family: db.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: db.cMuted } }
                            Repeater { model: db.calDays()
                                delegate: Rectangle { required property var modelData
                                    width: 42; height: 26; radius: 9
                                    color: modelData.today ? db.cAccent : "transparent"
                                    Text { anchors.centerIn: parent; text: modelData.day; font.family: db.fUi; font.pixelSize: 12
                                        font.weight: modelData.today ? Font.Bold : Font.Normal
                                        color: modelData.today ? db.cAccFg : (modelData.inMonth ? db.cFg : "#4a4f63") } } }
                        }
                    }
                    // rings
                    Card {
                        x: 494; y: 132; width: 114; height: parent.height - 132
                        Column { anchors.centerIn: parent; spacing: 4
                            Ring { size: 70; value: db.perf.cpu; icon: ""; anchors.horizontalCenter: parent.horizontalCenter }
                            Ring { size: 70; value: db.perf.memTotal ? 100 * db.perf.memUsed / db.perf.memTotal : 0; icon: ""; anchors.horizontalCenter: parent.horizontalCenter }
                            Ring { size: 70; value: db.perf.gpu ? db.perf.gpu.usage : 0; icon: String.fromCodePoint(0xf0379); anchors.horizontalCenter: parent.horizontalCenter } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: db.tab = "performance" }
                    }
                    // mini media
                    Card {
                        x: 620; y: 0; width: parent.width - 620; height: parent.height
                        Column {
                            anchors.centerIn: parent; spacing: 10; width: parent.width - 30
                            Disc { size: 150; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                text: db.player ? (db.player.trackTitle || "Unknown") : "Nothing playing"; font.family: db.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: db.cFg }
                            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                text: db.player ? (db.player.trackArtist || "") : ""; font.family: db.fUi; font.pixelSize: 12; color: db.cAccent }
                            Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 8; visible: db.player !== null
                                CtlBtn { icon: ""; onClicked: db.player.previous() }
                                CtlBtn { big: true; icon: db.player && db.player.isPlaying ? "" : ""; onClicked: db.player.togglePlaying() }
                                CtlBtn { icon: ""; onClicked: db.player.next() } }
                        }
                    }
                }

                // ═══════════════ MEDIA ═══════════════
                // same grid as Weather: a 300px card on the left, a column of cards on the right, 12px gutters
                Item {
                    id: mPage
                    anchors.fill: parent
                    // slides in from the side you are moving to, and fades
                    opacity: db.tab === "media" ? 1 : 0
                    visible: opacity > 0.01
                    enabled: db.tab === "media"
                    transform: Translate { x: (1 - db.tabIndex) * 46; Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    readonly property bool hasLyrics: db.lyrics.length > 0
                    readonly property var pl: db.player

                    // cover: the spinning disc with the visualizer ring, inside its own card
                    Card {
                        id: mCover
                        x: 0; y: 0; width: 300; height: parent.height
                        Disc { size: 264; anchors.centerIn: parent }
                    }

                    // now playing
                    Card {
                        id: mNow
                        x: 312; y: 0; width: parent.width - 312; height: parent.height - 12 - mLy.height

                        // header: source app (and the switcher when there are several players)
                        Row { x: 18; y: 16; spacing: 8; height: 22
                            Text { text: ""; font.family: db.fIcon; font.pixelSize: 13; color: db.cAccent; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: mPage.pl ? (mPage.pl.identity || Cfg.tr("Player")) : Cfg.tr("Now playing"); font.family: db.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: db.cFg
                                   anchors.verticalCenter: parent.verticalCenter; visible: db.players.length <= 1 } }
                        Row { x: 46; y: 16; spacing: 6; visible: db.players.length > 1
                            Repeater { model: db.players
                                delegate: Rectangle { required property var modelData; required property int index
                                    width: pt.implicitWidth + 18; height: 22; radius: 8
                                    color: index === db.pick ? db.cAccent : (pma.containsMouse ? db.cCard2 : "#14ffffff")
                                    Text { id: pt; anchors.centerIn: parent; text: modelData.identity || Cfg.tr("Player"); font.family: db.fUi; font.pixelSize: 11; font.weight: Font.DemiBold
                                        color: index === db.pick ? db.cAccFg : db.cFg }
                                    MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { Players.choose(modelData); db.lyricsKey = ""; db.fetchLyrics(); } } } } }

                        // track
                        Column {
                            id: mTrack
                            x: 18; y: 48; width: parent.width - 36; spacing: 2
                            Text { width: parent.width; elide: Text.ElideRight; text: mPage.pl ? (mPage.pl.trackTitle || Cfg.tr("Unknown")) : Cfg.tr("Nothing playing")
                                font.family: db.fUi; font.pixelSize: 22; font.weight: Font.ExtraBold; color: db.cFg }
                            Text { width: parent.width; elide: Text.ElideRight; visible: text !== ""
                                text: mPage.pl ? [mPage.pl.trackArtist, mPage.pl.trackAlbum].filter(s => s).join("  ·  ") : ""
                                font.family: db.fUi; font.pixelSize: 13; color: db.cAccent }
                        }

                        // spectrum: fills the card when there are no lyrics below it
                        Row {
                            id: mSpec
                            x: 18; width: parent.width - 36
                            anchors { top: mTrack.bottom; topMargin: 16; bottom: mProg.top; bottomMargin: 16 }
                            spacing: 3
                            visible: height > 36
                            opacity: height > 60 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Repeater { model: 48
                                delegate: Item { required property int index
                                    width: (mSpec.width - 47 * mSpec.spacing) / 48; height: mSpec.height
                                    readonly property real v: db.bars.length > index ? db.bars[index] : 0
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; radius: width / 2
                                        height: Math.max(width, parent.height * Math.min(1, parent.v / 100))
                                        color: db.cAccent; opacity: 0.35 + Math.min(0.65, parent.v / 100)
                                        Behavior on height { NumberAnimation { duration: 60 } } } } }
                        }

                        // progress (click or drag to seek)
                        Item {
                            id: mProg
                            x: 18; width: parent.width - 36; height: 18
                            anchors { bottom: mCtl.top; bottomMargin: 10 }
                            readonly property real len: mPage.pl ? mPage.pl.length : 0
                            readonly property real pos: mPage.pl ? mPage.pl.position : 0
                            Text { id: mp1; anchors { left: parent.left; verticalCenter: parent.verticalCenter } width: 36
                                text: db.fmt(mProg.pos); font.family: db.fUi; font.pixelSize: 11; color: db.cMuted }
                            Text { id: mp2; anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: 36; horizontalAlignment: Text.AlignRight
                                text: db.fmt(mProg.len); font.family: db.fUi; font.pixelSize: 11; color: db.cMuted }
                            Bar { anchors { left: mp1.right; right: mp2.left; leftMargin: 6; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                value: mProg.len > 0 ? mProg.pos / mProg.len : 0
                                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                    enabled: mPage.pl !== null && mPage.pl.canSeek && mProg.len > 0
                                    function seek(x) { mPage.pl.position = mProg.len * Math.max(0, Math.min(1, (x - 6) / (width - 12))); }
                                    onPressed: m => seek(m.x); onPositionChanged: m => { if (pressed) seek(m.x); } } }
                        }

                        // controls: lyrics overlay · shuffle prev play next repeat · volume
                        Item {
                            id: mCtl
                            x: 12; width: parent.width - 24; height: 40
                            anchors { bottom: parent.bottom; bottomMargin: 14 }
                            visible: mPage.pl !== null
                            CtlBtn { anchors.left: parent.left; icon: ""; lit: db.lyricsOn
                                onClicked: { db.lyricsOn = !db.lyricsOn; Quickshell.execDetached(["qs", "ipc", "call", "lyrics", "toggle"]); } }
                            Row { anchors.centerIn: parent; spacing: 8
                                CtlBtn { icon: ""; lit: mPage.pl && mPage.pl.shuffle; opacity: mPage.pl && mPage.pl.shuffleSupported ? 1 : 0.35
                                    onClicked: if (mPage.pl.shuffleSupported) mPage.pl.shuffle = !mPage.pl.shuffle }
                                CtlBtn { icon: "\uf048"; onClicked: mPage.pl.previous() }
                                CtlBtn { big: true; icon: mPage.pl && mPage.pl.isPlaying ? "\uf04c" : "\uf04b"; onClicked: mPage.pl.togglePlaying() }
                                CtlBtn { icon: "\uf051"; onClicked: mPage.pl.next() }
                                CtlBtn { icon: "\uf01e"; lit: db.repeatLit(mPage.pl); onClicked: db.toggleRepeat(mPage.pl) } }
                            // volume: click / drag / wheel
                            Row { anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter } spacing: 8
                                opacity: db.volOk ? 1 : 0.35
                                readonly property real vol: db.playerVol
                                Text { anchors.verticalCenter: parent.verticalCenter; font.family: db.fIcon; font.pixelSize: 14; color: db.cMuted; width: 16
                                    text: parent.vol <= 0.001 ? "" : parent.vol < 0.5 ? "" : "" }
                                Bar { id: mVol; width: 84; anchors.verticalCenter: parent.verticalCenter; value: parent.vol
                                    MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                                        enabled: db.volOk
                                        function set(x) { db.setPlayerVol((x - 8) / (width - 16)); }
                                        onPressed: m => set(m.x); onPositionChanged: m => { if (pressed) set(m.x); }
                                        onWheel: w => db.setPlayerVol(db.playerVol + (w.angleDelta.y > 0 ? 0.05 : -0.05)) } } }
                        }
                    }

                    // lyrics: a full card while synced lyrics exist, otherwise one slim row
                    Card {
                        id: mLy
                        x: 312; width: parent.width - 312
                        anchors.bottom: parent.bottom
                        height: mPage.hasLyrics ? 182 : 50
                        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        clip: true
                        Row { x: 18; y: 16; spacing: 8
                            Text { text: "\uf130"; font.family: db.fIcon; font.pixelSize: 13; color: db.cAccent; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: Cfg.tr("Lyrics"); font.family: db.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: db.cFg; anchors.verticalCenter: parent.verticalCenter } }
                        Text { anchors { right: parent.right; rightMargin: 18 } y: 17
                            visible: !mPage.hasLyrics; text: db.player ? Cfg.tr(db.lyricsState || "No lyrics found") : ""
                            font.family: db.fUi; font.pixelSize: 12; color: db.cMuted }
                        ListView {
                            id: lyList
                            x: 18; width: parent.width - 36
                            anchors { top: parent.top; topMargin: 44; bottom: parent.bottom; bottomMargin: 12 }
                            clip: true; interactive: false
                            opacity: mPage.hasLyrics ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            model: db.lyrics
                            currentIndex: Math.max(0, db.lyricIdx)
                            highlightRangeMode: ListView.ApplyRange
                            preferredHighlightBegin: height / 2 - 14; preferredHighlightEnd: height / 2 + 14
                            highlightMoveDuration: 350
                            delegate: Text {
                                required property var modelData
                                required property int index
                                width: lyList.width; wrapMode: Text.WordWrap; topPadding: 3; bottomPadding: 3
                                text: modelData.text
                                font.family: db.fUi; font.pixelSize: index === db.lyricIdx ? 15 : 13
                                font.weight: index === db.lyricIdx ? Font.Bold : Font.Normal
                                color: index === db.lyricIdx ? db.cAccent : (index < db.lyricIdx ? "#555a6e" : db.cMuted)
                                Behavior on color { ColorAnimation { duration: 250 } }
                            }
                        }
                    }
                }

                // ═══════════════ PERFORMANCE ═══════════════
                Item {
                    anchors.fill: parent
                    // slides in from the side you are moving to, and fades
                    opacity: db.tab === "performance" ? 1 : 0
                    visible: opacity > 0.01
                    enabled: db.tab === "performance"
                    transform: Translate { x: (2 - db.tabIndex) * 46; Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                    Card {
                        x: 0; y: 0; width: (parent.width - 12) / 2; height: 150
                        Column { anchors { fill: parent; margins: 18 } spacing: 6
                            Row { spacing: 10
                                Text { text: ""; font.family: db.fIcon; font.pixelSize: 18; color: db.cAccent }
                                Text { text: "CPU"; font.family: db.fUi; font.pixelSize: 16; font.weight: Font.Bold; color: db.cFg } }
                            Text { width: parent.width; elide: Text.ElideRight; text: db.perf.cpuName; font.family: db.fUi; font.pixelSize: 12; color: db.cMuted }
                            Item { width: 1; height: 8 }
                            Row { spacing: 22
                                Column { Text { text: Math.round(db.perf.cpu) + "%"; font.family: db.fUi; font.pixelSize: 28; font.weight: Font.ExtraBold; color: db.cFg }
                                         Text { text: "usage"; font.family: db.fUi; font.pixelSize: 11; color: db.cMuted } }
                                Column { Text { text: db.perf.cpuTemp !== null ? Math.round(db.perf.cpuTemp) + "°C" : "--"; font.family: db.fUi; font.pixelSize: 28; font.weight: Font.ExtraBold; color: db.cFg }
                                         Text { text: "temperature"; font.family: db.fUi; font.pixelSize: 11; color: db.cMuted } } }
                            Bar { width: parent.width; value: db.perf.cpu / 100 }
                        }
                    }
                    Card {
                        x: (parent.width + 12) / 2; y: 0; width: (parent.width - 12) / 2; height: 150
                        Column { anchors { fill: parent; margins: 18 } spacing: 6
                            Row { spacing: 10
                                Text { text: String.fromCodePoint(0xf0379); font.family: db.fIcon; font.pixelSize: 18; color: db.cAccent }
                                Text { text: "GPU"; font.family: db.fUi; font.pixelSize: 16; font.weight: Font.Bold; color: db.cFg } }
                            Text { width: parent.width; elide: Text.ElideRight; text: db.perf.gpu ? db.perf.gpu.name : (db.perf.gpuNote ? Cfg.tr(db.perf.gpuNote) : "-"); font.family: db.fUi; font.pixelSize: 12; color: db.cMuted }
                            Item { width: 1; height: 8 }
                            Row { spacing: 22
                                Column { Text { text: db.perf.gpu ? Math.round(db.perf.gpu.usage) + "%" : "--"; font.family: db.fUi; font.pixelSize: 28; font.weight: Font.ExtraBold; color: db.cFg }
                                         Text { text: "usage"; font.family: db.fUi; font.pixelSize: 11; color: db.cMuted } }
                                Column { Text { text: db.perf.gpu ? Math.round(db.perf.gpu.temp) + "°C" : "--"; font.family: db.fUi; font.pixelSize: 28; font.weight: Font.ExtraBold; color: db.cFg }
                                         Text { text: "temperature"; font.family: db.fUi; font.pixelSize: 11; color: db.cMuted } }
                                Column { Text { text: db.perf.gpu ? db.gb(db.perf.gpu.memUsed) + " / " + db.gb(db.perf.gpu.memTotal) : "--"; font.family: db.fUi; font.pixelSize: 18; font.weight: Font.Bold; color: db.cFg; topPadding: 8 }
                                         Text { text: "VRAM, GB"; font.family: db.fUi; font.pixelSize: 11; color: db.cMuted } } }
                            Bar { width: parent.width; value: db.perf.gpu ? db.perf.gpu.usage / 100 : 0 }
                        }
                    }
                    // storage
                    Card {
                        x: 0; y: 162; width: 330; height: parent.height - 162
                        Column { anchors { fill: parent; margins: 16 } spacing: 8
                            Row { spacing: 10
                                Text { text: ""; font.family: db.fIcon; font.pixelSize: 15; color: db.cAccent }
                                Text { text: "Storage"; font.family: db.fUi; font.pixelSize: 15; font.weight: Font.Bold; color: db.cFg } }
                            Repeater { model: db.perf.disks
                                delegate: Column { required property var modelData; width: parent.width; spacing: 4
                                    Item { width: parent.width; height: 16
                                        Text { text: modelData.label; font.family: db.fUi; font.pixelSize: 12; color: db.cFg }
                                        Text { anchors.right: parent.right; text: db.gb(modelData.used) + " / " + db.gb(modelData.total) + " GB"; font.family: db.fUi; font.pixelSize: 11; color: db.cMuted } }
                                    Bar { width: parent.width; height: 5; value: modelData.used / modelData.total } } }
                        }
                    }
                    // network
                    Card {
                        x: 342; y: 162; width: 260; height: parent.height - 162
                        Column { anchors { fill: parent; margins: 16 } spacing: 12
                            Row { spacing: 10
                                Text { text: ""; font.family: db.fIcon; font.pixelSize: 15; color: db.cAccent }
                                Text { text: "Network"; font.family: db.fUi; font.pixelSize: 15; font.weight: Font.Bold; color: db.cFg } }
                            Repeater { model: [ { i: "", t: "Download", v: db.rate(db.perf.down) }, { i: "", t: "Upload", v: db.rate(db.perf.up) },
                                                { i: "", t: "Total", v: "↓" + db.bytes(db.perf.rxTotal) + "  ↑" + db.bytes(db.perf.txTotal) } ]
                                delegate: Item { required property var modelData; width: parent.width; height: 20
                                    Row { spacing: 8
                                        Text { text: modelData.i; font.family: db.fIcon; font.pixelSize: 12; color: db.cAccent }
                                        Text { text: modelData.t; font.family: db.fUi; font.pixelSize: 12; color: db.cMuted } }
                                    Text { anchors.right: parent.right; text: modelData.v; font.family: db.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: db.cFg } } }
                        }
                    }
                    // memory
                    Card {
                        x: 614; y: 162; width: parent.width - 614; height: parent.height - 162
                        Column { anchors.centerIn: parent; spacing: 6
                            Ring { size: 120; value: db.perf.memTotal ? 100 * db.perf.memUsed / db.perf.memTotal : 0; icon: ""; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Memory"; font.family: db.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: db.cFg }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: db.gb(db.perf.memUsed) + " / " + db.gb(db.perf.memTotal) + " GB"; font.family: db.fUi; font.pixelSize: 12; color: db.cMuted } }
                    }
                }

                // ═══════════════ WEATHER ═══════════════
                Item {
                    anchors.fill: parent
                    // slides in from the side you are moving to, and fades
                    opacity: db.tab === "weather" ? 1 : 0
                    visible: opacity > 0.01
                    enabled: db.tab === "weather"
                    transform: Translate { x: (3 - db.tabIndex) * 46; Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                    Card {
                        id: wNow
                        x: 0; y: 0; width: 300; height: parent.height
                        Column { anchors.centerIn: parent; spacing: 6
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: db.cur ? db.wIcon(db.cur.weather_code, db.cur.is_day) : ""
                                font.family: db.fIcon; font.pixelSize: 86; color: db.cAccent }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: db.cur ? Math.round(db.cur.temperature_2m) + "°C" : "--"
                                font.family: db.fUi; font.pixelSize: 46; font.weight: Font.ExtraBold; color: db.cFg }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: db.cur ? db.wText(db.cur.weather_code) : ""; font.family: db.fUi; font.pixelSize: 15; color: db.cFg }
                            Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 6; visible: db.weather !== null
                                Text { text: "\uf041"; font.family: db.fIcon; font.pixelSize: 12; color: db.cAccent; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: db.weather ? db.weather.city : ""; font.family: db.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: db.cAccent; anchors.verticalCenter: parent.verticalCenter } }
                            Item { width: 1; height: 10 }
                            Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 18
                                Repeater { model: db.cur ? [ { t: "Feels", v: Math.round(db.cur.apparent_temperature) + "°" },
                                                             { t: "Humidity", v: db.cur.relative_humidity_2m + "%" },
                                                             { t: "Wind", v: Math.round(db.cur.wind_speed_10m) + " km/h" } ] : []
                                    delegate: Column { required property var modelData
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.v; font.family: db.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: db.cFg }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.t; font.family: db.fUi; font.pixelSize: 11; color: db.cMuted } } } }
                        }
                    }
                    // hourly
                    Card {
                        id: wHours
                        x: 312; y: 0; width: parent.width - 312; height: 120
                        Row {
                            anchors.centerIn: parent; spacing: 4
                            Repeater {
                                model: {
                                    if (!db.weather) return [];
                                    const h = db.weather.hourly, nowH = new Date(); nowH.setMinutes(0, 0, 0);
                                    let i0 = h.time.findIndex(t => new Date(t) >= nowH); if (i0 < 0) i0 = 0;
                                    const out = [];
                                    for (let i = i0; i < Math.min(h.time.length, i0 + 10); i++)
                                        out.push({ t: i === i0 ? "Now" : new Date(h.time[i]).getHours() + ":00", c: h.weather_code[i], v: Math.round(h.temperature_2m[i]),
                                                   d: (new Date(h.time[i]).getHours() >= 7 && new Date(h.time[i]).getHours() < 19) ? 1 : 0 });
                                    return out;
                                }
                                delegate: Column { required property var modelData; width: 52; spacing: 4
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.t; font.family: db.fUi; font.pixelSize: 11; color: db.cMuted }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: db.wIcon(modelData.c, modelData.d); font.family: db.fIcon; font.pixelSize: 22; color: db.cAccent }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.v + "°"; font.family: db.fUi; font.pixelSize: 13; font.weight: Font.Bold; color: db.cFg } }
                            }
                        }
                    }
                    // 7 days
                    Card {
                        x: 312; y: 132; width: parent.width - 312; height: parent.height - 132
                        Column {
                            anchors { fill: parent; margins: 14 }
                            spacing: 2
                            Repeater {
                                model: db.weather ? db.weather.daily.time.length : 0
                                delegate: Item {
                                    required property int index
                                    readonly property var d: db.weather.daily
                                    width: parent.width; height: 27
                                    readonly property real lo: d.temperature_2m_min[index]
                                    readonly property real hi: d.temperature_2m_max[index]
                                    readonly property real wkLo: Math.min.apply(null, d.temperature_2m_min)
                                    readonly property real wkHi: Math.max.apply(null, d.temperature_2m_max)
                                    Text { width: 70; anchors.verticalCenter: parent.verticalCenter; font.family: db.fUi; font.pixelSize: 12; color: index === 0 ? db.cAccent : db.cFg
                                        text: index === 0 ? Cfg.tr("Today") : Cfg.dayShort(new Date(d.time[index] + "T12:00")) }
                                    Text { x: 74; anchors.verticalCenter: parent.verticalCenter; text: db.wIcon(d.weather_code[index], 1); font.family: db.fIcon; font.pixelSize: 15; color: db.cAccent }
                                    Text { x: 104; width: 36; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: Math.round(lo) + "°"; font.family: db.fUi; font.pixelSize: 12; color: db.cMuted }
                                    Item { x: 150; width: parent.width - 200; height: 5; anchors.verticalCenter: parent.verticalCenter
                                        Rectangle { anchors.fill: parent; radius: 3; color: "#2a2e40" }
                                        Rectangle { radius: 3; height: parent.height; color: db.cAccent
                                            x: parent.width * (lo - wkLo) / Math.max(1, wkHi - wkLo); width: Math.max(6, parent.width * (hi - lo) / Math.max(1, wkHi - wkLo)) } }
                                    Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: 36; horizontalAlignment: Text.AlignRight
                                        text: Math.round(hi) + "°"; font.family: db.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: db.cFg }
                                }
                            }
                        }
                    }
                }

                // ═══════════════ TIMERS ═══════════════
                Item {
                    id: tPage
                    anchors.fill: parent
                    opacity: db.tab === "timers" ? 1 : 0
                    visible: opacity > 0.01
                    enabled: db.tab === "timers"
                    transform: Translate { x: (4 - db.tabIndex) * 46; Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    readonly property real cw: (width - 24) / 3

                    component Chip: Rectangle {
                        id: ch
                        property string text: ""
                        property bool on: false
                        property bool primary: false
                        signal clicked()
                        width: Math.max(34, cht.implicitWidth + 18); height: 30; radius: 10
                        color: primary ? (cha.containsMouse ? "#ffffff" : db.cAccent) : on ? Cfg.acc(0.20) : (cha.containsMouse ? db.cCard2 : "#14ffffff")
                        border.width: on ? 1 : 0; border.color: db.cAccent
                        Text { id: cht; anchors.centerIn: parent; text: ch.text; font.family: ch.text.length === 1 && ch.text.charCodeAt(0) > 0xe000 ? db.fIcon : db.fUi
                               font.pixelSize: 12; font.weight: Font.DemiBold; color: ch.primary ? db.cAccFg : db.cFg }
                        MouseArea { id: cha; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
                    }
                    component Dial: Item {
                        id: dial
                        property real frac: 0
                        property string big: ""
                        property string small: ""
                        width: 156; height: 156
                        onFracChanged: dcv.requestPaint()
                        Canvas {
                            id: dcv; anchors.fill: parent
                            onPaint: {
                                const c = getContext("2d"); c.reset();
                                const r = width / 2 - 7, x = width / 2, y = height / 2;
                                c.lineWidth = 8; c.lineCap = "round";
                                c.strokeStyle = "#2a2e40"; c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.stroke();
                                if (dial.frac > 0.001) { c.strokeStyle = String(Cfg.accent); c.beginPath(); c.arc(x, y, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, dial.frac)); c.stroke(); }
                            }
                        }
                        Column { anchors.centerIn: parent; spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: dial.big; font.family: db.fUi; font.pixelSize: 30; font.weight: Font.Bold; color: db.cFg }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: dial.small; visible: text !== ""; font.family: db.fUi; font.pixelSize: 11; color: db.cMuted } }
                    }

                    // ── timer ── (both cards share one grid: title · dial · buttons · bottom area)
                    Card {
                        id: tCard
                        x: 0; width: tPage.cw; height: parent.height
                        Text { x: 18; y: 16; text: Cfg.tr("Timer"); font.family: db.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: db.cFg }
                        Dial {
                            y: 44; anchors.horizontalCenter: parent.horizontalCenter
                            frac: Timers.tTotal > 0 ? Timers.tRemain / Timers.tTotal : 0
                            big: Timers.fmt(Timers.tRemain)
                            small: Timers.tRunning ? Cfg.tr("running") : (Timers.tLeft > 0 && Timers.tLeft < Timers.tTotal ? Cfg.tr("paused") : "")
                            MouseArea { anchors.fill: parent; onWheel: w => Timers.tAdd(w.angleDelta.y > 0 ? 60000 : -60000) }
                        }
                        Row {
                            y: 212; anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                            Chip { text: "−1"; width: 40; onClicked: Timers.tAdd(-60000) }
                            Chip { primary: true; text: Timers.tRunning ? Cfg.tr("Pause") : Cfg.tr("Start"); width: 90; onClicked: Timers.tRunning ? Timers.tPause() : Timers.tStart() }
                            Chip { text: "+1"; width: 40; onClicked: Timers.tAdd(60000) }
                            Chip { text: "\uf0e2"; width: 40; onClicked: Timers.tReset() }
                        }
                        Grid {
                            id: presets
                            x: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                            columns: 4; columnSpacing: 6; rowSpacing: 6
                            readonly property real cellW: (tCard.width - 36 - 3 * 6) / 4
                            Repeater { model: [1, 3, 5, 10, 15, 25, 45, 60]
                                Chip { required property int modelData; width: presets.cellW; text: modelData + " " + Cfg.tr("min")
                                       on: Timers.tTotal === modelData * 60000; onClicked: Timers.tSet(modelData * 60000) } }
                        }
                    }

                    // ── stopwatch ──
                    Card {
                        id: swCard
                        x: tPage.cw + 12; width: tPage.cw; height: parent.height
                        // redraw ~30 times a second only while it runs and you can see it
                        property real tick: Date.now()
                        Timer { interval: 33; repeat: true; running: Timers.swRunning && db.shown && db.tab === "timers"; onTriggered: swCard.tick = Date.now() }
                        readonly property real el: { tick; return Timers.swElapsed(Date.now()); }
                        Text { x: 18; y: 16; text: Cfg.tr("Stopwatch"); font.family: db.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: db.cFg }
                        Dial {
                            y: 44; anchors.horizontalCenter: parent.horizontalCenter
                            frac: (swCard.el % 60000) / 60000          // the ring goes round once a minute
                            big: Timers.fmtSw(swCard.el).replace(/\.\d\d$/, "")
                            small: "." + Timers.fmtSw(swCard.el).slice(-2)
                        }
                        Row {
                            y: 212; anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                            Chip { text: Cfg.tr("Lap"); width: 64; opacity: Timers.swRunning ? 1 : 0.45; onClicked: Timers.swLap() }
                            Chip { primary: true; text: Timers.swRunning ? Cfg.tr("Pause") : Cfg.tr("Start"); width: 90; onClicked: Timers.swToggle() }
                            Chip { text: "\uf0e2"; width: 40; onClicked: Timers.swReset() }
                        }
                        ListView {
                            x: 18; width: parent.width - 36
                            anchors { top: parent.top; topMargin: 258; bottom: parent.bottom; bottomMargin: 14 }
                            clip: true; spacing: 2
                            model: Timers.laps.slice().reverse()
                            delegate: Rectangle {
                                required property real modelData
                                required property int index
                                readonly property int n: Timers.laps.length - index
                                readonly property real prev: n > 1 ? Timers.laps[n - 2] : 0
                                width: ListView.view.width; height: 24; radius: 8; color: index === 0 ? "#14ffffff" : "transparent"
                                Text { x: 10; text: Cfg.tr("Lap") + " " + parent.n; font.family: db.fUi; font.pixelSize: 11; color: db.cMuted; anchors.verticalCenter: parent.verticalCenter }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "+" + Timers.fmtSw(parent.modelData - parent.prev); font.family: db.fUi; font.pixelSize: 11; color: db.cAccent; anchors.verticalCenter: parent.verticalCenter }
                                Text { anchors.right: parent.right; anchors.rightMargin: 10; text: Timers.fmtSw(parent.modelData); font.family: db.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: db.cFg; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Text { anchors.centerIn: parent; visible: Timers.laps.length === 0; text: Cfg.tr("Laps show up here"); font.family: db.fUi; font.pixelSize: 11; color: db.cMuted }
                        }
                    }

                    // ── alarms ── (same grid: title · clock · list · add)
                    Card {
                        id: alCard
                        x: 2 * (tPage.cw + 12); width: tPage.cw; height: parent.height
                        Text { x: 18; y: 16; text: Cfg.tr("Alarms"); font.family: db.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: db.cFg }
                        Column {
                            y: 66; anchors.horizontalCenter: parent.horizontalCenter; spacing: 4
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Cfg.timeStr(new Date(Timers.now), false)
                                   font.family: db.fUi; font.pixelSize: 44; font.weight: Font.Bold; color: db.cFg }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; font.family: db.fUi; font.pixelSize: 12
                                   color: Timers.nextAlarm ? db.cAccent : db.cMuted
                                   text: { const n = Timers.nextAlarm; if (!n) return Cfg.tr("No alarms set");
                                           const mins = Math.round((n.getTime() - Timers.now) / 60000), h = Math.floor(mins / 60), m = mins % 60;
                                           return "\uf0f3  " + Cfg.timeStr(n, false) + "  ·  " + Cfg.tr("in") + " " + (h > 0 ? h + " " + Cfg.tr("h") + " " : "") + m + " " + Cfg.tr("min"); } }
                        }
                        Column {
                            x: 18; y: 160; width: parent.width - 36; spacing: 6
                            Repeater {
                                model: Timers.alarms
                                Rectangle {
                                    id: al
                                    required property var modelData
                                    required property int index
                                    width: parent.width; height: 44; radius: 12; color: "#14ffffff"
                                    opacity: modelData.on ? 1 : 0.55
                                    Row {
                                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                        // hh : mm - scroll or click (right click = down) to change
                                        Repeater { model: ["h", "m"]
                                            Text {
                                                required property string modelData
                                                required property int index
                                                text: (index === 1 ? ":" : "") + String(al.modelData[modelData]).padStart(2, "0")
                                                font.family: db.fUi; font.pixelSize: 22; font.weight: Font.Bold; color: tma2.containsMouse ? db.cAccent : db.cFg
                                                MouseArea { id: tma2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.SizeVerCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                    function step(d) { const k = parent.modelData, max = k === "h" ? 24 : 60, st = k === "m" ? 5 : 1;
                                                        Timers.setAlarm(al.index, { [k]: ((al.modelData[k] + d * st) % max + max) % max, last: "" }); }
                                                    onClicked: m => step(m.button === Qt.RightButton ? -1 : 1)
                                                    onWheel: w => step(w.angleDelta.y > 0 ? 1 : -1) }
                                            }
                                        }
                                    }
                                    Row {
                                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                        spacing: 10
                                        Rectangle { width: 40; height: 22; radius: 11; anchors.verticalCenter: parent.verticalCenter
                                            color: al.modelData.on ? db.cAccent : "#33ffffff"
                                            Rectangle { width: 16; height: 16; radius: 8; y: 3; x: al.modelData.on ? 21 : 3; color: al.modelData.on ? db.cAccFg : "#ffffff"
                                                Behavior on x { NumberAnimation { duration: 150 } } }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Timers.setAlarm(al.index, { on: !al.modelData.on, last: "" }) } }
                                        Text { text: "\uf1f8"; font.family: db.fIcon; font.pixelSize: 12; color: dla.containsMouse ? "#ff8a9a" : db.cMuted; anchors.verticalCenter: parent.verticalCenter
                                            MouseArea { id: dla; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Timers.removeAlarm(al.index) } }
                                    }
                                }
                            }
                            Text { visible: Timers.alarms.length > 0; width: parent.width; wrapMode: Text.WordWrap; font.family: db.fUi; font.pixelSize: 10; color: db.cMuted
                                   text: Cfg.tr("Scroll or click the hours / minutes to change them (right click = back).") }
                        }
                        Chip {
                            visible: Timers.alarms.length < 3
                            x: 18; width: parent.width - 36; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                            text: "+  " + Cfg.tr("Add alarm"); onClicked: Timers.addAlarm()
                        }
                    }
                }
            }
        }
    }
}
