// sakura mono - the bar, top and bottom (it replaces waybar; barpos.sh only flips ~/.config/sakura/barpos).
// In the middle of every screen a notch with the clock hangs from the top edge. Hover it and two wings slide
// out to the sides - left: bar position, launcher, tray, windows, track; right: the indicators (capture,
// layout, sound, network, cpu, ram, updates, notifications, power). Each wing grows outward on its own,
// so the clock never moves. Every button lights up under the mouse and shows a tip under the bar.
// Shape: concave ears into the screen edge, wings with a rounded outer corner, an S-curve from each wing
// down into the notch. Collapsed, the wings are as tall as the notch and 0 wide: just the notch with its ears.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import QtQuick

Scope {
    id: tb
    property var tray: null                 // Tray.qml: pinned icons, the "^" flyout and the right-click menu
    property var dashboard: null            // Dashboard.qml: opens from the clock and takes the bar's place
    property var mixer: null                // Mixer.qml, NetMenu.qml, PowerMenu.qml: flow out of the bar under their button
    property var netMenu: null
    property var powerMenu: null
    property var notifCenter: null          // NotifCenter.qml (our own notifications, no swaync)
    property var camPanel: null             // SakuraCam.qml (iPhone webcam), flows out of the notch
    function openUnder(menu, bar, btn) { if (menu) menu.toggleAt(bar.screenName, btn.mapToItem(null, btn.width / 2, 0).x); }

    readonly property int deep: 40          // notch height (= the space reserved at the top)
    readonly property int wingH: 30         // wing height when open
    readonly property int sW: 24            // width of the S-curve between a wing and the notch
    readonly property int earW: 22          // concave ear into the screen edge (same as the dock)
    readonly property int earH: 16
    readonly property int wingR: 15         // rounded outer bottom corner of a wing
    readonly property color fill: Cfg.glass   // = the dock; hyprland blurs behind it (layer rule "blur-topbar")
    readonly property color cFg: "#eceef4"
    readonly property color cMuted: "#8a8fa3"
    readonly property color cAccent: Cfg.accent
    readonly property string fUi: Cfg.fontUi
    readonly property string fIcon: "Symbols Nerd Font"
    readonly property string sc: Quickshell.env("HOME") + "/.config/hypr/scripts/"
    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }
    // music in the notch: the quick Media menu; only with Settings → Music → "Sakura Sound" its own window opens
    function openMusic() {
        const p = Notch.player || tb.player;
        if (Cfg.data.musicNotch === "sound" && p && String(p.trackArtUrl || "").indexOf("/sakura-sound/covers/") >= 0) run("$HOME/.local/bin/sakura-sound");
        else run("qs ipc call media toggle");
    }

    // ── the shape, shared with the dashboard and the tray flyout ──
    // g = { xl, xr: outer ends of the wings · x0, x1: the notch · wh: wing height · d: notch depth · r: wing corner }.
    // A menu that opens from the bar draws this same shape and morphs g from the bar's to its own box
    // (xl/xr → its sides, wh = d → its height), so bar and menu read as one piece.
    function drawShape(ctx, g) {
        shapePath(ctx, g);
        ctx.fillStyle = fill;
        ctx.fill();
    }
    function shapePath(ctx, g) {
        const k = 0.5523, ew = earW, eh = earH, s = sW;
        const xl = g.xl, xr = g.xr, x0 = g.x0, x1 = g.x1, wh = g.wh, d = g.d, r = Math.min(g.r, wh / 2);
        ctx.beginPath();
        ctx.moveTo(xl - ew, 0);
        ctx.bezierCurveTo(xl - ew + ew * k, 0, xl, eh - eh * k, xl, eh);
        ctx.lineTo(xl, wh - r);
        ctx.bezierCurveTo(xl, wh - r + r * k, xl + r - r * k, wh, xl + r, wh);
        ctx.lineTo(x0 - s, wh);
        ctx.bezierCurveTo(x0 - s / 2, wh, x0 - s / 2, d, x0, d);
        ctx.lineTo(x1, d);
        ctx.bezierCurveTo(x1 + s / 2, d, x1 + s / 2, wh, x1 + s, wh);
        ctx.lineTo(xr - r, wh);
        ctx.bezierCurveTo(xr - r + r * k, wh, xr, wh - r + r * k, xr, wh - r);
        ctx.lineTo(xr, eh);
        ctx.bezierCurveTo(xr, eh - eh * k, xr + ew - ew * k, 0, xr + ew, 0);
        ctx.closePath();
    }
    function lerpGeo(a, b, t) { const o = {}; for (const key in b) o[key] = a[key] + (b[key] - a[key]) * t; return o; }
    property var genie: null               // Genie.qml: a minimized window clicked here is spat back out of the notch
    function barOn(name) { return bars.instances.find(w => w.modelData.name === name) || null; }
    function gulp(name) { const w = barOn(name); if (w && w.visible) w.doGulp(); }
    // the bar on that screen as it looks right now (a menu starts from it)…
    function geoFor(name) {
        const w = barOn(name);
        return w ? { xl: w.xl, xr: w.xr, x0: w.x0, x1: w.x1, wh: w.wh, d: deep + w.ext, r: wingR } : null;
    }
    // …and collapsed, just the clock (a closing menu ends in it, then the bar takes over)
    function restGeoFor(name) {
        const w = barOn(name);
        if (w && Cfg.barAlways) return { xl: w.x0 - sW - w.lw, xr: w.x1 + sW + w.rw, x0: w.x0, x1: w.x1, wh: wingH, d: deep, r: wingR };
        return w ? { xl: w.x0 - sW, xr: w.x1 + sW, x0: w.x0, x1: w.x1, wh: deep, d: deep, r: wingR } : null;
    }

    // ~/.config/sakura/barpos = bottom → on the main monitor the bar sits next to the dock (waybar): no top bar there
    property bool barBottom: false
    FileView {
        path: Quickshell.env("HOME") + "/.config/sakura/barpos"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: tb.barBottom = text().trim() === "bottom"
        onLoadFailed: tb.barBottom = false
    }

    // ── live state, shared by all screens ───────────────────
    SystemClock { id: clock; precision: Cfg.data.seconds ? SystemClock.Seconds : SystemClock.Minutes }
    readonly property string timeText: Cfg.timeStr(clock.date, Cfg.data.seconds)
    readonly property string dateText: Cfg.cap(Cfg.locale.toString(clock.date, "ddd, d MMM"))
    // ── the notch at rest (Settings > Taskbar > "Notch at rest"): plain | comet | tide | rings ──
    // comet: a spark on the notch's lower edge, how far it ran = how far the hour is · tide: the notch fills
    // with water up to how far the day is (waves move only under the mouse) · rings: day / week / month.
    // All repaint once a minute (with a clock tick) - nothing runs at the monitor's 200 Hz.
    readonly property string face: Cfg.data.notchFace || "plain"
    readonly property real hourFrac: (clock.date.getMinutes() + clock.date.getSeconds() / 60) / 60
    readonly property real dayFrac: (clock.date.getHours() * 60 + clock.date.getMinutes()) / 1440
    readonly property real weekFrac: (((clock.date.getDay() + 6) % 7) + dayFrac) / 7
    readonly property real monthFrac: (clock.date.getDate() - 1 + dayFrac) / new Date(clock.date.getFullYear(), clock.date.getMonth() + 1, 0).getDate()

    PwObjectTracker { objects: [ Pipewire.defaultAudioSink ] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: !!(sink && sink.audio && sink.audio.muted)
    readonly property var player: Players.player

    property var layout: ({ text: "", tip: "" })
    Process {     // streams {"text": "RU", "tooltip": …} on every switch
        id: layoutProc
        running: true
        command: ["python3", "-I", tb.sc + "layout.py"]
        stdout: SplitParser { onRead: d => { try { const j = JSON.parse(d); tb.layout = { text: j.text || "", tip: (j.tooltip || "").split("\n")[0] }; } catch (e) {} } }
        onRunningChanged: if (!running) layoutRestart.start()
    }
    Timer { id: layoutRestart; interval: 3000; onTriggered: layoutProc.running = true }

    // network: cable, wifi or nothing (the VPN tunnel and loopback don't count)
    property var net: ({ kind: "eth", name: "" })
    Process {
        id: netProc
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device", "status"]
        stdout: StdioCollector { onStreamFinished: {
            const devs = this.text.split("\n").filter(l => l).map(l => l.split(":"));
            const up = t => devs.find(d => d[0] === t && d[1] === "connected");
            const e = up("ethernet"), w = up("wifi");
            tb.net = e ? { kind: "eth", name: e[2] } : w ? { kind: "wifi", name: w[2] } : { kind: "off", name: "" };
        } }
    }

    property int cpu: 0
    property int mem: 0
    property string memTip: ""
    property var cpuPrev: null
    Process {
        id: statProc
        command: ["sh", "-c", "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo"]
        stdout: StdioCollector { onStreamFinished: {
            const l = this.text.split("\n");
            const c = l[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = c[3] + c[4], total = c.reduce((a, b) => a + b, 0);
            if (tb.cpuPrev) tb.cpu = Math.round(100 * (1 - (idle - tb.cpuPrev.idle) / Math.max(1, total - tb.cpuPrev.total)));
            tb.cpuPrev = { idle: idle, total: total };
            const mt = parseInt(l[1].split(/\s+/)[1]), ma = parseInt(l[2].split(/\s+/)[1]);
            tb.mem = Math.round(100 * (1 - ma / mt));
            tb.memTip = ((mt - ma) / 1048576).toFixed(1) + " / " + (mt / 1048576).toFixed(1) + " GB";
        } }
    }
    property var capture: ({ text: "", cls: "", tip: "" })
    Process {
        id: capProc
        command: [tb.sc + "capture.sh", "status"]
        stdout: StdioCollector { onStreamFinished: { try { const j = JSON.parse(this.text); tb.capture = { text: j.text || "", cls: j.class || "", tip: (j.tooltip || "").replace(/\s*[---]\s*click.*$/i, "") }; } catch (e) {} } }
    }
    Binding { target: Notch; property: "capture"; value: tb.capture }     // live activity "recording"
    // the mouse wheel on the bar (Settings > Taskbar): volume, workspaces or nothing - the live activity uses it too
    function wheelAct(up) {
        const act = Cfg.data.barWheel || "volume";
        if (act === "volume" && sink && sink.audio) sink.audio.volume = Math.max(0, Math.min((Cfg.data.volMax || 100) / 100, sink.audio.volume + (up ? 1 : -1) * (Cfg.data.volStep || 5) / 100));
        else if (act === "workspace") Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = '" + (up ? "e-1" : "e+1") + "' })"]);
    }
    property string minimized: ""
    Process {
        id: minProc
        command: [tb.sc + "minimize.sh", "count"]
        stdout: StdioCollector { onStreamFinished: { try { tb.minimized = JSON.parse(this.text).text || ""; } catch (e) { tb.minimized = ""; } } }
    }
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { capProc.running = true; minProc.running = true; statProc.running = true; }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: netProc.running = true }

    property var updates: ({ text: "", tip: "" })
    Process {
        id: updProc
        command: [tb.sc + "updates.sh"]
        stdout: StdioCollector { onStreamFinished: { try { const j = JSON.parse(this.text); tb.updates = { text: j.text || "", tip: (j.tooltip || "").replace(/\n*click:[^\n]*$/i, "").trim().replace(/\n/g, "<br>") }; } catch (e) {} } }
    }
    Timer { interval: 1800000; running: true; repeat: true; triggeredOnStart: true; onTriggered: updProc.running = true }

    readonly property bool notifDot: Notifs.unread > 0
    readonly property bool dnd: Notifs.dnd

    // ── a button: icon and/or text; lights up under the mouse, tip under the bar ──
    component BarBtn: Rectangle {
        id: g
        property var bar                    // the PanelWindow, for the tip
        property string glyph: ""
        property string label: ""
        property string icon: ""
        property string tip: ""
        property color tint: tb.cFg
        property bool active: false
        signal clicked(var m)
        signal wheel(int dy)
        readonly property bool hot: ga.containsMouse
        implicitWidth: row.implicitWidth + 14
        implicitHeight: 24
        radius: 9
        color: hot ? Cfg.acc(0.22) : (active ? "#16ffffff" : "transparent")
        scale: ga.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 90 } }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            IconImage { visible: g.icon !== ""; implicitSize: 17; source: g.icon; anchors.verticalCenter: parent.verticalCenter }
            Text { visible: g.glyph !== ""; text: g.glyph; color: g.hot ? tb.cAccent : g.tint; font.family: tb.fIcon; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 120 } } }
            Text { visible: g.label !== ""; text: g.label; color: g.hot ? "#ffffff" : tb.cFg; font.family: tb.fUi; font.pixelSize: 12; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
        }
        Rectangle {     // active window
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            width: g.active ? 12 : 0; height: 2; radius: 1; color: tb.cAccent
            Behavior on width { NumberAnimation { duration: 180 } }
        }
        MouseArea {
            id: ga; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: m => g.clicked(m)
            onWheel: w => g.wheel(w.angleDelta.y > 0 ? 1 : -1)
            onContainsMouseChanged: if (g.bar) g.bar.hover(g, containsMouse)
        }
    }

    // ── what the two sides hold: the top bar's wings and the bottom islands use the same ones ──
    // bar: the window they sit in (screenName, hover() for the tips)
    component LeftItems: Row {      // bar position, (clock at the bottom), launcher, tray, windows, track - order: Settings > Taskbar
        id: li
        property var bar
        property bool atBottom: false
        spacing: 2
        BarBtn { bar: li.bar; visible: li.atBottom; label: tb.timeText + "  " + tb.dateText; tip: Cfg.dateLong(clock.date)
            onClicked: tb.run("qs ipc call dashboard toggle") }
        Repeater {
            model: Cfg.barLeft
            delegate: Loader {
                required property string modelData
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                width: item && item.visible ? item.implicitWidth : 0      // a hidden module (no updates…) takes no room
                sourceComponent: modelData === "barpos" ? mBarpos : modelData === "launcher" ? mLauncher : modelData === "tray" ? mTray
                               : modelData === "windows" ? mWindows : modelData === "minimized" ? mMin : modelData === "track" ? mTrack : null
            }
        }
        Component { id: mBarpos
            BarBtn { bar: li.bar; glyph: li.atBottom ? "\uf077" : "\uf078"; tint: tb.cMuted; tip: li.atBottom ? "Bar to the top" : "Bar to the bottom"
                onClicked: tb.run(tb.sc + "barpos.sh " + (li.atBottom ? "top" : "bottom")) } }
        Component { id: mLauncher
            BarBtn { bar: li.bar; glyph: "\uf303"; tint: tb.cAccent; tip: Cfg.tr("Start menu")
                onClicked: tb.run(tb.sc + "menu.sh") } }
        Component { id: mTray
            Row {
                spacing: 2
                BarBtn { bar: li.bar; glyph: "\uf077"; tint: tb.cMuted; tip: "Hidden tray icons"
                    onClicked: m => tb.run(m.button === Qt.RightButton ? "qs ipc call tray edit" : "qs ipc call tray toggle") }
                Repeater {      // pinned tray icons
                    model: tb.tray ? tb.tray.slots : []
                    delegate: Item {
                        id: ts
                        required property var modelData
                        implicitWidth: tbtn.implicitWidth; implicitHeight: tbtn.implicitHeight
                        BarBtn {
                            id: tbtn
                            bar: li.bar
                            icon: ts.modelData.icon
                            tip: tb.tray.nameOf(ts.modelData)
                            onClicked: m => {
                                if (m.button === Qt.RightButton) tb.tray.openMenu(ts.modelData);
                                else if (m.button === Qt.MiddleButton) ts.modelData.secondaryActivate();
                                else tb.tray.click(ts.modelData);
                            }
                            onWheel: dy => ts.modelData.scroll(dy * 120, false)
                        }
                    }
                }
            } }
        Component { id: mWindows
            Row {
                spacing: 2
                Rectangle { width: 1; height: 16; color: "#26ffffff"; anchors.verticalCenter: parent.verticalCenter }
                Repeater {      // windows on this monitor
                    model: ToplevelManager.toplevels.values.filter(t => t.screens.some(s => s.name === li.bar.screenName))
                    delegate: Item {
                        id: ws
                        required property var modelData
                        readonly property var entry: DesktopEntries.heuristicLookup(modelData.appId)
                        implicitWidth: wbtn.implicitWidth; implicitHeight: wbtn.implicitHeight
                        BarBtn {
                            id: wbtn
                            bar: li.bar
                            icon: Quickshell.iconPath(ws.entry ? ws.entry.icon : String(ws.modelData.appId || "").toLowerCase(), "application-x-executable")
                            tip: ws.modelData.title || ws.modelData.appId || ""
                            active: ws.modelData.activated
                            onClicked: m => {
                                if (m.button === Qt.MiddleButton) ws.modelData.close();
                                else if (ws.modelData.activated) tb.run(tb.sc + "minimize.sh hide");
                                else if (!(tb.genie && tb.genie.bringBack(ws.modelData))) ws.modelData.activate();
                            }
                        }
                    }
                }
            } }
        Component { id: mMin
            BarBtn {
                bar: li.bar; visible: tb.minimized !== ""
                label: tb.minimized; tint: tb.cAccent; tip: "Minimized windows"
                onClicked: tb.run(tb.sc + "minimize.sh restore")
            } }
        Component { id: mTrack
            BarBtn {
                bar: li.bar; visible: tb.player !== null
                icon: tb.player && Cfg.mo("track", "art") ? (tb.player.trackArtUrl || "") : ""
                glyph: Cfg.mo("track", "art") || Cfg.mo("track", "text") ? "" : "\uf001"
                label: { if (!Cfg.mo("track", "text")) return ""; const t = tb.player ? (tb.player.trackArtist || tb.player.trackTitle || tb.player.identity || "") : ""; return t.length > 22 ? t.slice(0, 21) + "…" : t; }
                tip: tb.player ? [tb.player.trackTitle, tb.player.trackArtist].filter(x => x).join(" - ") || tb.player.identity : ""
                color: hot ? Cfg.acc(0.22) : "#12ffffff"
                onClicked: m => { if (m.button === Qt.MiddleButton) tb.player.togglePlaying(); else tb.run("qs ipc call media toggle"); }
                onWheel: dy => { if (dy > 0) tb.player.previous(); else tb.player.next(); }
            } }
    }
    component RightItems: Row {     // the indicators - order: Settings > Taskbar
        id: ri
        property var bar
        spacing: 2
        Repeater {
            model: Cfg.barRight
            delegate: Loader {
                required property string modelData
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                width: item && item.visible ? item.implicitWidth : 0      // a hidden module (no updates…) takes no room
                sourceComponent: ({ capture: r_capture, layout: r_layout, volume: r_volume, network: r_network, cpu: r_cpu,
                                    ram: r_ram, updates: r_updates, notify: r_notify, devices: r_devices, power: r_power })[modelData] || null
            }
        }
        Component { id: r_capture
            BarBtn {
                bar: ri.bar; visible: tb.capture.text !== ""
                glyph: tb.capture.text; tip: tb.capture.tip
                tint: tb.capture.cls === "rec" ? "#f28fad" : tb.cAccent
                onClicked: tb.run("qs ipc call capture toggle")
            }
        }
        Component { id: r_layout
            BarBtn {
                bar: ri.bar; visible: tb.layout.text !== ""
                label: Cfg.mo("layout", "long") && tb.layout.tip ? tb.layout.tip : tb.layout.text; tip: tb.layout.tip
                onClicked: tb.run("hyprctl switchxkblayout all next")
            }
        }
        Component { id: r_volume
            BarBtn {
                id: volBtn
                bar: ri.bar
                glyph: tb.muted ? "" : (tb.vol < 0.34 ? "" : tb.vol < 0.67 ? "" : "")
                tint: tb.muted ? tb.cMuted : tb.cFg
                label: tb.muted ? (Cfg.mo("volume", "pct") ? "mute" : "") : Cfg.mo("volume", "pct") ? Math.round(tb.vol * 100) + "%" : ""
                tip: tb.sink ? (tb.sink.description || tb.sink.name) : ""
                onClicked: m => { if (m.button === Qt.RightButton) { if (tb.sink && tb.sink.audio) tb.sink.audio.muted = !tb.sink.audio.muted; } else tb.openUnder(tb.mixer, ri.bar, volBtn); }
                onWheel: dy => { if (tb.sink && tb.sink.audio) tb.sink.audio.volume = Math.max(0, Math.min((Cfg.data.volMax || 100) / 100, tb.sink.audio.volume + dy * (Cfg.data.volStep || 5) / 100)); }
            }
        }
        Component { id: r_network
            BarBtn {
                id: netBtn
                bar: ri.bar
                glyph: tb.net.kind === "eth" ? "\u{F0200}" : tb.net.kind === "wifi" ? "" : "\u{F0C9B}"
                tint: tb.net.kind === "off" ? tb.cMuted : tb.cFg
                label: Cfg.mo("network", "name") ? tb.net.name : ""
                tip: tb.net.kind === "eth" ? "Cable · " + tb.net.name : tb.net.kind === "wifi" ? "Wi-Fi · " + tb.net.name : "Offline"
                onClicked: tb.openUnder(tb.netMenu, ri.bar, netBtn)
            }
        }
        Component { id: r_cpu
            BarBtn { bar: ri.bar; glyph: ""; label: Cfg.mo("cpu", "pct") ? tb.cpu + "%" : ""; tip: "CPU · " + tb.cpu + "%"; onClicked: tb.run("~/.local/bin/taskmgr cpu") }
        }
        Component { id: r_ram
            BarBtn { bar: ri.bar; glyph: "\u{F035B}"; label: Cfg.mo("ram", "pct") ? tb.mem + "%" : ""; tip: tb.mem + "% · RAM · " + tb.memTip; onClicked: tb.run("~/.local/bin/taskmgr mem") }
        }
        Component { id: r_updates
            BarBtn {
                bar: ri.bar; visible: tb.updates.text !== ""
                glyph: ""; tint: tb.cAccent; label: tb.updates.text
                tip: tb.updates.tip
                onClicked: m => { if (m.button === Qt.RightButton) updProc.running = true; else tb.run(tb.sc + "updates.sh install"); }
            }
        }
        Component { id: r_notify
            BarBtn {
                id: bellBtn
                bar: ri.bar
                glyph: tb.dnd ? "" : ""
                tint: tb.notifDot ? tb.cAccent : tb.cFg
                label: Cfg.mo("notify", "count") && Notifs.unread > 0 ? String(Notifs.unread) : ""
                tip: tb.dnd ? "Do not disturb" : "Notifications"
                onClicked: m => { if (m.button === Qt.RightButton) Notifs.toggleDnd(); else tb.openUnder(tb.notifCenter, ri.bar, bellBtn); }
            }
        }
        Component { id: r_devices        // battery of wireless headset / mouse / keyboard (Devices.qml); nothing known = nothing shown
            Row {
                spacing: 2
                Repeater {
                    model: Devices.ids
                    BarBtn {
                        required property string modelData
                        readonly property var d: Devices.map[modelData] || null
                        bar: ri.bar; visible: Devices.wanted(d)
                        glyph: d ? Devices.glyph(d.kind) : ""
                        tint: !d ? tb.cFg : d.charging ? tb.cAccent : (d.percent !== undefined && d.percent < Devices.low) ? "#f28fad" : d.percent === undefined ? tb.cMuted : tb.cFg
                        label: d && Cfg.mo("devices", "pct") && d.percent !== undefined ? d.percent + "%" : ""
                        tip: Devices.tip
                        onClicked: Devices.poll()
                    }
                }
            }
        }
        Component { id: r_power
            BarBtn { id: pwrBtn; bar: ri.bar; glyph: ""; tint: tb.cAccent; tip: "Power"; onClicked: tb.openUnder(tb.powerMenu, ri.bar, pwrBtn) }
        }
    }

    // Hyprland fades the Top layer out under a fullscreen window and back in after. When a game goes fullscreen
    // for a moment while starting (CS2's shader step) the fade-in sometimes never comes: the bar stays mapped
    // with alpha 0 until the shell restarts. After such events check `hyprctl layers` and remap a bar that is
    // still invisible on a monitor with no fullscreen window.
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (/^(fullscreen|closewindow|openwindow|movewindow|workspace|focusedmon|activewindow)/.test(e.name)) layerCheckT.restart();
        }
    }
    Timer { id: layerCheckT; interval: 1200; onTriggered: if (!layerCheck.running) layerCheck.running = true }
    Process {
        id: layerCheck
        command: ["sh", "-c", "hyprctl layers -j; echo; echo '@@'; hyprctl monitors -j; echo '@@'; hyprctl workspaces -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parts = this.text.split("@@");
                    const layers = JSON.parse(parts[0]), mons = JSON.parse(parts[1]), wss = JSON.parse(parts[2]);
                    const fsWs = new Set(wss.filter(w => w.hasfullscreen).map(w => w.id));
                    for (const m of mons) {
                        if (fsWs.has(m.activeWorkspace.id)) continue;
                        const lv = (layers[m.name] || {}).levels || {};
                        const dead = Object.values(lv).some(ls => ls.some(l => l.namespace === "topbar" && l.alpha < 0.05));
                        if (!dead) continue;
                        for (const w of bars.instances) if (w.screenName === m.name && w.visible) {
                            console.log("[topbar] layer stuck at alpha 0 on " + m.name + ", remapping");
                            w.kick = true; Qt.callLater(() => { w.kick = false; });
                        }
                    }
                } catch (x) {}
            }
        }
    }
    Component.onCompleted: layerCheckT.restart()

    Variants {
        id: bars
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            readonly property string screenName: modelData.name
            screen: modelData
            property bool kick: false        // remap once when Hyprland left this layer faded out (see layerCheck)
            visible: !kick && !(tb.barBottom && modelData.name === Cfg.mainName)
            anchors { top: true; left: true; right: true }
            implicitHeight: tb.deep + 44            // room for the tip under the bar (not clickable, see mask)
            exclusiveZone: tb.deep
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "topbar"
            mask: Region { item: Choreo.still ? hitRegion : null }
            // login / restart / leaving (Choreo.qml): the whole bar flows down out of the top edge and back
            Binding { target: win.contentItem; property: "y"; value: -Math.round((1 - Choreo.bar) * (tb.deep + 4)) }

            // the dashboard or the tray flyout is on this screen: it has taken the bar's shape over and morphs
            // it (see drawShape), so the bar itself is gone meanwhile - at once, else two shapes would show
            readonly property bool dropped:
                (!!tb.dashboard && tb.dashboard.covering === modelData.name) ||
                [tb.tray, tb.mixer, tb.netMenu, tb.powerMenu, tb.notifCenter, tb.camPanel].some(m => !!m && m.covering === modelData.name)
            onDroppedChanged: if (dropped) { open = false; hotItem = null; tipText = ""; }

            // a gulp: the notch swells for a moment and springs back (Genie.qml: a window flies in or out of it)
            property real gulpV: 0
            function doGulp() { gulpAnim.restart(); }
            // the shape exactly as drawn now (gulp included). The gulp deepens the notch; with the wings folded the
            // sides must deepen with it, else the corner stops at the old height and an S-step shows under the ears
            // (and an inverted one on the elastic bounce back). Genie.qml masks the flying window with this too.
            readonly property var drawGeo: {
                const gv = gulpV, dd = gv * 7;
                return { xl: xl - gv * 12, xr: xr + gv * 12, x0: x0 - gv * 12, x1: x1 + gv * 12,
                         wh: wh + dd * (1 - p), d: tb.deep + dd + ext, r: tb.wingR };
            }
            SequentialAnimation {
                id: gulpAnim
                NumberAnimation { target: win; property: "gulpV"; to: 1; duration: 110 * Cfg.anim; easing.type: Easing.OutQuad }
                NumberAnimation { target: win; property: "gulpV"; to: 0; duration: 520 * Cfg.anim; easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.45 }
            }

            // 0 = only the clock, 1 = both wings out
            property bool open: false
            property real p: open || Cfg.barAlways ? 1 : 0
            Behavior on p { NumberAnimation { duration: 340 * Cfg.anim; easing.type: Easing.OutCubic } }
            // close only when the mouse is neither on the bar nor on one of its buttons (a button takes the
            // hover from the bar's own MouseArea, so each one reports itself through hover())
            Timer {
                id: closeT; interval: 450
                onTriggered: if (!barHover.containsMouse && !win.hotItem) { win.open = false; win.tipText = ""; }
            }

            // the notch speaks (Notch.qml): an OSD level or a notice on this screen - it grows deeper by ext and
            // wider to the content, shows it under the clock, then folds back. fmode keeps what it showed while folding.
            readonly property bool flash: Notch.active && Notch.screen === screenName && !dropped && visible
            property string fmode: "osd"
            Connections { target: Notch; function onSerialChanged() { if (Notch.screen === win.screenName) win.fmode = Notch.mode; } }
            property real fq: flash ? 1 : 0
            Behavior on fq { NumberAnimation { duration: (win.flash ? 360 : 300) * Cfg.anim; easing.type: win.flash ? Easing.OutBack : Easing.InOutCubic; easing.overshoot: 1.2 } }
            property real fh: flashRow.implicitWidth / 2 + 24          // half width the content needs
            Behavior on fh { NumberAnimation { duration: 220 * Cfg.anim; easing.type: Easing.OutCubic } }
            readonly property real ext: 34 * fq
            // the rest design draws only after the notch has settled (comet runs, tide waves under the mouse)
            property real cometT: tb.hourFrac
            Behavior on cometT { NumberAnimation { duration: 1400; easing.type: Easing.InOutCubic } }
            property real tidePh: 0
            NumberAnimation on tidePh { running: tb.face === "tide" && win.open && win.visible; from: 0; to: Math.PI * 2; duration: 3400; loops: Animation.Infinite }

            readonly property real cx: Math.round(width / 2)
            readonly property real nh0: Math.round(clockRow.implicitWidth / 2) + 18
            // a live activity (Notch.act: music, timer, rec…) sits beside the clock: the notch grows by aw on
            // both sides (the clock stays in the middle). An OSD / notice takes over (aq → 0), then it comes back.
            readonly property bool liveOn: Notch.act !== "" && visible
            property real aq: liveOn && !flash ? 1 : 0
            Behavior on aq { NumberAnimation { duration: 340 * Cfg.anim; easing.type: Easing.InOutCubic } }
            property string lact: Notch.act      // what it shows (kept while it folds away)
            Connections { target: Notch; function onActChanged() { if (Notch.act !== "") win.lact = Notch.act; } }
            // each side as wide as its own content (the clock stays put): no empty glass on the narrower side
            property real aw: liveL.implicitWidth + 8          // left side (icon / cover)
            property real awR: liveR.implicitWidth + 8         // right side (value / bars, +N)
            readonly property bool liveHot: liveLma.containsMouse || liveRma.containsMouse || plusMa.containsMouse   // lights the notch like the clock
            function liveClick(m, btn) {
                const a = lact;
                if (a === "music" && m.button === Qt.MiddleButton) { if (Notch.player) Notch.player.togglePlaying(); }
                else if (a === "music") tb.openMusic();
                else if (a === "rec" || a === "replay") tb.run("qs ipc call capture toggle");
                else if (a === "timer") tb.run("qs ipc call dashboard open timers");
                else if (a === "mic") tb.openUnder(tb.mixer, win, btn);
                else if (a === "cam" && m.button === Qt.MiddleButton) CamLink.stream(!CamLink.want);
                else if (a === "cam") tb.openUnder(tb.camPanel, win, btn);
            }
            Behavior on aw { NumberAnimation { duration: 260 * Cfg.anim; easing.type: Easing.OutCubic } }
            Behavior on awR { NumberAnimation { duration: 260 * Cfg.anim; easing.type: Easing.OutCubic } }
            readonly property real nhA: nh0 + aw * aq          // left half
            readonly property real nhAR: nh0 + awR * aq        // right half
            readonly property real nh: nhA + Math.max(0, fh - nhA) * Math.min(1, fq)
            readonly property real nhR: nhAR + Math.max(0, fh - nhAR) * Math.min(1, fq)
            readonly property real x0: cx - nh
            readonly property real x1: cx + nhR
            readonly property real lw: leftRow.implicitWidth + 18
            readonly property real rw: rightRow.implicitWidth + 18
            readonly property real wh: tb.deep - (tb.deep - tb.wingH) * p + ext * (1 - p)   // wing height: deep → wingH
            readonly property real xl: x0 - tb.sW - lw * p                     // outer end of the left wing
            readonly property real xr: x1 + tb.sW + rw * p

            // a button under the mouse: keeps the bar open and shows its tip under the bar
            property var hotItem: null
            property string tipText: ""
            property real tipX: 0
            function hover(item, on) {
                if (on) {
                    hotItem = item; closeT.stop(); open = true;
                    tipText = item.tip; tipX = item.mapToItem(null, item.width / 2, 0).x;
                } else {
                    if (hotItem === item) hotItem = null;
                    if (tipText === item.tip) tipText = "";
                    closeT.restart();
                }
            }

            // what takes the mouse: the whole shape
            Item { id: hitRegion; x: win.xl - tb.earW; width: win.xr - win.xl + 2 * tb.earW; height: tb.deep + win.ext }

            // the bar itself (the shape between the buttons)
            MouseArea {
                id: barHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                enabled: !win.dropped
                visible: !win.dropped
                onContainsMouseChanged: {
                    if (containsMouse) { closeT.stop(); win.open = true; }
                    else closeT.restart();
                }
                // wheel on the empty bar (Settings > Taskbar): volume, workspaces or nothing
                onWheel: w => {
                    const up = w.angleDelta.y > 0, act = Cfg.data.barWheel || "volume";
                    if (act === "volume" && tb.sink && tb.sink.audio) tb.sink.audio.volume = Math.max(0, Math.min((Cfg.data.volMax || 100) / 100, tb.sink.audio.volume + (up ? 1 : -1) * (Cfg.data.volStep || 5) / 100));
                    else if (act === "workspace") Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = '" + (up ? "e-1" : "e+1") + "' })"]);
                }

                Canvas {
                    anchors.fill: parent
                    readonly property string key: [win.p, win.lw, win.rw, win.nh, win.nhR, width, Cfg.glass, win.gulpV, win.ext, tb.face,
                                                    tb.face === "comet" ? win.cometT : 0, tb.face === "tide" ? tb.dayFrac + "," + win.tidePh : 0, Cfg.accent].join(",")
                    onKeyChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const g = win.drawGeo;        // the gulp swells the notch: wider and deeper
                        tb.drawShape(ctx, g);
                        const a = 1 - Math.min(1, win.fq);          // the rest design steps aside while the notch speaks
                        if (a <= 0.01 || (tb.face !== "comet" && tb.face !== "tide")) return;
                        ctx.save();
                        tb.shapePath(ctx, g);
                        ctx.clip();
                        const A = c => Cfg.acc(c * a);
                        if (tb.face === "comet") {
                            // along the notch's lower edge, left → right over the hour; a fading tail behind it
                            const l = g.x0 + 4, rr = g.x1 - 4, x = l + (rr - l) * win.cometT, y = g.d - 1.5, tl = Math.min(56, x - l + 1);
                            const tail = ctx.createLinearGradient(x - tl, y, x, y);
                            tail.addColorStop(0, A(0)); tail.addColorStop(1, A(0.85));
                            ctx.strokeStyle = tail; ctx.lineWidth = 2; ctx.lineCap = "round";
                            ctx.beginPath(); ctx.moveTo(x - tl, y); ctx.lineTo(x, y); ctx.stroke();
                            const glow = ctx.createRadialGradient(x, y, 0, x, y, 11);
                            glow.addColorStop(0, A(0.9)); glow.addColorStop(0.35, A(0.35)); glow.addColorStop(1, A(0));
                            ctx.fillStyle = glow; ctx.beginPath(); ctx.arc(x, y, 11, 0, Math.PI * 2); ctx.fill();
                        } else {
                            // water up to how far the day is; two soft waves (they move only while the bar is hovered)
                            const top = g.d - (g.d - 3) * tb.dayFrac, ph = win.tidePh, L = g.xl - tb.earW, R = g.xr + tb.earW;
                            const wave = (amp, k, off, alpha, line) => {
                                ctx.beginPath();
                                for (let xx = L; xx <= R + 6; xx += 6) ctx.lineTo(xx, top + amp * Math.sin(xx * k + ph + off));
                                if (line) { ctx.strokeStyle = A(0.5); ctx.lineWidth = 1.2; ctx.stroke(); }
                                ctx.lineTo(R + 6, g.d + 2); ctx.lineTo(L, g.d + 2); ctx.closePath();
                                const wg = ctx.createLinearGradient(0, top - amp, 0, g.d);
                                wg.addColorStop(0, A(alpha)); wg.addColorStop(1, A(alpha * 0.4));
                                ctx.fillStyle = wg; ctx.fill();
                            };
                            wave(1.6, 0.07, 2.1, 0.13, false);
                            wave(2.2, 0.045, 0, 0.2, true);
                        }
                        ctx.restore();
                    }
                }

                // ── the clock (never moves) ─────────────────
                Rectangle {
                    id: clockBox
                    readonly property string tip: Cfg.dateLong(clock.date)
                    x: win.x0 + 6; y: 5; width: win.x1 - win.x0 - 12; height: tb.deep - 10
                    radius: 12
                    color: ca.containsMouse || win.liveHot ? Cfg.acc(0.18) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                        id: clockRow
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: (win.nh - win.nhR) / 2      // the notch may be lopsided: the clock stays at the screen's centre
                        spacing: 8
                        Text { text: tb.timeText; color: ca.containsMouse ? tb.cAccent : tb.cFg; font.family: tb.fUi; font.pixelSize: 13; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: tb.dateText; color: "#a9adbd"; font.family: tb.fUi; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        Canvas {        // "rings" rest design: day · week · month
                            visible: tb.face === "rings"
                            width: visible ? 44 : 0; height: 12
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property string key: [tb.dayFrac, tb.weekFrac, tb.monthFrac, Cfg.accent, visible].join(",")
                            onKeyChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                if (!visible) return;
                                [tb.dayFrac, tb.weekFrac, tb.monthFrac].forEach((f, i) => {
                                    const x = 6 + i * 16, y = 6, r = 4.6;
                                    ctx.lineWidth = 2; ctx.lineCap = "round";
                                    ctx.strokeStyle = "#24ffffff";
                                    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.stroke();
                                    ctx.strokeStyle = Cfg.acc(1 - i * 0.22);
                                    ctx.beginPath(); ctx.arc(x, y, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.02, f)); ctx.stroke();
                                });
                            }
                        }
                    }
                    MouseArea {
                        id: ca; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: tb.run("qs ipc call dashboard toggle")
                        onContainsMouseChanged: win.hover(clockBox, containsMouse)
                    }
                }

                // ── what the notch says (Notch.qml): OSD level or a notice, under the clock ──
                Item {
                    id: flashArea
                    visible: win.fq > 0.02
                    onVisibleChanged: if (!visible) Notch.hold(false)     // folded under the cursor: no hover-out comes
                    opacity: Math.max(0, Math.min(1, (win.fq - 0.45) / 0.55))
                    x: win.x0 + 8; width: win.x1 - win.x0 - 16
                    y: tb.deep - 3; height: Math.max(0, win.ext - 3)
                    clip: true
                    Row {
                        id: flashRow
                        anchors.centerIn: parent
                        spacing: 10
                        readonly property bool isOsd: win.fmode === "osd"
                        readonly property color tint: Notch.off && isOsd ? tb.cMuted : tb.cAccent
                        ClippingRectangle {     // a track change: the cover instead of the icon
                            visible: !flashRow.isOsd && Notch.img !== ""
                            width: 20; height: 20; radius: 10; color: "#22ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            Image { anchors.fill: parent; source: parent.visible ? Notch.img : ""; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(48, 48); asynchronous: true }
                        }
                        Text {
                            visible: flashRow.isOsd || Notch.img === ""
                            text: flashRow.isOsd ? Notch.osdGlyph() : Notch.glyph(Notch.kind)
                            color: flashRow.tint; font.family: tb.fIcon; font.pixelSize: 15
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Rectangle {     // the level
                            visible: flashRow.isOsd
                            width: 168; height: 6; radius: 3
                            color: "#22ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                height: parent.height; radius: 3
                                width: Math.max(height, parent.width * Math.min(1, Notch.level))
                                color: flashRow.tint
                                opacity: Notch.off ? 0.45 : 1
                                Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Rectangle {     // over 100 % (volMax): the rest in white
                                visible: Notch.level > 1.001
                                x: parent.width - width; height: parent.height; radius: 3
                                width: Math.min(parent.width, parent.width * (Notch.level - 1))
                                color: "#eceef4"; opacity: 0.8
                            }
                        }
                        Text {
                            visible: flashRow.isOsd
                            width: 38; horizontalAlignment: Text.AlignRight
                            text: Notch.off ? Cfg.tr("mute") : Math.round(Notch.level * 100) + "%"
                            color: Notch.off ? tb.cMuted : tb.cFg; font.family: tb.fUi; font.pixelSize: 12; font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: !flashRow.isOsd
                            text: Cfg.tr(Notch.text)
                            width: Math.min(implicitWidth, 340); elide: Text.ElideRight
                            color: tb.cFg; font.family: tb.fUi; font.pixelSize: 12; font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {     // under the mouse it stays; a click opens the file it is about (a screenshot…) or folds it
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (win.flash || !containsMouse) Notch.hold(containsMouse)
                        onClicked: { if (win.fmode === "notice" && Notch.path !== "") Quickshell.execDetached(["xdg-open", Notch.path]);
                                     else if (win.fmode === "notice" && Notch.kind === "music") tb.openMusic();
                                     Notch.dismiss(); }
                        onWheel: w => { if (win.fmode === "osd" && Notch.osdKind === "volume" && tb.sink && tb.sink.audio)
                            tb.sink.audio.volume = Math.max(0, Math.min((Cfg.data.volMax || 100) / 100, tb.sink.audio.volume + (w.angleDelta.y > 0 ? 1 : -1) * (Cfg.data.volStep || 5) / 100)); }
                    }
                }

                // ── live activity (Notch.qml): left of the clock an icon (music: the cover), right a value
                //    (music: the dancing bars) and "+N" when more go on. Click = open what it is, wheel = the bar's wheel. ──
                Item {
                    id: liveL
                    readonly property string tip: Notch.actTip(win.lact)
                    implicitWidth: win.lact === "music" ? 22 : liveLG.implicitWidth
                    width: implicitWidth; height: 24
                    x: win.cx - clockRow.implicitWidth / 2 - 10 - width; y: tb.deep / 2 - height / 2     // right next to the clock
                    visible: win.aq > 0.02
                    opacity: Math.max(0, Math.min(1, (win.aq - 0.35) / 0.65))
                    ClippingRectangle {
                        visible: win.lact === "music"
                        anchors.centerIn: parent; width: 22; height: 22; radius: 11; color: Cfg.acc(0.22)
                        opacity: Notch.playing ? 1 : 0.55
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        Image { id: liveArt; anchors.fill: parent; source: parent.visible ? Notch.art : ""; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(48, 48); asynchronous: true }
                        Text { anchors.centerIn: parent; visible: liveArt.status !== Image.Ready; text: Notch.glyphs.music; color: tb.cAccent; font.family: tb.fIcon; font.pixelSize: 12 }
                    }
                    Text {
                        id: liveLG
                        visible: win.lact !== "music"
                        anchors.centerIn: parent
                        text: Notch.actGlyph(win.lact)
                        color: win.lact === "rec" ? "#f28fad" : win.lact === "mic" && Notch.micMuted ? tb.cMuted : tb.cAccent
                        font.family: tb.fIcon; font.pixelSize: 15
                    }
                    MouseArea {
                        id: liveLma
                        anchors.fill: parent; anchors.margins: -4
                        hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: win.lact === "share" ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: m => win.liveClick(m, liveL)
                        onWheel: w => tb.wheelAct(w.angleDelta.y > 0)
                        onContainsMouseChanged: win.hover(liveL, containsMouse)
                    }
                }
                Item {
                    id: liveR
                    readonly property string tip: liveL.tip
                    implicitWidth: liveRow.implicitWidth
                    width: implicitWidth; height: 24
                    x: win.cx + win.nhAR - 14 - width; y: tb.deep / 2 - height / 2
                    visible: win.aq > 0.02
                    opacity: liveL.opacity
                    MouseArea {
                        id: liveRma
                        anchors.fill: parent; anchors.margins: -4
                        hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: win.lact === "share" ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: m => win.liveClick(m, liveR)
                        onWheel: w => tb.wheelAct(w.angleDelta.y > 0)
                        onContainsMouseChanged: win.hover(liveR, containsMouse)
                    }
                    Row {
                        id: liveRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Item {      // fixed box: only the heights dance, so neither the notch nor the row re-lays out to the beat
                            visible: win.lact === "music"
                            width: Notch.nBars * 3 + (Notch.nBars - 1) * 2; height: 28
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: Notch.nBars      // a number: the bars are made once, never rebuilt
                                Rectangle {     // exactly like the desktop visualizer widget: a capsule whose height follows cava, 60 ms
                                    required property int index
                                    readonly property real v: Math.max(0, Math.min(1, Notch.bars[index] || 0))
                                    x: index * 5; width: 3; radius: width / 2
                                    antialiasing: true
                                    // mirrored around the middle: the top is exactly half of what is left (sub-pixel, antialiased),
                                    // so it never sticks out more above than below; no pixel snapping, so no 1-2 px hopping
                                    height: 4 + v * (28 - 4)              // a dot … ~70 % of the notch
                                    Behavior on height { NumberAnimation { duration: 90 } }
                                    y: 14 - height / 2
                                    color: tb.cAccent        // = Cfg.accent, like everything in the shell
                                    opacity: Notch.playing ? 1 : 0.4
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                }
                            }
                        }
                        Text {
                            visible: win.lact !== "music" && text !== ""
                            text: Notch.actText(win.lact)
                            width: Math.min(implicitWidth, 120); elide: Text.ElideRight
                            color: tb.cFg; font.family: tb.fUi; font.pixelSize: 12; font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {     // more going on: a click steps to the next one
                            id: livePlus
                            readonly property string tip: Notch.acts.filter(a => a !== win.lact).map(a => Notch.actTip(a)).filter(x => x).join(" · ")
                            visible: Notch.acts.length > 1
                            width: plusT.implicitWidth + 10; height: 16; radius: 8
                            color: plusMa.containsMouse ? Cfg.acc(0.3) : "#1fffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            Text { id: plusT; anchors.centerIn: parent; text: "+" + Math.max(1, Notch.acts.length - 1); color: tb.cFg; font.family: tb.fUi; font.pixelSize: 10; font.weight: Font.Bold }
                            MouseArea {
                                id: plusMa; anchors.fill: parent; anchors.margins: -3
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Notch.cycle()
                                onContainsMouseChanged: win.hover(livePlus, containsMouse)
                            }
                        }
                    }
                }

                // ── left wing: bar position, launcher, tray, windows, track ──
                Item {
                    x: win.xl; width: Math.max(0, win.x0 - tb.sW - win.xl); height: win.wh
                    clip: true
                    opacity: win.p
                    LeftItems {
                        id: leftRow
                        bar: win
                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    }
                }

                // ── right wing: the indicators ──────────────
                Item {
                    x: win.x1 + tb.sW; width: Math.max(0, win.xr - win.x1 - tb.sW); height: win.wh
                    clip: true
                    opacity: win.p
                    RightItems {
                        id: rightRow
                        bar: win
                        anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                    }
                }

                // ── the tip ─────────────────────────────────
                Rectangle {
                    visible: opacity > 0.01
                    opacity: win.tipText !== "" && win.p > 0.9 && win.fq < 0.05 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    x: Math.max(8, Math.min(win.width - width - 8, win.tipX - width / 2))
                    y: tb.deep + 6
                    width: tipLabel.width + 20; height: tipLabel.height + 12
                    radius: 10
                    color: tb.fill; border.width: 1; border.color: "#1fffffff"
                    Text {
                        id: tipLabel
                        anchors.centerIn: parent
                        text: win.tipText
                        width: Math.min(implicitWidth, 560); wrapMode: Text.WordWrap
                        color: tb.cFg; font.family: tb.fUi; font.pixelSize: 12
                        horizontalAlignment: Text.AlignLeft
                    }
                }
            }
        }
    }

    // ── bar at the bottom (barpos.sh, main monitor): two islands on both sides of the dock, growing out of
    //    the bottom edge like the dock itself (concave ears, rounded top); the menus open as cards above ──
    PanelWindow {
        id: bwin
        readonly property string screenName: Cfg.mainName
        screen: Cfg.mainScreen
        visible: tb.barBottom
        anchors { bottom: true; left: true; right: true }
        implicitHeight: ih + 44                    // + room for the tip above
        exclusionMode: ExclusionMode.Ignore        // the dock reserves the row
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "topbar"
        mask: Region { item: Choreo.still ? islL : null; Region { item: Choreo.still ? islR : null } }
        Binding { target: bwin.contentItem; property: "y"; value: Math.round((1 - Choreo.dock) * (bwin.ih + 4)) }   // rises with the dock (Choreo.qml)

        readonly property int ih: 56               // island height (the dock is 60)
        readonly property int edge: 14             // gap to the screen side

        // tips (same as the top bar's, above the islands)
        property var hotItem: null
        property string tipText: ""
        property real tipX: 0
        function hover(item, on) {
            if (on) { hotItem = item; tipText = item.tip; tipX = item.mapToItem(null, item.width / 2, 0).x; }
            else { if (hotItem === item) hotItem = null; if (tipText === item.tip) tipText = ""; }
        }

        Canvas {
            anchors.fill: parent
            readonly property string key: [islL.x, islL.width, islR.x, islR.width, width, height, Cfg.glass].join(",")
            onKeyChanged: requestPaint()
            function island(ctx, x, w) {      // = the dock's bump (shell.qml): ears 22 x 16, corners 24
                const k = 0.5523, ex = tb.earW, ey = tb.earH, r = 24, h = height, top = h - bwin.ih;
                ctx.beginPath();
                ctx.moveTo(x - ex, h);
                ctx.bezierCurveTo(x - ex + ex * k, h, x, h - ey + ey * k, x, h - ey);
                ctx.lineTo(x, top + r);
                ctx.bezierCurveTo(x, top + r - r * k, x + r - r * k, top, x + r, top);
                ctx.lineTo(x + w - r, top);
                ctx.bezierCurveTo(x + w - r + r * k, top, x + w, top + r - r * k, x + w, top + r);
                ctx.lineTo(x + w, h - ey);
                ctx.bezierCurveTo(x + w, h - ey + ey * k, x + w + ex - ex * k, h, x + w + ex, h);
                ctx.closePath();
                ctx.fillStyle = tb.fill;
                ctx.fill();
            }
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                island(ctx, islL.x, islL.width);
                island(ctx, islR.x, islR.width);
            }
        }

        Item {
            id: islL
            x: bwin.edge + tb.earW; y: parent.height - bwin.ih
            width: leftB.implicitWidth + 24; height: bwin.ih
            LeftItems { id: leftB; bar: bwin; atBottom: true; anchors.centerIn: parent }
        }
        Item {
            id: islR
            x: parent.width - bwin.edge - tb.earW - width; y: parent.height - bwin.ih
            width: rightB.implicitWidth + 24; height: bwin.ih
            RightItems { id: rightB; bar: bwin; anchors.centerIn: parent }
        }

        Rectangle {
            visible: opacity > 0.01
            opacity: bwin.tipText !== "" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            x: Math.max(8, Math.min(bwin.width - width - 8, bwin.tipX - width / 2))
            y: parent.height - bwin.ih - height - 6
            width: btipLabel.width + 20; height: btipLabel.height + 12
            radius: 10
            color: tb.fill; border.width: 1; border.color: "#1fffffff"
            Text {
                id: btipLabel
                anchors.centerIn: parent
                text: bwin.tipText
                width: Math.min(implicitWidth, 560); wrapMode: Text.WordWrap
                color: tb.cFg; font.family: tb.fUi; font.pixelSize: 12
                horizontalAlignment: Text.AlignLeft
            }
        }
    }
}
