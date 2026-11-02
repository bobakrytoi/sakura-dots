//@ pragma UseQApplication
// sakura mono — start menu (opens on the Win key)
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // ── palette ─────────────────────────────────────────────
    readonly property color cBg:      "#e60f1119"
    readonly property color cCard:    "#14ffffff"
    readonly property color cHover:   "#22ffffff"
    readonly property color cBorder:  "#1fffffff"
    readonly property color cFg:      "#eceef4"
    readonly property color cMuted:   "#8a8fa3"
    readonly property color cAccent:  "#f2b8d0"
    readonly property color cAccFg:   "#1a121a"
    readonly property string fUi:     "Inter"
    readonly property string fIcon:   "Symbols Nerd Font"
    readonly property string home:    Quickshell.env("HOME")
    readonly property string user:    Quickshell.env("USER")

    Settings { id: settings }
    Switcher { id: switcher }
    Capture { id: capture }
    Media { id: media }
    Dashboard { id: dashboard }
    Mixer { id: mixer }
    DesktopWidgets { id: desktopWidgets }
    Snap { id: snap }

    property bool open: false
    // the monitor the menu opens on: the one you are using right now
    property var menuScreen: Quickshell.screens.find(s => s.name === "DP-3") || Quickshell.screens[0]
    property bool fsUnder: false     // a fullscreen app (game) is under the menu
    function pickScreen() {
        const m = Hyprland.focusedMonitor;
        const sc = m ? Quickshell.screens.find(s => s.name === m.name) : null;
        if (sc) menuScreen = sc;
        fsProc.running = true;
    }
    Process {
        id: fsProc
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { root.fsUnder = JSON.parse(this.text).hasfullscreen === true; } catch (e) { root.fsUnder = false; } } }
    }
    readonly property bool menuOnMain: menuScreen && menuScreen.name === "DP-3"
    property bool allApps: false

    property real openedAt: 0
    property bool grabOn: false
    function show()   { pickScreen(); search.text = ""; allApps = false; openedAt = Date.now(); open = true; grabOn = true; }
    function hide()   { open = false; mctxOpen = false; grabOn = false; }
    function toggle() { open ? hide() : show(); }
    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); hide(); }

    IpcHandler {
        target: "menu"
        function toggle(): void { root.toggle(); }
        function open(): void   { root.show(); }
        function close(): void  { root.hide(); }
        function query(q: string): void { root.show(); search.text = q; }
        function menuctx(i: int): void { root.show(); root.openMctx(root.pinned[i], Qt.point(140, 260)); }
        function dockctx(i: int): void { root.ctxApp = root.dockApps[i]; root.ctxX = 480; root.ctxOpen = true; }
    }

    // ── live state ──────────────────────────────────────────
    PwObjectTracker { objects: [ Pipewire.defaultAudioSink ] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var player: Mpris.players.values.find(p => !String(p.dbusName || "").includes("playerctld")) || null

    property bool vpnOn: false
    property string vpnText: "VPN"
    property bool dndOn: false
    property string uptime: ""

    Process {
        id: vpnProc
        command: ["sh", "-c", "mullvad status 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                root.vpnOn = t.startsWith("Connected");
                root.vpnText = t.startsWith("Connected") ? "VPN on" : (t.startsWith("Connecting") ? "VPN…" : "VPN off");
            }
        }
    }
    Process {
        id: dndProc
        command: ["swaync-client", "-D"]
        stdout: StdioCollector { onStreamFinished: root.dndOn = this.text.trim() === "true" }
    }
    Process {
        id: upProc
        command: ["sh", "-c", "uptime -p | sed 's/^up //'"]
        stdout: StdioCollector { onStreamFinished: root.uptime = this.text.trim() }
    }
    Timer {
        interval: 2000; running: root.open; repeat: true; triggeredOnStart: true
        onTriggered: { vpnProc.running = true; dndProc.running = true; upProc.running = true; }
    }

    // ── apps ────────────────────────────────────────────────
    property var menuPinned: [
        "brave-browser", "firefox", "org.gnome.Nautilus", "kitty", "discord", "code-oss",
        "org.gnome.TextEditor", "org.gnome.Calculator", "org.gnome.Loupe", "mpv",
        "mullvad-vpn", "btop"
    ]
    FileView {
        id: menuFile
        path: root.home + "/.config/quickshell/menu.json"
        blockLoading: true
        onLoaded: { try { const j = JSON.parse(text()); if (Array.isArray(j.pinned)) root.menuPinned = j.pinned; } catch (e) {} }
    }
    function menuIsPinned(id) { return menuPinned.indexOf(id) >= 0; }
    function menuTogglePin(id) {
        const l = menuIsPinned(id) ? menuPinned.filter(x => x !== id) : menuPinned.concat([id]);
        menuPinned = l; menuFile.setText(JSON.stringify({ pinned: l }, null, 2));
    }
    // start-menu right-click
    property var mctxApp: null
    property point mctxPos: Qt.point(0, 0)
    property bool mctxOpen: false
    function openMctx(app, pos) { mctxApp = app; mctxPos = pos; mctxOpen = true; }
    readonly property var everyApp: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .slice().sort((a, b) => a.name.localeCompare(b.name))
    readonly property var pinned: menuPinned.map(id => everyApp.find(e => e.id === id)).filter(e => e)
    readonly property var results: {
        const q = search.text.trim().toLowerCase();
        if (q === "") return everyApp;
        return everyApp.filter(e =>
            e.name.toLowerCase().includes(q) ||
            (e.genericName || "").toLowerCase().includes(q) ||
            (e.keywords || []).join(" ").toLowerCase().includes(q));
    }
    readonly property bool searching: search.text.trim() !== ""


    // ── smart search: calculator, currency, commands, apps, files, web ──
    property int selIndex: 0
    property var fx: null                       // currency rates (base USD)
    Process {
        id: fxProc
        command: ["curl", "-s", "--max-time", "6", "https://open.er-api.com/v6/latest/USD"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(this.text); if (d.rates) root.fx = d.rates; } catch (e) {} } }
    }
    property var fileHits: []
    property string fileQuery: ""
    Process {
        id: findProc
        stdout: StdioCollector { onStreamFinished: root.fileHits = this.text.split("\n").filter(x => x !== "").slice(0, 8) }
    }
    Timer {
        id: findTimer; interval: 280
        onTriggered: {
            const q = search.text.trim();
            if (q.length < 3 || root.calcValue(q) !== null) { root.fileHits = []; return; }
            root.fileQuery = q;
            findProc.running = false;
            findProc.command = ["sh", "-c",
                "timeout 2 find \"$HOME\" -maxdepth 6 \\( -path '*/.*' -o -path '*/node_modules' \\) -prune -o -iname \"*$1*\" -print 2>/dev/null | head -8; " +
                "timeout 2 find /mnt -maxdepth 4 -iname \"*$1*\" -print 2>/dev/null | head -6", "sh", q];
            findProc.running = true;
        }
    }
    Connections { target: search; function onTextChanged() { root.selIndex = 0; findTimer.restart(); if (!root.fx && /[a-z]{3}\s*(to|in|в)\s*[a-z]{3}/i.test(search.text)) fxProc.running = true; } }

    function calcValue(q) {
        let e = q.replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/").replace(/\^/g, "**").toLowerCase();
        e = e.replace(/(\d+(?:\.\d+)?)\s*%\s*(of|от)\s*(\d+(?:\.\d+)?)/g, "($1/100*$3)");
        if (!/[\d)]/.test(e) || !/[-+*/%()]|sqrt|sin|cos|tan|log|pi/.test(e)) return null;
        if (!/^[\d\s.+\-*/%()a-z]+$/.test(e)) return null;
        const names = ["sqrt","sin","cos","tan","log","pi","abs","round","floor","ceil","pow"];
        const words = e.match(/[a-z]+/g) || [];
        if (words.some(w => names.indexOf(w) < 0)) return null;
        e = e.replace(/\b(sqrt|sin|cos|tan|abs|round|floor|ceil|pow)\b/g, "Math.$1").replace(/\blog\b/g, "Math.log10").replace(/\bpi\b/g, "Math.PI");
        try { const v = Function("return (" + e + ")")(); return (typeof v === "number" && isFinite(v)) ? v : null; } catch (err) { return null; }
    }
    function fmtNum(v) { return Math.abs(v) >= 1e15 || (Math.abs(v) < 1e-6 && v !== 0) ? v.toExponential(6) : String(Math.round(v * 1e8) / 1e8); }
    function fxConvert(q) {
        const m = q.match(/^\s*(\d+(?:[.,]\d+)?)\s*([a-z]{3})\s*(?:to|in|в|->)\s*([a-z]{3})\s*$/i);
        if (!m || !fx) return null;
        const a = parseFloat(m[1].replace(",", ".")), f = m[2].toUpperCase(), t = m[3].toUpperCase();
        if (!fx[f] || !fx[t]) return null;
        return { text: (Math.round(a / fx[f] * fx[t] * 100) / 100).toLocaleString(Qt.locale("en_US"), "f", 2) + " " + t, sub: a + " " + f + " → " + t };
    }
    readonly property var commands: [
        { k: ["lock", "блок", "заблок"],            t: "Lock screen",      g: "\uf023", run: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
        { k: ["reboot", "restart", "перезагр"],      t: "Restart",          g: "\uf01e", run: () => Quickshell.execDetached(["sh", "-c", root.home + "/.config/hypr/scripts/session.py save; systemctl reboot"]) },
        { k: ["shutdown", "power off", "poweroff", "выключ"], t: "Shut down", g: "\uf011", run: () => Quickshell.execDetached(["sh", "-c", root.home + "/.config/hypr/scripts/session.py save; systemctl poweroff"]) },
        { k: ["sleep", "suspend", "сон", "спать"],   t: "Sleep",            g: "\uf186", run: () => Quickshell.execDetached(["systemctl", "suspend"]) },
        { k: ["logout", "log out", "выход", "выйти"], t: "Log out",         g: "\uf08b", run: () => Quickshell.execDetached(["sh", "-c", "uwsm stop || hyprctl dispatch 'hl.dsp.exit()'"]) },
        { k: ["settings", "настройк", "параметр"],  t: "Settings",         g: "\uf013", run: () => settings.openPage("sound") },
        { k: ["sound", "звук", "audio", "громк"],    t: "Sound settings",   g: "\uf028", run: () => settings.openPage("sound") },
        { k: ["display", "monitor", "монитор", "экран"], t: "Displays",     g: "\uf108", run: () => settings.openPage("display") },
        { k: ["color", "vibrance", "цвет"],          t: "Color Control",    g: "\uf042", run: () => settings.openPage("color") },
        { k: ["rgb", "light", "подсвет"],            t: "Lighting",         g: "\uf0eb", run: () => settings.openPage("lighting") },
        { k: ["wifi", "network", "сеть", "vpn"],     t: "Network & VPN",    g: "\uf0e8", run: () => settings.openPage("network") },
        { k: ["screenshot", "скрин"],                t: "Screenshot",       g: "\uf030", run: () => Quickshell.execDetached(["sh", "-c", "sleep 0.4; " + root.home + "/.config/hypr/scripts/screenshot.sh region"]) },
        { k: ["record", "replay", "clip", "запис", "клип"], t: "Capture (Alt+Z)", g: "\uf03d", run: () => Quickshell.execDetached(["qs", "ipc", "call", "capture", "open"]) },
        { k: ["weather", "погод"],                   t: "Weather",          g: "\uf0c2", run: () => Quickshell.execDetached(["qs", "ipc", "call", "dashboard", "open", "weather"]) },
        { k: ["clipboard", "буфер"],                 t: "Clipboard history", g: "\uf0ea", run: () => Quickshell.execDetached([root.home + "/.config/hypr/scripts/clipboard.sh"]) },
        { k: ["keybind", "hotkey", "клавиш"],        t: "Keybinds",         g: "\uf11c", run: () => Quickshell.execDetached([root.home + "/.config/hypr/scripts/keybinds.sh"]) }
    ]
    readonly property var items: {
        const raw = search.text.trim(), q = raw.toLowerCase();
        const out = [];
        if (q === "") return everyApp.map(e => ({ kind: "app", entry: e, title: e.name, sub: e.genericName || "" }));
        const v = calcValue(raw);
        if (v !== null) out.push({ kind: "calc", title: "= " + fmtNum(v), sub: "Enter to copy", glyph: "", copy: fmtNum(v) });
        const c = fxConvert(raw);
        if (c) out.push({ kind: "calc", title: c.text, sub: c.sub + " · Enter to copy", glyph: "\uf155", copy: c.text });
        else if (/^\s*\d+(?:[.,]\d+)?\s*[a-z]{3}\s*(to|in|в|->)\s*[a-z]{3}\s*$/i.test(raw) && !fx)
            out.push({ kind: "info", title: "Getting exchange rates…", sub: "", glyph: "\uf021" });
        commands.forEach(cm => { if (cm.k.some(k => k.startsWith(q) || q.startsWith(k))) out.push({ kind: "cmd", title: cm.t, sub: "command", glyph: cm.g, run: cm.run }); });
        results.slice(0, 8).forEach(e => out.push({ kind: "app", entry: e, title: e.name, sub: e.genericName || "" }));
        fileHits.forEach(f => out.push({ kind: "file", path: f, title: f.split("/").pop(), sub: f.replace(root.home, "~"), glyph: "\uf15b" }));
        out.push({ kind: "web", title: "Search the web for “" + raw + "”", sub: "", glyph: "\uf002", q: raw });
        return out;
    }
    function runItem(it, alt) {
        if (!it) return;
        if (it.kind === "app") it.entry.execute();
        else if (it.kind === "calc") Quickshell.execDetached(["wl-copy", it.copy]);
        else if (it.kind === "cmd") it.run();
        else if (it.kind === "file") Quickshell.execDetached(["xdg-open", alt ? it.path.replace(/\/[^/]*$/, "") : it.path]);
        else if (it.kind === "web") Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(it.q)]);
        else return;
        root.hide();
    }

    // ── window ──────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.open
        screen: root.menuScreen
        anchors.bottom: true
        margins.bottom: (root.menuOnMain && root.fsUnder) ? 146 : 74
        implicitWidth: 700
        implicitHeight: root.player !== null ? 884 : 800      // taller when the media card is shown
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "startmenu"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        HyprlandFocusGrab {
            windows: [ win ]
            active: root.grabOn
            onCleared: {
                // a fullscreen game grabs focus back right after the menu opens: ignore that, re-grab
                if (Date.now() - root.openedAt < 700) { root.grabOn = false; regrab.restart(); return; }
                root.hide();
            }
        }
        Timer { id: regrab; interval: 60; onTriggered: if (root.open) root.grabOn = true }

        ClippingRectangle {
            id: panel
            anchors.fill: parent
            radius: 26
            color: root.cBg
            border.width: 1
            border.color: root.cBorder

            opacity: root.open ? 1 : 0
            transform: Translate { y: root.open ? 0 : 16; Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Keys.onEscapePressed: root.hide()

            // banner
            Item {
                id: banner
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 150
                Image {
                    anchors.fill: parent
                    source: "file://" + root.home + "/.config/quickshell/banner.jpg"
                    fillMode: Image.PreserveAspectCrop
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#000f1119" }
                        GradientStop { position: 1.0; color: "#f20f1119" }
                    }
                }
                // search box
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 22; bottomMargin: 6 }
                    height: 48; radius: 16
                    color: "#cc1a1d28"
                    border.width: 1
                    border.color: search.activeFocus ? root.cAccent : root.cBorder
                    Text {
                        id: sIcon
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        text: ""; font.family: root.fIcon; font.pixelSize: 16; color: root.cAccent
                    }
                    TextInput {
                        id: search
                        anchors { left: sIcon.right; right: parent.right; leftMargin: 12; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        color: root.cFg; font.family: root.fUi; font.pixelSize: 15
                        selectionColor: root.cAccent
                        focus: root.open
                        clip: true
                        Keys.onEscapePressed: root.hide()
                        Keys.onReturnPressed: root.runItem(root.items[root.selIndex])
                        Keys.onEnterPressed: root.runItem(root.items[root.selIndex])
                        Keys.onDownPressed: { root.selIndex = Math.min(root.items.length - 1, root.selIndex + 1); list.positionViewAtIndex(root.selIndex, ListView.Contain); }
                        Keys.onUpPressed: { root.selIndex = Math.max(0, root.selIndex - 1); list.positionViewAtIndex(root.selIndex, ListView.Contain); }
                        onTextChanged: if (text !== "") root.allApps = false
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search apps, files, 2+2, 100 usd to uah…"
                            color: root.cMuted; font: search.font
                            visible: search.text === ""
                        }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        text: root.allApps ? "Pinned" : "All apps  "
                        font.family: root.fUi; font.pixelSize: 12; font.weight: Font.DemiBold
                        color: allArea.containsMouse ? root.cFg : root.cAccent
                        visible: !root.searching
                        MouseArea { id: allArea; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.allApps = !root.allApps }
                    }
                }
            }

            // ── main content ───────────────────────────────
            Item {
                id: body
                anchors { top: banner.bottom; left: parent.left; right: parent.right; bottom: footer.top; margins: 22; topMargin: 14 }

                // search results / all apps list
                ListView {
                    id: list
                    anchors.fill: parent
                    visible: root.searching || root.allApps
                    clip: true
                    spacing: 2
                    model: root.items
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool sel: root.searching && index === root.selIndex
                        width: list.width; height: modelData.kind === "calc" ? 56 : 46; radius: 12
                        color: sel ? "#26f2b8d0" : (rowArea.containsMouse ? root.cHover : "transparent")
                        border.width: sel ? 1 : 0; border.color: "#55f2b8d0"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Item {
                            id: rowIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: 28; height: 28
                            IconImage { anchors.fill: parent; visible: modelData.kind === "app"
                                source: modelData.kind === "app" ? Quickshell.iconPath(modelData.entry.icon, "application-x-executable") : "" }
                            Text { anchors.centerIn: parent; visible: modelData.kind !== "app"; text: modelData.glyph || ""
                                font.family: root.fIcon; font.pixelSize: 17; color: root.cAccent }
                        }
                        Column {
                            anchors { left: rowIcon.right; leftMargin: 14; right: openDir.visible ? openDir.left : parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text { width: parent.width; elide: Text.ElideMiddle; text: modelData.title
                                color: root.cFg; font.family: root.fUi; font.pixelSize: modelData.kind === "calc" ? 20 : 14
                                font.weight: modelData.kind === "calc" ? Font.Bold : Font.Normal }
                            Text { width: parent.width; elide: Text.ElideMiddle; visible: text !== ""; text: modelData.sub || ""
                                color: root.cMuted; font.family: root.fUi; font.pixelSize: 11 }
                        }
                        Rectangle {
                            id: openDir
                            visible: modelData.kind === "file"
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            width: 30; height: 30; radius: 10; color: odA.containsMouse ? root.cHover : "transparent"
                            Text { anchors.centerIn: parent; text: "\uf07c"; font.family: root.fIcon; font.pixelSize: 13; color: root.cMuted }
                            MouseArea { id: odA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.runItem(modelData, true) }
                        }
                        MouseArea { id: rowArea; anchors.fill: parent; anchors.rightMargin: openDir.visible ? 44 : 0
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: m => {
                                if (m.button === Qt.RightButton && modelData.kind === "app") { root.openMctx(modelData.entry, mapToItem(panel, m.x, m.y)); return; }
                                root.runItem(modelData);
                            } }
                    }
                }

                // home view
                Column {
                    anchors.fill: parent
                    visible: !list.visible
                    spacing: 16

                    // pinned
                    Text { text: "Pinned"; color: root.cFg; font.family: root.fUi; font.pixelSize: 14; font.weight: Font.Bold }
                    Grid {
                        id: pinGrid
                        columns: 6
                        columnSpacing: 6; rowSpacing: 6
                        width: parent.width
                        Repeater {
                            model: root.pinned
                            delegate: Rectangle {
                                required property var modelData
                                width: (pinGrid.width - 5 * 6) / 6; height: 92; radius: 16
                                color: pinArea.containsMouse ? root.cHover : "transparent"
                                scale: pinArea.pressed ? 0.94 : 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    IconImage {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        implicitSize: 40
                                        source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 92; horizontalAlignment: Text.AlignHCenter
                                        text: modelData.name; elide: Text.ElideRight
                                        color: root.cFg; font.family: root.fUi; font.pixelSize: 11
                                    }
                                }
                                MouseArea { id: pinArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: m => {
                                        if (m.button === Qt.RightButton) { root.openMctx(modelData, mapToItem(panel, m.x, m.y)); return; }
                                        modelData.execute(); root.hide();
                                    } }
                            }
                        }
                    }

                    // volume
                    Rectangle {
                        width: parent.width; height: 52; radius: 16; color: root.cCard
                        Text {
                            id: volIcon
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            text: (root.sink && root.sink.audio && root.sink.audio.muted) ? "" : ""
                            font.family: root.fIcon; font.pixelSize: 17; color: root.cAccent
                            MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted }
                        }
                        Item {
                            id: track
                            anchors { left: volIcon.right; right: volPct.left; leftMargin: 16; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            height: 22
                            readonly property real v: (root.sink && root.sink.audio) ? Math.min(1, root.sink.audio.volume) : 0
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: "#26ffffff" }
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * track.v; height: 6; radius: 3; color: root.cAccent }
                            Rectangle { x: parent.width * track.v - 8; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: "#ffffff" }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                function setAt(mx) { if (root.sink && root.sink.audio) root.sink.audio.volume = Math.round(Math.max(0, Math.min(1, mx / width)) * 20) / 20; }
                                onPressed: m => setAt(m.x)
                                onPositionChanged: m => { if (pressed) setAt(m.x); }
                                onWheel: w => { if (root.sink && root.sink.audio) root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05))); }
                            }
                        }
                        Text {
                            id: volPct
                            anchors { right: soundBtn.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: Math.round(track.v * 100) + "%"; width: 40; horizontalAlignment: Text.AlignRight
                            color: root.cFg; font.family: root.fUi; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Rectangle {
                            id: soundBtn
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            width: 36; height: 36; radius: 12
                            color: sbArea.containsMouse ? root.cHover : "transparent"
                            Text { anchors.centerIn: parent; text: ""; font.family: root.fIcon; font.pixelSize: 15; color: root.cFg }
                            MouseArea { id: sbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { settings.openPage("sound"); root.hide(); } }
                        }
                    }

                    // quick toggles
                    Row {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: [
                                { icon: "", label: root.vpnText, on: root.vpnOn,
                                  act: root.vpnOn ? "mullvad disconnect" : "mullvad connect", keep: true },
                                { icon: root.dndOn ? "" : "", label: root.dndOn ? "Silent" : "Alerts", on: root.dndOn,
                                  act: "swaync-client -d", keep: true },
                                { icon: "", label: "Screenshot", on: false,
                                  act: "sleep 0.4; ~/.config/hypr/scripts/screenshot.sh region" },
                                { icon: "", label: "Color", on: false, act: "sleep 0.3; hyprpicker -a -n" },
                                { icon: "", label: "Clipboard", on: false, act: "~/.config/hypr/scripts/clipboard.sh" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: (parent.width - 4 * 8) / 5; height: 70; radius: 16
                                color: modelData.on ? root.cAccent : (tArea.containsMouse ? root.cHover : root.cCard)
                                Behavior on color { ColorAnimation { duration: 160 } }
                                scale: tArea.pressed ? 0.94 : 1
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Column {
                                    anchors.centerIn: parent; spacing: 6
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon
                                        font.family: root.fIcon; font.pixelSize: 18; color: modelData.on ? root.cAccFg : root.cFg }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label
                                        font.family: root.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: modelData.on ? root.cAccFg : root.cFg }
                                }
                                MouseArea { id: tArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.keep) { Quickshell.execDetached(["sh", "-c", modelData.act]); refresh.restart(); }
                                        else root.run(modelData.act);
                                    } }
                            }
                        }
                    }
                    Timer { id: refresh; interval: 600; onTriggered: { vpnProc.running = true; dndProc.running = true; } }

                    // settings shortcuts
                    Text { text: "Settings"; color: root.cFg; font.family: root.fUi; font.pixelSize: 14; font.weight: Font.Bold }
                    Grid {
                        id: setGrid
                        width: parent.width
                        columns: 3; columnSpacing: 8; rowSpacing: 8
                        Repeater {
                            model: [
                                { icon: "\uf028", label: "Sound",        page: "sound" },
                                { icon: "\uf108", label: "Displays",     page: "display" },
                                { icon: "\uf0e8", label: "Network & VPN", page: "network" },
                                { icon: "\uf1fc", label: "Appearance",   page: "appearance" },
                                { icon: "\uf11c", label: "Keyboard",     page: "input" },
                                { icon: "\uf05a", label: "About",        page: "about" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: (setGrid.width - 2 * 8) / 3; height: 44; radius: 14
                                color: setArea.containsMouse ? root.cHover : root.cCard
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Row {
                                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                    spacing: 10
                                    Text { text: modelData.icon; font.family: root.fIcon; font.pixelSize: 14; color: root.cAccent; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: modelData.label; font.family: root.fUi; font.pixelSize: 13; color: root.cFg; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { id: setArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { settings.openPage(modelData.page); root.hide(); } }
                            }
                        }
                    }

                    // media player
                    Rectangle {
                        visible: root.player !== null
                        width: parent.width; height: 64; radius: 16; color: root.cCard
                        Image {
                            id: art
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: 44; height: 44
                            source: root.player ? (root.player.trackArtUrl || "") : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }
                        Column {
                            anchors { left: art.visible ? art.right : parent.left; leftMargin: 14; right: ctrls.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            Text { width: parent.width; elide: Text.ElideRight; text: root.player ? (root.player.trackTitle || "Nothing playing") : ""
                                color: root.cFg; font.family: root.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideRight; text: root.player ? (root.player.trackArtist || root.player.identity || "") : ""
                                color: root.cMuted; font.family: root.fUi; font.pixelSize: 12 }
                        }
                        Row {
                            id: ctrls
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            Repeater {
                                model: [ "prev", "play", "next" ]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: 36; height: 36; radius: 12
                                    color: modelData === "play" ? root.cAccent : (mArea.containsMouse ? root.cHover : "transparent")
                                    Text { anchors.centerIn: parent; font.family: root.fIcon; font.pixelSize: 13
                                        color: modelData === "play" ? root.cAccFg : root.cFg
                                        text: modelData === "prev" ? "" : modelData === "next" ? ""
                                            : (root.player && root.player.isPlaying ? "" : "") }
                                    MouseArea { id: mArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.player) return;
                                            if (modelData === "prev") root.player.previous();
                                            else if (modelData === "next") root.player.next();
                                            else root.player.togglePlaying();
                                        } }
                                }
                            }
                        }
                    }
                }
            }

            // ── footer: user + power ───────────────────────
            Rectangle {
                id: footer
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 70
                color: "#0dffffff"
                Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 1; color: root.cBorder }

                Row {
                    anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                    spacing: 12
                    Rectangle {
                        width: 42; height: 42; radius: 21; color: root.cAccent
                        Image {
                            anchors.centerIn: parent; width: 38; height: 38
                            source: "file://" + root.home + "/.config/hypr/assets/avatar.png"
                            smooth: true; mipmap: true
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: root.user; color: root.cFg; font.family: root.fUi; font.pixelSize: 14; font.weight: Font.Bold }
                        Text { text: "up " + root.uptime; color: root.cMuted; font.family: root.fUi; font.pixelSize: 11 }
                    }
                }

                Row {
                    anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Repeater {
                        model: [
                            { icon: "", tip: "Lock",     act: "loginctl lock-session" },
                            { icon: "", tip: "Log out",  act: "~/.config/hypr/scripts/session.py save; uwsm stop || hyprctl dispatch 'hl.dsp.exit()'" },
                            { icon: "", tip: "Sleep",    act: "systemctl suspend" },
                            { icon: "", tip: "Restart",  act: "~/.config/hypr/scripts/session.py save; systemctl reboot" },
                            { icon: "", tip: "Shut down", act: "~/.config/hypr/scripts/session.py save; systemctl poweroff" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 40; height: 40; radius: 13
                            color: pwArea.containsMouse ? root.cAccent : "transparent"
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Text { anchors.centerIn: parent; text: modelData.icon; font.family: root.fIcon; font.pixelSize: 15
                                color: pwArea.containsMouse ? root.cAccFg : root.cFg }
                            MouseArea { id: pwArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.run(modelData.act) }
                        }
                    }
                }
            }

            // right-click menu for apps
            MouseArea {
                anchors.fill: parent
                visible: root.mctxOpen
                z: 50
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: root.mctxOpen = false
            }
            Rectangle {
                id: mctx
                visible: root.mctxOpen
                z: 51
                width: 230
                height: mctxCol.implicitHeight + 16
                x: Math.min(panel.width - width - 10, root.mctxPos.x)
                y: Math.min(panel.height - height - 10, root.mctxPos.y)
                radius: 14
                color: "#fa151824"
                border.width: 1; border.color: root.cBorder
                Column {
                    id: mctxCol
                    x: 8; y: 8; width: parent.width - 16; spacing: 2
                    Repeater {
                        model: {
                            const a = root.mctxApp;
                            if (!a) return [];
                            const dockKey = a.id.toLowerCase();
                            return [
                                { icon: "\uf04b", label: "Open", act: "open" },
                                { icon: "\uf08d", label: root.menuIsPinned(a.id) ? "Unpin from Start" : "Pin to Start", act: "start" },
                                { icon: "\uf0c9", label: root.isPinned(dockKey) ? "Unpin from dock" : "Pin to dock", act: "dock" }
                            ];
                        }
                        delegate: Rectangle {
                            required property var modelData
                            width: mctxCol.width; height: 36; radius: 10
                            color: ma.containsMouse ? root.cHover : "transparent"
                            Text { id: mi; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } width: 18
                                text: modelData.icon; font.family: root.fIcon; font.pixelSize: 12; color: root.cAccent }
                            Text { anchors { left: mi.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                text: modelData.label; font.family: root.fUi; font.pixelSize: 13; color: root.cFg }
                            MouseArea {
                                id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const a = root.mctxApp;
                                    root.mctxOpen = false;
                                    if (modelData.act === "open") { a.execute(); root.hide(); }
                                    else if (modelData.act === "start") root.menuTogglePin(a.id);
                                    else root.togglePin({ key: a.id.toLowerCase(), entry: a });
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── dock ────────────────────────────────────────────────
    property var dockPinned: [ "brave-browser", "firefox", "org.gnome.Nautilus", "kitty", "discord", "code-oss" ]
    FileView {
        id: dockFile
        path: root.home + "/.config/quickshell/dock.json"
        blockLoading: true
        onLoaded: { try { const j = JSON.parse(text()); if (Array.isArray(j.pinned)) root.dockPinned = j.pinned; } catch (e) {} }
    }
    function savePinned(list) { dockPinned = list; dockFile.setText(JSON.stringify({ pinned: list }, null, 2)); }
    function isPinned(key) { return dockPinned.some(id => id.toLowerCase() === key); }
    function togglePin(app) {
        const id = app.entry ? app.entry.id : app.key;
        if (isPinned(app.key)) savePinned(dockPinned.filter(x => x.toLowerCase() !== app.key));
        else savePinned(dockPinned.concat([id]));
    }

    function appOf(t) { return String(t.appId || "").toLowerCase(); }
    readonly property var dockApps: {
        const tops = ToplevelManager.toplevels.values;
        const out = [];
        const seen = {};
        for (const id of dockPinned) {
            const key = id.toLowerCase();
            if (seen[key]) continue;
            const e = everyApp.find(x => x.id.toLowerCase() === key);
            seen[key] = true;
            out.push({ key: key, entry: e, wins: tops.filter(t => appOf(t) === key) });
        }
        for (const t of tops) {
            const key = appOf(t);
            if (!key || seen[key]) continue;
            seen[key] = true;
            const e = everyApp.find(x => x.id.toLowerCase() === key) || DesktopEntries.heuristicLookup(key);
            out.push({ key: key, entry: e, wins: tops.filter(w => appOf(w) === key) });
        }
        return out;
    }

    // right-click menu state
    property var ctxApp: null
    property real ctxX: 0
    property bool ctxOpen: false
    // drag-to-reorder state
    property int dragFrom: -1
    property int dragTo: -1
    function dockMove(from, to) {
        const apps = dockApps;
        if (from < 0 || from >= apps.length) return;
        const app = apps[from];
        const id = app.entry ? app.entry.id : app.key;
        let list = dockPinned.filter(x => x.toLowerCase() !== app.key);
        const pos = Math.max(0, Math.min(to, list.length));
        list.splice(pos, 0, id);
        savePinned(list);
    }

    component DockWindow: PanelWindow {
        id: dock
        property bool overlay: false
        anchors.bottom: true
        margins.bottom: 8
        implicitWidth: Math.max(dockRow.implicitWidth + 20, 200) + 120   // extra room so edge tooltips are not cut
        implicitHeight: 320                                                // room above for tooltips + right-click menu
        exclusiveZone: 64
        exclusionMode: overlay ? ExclusionMode.Ignore : ExclusionMode.Normal   // the overlay copy reserves nothing and sits at the very bottom
        color: "transparent"
        WlrLayershell.namespace: "dock"
        WlrLayershell.layer: overlay ? WlrLayer.Overlay : WlrLayer.Top
        mask: Region { item: dockBg; Region { item: ctxHit } }             // only the bar (and open menu) take clicks
        HyprlandFocusGrab { windows: [ dock ]; active: root.ctxOpen; onCleared: root.ctxOpen = false }

        Rectangle {
            id: dockBg
            HoverHandler { id: dockHover }
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            width: dockRow.implicitWidth + 20
            height: 60
            radius: 20
            color: "#b30f1119"
            border.width: 1
            border.color: root.cBorder
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }

        Row {
            id: dockRow
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            spacing: 4

            // start button (avatar)
            Item {
                width: 48; height: 60
                ClippingRectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 9
                    width: 42; height: 42; radius: 21
                    color: root.open || startArea.containsMouse ? root.cAccent : "#33ffffff"
                    scale: startArea.pressed ? 0.93 : (startArea.containsMouse ? 1.05 : 1)
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Image {
                        anchors.fill: parent; anchors.margins: 2
                        source: "file://" + root.home + "/.config/hypr/assets/avatar.png"
                        mipmap: true; smooth: true
                    }
                }
                MouseArea { id: startArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggle() }
            }
            Item { width: 9; height: 60
                Rectangle { anchors.centerIn: parent; width: 1; height: 30; color: root.cBorder } }

            Repeater {
                model: root.dockApps
                delegate: Item {
                    id: slot
                    required property var modelData
                    required property int index
                    readonly property bool running: modelData.wins.length > 0
                    readonly property bool active: modelData.wins.some(w => w.activated)
                    property int cycle: 0
                    property bool dragging: false
                    property real dragDx: 0
                    width: 52; height: 60
                    z: dragging ? 10 : 0
                    // neighbours slide aside while you drag
                    readonly property real shift: {
                        const f = root.dragFrom, t = root.dragTo, i = slot.index;
                        if (f < 0 || i === f) return 0;
                        if (f < t && i > f && i <= t) return -56;
                        if (f > t && i < f && i >= t) return 56;
                        return 0;
                    }
                    transform: Translate {
                        x: slot.dragging ? slot.dragDx : slot.shift
                        Behavior on x { enabled: !slot.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }

                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: slot.dragging ? 4 : (area.containsMouse ? 8 : 11)
                        implicitSize: slot.dragging ? 46 : (area.containsMouse ? 42 : 38)
                        source: Quickshell.iconPath(slot.modelData.entry ? slot.modelData.entry.icon : slot.modelData.key, "application-x-executable")
                        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on implicitSize { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 4 }
                        height: 4; radius: 2
                        width: slot.active ? 18 : (slot.running ? 6 : 0)
                        color: slot.active ? root.cAccent : root.cMuted
                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    // name tooltip (inside the taller dock window, so it is never cut)
                    Rectangle {
                        opacity: area.containsMouse && !root.ctxOpen && root.dragFrom < 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 8 }
                        width: tip.implicitWidth + 18; height: 28; radius: 9
                        color: "#f21a1d28"; border.width: 1; border.color: root.cBorder
                        Text { id: tip; anchors.centerIn: parent; color: root.cFg; font.family: root.fUi; font.pixelSize: 12
                            text: slot.modelData.entry ? slot.modelData.entry.name : slot.modelData.key }
                    }
                    MouseArea {
                        id: area; anchors.fill: parent; hoverEnabled: true
                        cursorShape: slot.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        property real pressX: 0
                        property bool wasDrag: false
                        // measure in dock coordinates (the icon itself moves, so its own coords would feed back and jitter)
                        onPressed: m => { pressX = area.mapToItem(dockBg, m.x, 0).x; wasDrag = false; }
                        onPositionChanged: m => {
                            if (!(pressedButtons & Qt.LeftButton)) return;
                            const dx = area.mapToItem(dockBg, m.x, 0).x - pressX;
                            if (!slot.dragging && Math.abs(dx) > 8) { slot.dragging = true; root.dragFrom = slot.index; }
                            if (slot.dragging) {
                                slot.dragDx = dx;
                                root.dragTo = Math.max(0, Math.min(root.dockApps.length - 1, slot.index + Math.round(dx / 56)));
                            }
                        }
                        onReleased: m => {
                            if (!slot.dragging) return;
                            wasDrag = true;
                            const from = root.dragFrom, to = root.dragTo;
                            slot.dragging = false; slot.dragDx = 0;
                            root.dragFrom = -1; root.dragTo = -1;
                            if (to !== from) root.dockMove(from, to);
                        }
                        onClicked: m => {
                            if (wasDrag) { wasDrag = false; return; }
                            const wins = slot.modelData.wins;
                            if (m.button === Qt.RightButton) {
                                root.ctxApp = slot.modelData;
                                root.ctxX = slot.mapToItem(null, slot.width / 2, 0).x;
                                root.ctxOpen = true;
                                return;
                            }
                            if (m.button === Qt.MiddleButton || wins.length === 0) {
                                if (slot.modelData.entry) slot.modelData.entry.execute();
                                return;
                            }
                            if (wins.length === 1 && wins[0].activated) {
                                Quickshell.execDetached([root.home + "/.config/hypr/scripts/minimize.sh", "hide"]);
                                return;
                            }
                            slot.cycle = (slot.cycle + 1) % wins.length;
                            wins[slot.cycle].activate();
                            Quickshell.execDetached(["sh", "-c", "sleep 0.08; hyprctl eval 'hl.dispatch(hl.dsp.window.bring_to_top())'"]);
                        }
                    }
                }
            }
        }

        // right-click menu (lives inside the dock window so outside clicks close it)
        Item {
            id: ctxHit
            x: Math.max(8, Math.min(dock.implicitWidth - width - 8, root.ctxX - width / 2))
            y: dock.implicitHeight - 60 - height - 10
            width: root.ctxOpen ? 240 : 0
            height: root.ctxOpen ? ctxCol.implicitHeight + 16 : 0
            visible: root.ctxOpen
            focus: root.ctxOpen
            Keys.onEscapePressed: root.ctxOpen = false
            HoverHandler { id: ctxHover }
            Timer {
                interval: 1200
                running: root.ctxOpen && !ctxHover.hovered && !dockHover.hovered
                onTriggered: root.ctxOpen = false
            }
            Rectangle {
                id: ctxBox
                anchors.fill: parent
                radius: 16
                color: "#f50f1119"
                border.width: 1
                border.color: root.cBorder

                Column {
                    id: ctxCol
                    x: 8; y: 8
                    width: parent.width - 16
                    spacing: 2

                    Row {
                        spacing: 10; leftPadding: 8; topPadding: 4; bottomPadding: 6
                        IconImage { implicitSize: 22; anchors.verticalCenter: parent.verticalCenter
                            source: root.ctxApp ? Quickshell.iconPath(root.ctxApp.entry ? root.ctxApp.entry.icon : root.ctxApp.key, "application-x-executable") : "" }
                        Text { anchors.verticalCenter: parent.verticalCenter; color: root.cFg; font.family: root.fUi; font.pixelSize: 13; font.weight: Font.Bold
                            text: root.ctxApp ? (root.ctxApp.entry ? root.ctxApp.entry.name : root.ctxApp.key) : "" }
                    }
                    Rectangle { width: parent.width; height: 1; color: root.cBorder }

                    Repeater {
                        model: {
                            const a = root.ctxApp;
                            if (!a) return [];
                            const items = [];
                            if (a.entry) items.push({ icon: "", label: "New window", act: "new" });
                            items.push({ icon: "", label: root.isPinned(a.key) ? "Unpin from dock" : "Pin to dock", act: "pin" });
                            if (a.wins.length === 1) items.push({ icon: "", label: "Close window", act: "close", danger: true });
                            if (a.wins.length > 1) items.push({ icon: "", label: "Close all " + a.wins.length + " windows", act: "close", danger: true });
                            return items;
                        }
                        delegate: Rectangle {
                            required property var modelData
                            width: ctxCol.width; height: 38; radius: 10
                            color: ca.containsMouse ? (modelData.danger ? "#33f28fad" : root.cHover) : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Text { id: ci; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } width: 18
                                text: modelData.icon; font.family: root.fIcon; font.pixelSize: 13
                                color: modelData.danger ? "#f28fad" : root.cAccent }
                            Text { anchors { left: ci.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                text: modelData.label; font.family: root.fUi; font.pixelSize: 13
                                color: modelData.danger ? "#f28fad" : root.cFg }
                            MouseArea {
                                id: ca; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const a = root.ctxApp;
                                    if (modelData.act === "new" && a.entry) a.entry.execute();
                                    else if (modelData.act === "pin") root.togglePin(a);
                                    else if (modelData.act === "close") a.wins.forEach(w => w.close());
                                    root.ctxOpen = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // the normal dock on the main monitor
    DockWindow {
        screen: Quickshell.screens.find(s => s.name === "DP-3") || Quickshell.screens[0]
    }
    // a copy that shows above fullscreen apps (games) while the start menu is open
    DockWindow {
        overlay: true
        visible: root.open && (!root.menuOnMain || root.fsUnder)
        screen: root.menuScreen
    }
}
