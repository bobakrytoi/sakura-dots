// sakura mono - the corner island: a small strip of glass in one screen corner, along the top (or bottom) edge,
// an S-curve back into that edge on the inner end and a concave ear down the side edge, tinted with the
// color the wallpaper has right in that corner. It holds the same modules as the bar's wings plus quick buttons,
// so the bar can stay folded. Settings > Taskbar > Corner island (settings.json: islandOn, islandCorner,
// islandScreen main|second|both, islandSize s|m|l, islandItems = order, Cfg.islandCatalog).
// Hidden while a game is fullscreen on that screen, and in a bottom corner of the main monitor while the bar is
// at the bottom (its pills live there). Layer Top, only the island itself takes the mouse.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import QtQuick

Scope {
    id: isl
    property var topBar: null             // live state (time, sound, net, cpu …) and the menus that flow out of the bar
    property var settings: null           // night light lives in Settings.cfg

    // Quickshell's workspace.hasFullscreen goes stale when a fullscreen game closes or moves (no "fullscreen>>0"
    // comes then), so the island stayed hidden after a game. Re-read the workspaces from Hyprland on those events
    // (also fixes the hot corners / converter edge, which read the same flag).
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (/^(fullscreen|closewindow|movewindow|workspace|focusedmon|activewindow|destroyworkspace)/.test(e.name)) fsSync.restart();
        }
    }
    Timer { id: fsSync; interval: 250; onTriggered: { Hyprland.refreshWorkspaces(); Hyprland.refreshMonitors(); } }

    readonly property bool on: Cfg.data.islandOn !== false
    readonly property string corner: ["tl", "tr", "bl", "br"].includes(Cfg.data.islandCorner) ? Cfg.data.islandCorner : "tr"
    readonly property bool right: corner[1] === "r"
    readonly property bool bottom: corner[0] === "b"
    readonly property string where: Cfg.data.islandScreen || "main"
    readonly property string size: Cfg.data.islandSize || "m"
    readonly property int h: size === "s" ? 30 : size === "l" ? 42 : 36        // strip height (the bar's notch is 40)
    readonly property int btnH: h - 10
    readonly property int glyphPx: size === "s" ? 12 : size === "l" ? 15 : 13
    readonly property int textPx: size === "s" ? 11 : size === "l" ? 13 : 12
    readonly property int padX: 10
    readonly property int sW: 24                                                 // S-curve into the edge, as in the bar
    // reads as a piece cut out of the screen: nearly opaque dark (≈ the bezel), a thin rim down the side edge
    // and the wallpaper's own corner rounded under the strip
    readonly property int band: 8
    readonly property int cutR: 22
    readonly property int bandL: 90
    readonly property color fillC: { const c = tinted(0.08); return Qt.rgba(c.r * 0.7, c.g * 0.7, c.b * 0.7, Math.max(0.9, Cfg.glassAlpha)); }
    readonly property var items: Cfg.islandItems

    readonly property int earW: 22
    readonly property int earH: 16
        readonly property color cFg: "#eceef4"
    readonly property color cMuted: "#8a8fa3"
    readonly property string fIcon: "Symbols Nerd Font"
    readonly property string sc: Quickshell.env("HOME") + "/.config/hypr/scripts/"
    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }

    // ── the wallpaper's color in this corner (a 16 x 9 copy, the pixel next to the corner) ──
    property color tone: Cfg.accent
    property bool toneOk: false
    readonly property string wall: Cfg.data.wallpaper || ""
    onWallChanged: toneProc.running = true
    onCornerChanged: toneProc.running = true
    Process {
        id: toneProc
        running: isl.on
        command: ["sh", "-c", "f=$(\"$0\" \"$1\" 320) && magick \"$f\" -resize '16x9!' -format '%[hex:p{" + (isl.right ? 14 : 1) + "," + (isl.bottom ? 7 : 1) + "}]' info:",
                  isl.sc + "wallthumb.sh", isl.wall]
        stdout: StdioCollector { onStreamFinished: {
            const h = this.text.trim();
            if (/^[0-9a-fA-F]{6}/.test(h)) { isl.tone = "#" + h.slice(0, 6); isl.toneOk = true; } else isl.toneOk = false;
        } }
    }
    // glass (15,17,25 at Cfg.glassAlpha) with t of the tone mixed in
    function tinted(t) {
        const c = toneOk ? tone : Cfg.accent, k = toneOk ? t : t * 0.5;
        return Qt.rgba((15 / 255) * (1 - k) + c.r * k, (17 / 255) * (1 - k) + c.g * k, (25 / 255) * (1 - k) + c.b * k, Cfg.glassAlpha);
    }

    // ── what the bar doesn't track itself ──
    property bool vpnOn: false
    property string vpnTip: "VPN"
    Process {
        id: vpnProc
        command: ["mullvad", "status"]
        stdout: StdioCollector { onStreamFinished: {
            const l = this.text.split("\n");
            isl.vpnOn = /^(Connected|Connecting)/.test(l[0] || "");
            isl.vpnTip = "VPN · " + (l[0] || "").trim();
        } }
    }
    Timer {
        interval: 5000; repeat: true; triggeredOnStart: true
        running: isl.on && Cfg.has.mullvad === true && isl.items.includes("vpn")
        onTriggered: vpnProc.running = true
    }
    PwObjectTracker { objects: [ Pipewire.defaultAudioSource ] }
    readonly property var src: Pipewire.defaultAudioSource

    // one module → what its button shows and does (the same ones as the bar's wings + quick buttons)
    // pill: glyph + text · round: glyph only. m = mouse event, b = the button (to open a menu under it)
    function def(id) {
        const tb = topBar;
        if (!tb) return null;
        if (id.startsWith("dev:")) {     // one wireless device's battery (Devices.qml), the "devices" module = a row of these
            const v = Devices.map[id.slice(4)] || null;
            return !Devices.wanted(v) ? null : { glyph: Devices.glyph(v.kind), tip: Devices.tip,
                tint: v.charging ? Cfg.accent : (v.percent !== undefined && v.percent < Devices.low) ? "#f28fad" : v.percent === undefined ? cMuted : cFg,
                label: Cfg.mo("devices", "pct") && v.percent !== undefined ? v.percent + "%" : "", click: () => Devices.poll() };
        }
        switch (id) {
        case "layout": return tb.layout.text === "" ? null : { label: Cfg.mo("layout", "long") && tb.layout.tip ? tb.layout.tip : tb.layout.text, tip: tb.layout.tip || Cfg.tr("Keyboard layout"),
            click: () => run("hyprctl switchxkblayout all next") };
        case "volume": return { glyph: tb.muted ? "" : (tb.vol < 0.34 ? "" : tb.vol < 0.67 ? "" : ""), tint: tb.muted ? cMuted : cFg,
            label: tb.muted ? (Cfg.mo("volume", "pct") ? "mute" : "") : Cfg.mo("volume", "pct") ? Math.round(tb.vol * 100) + "%" : "", tip: tb.sink ? (tb.sink.description || tb.sink.name) : Cfg.tr("Sound"),
            click: (m, b) => { if (m.button === Qt.RightButton) { if (tb.sink && tb.sink.audio) tb.sink.audio.muted = !tb.sink.audio.muted; } else menu(tb.mixer, b); },
            wheel: dy => { if (tb.sink && tb.sink.audio) tb.sink.audio.volume = Math.max(0, Math.min((Cfg.data.volMax || 100) / 100, tb.sink.audio.volume + dy * (Cfg.data.volStep || 5) / 100)); } };
        case "network": return { glyph: tb.net.kind === "eth" ? "\u{F0200}" : tb.net.kind === "wifi" ? "" : "\u{F0C9B}", tint: tb.net.kind === "off" ? cMuted : cFg,
            label: tb.net.kind === "off" ? "off" : Cfg.mo("network", "name") ? tb.net.name : "", tip: tb.net.kind === "eth" ? "Cable · " + tb.net.name : tb.net.kind === "wifi" ? "Wi-Fi · " + tb.net.name : "Offline",
            click: (m, b) => menu(tb.netMenu, b) };
        case "cpu": return { glyph: "", label: Cfg.mo("cpu", "pct") ? tb.cpu + "%" : "", tip: "CPU · " + tb.cpu + "%", click: () => run("~/.local/bin/taskmgr cpu") };
        case "ram": return { glyph: "\u{F035B}", label: Cfg.mo("ram", "pct") ? tb.mem + "%" : "", tip: tb.mem + "% · RAM · " + tb.memTip, click: () => run("~/.local/bin/taskmgr mem") };
        case "notify": return { glyph: tb.dnd ? "" : "", tint: tb.notifDot ? Cfg.accent : cFg, label: Cfg.mo("notify", "count") && Notifs.unread > 0 ? String(Notifs.unread) : "",
            tip: tb.dnd ? Cfg.tr("Do not disturb") : Cfg.tr("Notifications"),
            click: (m, b) => { if (m.button === Qt.RightButton) Notifs.toggleDnd(); else menu(tb.notifCenter, b); } };
        case "capture": return tb.capture.text === "" ? null : { glyph: tb.capture.text, tip: tb.capture.tip, tint: tb.capture.cls === "rec" ? "#f28fad" : Cfg.accent,
            click: () => run("qs ipc call capture toggle") };
        case "updates": return tb.updates.text === "" ? null : { glyph: "", tint: Cfg.accent, label: tb.updates.text, tip: tb.updates.tip,
            click: () => run(sc + "updates.sh install") };
        case "track": {
            const p = tb.player;
            if (!p) return null;
            const t = p.trackTitle || p.trackArtist || p.identity || "";
            return { glyph: p.isPlaying ? "" : "", label: !Cfg.mo("track", "text") ? "" : t.length > 18 ? t.slice(0, 17) + "…" : t,
                tip: [p.trackTitle, p.trackArtist].filter(x => x).join(" - ") || p.identity,
                click: m => { if (m.button === Qt.MiddleButton) p.togglePlaying(); else run("qs ipc call media toggle"); },
                wheel: dy => { if (dy > 0) p.previous(); else p.next(); } };
        }
        case "power": return { round: true, glyph: "", tint: Cfg.accent, tip: Cfg.tr("Power"), click: (m, b) => menu(tb.powerMenu, b) };
        case "screenshot": return { round: true, glyph: "", tip: Cfg.tr("Screenshot"), click: () => run("sleep 0.3; " + sc + "screenshot.sh region") };
        case "vpn": return Cfg.has.mullvad !== true ? null : { round: true, glyph: "", active: vpnOn, tip: vpnTip,
            click: () => { run(vpnOn ? "mullvad disconnect" : "mullvad connect"); vpnOn = !vpnOn; vpnPoke.restart(); } };
        case "dnd": return { round: true, glyph: "\uf1f6", active: Notifs.dnd, tip: Cfg.tr("Do not disturb"), click: () => Notifs.toggleDnd() };
        case "mixer": return { round: true, glyph: "\uf1de", tip: Cfg.tr("Sound"), click: (m, b) => menu(tb.mixer, b) };
        case "mic": {
            const mu = !!(src && src.audio && src.audio.muted);
            return { round: true, glyph: mu ? "" : "", active: !mu, tint: mu ? cMuted : cFg, tip: Cfg.tr("Microphone"),
                click: () => { if (src && src.audio) src.audio.muted = !src.audio.muted; } };
        }
        case "night": {
            const n = !!settings && (settings.cfg.warmth || 0) > 0;
            return !settings ? null : { round: true, glyph: "", active: n, tip: Cfg.tr("Night light"),
                click: () => settings.setCfg("warmth", n ? 0 : 0.5) };
        }
        case "clipboard": return { round: true, glyph: "", tip: Cfg.tr("Clipboard"), click: () => run("qs ipc call clipboard toggle") };
        case "color": return Cfg.has.hyprpicker !== true ? null : { round: true, glyph: "", tip: Cfg.tr("Color picker"), click: () => run("sleep 0.3; hyprpicker -a -n") };
        case "wallpaper": return { round: true, glyph: "", tip: Cfg.tr("Wallpaper"), click: () => run("qs ipc call wallpicker toggle") };
        case "lock": return { round: true, glyph: "", tip: Cfg.tr("Lock"), click: () => run(sc + "lock.sh") };
        }
        return null;
    }
    Timer { id: vpnPoke; interval: 2500; onTriggered: vpnProc.running = true }
    // the bar's menus flow out of the top edge; this opens one above the button's column on this screen
    function menu(m, b) { if (m && b && b.win) m.toggleAt(b.win.screen.name, b.win.screenX + b.mapToItem(null, b.width / 2, 0).x); }

    SystemClock { id: clock; precision: Cfg.data.seconds ? SystemClock.Seconds : SystemClock.Minutes }

    // like the bar's buttons: no card, lights up under the mouse
    component IslBtn: Rectangle {
        id: g
        property var win
        property var d: null
        readonly property bool round: !!d && d.round === true
        readonly property string glyph: d && d.glyph ? d.glyph : ""
        readonly property string label: d && d.label ? d.label : ""
        readonly property string tip: d && d.tip ? d.tip : ""
        readonly property bool hot: ga.containsMouse
        visible: d !== null
        implicitHeight: isl.btnH
        implicitWidth: round ? isl.btnH + 4 : row.implicitWidth + 14
        radius: 9
        color: hot ? Cfg.acc(0.22) : (d && d.active ? Cfg.acc(0.14) : "transparent")
        scale: ga.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 90 } }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 5
            Text { visible: g.glyph !== ""; text: g.glyph; font.family: isl.fIcon; font.pixelSize: isl.glyphPx; anchors.verticalCenter: parent.verticalCenter
                color: g.hot || (g.d && g.d.active) ? Cfg.accent : (g.d && g.d.tint ? g.d.tint : isl.cFg)
                Behavior on color { ColorAnimation { duration: 120 } } }
            Text { visible: g.label !== ""; text: g.label; color: g.hot ? "#ffffff" : isl.cFg; font.family: Cfg.fontUi; font.pixelSize: isl.textPx; font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            id: ga; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: m => { if (g.d && g.d.click) g.d.click(m, g); }
            onWheel: w => { if (g.d && g.d.wheel) g.d.wheel(w.angleDelta.y > 0 ? 1 : -1); }
            onContainsMouseChanged: if (g.win) g.win.hover(g, containsMouse)
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: iwin
            required property var modelData
            screen: modelData
            readonly property bool isMain: modelData.name === Cfg.mainName
            readonly property var hmon: Hyprland.monitorFor(modelData)
            readonly property bool fs: hmon && hmon.activeWorkspace ? hmon.activeWorkspace.hasFullscreen === true : false
            readonly property bool wanted: isl.on && (isl.where === "both" || (isl.where === "main") === isMain)
                                           && !(isl.bottom && isMain && !!isl.topBar && isl.topBar.barBottom)
            // fullscreen only hides what is drawn and takes the input away: unmapping the window and mapping it again
            // after a game needed a new EGL surface, and with the VRAM full that failed once ("Could not create EGL
            // surface 0x3003") - Qt never retries, so the island was gone until a shell restart
            visible: wanted
            readonly property bool shown: wanted && !fs
            Binding { target: iwin.contentItem; property: "opacity"; value: iwin.shown ? 1 : 0 }
            // where this window starts on the screen (to open the bar's menus right above a button)
            readonly property real screenX: isl.right ? modelData.width - width : 0

            anchors { top: !isl.bottom; bottom: isl.bottom; left: !isl.right; right: isl.right }
            implicitWidth: iw + isl.sW + 260                  // + room for the tip beside it
            implicitHeight: isl.h + isl.cutR + isl.bandL + isl.earW + 40   // + the rim down the side edge, the tip
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "corner-island"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { item: iwin.shown ? box : null }

            readonly property real iw: row.implicitWidth + 2 * isl.padX

            // slides out of the side edge when it shows up
            property real p: 0
            onShownChanged: if (shown) { p = 0; growIn.restart(); }
            Component.onCompleted: growIn.restart()
            NumberAnimation { id: growIn; target: iwin; property: "p"; from: 0; to: 1; duration: 380 * Cfg.anim; easing.type: Easing.OutCubic }

            property string tipText: ""
            property real tipX: 0
            function hover(item, on) {
                if (on) { tipText = item.tip; tipX = item.mapToItem(null, item.width / 2, 0).x; }
                else if (tipText === item.tip) tipText = "";
            }

            // the strip along the top/bottom edge: an S-curve into that edge on the inner end (like the bar's
            // wings into the notch), a concave ear down the side edge - drawn top-left, mirrored into the corner
            Canvas {
                anchors.fill: parent
                readonly property string key: [width, height, iwin.iw, isl.h, isl.corner, Cfg.glass, isl.tone, isl.toneOk, iwin.p].join(",")
                onKeyChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const W = width, H = height, k = 0.5523, ew = isl.earW, s = isl.sW;
                    const b = isl.band, R = isl.cutR, L = isl.bandL * iwin.p;
                    const X = x => isl.right ? W - x : x, Y = y => isl.bottom ? H - y : y;
                    const w = iwin.iw * iwin.p, h = isl.h;
                    if (w < 1) return;
                    ctx.beginPath();
                    ctx.moveTo(X(0), Y(0));
                    ctx.lineTo(X(w + s), Y(0));
                    ctx.bezierCurveTo(X(w + s / 2), Y(0), X(w + s / 2), Y(h), X(w), Y(h));            // S-curve into the edge
                    ctx.lineTo(X(b + R), Y(h));
                    ctx.bezierCurveTo(X(b + R - R * k), Y(h), X(b), Y(h + R - R * k), X(b), Y(h + R)); // the wallpaper's corner, rounded
                    ctx.lineTo(X(b), Y(h + R + L));
                    ctx.bezierCurveTo(X(b), Y(h + R + L + ew * k), X(0), Y(h + R + L + ew - ew * k), X(0), Y(h + R + L + ew)); // the rim melts into the side
                    ctx.closePath();
                    ctx.fillStyle = isl.fillC;
                    ctx.fill();
                }
            }

            Item {
                id: box
                x: isl.right ? parent.width - width : 0
                y: isl.bottom ? parent.height - height : 0
                width: iwin.iw * iwin.p + isl.sW / 2; height: isl.h
                clip: true
                Row {
                    id: row
                    x: isl.right ? parent.width - width - isl.padX : isl.padX
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    layoutDirection: isl.right ? Qt.RightToLeft : Qt.LeftToRight
                    opacity: Math.max(0, (iwin.p - 0.4) / 0.6)
                    Repeater {
                        model: isl.items
                        delegate: Loader {
                            required property string modelData
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                            sourceComponent: modelData === "clock" ? clockC : modelData === "devices" ? devC : btnC
                        }
                    }
                }
                Component { id: btnC
                    IslBtn { win: iwin; d: isl.def(parent ? parent.modelData : "") } }
                Component { id: devC
                    Row { spacing: 2; layoutDirection: isl.right ? Qt.RightToLeft : Qt.LeftToRight
                        Repeater { model: Devices.ids
                            IslBtn { required property string modelData; win: iwin; d: isl.def("dev:" + modelData) } } } }
                Component { id: clockC
                    Rectangle {     // time + day, click = dashboard
                        readonly property string tip: Cfg.dateLong(clock.date)
                        implicitWidth: clockRow.implicitWidth + 14; implicitHeight: isl.btnH
                        radius: 9
                        color: ca.containsMouse ? Cfg.acc(0.18) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            id: clockRow
                            anchors.centerIn: parent; spacing: 6
                            Text { visible: Cfg.mo("clock", "date"); text: Cfg.locale.toString(clock.date, "ddd"); color: "#a9adbd"; font.family: Cfg.fontUi; font.pixelSize: isl.textPx - 1; anchors.verticalCenter: parent.verticalCenter }
                            Text { visible: Cfg.mo("clock", "date"); text: clock.date.getDate(); color: Cfg.accent; font.family: Cfg.fontUi; font.pixelSize: isl.textPx - 1; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: Cfg.timeStr(clock.date, Cfg.data.seconds); color: ca.containsMouse ? Cfg.accent : isl.cFg
                                font.family: Cfg.fontUi; font.pixelSize: isl.textPx + 2; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: ca; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: isl.run("qs ipc call dashboard toggle")
                            onContainsMouseChanged: iwin.hover(parent, containsMouse) }
                    }
                }
            }

            // the tip, glass like the bar's, just past the strip (not clickable)
            Rectangle {
                visible: opacity > 0.01
                opacity: iwin.tipText !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                x: Math.max(6, Math.min(iwin.width - width - 6, iwin.tipX - width / 2))
                y: isl.bottom ? iwin.height - isl.h - height - 6 : isl.h + 6
                width: tipL.width + 20; height: tipL.height + 12
                radius: 10
                color: Cfg.glass; border.width: 1; border.color: "#1fffffff"
                Text { id: tipL; anchors.centerIn: parent; text: iwin.tipText; color: isl.cFg; font.family: Cfg.fontUi; font.pixelSize: 12
                       width: Math.min(implicitWidth, 560); wrapMode: Text.WordWrap }   // never wider than 560 px
            }
        }
    }
}
