// sakura mono — dashboard (click the clock on the top bar)
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick

Scope {
    id: db

    // palette
    readonly property color cBg:     "#f20f1119"
    readonly property color cCard:   "#1a1d28"
    readonly property color cCard2:  "#22263a"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: "#f2b8d0"
    readonly property color cAccDim: "#55f2b8d0"
    readonly property color cAccFg:  "#1a121a"
    readonly property string fUi:    "Inter"
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string home:   Quickshell.env("HOME")
    readonly property string scripts: home + "/.config/hypr/scripts"

    property bool shown: false
    property string tab: "dashboard"
    readonly property var tabIds: ["dashboard", "media", "performance", "weather"]
    readonly property int tabIndex: Math.max(0, tabIds.indexOf(tab))
    property var screen0: Quickshell.screens[0]

    function toggle() {
        if (!shown) {
            const m = Hyprland.focusedMonitor;
            const sc = m ? Quickshell.screens.find(s => s.name === m.name) : null;
            if (sc) screen0 = sc;
            calMonth = new Date(); now = new Date();
            perfProc.running = true;
            if (Date.now() - weatherAt > 15 * 60 * 1000) weatherFetch.running = true; else weatherRead.running = true;
            const i = players.findIndex(p => p.isPlaying); if (i >= 0) pick = i;
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
    function wText(code) {
        if (code === 0) return "Clear"; if (code <= 2) return "Partly cloudy"; if (code === 3) return "Cloudy";
        if (code <= 48) return "Fog"; if (code <= 57) return "Drizzle"; if (code <= 67) return "Rain";
        if (code <= 77) return "Snow"; if (code <= 82) return "Showers"; if (code <= 86) return "Snow showers"; return "Thunderstorm";
    }
    readonly property var cur: weather ? weather.current : null

    // ── media ───────────────────────────────────────────────
    property int pick: 0
    readonly property var players: Mpris.players.values.filter(p => !String(p.dbusName || "").includes("playerctld"))
    readonly property var player: players.length > 0 ? players[Math.min(pick, players.length - 1)] : null
    Timer { interval: 500; running: db.shown && db.player !== null; repeat: true; onTriggered: if (db.player) db.player.positionChanged() }
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

    // synced lyrics (lrclib.net)
    property var lyrics: []
    property string lyricsKey: ""
    property string lyricsState: ""
    readonly property string trackKey: player ? (player.trackArtist + "|" + player.trackTitle) : ""
    onTrackKeyChanged: if (shown && tab === "media") fetchLyrics()
    onTabChanged: if (tab === "media") fetchLyrics()
    function fetchLyrics() {
        if (!player || trackKey === lyricsKey) return;
        lyricsKey = trackKey; lyrics = []; lyricsState = "Loading lyrics…";
        const q = "artist_name=" + encodeURIComponent(player.trackArtist || "") + "&track_name=" + encodeURIComponent(player.trackTitle || "");
        lyricsProc.command = ["curl", "-s", "--max-time", "6", "-A", "sakura-dashboard", "https://lrclib.net/api/get?" + q];
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
                c.strokeStyle = "#f2b8d0"; c.beginPath(); c.arc(cx, cy, r, a0, a0 + sweep * Math.max(0.001, Math.min(1, ring.value / 100))); c.stroke();
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
        visible: db.shown
        screen: db.screen0
        anchors.top: true
        margins.top: 54
        implicitWidth: 920
        implicitHeight: 480
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dashboard"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        HyprlandFocusGrab { windows: [ win ]; active: db.shown; onCleared: db.shown = false }

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: 28
            color: db.cBg
            border.width: 1; border.color: db.cBorder
            opacity: db.shown ? 1 : 0
            transform: Translate { y: db.shown ? 0 : -12; Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 200 } }
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
                                 { id: "weather",     cp: 0xf0595, t: "Weather" } ]
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

                    // weather mini
                    Card {
                        id: wMini
                        x: 0; y: 0; width: 290; height: 120
                        Row {
                            anchors.centerIn: parent; spacing: 18
                            Text { text: db.cur ? db.wIcon(db.cur.weather_code, db.cur.is_day) : ""; font.family: db.fIcon; font.pixelSize: 54; color: db.cAccent; anchors.verticalCenter: parent.verticalCenter }
                            Column { anchors.verticalCenter: parent.verticalCenter
                                Text { text: db.cur ? Math.round(db.cur.temperature_2m) + "°C" : "--"; font.family: db.fUi; font.pixelSize: 32; font.weight: Font.Bold; color: db.cFg }
                                Text { text: db.cur ? db.wText(db.cur.weather_code) : "loading…"; font.family: db.fUi; font.pixelSize: 13; color: db.cMuted }
                                Text { text: db.weather ? db.weather.city : ""; font.family: db.fUi; font.pixelSize: 11; color: db.cAccent } }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: db.tab = "weather" }
                    }
                    // user card
                    Card {
                        x: 302; y: 0; width: 306; height: 120
                        Row {
                            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter } spacing: 16
                            ClippingRectangle { width: 76; height: 76; radius: 38; color: db.cAccent; anchors.verticalCenter: parent.verticalCenter
                                Image { anchors.fill: parent; anchors.margins: 3; source: "file://" + db.home + "/.config/hypr/assets/avatar.png"; mipmap: true } }
                            Column { anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                Text { text: Quickshell.env("USER"); font.family: db.fUi; font.pixelSize: 17; font.weight: Font.Bold; color: db.cFg }
                                Rectangle { width: hl.implicitWidth + 18; height: 24; radius: 9; color: db.cCard2
                                    Row { id: hl; anchors.centerIn: parent; spacing: 6
                                        Text { text: ""; font.family: db.fIcon; font.pixelSize: 12; color: db.cAccent }
                                        Text { text: "Arch · Hyprland"; font.family: db.fUi; font.pixelSize: 11; color: db.cFg } } }
                                Text { text: "up " + db.upText(db.perf.uptime); font.family: db.fUi; font.pixelSize: 12; color: db.cMuted } }
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
                Item {
                    anchors.fill: parent
                    // slides in from the side you are moving to, and fades
                    opacity: db.tab === "media" ? 1 : 0
                    visible: opacity > 0.01
                    enabled: db.tab === "media"
                    transform: Translate { x: (1 - db.tabIndex) * 46; Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                    Disc { id: bigDisc; size: 300; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }

                    Column {
                        id: mInfo
                        anchors { left: bigDisc.right; leftMargin: 26; top: parent.top; topMargin: 30 }
                        width: 300; spacing: 6
                        Text { width: parent.width; elide: Text.ElideRight; text: db.player ? (db.player.trackTitle || "Unknown") : "Nothing playing"
                            font.family: db.fUi; font.pixelSize: 24; font.weight: Font.ExtraBold; color: db.cFg }
                        Text { width: parent.width; elide: Text.ElideRight; text: db.player ? (db.player.trackArtist || "") : ""; font.family: db.fUi; font.pixelSize: 15; color: db.cAccent }
                        Text { width: parent.width; elide: Text.ElideRight; text: db.player ? (db.player.trackAlbum || "") : ""; font.family: db.fUi; font.pixelSize: 13; color: db.cMuted }
                        Item { width: 1; height: 26 }
                        // progress
                        Item {
                            id: mProg
                            width: parent.width; height: 18
                            readonly property real len: db.player ? db.player.length : 0
                            readonly property real pos: db.player ? db.player.position : 0
                            Text { id: mp1; anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: db.fmt(mProg.pos); font.family: db.fUi; font.pixelSize: 11; color: db.cMuted }
                            Text { id: mp2; anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: db.fmt(mProg.len); font.family: db.fUi; font.pixelSize: 11; color: db.cMuted }
                            Bar { anchors { left: mp1.right; right: mp2.left; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                value: mProg.len > 0 ? mProg.pos / mProg.len : 0
                                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                    enabled: db.player !== null && db.player.canSeek && mProg.len > 0
                                    onClicked: m => db.player.position = mProg.len * Math.max(0, Math.min(1, m.x / width)) } }
                        }
                        Item { width: 1; height: 12 }
                        Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 8; visible: db.player !== null
                            CtlBtn { icon: ""; lit: db.player && db.player.shuffle; onClicked: if (db.player.shuffleSupported) db.player.shuffle = !db.player.shuffle }
                            CtlBtn { icon: ""; onClicked: db.player.previous() }
                            CtlBtn { big: true; icon: db.player && db.player.isPlaying ? "" : ""; onClicked: db.player.togglePlaying() }
                            CtlBtn { icon: ""; onClicked: db.player.next() }
                            CtlBtn { icon: ""; lit: db.player && db.player.loopState !== MprisLoopState.None
                                onClicked: if (db.player.loopSupported) db.player.loopState = db.player.loopState === MprisLoopState.None ? MprisLoopState.Playlist : MprisLoopState.None } }
                        Item { width: 1; height: 10 }
                        Row { spacing: 6; visible: db.players.length > 1
                            Repeater { model: db.players
                                delegate: Rectangle { required property var modelData; required property int index
                                    width: pt.implicitWidth + 16; height: 24; radius: 8; color: index === db.pick ? db.cAccent : db.cCard
                                    Text { id: pt; anchors.centerIn: parent; text: modelData.identity || "player"; font.family: db.fUi; font.pixelSize: 11
                                        color: index === db.pick ? db.cAccFg : db.cFg }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { db.pick = index; db.lyricsKey = ""; db.fetchLyrics(); } } } } }
                    }

                    // lyrics
                    Card {
                        anchors { left: mInfo.right; leftMargin: 20; right: parent.right; top: parent.top; bottom: parent.bottom }
                        Row { id: lyHead; anchors { left: parent.left; top: parent.top; margins: 16 } spacing: 8
                            Text { text: ""; font.family: db.fIcon; font.pixelSize: 13; color: db.cAccent }
                            Text { text: "Lyrics"; font.family: db.fUi; font.pixelSize: 13; font.weight: Font.Bold; color: db.cFg } }
                        Text { anchors.centerIn: parent; visible: db.lyricsState !== ""; text: db.lyricsState; font.family: db.fUi; font.pixelSize: 13; color: db.cMuted }
                        ListView {
                            id: lyList
                            anchors { top: lyHead.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                            clip: true; interactive: false
                            model: db.lyrics
                            currentIndex: Math.max(0, db.lyricIdx)
                            highlightRangeMode: ListView.ApplyRange
                            preferredHighlightBegin: height / 2 - 16; preferredHighlightEnd: height / 2 + 16
                            highlightMoveDuration: 350
                            delegate: Text {
                                required property var modelData
                                required property int index
                                width: lyList.width; wrapMode: Text.WordWrap; topPadding: 4; bottomPadding: 4
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
                            Text { width: parent.width; elide: Text.ElideRight; text: db.perf.gpu ? db.perf.gpu.name : "—"; font.family: db.fUi; font.pixelSize: 12; color: db.cMuted }
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
                                        text: index === 0 ? "Today" : ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][new Date(d.time[index]).getDay()] }
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
            }
        }
    }
}
