// sakura mono - wallpaper picker: a glass window in the middle of the focused monitor.
//   Library   - folders (Wallpapers, Pictures, Videos, Downloads, Home) or any path typed into the search
//   Wallhaven - search wallhaven.cc (sfw), the picture is downloaded into ~/Pictures/Wallpapers on Apply
//   Live      - every video wallpaper from those folders
// Big preview of the selected one + a strip of thumbnails. ←/→ browse, Enter applies, Esc closes.
// qs ipc call wallpicker toggle | random
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

Scope {
    id: wpk
    property var settings: null
    property bool shown: false
    property var screen0: Quickshell.screens[0]

    readonly property color cBg:     Cfg.glass
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cCard:   "#14ffffff"
    readonly property color cCard2:  "#1fffffff"
    readonly property color cHover:  "#29ffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string home:   Quickshell.env("HOME")
    readonly property string scripts: home + "/.config/hypr/scripts"

    // ── state ───────────────────────────────────────────────
    property string source: "library"      // library | wallhaven | live
    property string folder: (Cfg.data.wallDir || "~/Pictures/Wallpapers").replace(/^~/, home)
    property string query: ""
    property string kind: "all"            // all | photo | video  (library only)
    property string whMode: "toplist"      // toplist | hot | latest | random
    property string whCat: "all"           // all | general | anime | people
    property int whPage: 1
    property bool whMore: true
    property var items: []                 // [{ file | path, thumb, large, res, type, date, wh }]
    property int sel: 0
    property bool busy: listProc.running || whProc.running
    property bool downloading: getProc.running

    readonly property var folders: [
        { t: "Wallpapers", icon: "", p: (Cfg.data.wallDir || "~/Pictures/Wallpapers").replace(/^~/, home) },
        { t: "Pictures",   icon: "", p: home + "/Pictures" },
        { t: "Videos",     icon: "", p: home + "/Videos" },
        { t: "Downloads",  icon: "", p: home + "/Downloads" },
        { t: "Home",       icon: "", p: home }
    ]
    readonly property var whModes: [
        { k: "toplist", t: "Top",    icon: "\uf005" },
        { k: "hot",     t: "Hot",    icon: "\uf06d" },
        { k: "latest",  t: "Latest", icon: "\uf017" },
        { k: "random",  t: "Random", icon: "\uf074" }
    ]

    function step(d) { sel = Math.max(0, Math.min(shownItems.length - 1, sel + d)); }
    function isVideo(f) { return /\.(mp4|webm|mkv|mov)$/i.test(f || ""); }
    function ext(f) { const m = /\.([a-z0-9]+)$/i.exec(f || ""); return m ? m[1].toUpperCase() : ""; }
    readonly property var cur: items.length ? items[Math.max(0, Math.min(sel, items.length - 1))] : null
    readonly property var shownItems: {
        if (source === "wallhaven") return items;
        let L = items;
        if (source === "library" && kind !== "all") L = L.filter(i => isVideo(i.file) === (kind === "video"));
        if (query === "" || query.startsWith("/") || query.startsWith("~")) return L;
        const q = query.toLowerCase();
        return L.filter(i => (i.file || "").split("/").pop().toLowerCase().includes(q));
    }
    onKindChanged: { const i = shownItems.findIndex(x => x.file === Cfg.data.wallpaper); sel = Math.max(0, i); }
    readonly property var curShown: shownItems.length ? shownItems[Math.max(0, Math.min(sel, shownItems.length - 1))] : null

    // ── open / close ────────────────────────────────────────
    function open(sc) {
        if (!sc) { const fm = Hyprland.focusedMonitor; sc = fm ? Quickshell.screens.find(s => s.name === fm.name) : null; }
        screen0 = sc || Cfg.mainScreen || Quickshell.screens[0];
        reload();
        shown = true;
    }
    function close() { shown = false; }
    function toggle() { if (shown) close(); else open(null); }

    // ── loading ─────────────────────────────────────────────
    function reload() {
        sel = 0;
        if (source === "wallhaven") { items = []; whPage = 1; whMore = true; whFetch(); return; }
        let dirs;
        if (source === "live") dirs = folders.slice(0, 4).map(f => f.p);
        else if (query.startsWith("/") || query.startsWith("~")) dirs = [query.replace(/^~/, home).replace(/\/+$/, "")];
        else dirs = [folder];
        listProc.running = false;
        listProc.command = [scripts + "/walllist.sh"].concat(dirs);
        listProc.running = true;
    }
    Process {
        id: listProc
        stdout: StdioCollector { onStreamFinished: {
            let L = this.text.trim().split("\n").filter(x => x !== "").map(l => {
                const i = l.indexOf("\t"), f = l.slice(i + 1), d = new Date(parseFloat(l.slice(0, i)) * 1000);
                return { file: f, date: Cfg.locale.toString(d, "d MMM yyyy"), type: wpk.ext(f), wh: false };
            });
            if (wpk.source === "live") L = L.filter(x => wpk.isVideo(x.file));
            wpk.items = L;
            const i = L.findIndex(x => x.file === Cfg.data.wallpaper);
            wpk.sel = Math.max(0, i);
        } }
    }
    function whFetch() {
        if (whProc.running || !whMore) return;
        whProc.command = [scripts + "/wallhaven.sh", "search", whMode, String(whPage), query,
                          whCat === "general" ? "100" : whCat === "anime" ? "010" : whCat === "people" ? "001" : "111"];
        whProc.running = true;
    }
    Process {
        id: whProc
        stdout: StdioCollector { onStreamFinished: {
            const L = [];
            this.text.trim().split("\n").forEach(l => { try { const j = JSON.parse(l); j.wh = true; L.push(j); } catch (e) {} });
            if (L.length === 0) wpk.whMore = false;
            wpk.items = wpk.items.concat(L);
            wpk.whPage += 1;
        } }
    }
    onSourceChanged: { query = ""; reload(); }
    onFolderChanged: reload()
    onWhModeChanged: reload()
    onWhCatChanged: reload()
    Timer { id: searchT; interval: 450; onTriggered: if (wpk.source === "wallhaven" || wpk.query.startsWith("/") || wpk.query.startsWith("~")) wpk.reload(); else wpk.sel = 0 }

    // ── apply ───────────────────────────────────────────────
    function apply(it) {
        if (!it) return;
        if (!it.wh) { if (settings) settings.setWallpaper(it.file); return; }
        getProc.command = [scripts + "/wallhaven.sh", "get", it.path];
        getProc.running = true;
    }
    Process {
        id: getProc
        stdout: StdioCollector { onStreamFinished: { const f = this.text.trim(); if (f !== "" && wpk.settings) wpk.settings.setWallpaper(f); } }
    }
    function random() {
        const pool = shownItems.filter(i => i.wh || i.file !== Cfg.data.wallpaper);
        if (pool.length) { const it = pool[Math.floor(Math.random() * pool.length)]; sel = shownItems.indexOf(it); apply(it); }
    }
    // random wallpaper from the library without opening the window (desktop menu)
    function randomNow() { rndProc.running = false; rndProc.running = true; }
    Process {
        id: rndProc
        command: [wpk.scripts + "/wallpaper.sh", "list"]
        stdout: StdioCollector { onStreamFinished: {
            const pool = this.text.trim().split("\n").filter(x => x !== "" && x !== Cfg.data.wallpaper);
            if (pool.length && wpk.settings) wpk.settings.setWallpaper(pool[Math.floor(Math.random() * pool.length)]);
        } }
    }

    // change the wallpaper every N minutes (Settings > Wallpaper; 0 = off)
    Timer {
        interval: Math.max(1, Cfg.data.wallShuffle || 0) * 60000
        running: (Cfg.data.wallShuffle || 0) > 0
        repeat: true
        onTriggered: wpk.randomNow()
    }
    IpcHandler {
        target: "wallpicker"
        function toggle(): void { wpk.toggle(); }
        function random(): void { wpk.randomNow(); }
    }

    // ── small pieces ────────────────────────────────────────
    component Chip: Rectangle {
        id: ch
        property string label: ""
        property string icon: ""
        property bool on: false
        signal clicked()
        width: chRow.implicitWidth + 24; height: 30; radius: 10
        color: on ? Cfg.acc(0.18) : cma.containsMouse ? wpk.cHover : wpk.cCard
        border.width: on ? 1 : 0; border.color: Cfg.acc(0.45)
        Behavior on color { ColorAnimation { duration: 140 } }
        Row {
            id: chRow; anchors.centerIn: parent; spacing: 7
            Text { visible: ch.icon !== ""; text: ch.icon; font.family: wpk.fIcon; font.pixelSize: 12; color: ch.on ? wpk.cAccent : wpk.cMuted; anchors.verticalCenter: parent.verticalCenter }
            Text { text: Cfg.tr(ch.label); font.family: wpk.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: ch.on ? wpk.cAccent : wpk.cFg; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }
    component IconBtn: Rectangle {
        id: ib
        property string icon: ""
        signal clicked()
        width: 30; height: 30; radius: 10
        color: ima.containsMouse ? wpk.cHover : wpk.cCard
        Behavior on color { ColorAnimation { duration: 140 } }
        Text { anchors.centerIn: parent; text: ib.icon; font.family: wpk.fIcon; font.pixelSize: 13; color: ima.containsMouse ? wpk.cAccent : wpk.cFg }
        MouseArea { id: ima; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
    }
    component Badge: Rectangle {
        id: bd
        property string label: ""
        property string icon: ""
        width: bRow.implicitWidth + 16; height: 24; radius: 12; color: "#a60f1119"
        Row {
            id: bRow; anchors.centerIn: parent; spacing: 5
            Text { visible: bd.icon !== ""; text: bd.icon; font.family: wpk.fIcon; font.pixelSize: 10; color: wpk.cFg; anchors.verticalCenter: parent.verticalCenter }
            Text { text: bd.label; font.family: wpk.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: wpk.cFg; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ── window ──────────────────────────────────────────────
    // moved by dragging the header; offset from the centre of the screen, kept until the shell restarts
    property real offX: 0
    property real offY: 0
    PanelWindow {
        id: win
        screen: wpk.screen0
        // the surface covers the whole screen (input only on the panel): moving the panel inside it is smooth,
        // moving a small surface around made it shake (the cursor position lags behind the surface)
        anchors { left: true; right: true; top: true; bottom: true }
        mask: Region { item: panel }
        visible: wpk.shown || panel.opacity > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "wallpicker"
        WlrLayershell.keyboardFocus: wpk.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        property bool grabOn: false
        onVisibleChanged: { grabOn = false; if (visible) regrab.restart(); }
        Timer { id: regrab; interval: 60; onTriggered: if (wpk.shown) win.grabOn = true }
        HyprlandFocusGrab { windows: [ win ]; active: win.grabOn && wpk.shown; onCleared: wpk.close() }

        Rectangle {
            id: panel
            width: 1000; height: 660
            x: Math.round(Math.max(0, Math.min(win.width - width, (win.width - width) / 2 + wpk.offX)))
            y: Math.round(Math.max(0, Math.min(win.height - height, (win.height - height) / 2 + wpk.offY)))
            radius: 26
            color: wpk.cBg
            border.width: 0
            opacity: wpk.shown ? 1 : 0
            scale: wpk.shown ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            focus: wpk.shown
            Keys.onEscapePressed: wpk.close()
            Keys.onLeftPressed: wpk.step(-1)
            Keys.onRightPressed: wpk.step(1)
            Keys.onReturnPressed: wpk.apply(wpk.curShown)
            Keys.onEnterPressed: wpk.apply(wpk.curShown)

            // ── row 1: path · source tabs ────────────
            // grab anywhere on the header to move the window
            MouseArea {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 58
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real px: 0
                property real py: 0
                property real ox: 0
                property real oy: 0
                // screen coords (the surface is full-screen and never moves)
                onPressed: m => { const g = mapToItem(null, m.x, m.y); px = g.x; py = g.y; ox = wpk.offX; oy = wpk.offY; }
                onPositionChanged: m => {
                    if (!pressed) return;
                    const g = mapToItem(null, m.x, m.y);
                    const mx = (win.width - panel.width) / 2, my = (win.height - panel.height) / 2;
                    wpk.offX = Math.max(-mx, Math.min(mx, ox + g.x - px));
                    wpk.offY = Math.max(-my, Math.min(my, oy + g.y - py));
                }
                onDoubleClicked: { wpk.offX = 0; wpk.offY = 0; }
            }
            Item {
                id: r1
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                height: 34
                Row {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Text { text: wpk.source === "wallhaven" ? "" : wpk.source === "live" ? "" : ""
                           font.family: wpk.fIcon; font.pixelSize: 14; color: wpk.cAccent; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: wpk.source === "wallhaven" ? "Wallhaven" : wpk.source === "live" ? Cfg.tr("Live wallpapers")
                              : (wpk.query.startsWith("/") || wpk.query.startsWith("~") ? wpk.query : wpk.folder).replace(wpk.home, "~").split("/").join("  ›  ")
                        font.family: wpk.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: wpk.cFg
                    }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: cnt.implicitWidth + 12; height: 20; radius: 10; color: Cfg.acc(0.2)
                        Text { id: cnt; anchors.centerIn: parent; text: wpk.shownItems.length; font.family: wpk.fUi; font.pixelSize: 11; font.weight: Font.Bold; color: wpk.cAccent } }
                }
                // segmented tabs
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: segRow.implicitWidth + 8; height: 34; radius: 12; color: wpk.cCard
                    Rectangle {
                        readonly property var it: segRep.count === 3 ? segRep.itemAt(["library", "wallhaven", "live"].indexOf(wpk.source)) : null
                        x: it ? it.x + 4 : 4; width: it ? it.width : 0; y: 4; height: 26; radius: 9; color: wpk.cAccent
                        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    }
                    Row {
                        id: segRow; x: 4; y: 4
                        Repeater {
                            id: segRep
                            model: [ { k: "library", t: "Library" }, { k: "wallhaven", t: "Wallhaven" }, { k: "live", t: "Live" } ]
                            delegate: Item {
                                required property var modelData
                                width: sl.implicitWidth + 28; height: 26
                                Text { id: sl; anchors.centerIn: parent; text: Cfg.tr(modelData.t); font.family: wpk.fUi; font.pixelSize: 12; font.weight: Font.DemiBold
                                       color: wpk.source === modelData.k ? wpk.cAccFg : wpk.cFg; Behavior on color { ColorAnimation { duration: 200 } } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wpk.source = parent.modelData.k }
                            }
                        }
                    }
                }
            }

            // ── row 2: search · shuffle ──────────────
            Item {
                id: r2
                anchors { left: parent.left; right: parent.right; top: r1.bottom; topMargin: 12; leftMargin: 16; rightMargin: 16 }
                height: 38
                Rectangle {
                    anchors { left: parent.left; right: shuf.left; rightMargin: 8; top: parent.top; bottom: parent.bottom }
                    radius: 12; color: wpk.cCard
                    border.width: search.activeFocus ? 1 : 0; border.color: Cfg.acc(0.5)
                    Text { id: sIc; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                           text: ""; font.family: wpk.fIcon; font.pixelSize: 12; color: wpk.cMuted }
                    TextInput {
                        id: search
                        anchors { left: sIc.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        color: wpk.cFg; font.family: wpk.fUi; font.pixelSize: 13; clip: true
                        selectionColor: Cfg.acc(0.4)
                        Connections { target: wpk; function onQueryChanged() { if (search.text !== wpk.query) search.text = wpk.query; } }
                        onTextEdited: { wpk.query = text; searchT.restart(); }
                        Keys.onEscapePressed: { if (text !== "") { wpk.query = ""; searchT.restart(); } else wpk.close(); }
                        Keys.onReturnPressed: { searchT.stop(); if (wpk.source === "wallhaven" || text.startsWith("/") || text.startsWith("~")) wpk.reload(); else wpk.apply(wpk.curShown); }
                        Keys.onDownPressed: panel.forceActiveFocus()
                        Text {
                            visible: search.text === ""
                            text: wpk.source === "wallhaven" ? Cfg.tr("Search Wallhaven") : Cfg.tr("Search, or type a path")
                            color: wpk.cMuted; font: search.font
                        }
                    }
                }
                IconBtn { id: shuf; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 38; height: 38; icon: ""; onClicked: wpk.random() }
            }

            // ── row 3: folders / wallhaven modes ─────
            Row {
                id: r3
                anchors { left: parent.left; top: r2.bottom; topMargin: 10; leftMargin: 16 }
                spacing: 6
                Repeater {
                    model: wpk.source === "library" ? wpk.folders : wpk.source === "wallhaven" ? wpk.whModes : []
                    delegate: Chip {
                        required property var modelData
                        label: modelData.t; icon: modelData.icon
                        on: wpk.source === "library" ? (wpk.folder === modelData.p && !wpk.query.startsWith("/") && !wpk.query.startsWith("~")) : wpk.whMode === modelData.k
                        onClicked: { if (wpk.source === "library") { wpk.query = ""; if (wpk.folder === modelData.p) wpk.reload(); else wpk.folder = modelData.p; } else wpk.whMode = modelData.k; }
                    }
                }
            }

            // photo / video filter (library)
            Rectangle {
                visible: wpk.source !== "live"
                readonly property bool wh: wpk.source === "wallhaven"
                readonly property var opts: wh
                    ? [ { k: "all", t: "All", i: "\uf00a" }, { k: "general", t: "General", i: "\uf03e" }, { k: "anime", t: "Anime", i: "\uf004" }, { k: "people", t: "People", i: "\uf007" } ]
                    : [ { k: "all", t: "All", i: "\uf00a" }, { k: "photo", t: "Photo", i: "\uf03e" }, { k: "video", t: "Video", i: "\uf03d" } ]
                readonly property string val: wh ? wpk.whCat : wpk.kind
                function pick(k) { if (wh) wpk.whCat = k; else wpk.kind = k; }
                id: kBox
                anchors { right: parent.right; rightMargin: 16; verticalCenter: r3.verticalCenter }
                width: kRow.implicitWidth + 8; height: 30; radius: 10; color: wpk.cCard
                Rectangle {
                    readonly property var it: kRep.count === kBox.opts.length ? kRep.itemAt(kBox.opts.findIndex(o => o.k === kBox.val)) : null
                    x: it ? it.x + 4 : 4; width: it ? it.width : 0; y: 3; height: 24; radius: 8; color: Cfg.acc(0.22)
                    Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                }
                Row {
                    id: kRow; x: 4; y: 3
                    Repeater {
                        id: kRep
                        model: kBox.opts
                        delegate: Item {
                            required property var modelData
                            width: kr.implicitWidth + 22; height: 24
                            Row { id: kr; anchors.centerIn: parent; spacing: 6
                                Text { text: modelData.i; font.family: wpk.fIcon; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
                                       color: kBox.val === modelData.k ? wpk.cAccent : wpk.cMuted }
                                Text { text: Cfg.tr(modelData.t); font.family: wpk.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter
                                       color: kBox.val === modelData.k ? wpk.cAccent : wpk.cFg } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: kBox.pick(parent.modelData.k) }
                        }
                    }
                }
            }

            // ── big preview ──────────────────────────
            ClippingRectangle {
                id: big
                anchors { left: parent.left; right: parent.right; top: r3.bottom; topMargin: 12; bottom: strip.top; bottomMargin: 12; leftMargin: 16; rightMargin: 16 }
                radius: 18; color: wpk.cCard
                readonly property var it: wpk.curShown

                WallThumb {
                    anchors.fill: parent
                    visible: big.it !== null && !big.it.wh
                    file: big.it && !big.it.wh ? big.it.file : ""
                    size: 1600
                    live: wpk.shown
                }
                Image {
                    anchors.fill: parent
                    visible: big.it !== null && big.it.wh === true
                    source: big.it && big.it.wh ? big.it.large : ""
                    fillMode: Image.PreserveAspectCrop; asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
                Image {
                    id: full
                    anchors.fill: parent
                    visible: big.it !== null && big.it.wh === true
                    source: big.it && big.it.wh ? big.it.path : ""
                    sourceSize.width: big.width * 1.5
                    fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true; mipmap: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 260 } }
                }
                Rectangle { id: spin   // loading the full picture
                    visible: big.it !== null && big.it.wh === true && full.status === Image.Loading
                    anchors { right: parent.right; top: parent.top; margins: 12 }
                    width: 26; height: 26; radius: 13; color: "#a60f1119"
                    Text { anchors.centerIn: parent; text: "\uf110"; font.family: wpk.fIcon; font.pixelSize: 11; color: wpk.cFg
                           RotationAnimation on rotation { from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: spin.visible } }
                }
                // wheel over the preview = previous / next
                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.NoButton
                    property real acc: 0
                    onWheel: e => { acc += e.angleDelta.y + e.angleDelta.x; if (Math.abs(acc) >= 120) { wpk.step(acc > 0 ? -1 : 1); acc = 0; } }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 70
                    gradient: Gradient { GradientStop { position: 0; color: "#000f1119" } GradientStop { position: 1; color: "#990f1119" } }
                }
                // empty / loading
                Text {
                    anchors.centerIn: parent
                    visible: wpk.shownItems.length === 0
                    text: wpk.busy ? Cfg.tr("Loading…") : Cfg.tr("Nothing here yet")
                    color: wpk.cMuted; font.family: wpk.fUi; font.pixelSize: 14
                }
                // in use
                Rectangle {
                    visible: big.it !== null && !big.it.wh && big.it.file === Cfg.data.wallpaper
                    anchors { right: parent.right; top: parent.top; margins: 12 }
                    width: iuRow.implicitWidth + 18; height: 26; radius: 13; color: wpk.cAccent
                    Row { id: iuRow; anchors.centerIn: parent; spacing: 6
                        Text { text: ""; font.family: wpk.fIcon; font.pixelSize: 10; color: wpk.cAccFg; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: Cfg.tr("In use"); font.family: wpk.fUi; font.pixelSize: 11; font.weight: Font.Bold; color: wpk.cAccFg; anchors.verticalCenter: parent.verticalCenter } }
                }
                // info
                Row {
                    visible: big.it !== null
                    anchors { left: parent.left; bottom: parent.bottom; margins: 12 }
                    spacing: 6
                    Badge { label: big.it && !big.it.wh && wpk.isVideo(big.it.file) ? Cfg.tr("Live") : Cfg.tr("Picture")
                            icon: big.it && !big.it.wh && wpk.isVideo(big.it.file) ? "" : "" }
                    Badge { label: big.it ? big.it.type : "" }
                    Badge { visible: !!(big.it && big.it.res); label: big.it && big.it.res ? big.it.res : "" }
                    Badge { label: big.it ? big.it.date : ""; icon: "" }
                }
                Text {
                    visible: big.it !== null && !big.it.wh
                    anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
                    width: parent.width * 0.4; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle
                    text: big.it && big.it.file ? big.it.file.split("/").pop() : ""
                    color: "#d9ffffff"; font.family: wpk.fUi; font.pixelSize: 11
                }
            }

            // ── thumbnail strip ──────────────────────
            ListView {
                id: strip
                anchors { left: parent.left; right: parent.right; bottom: r5.top; bottomMargin: 12; leftMargin: 16; rightMargin: 16 }
                height: 76
                orientation: ListView.Horizontal
                spacing: 10
                clip: true
                // a ListModel of indexes instead of the JS array: a new array resets the view to the start
                // (that happened when Wallhaven loaded the next page); new items are appended, the scroll stays
                model: ListModel { id: stripModel }
                property int synced: 0
                function sync() {
                    const n = wpk.shownItems.length;
                    if (n < synced || (n > 0 && synced > 0 && stripModel.count !== synced)) { stripModel.clear(); synced = 0; }
                    for (let i = synced; i < n; i++) stripModel.append({ i: i });
                    synced = n;
                }
                Connections {
                    target: wpk
                    property var last: []
                    function onShownItemsChanged() {
                        // the same list grown at the end = append; anything else = start over
                        const a = wpk.shownItems, l = last;
                        const grown = l.length > 0 && a.length >= l.length && l.every((x, k) => (x.file || x.id) === (a[k].file || a[k].id));
                        if (!grown) { stripModel.clear(); strip.synced = 0; }
                        strip.sync(); last = a.slice();
                    }
                }
                Component.onCompleted: sync()
                currentIndex: wpk.sel
                // clearing the model resets currentIndex and drops the binding: keep following wpk.sel
                Connections { target: wpk; function onSelChanged() { if (strip.currentIndex !== wpk.sel) strip.currentIndex = wpk.sel; } }
                onCountChanged: if (currentIndex !== wpk.sel && wpk.sel < count) currentIndex = wpk.sel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                highlightMoveDuration: 260
                preferredHighlightBegin: width / 2 - 66; preferredHighlightEnd: width / 2 + 66
                highlightRangeMode: ListView.NoHighlightRange
                boundsBehavior: Flickable.StopAtBounds
                onAtXEndChanged: if (atXEnd && wpk.source === "wallhaven" && count > 0) wpk.whFetch()
                highlightFollowsCurrentItem: true
                delegate: Item {
                    id: th
                    required property int i
                    readonly property int index: i
                    readonly property var modelData: wpk.shownItems[i] || ({ wh: false, file: "" })
                    readonly property bool cur: index === wpk.sel
                    readonly property bool inUse: !modelData.wh && modelData.file === Cfg.data.wallpaper
                    width: 132; height: 76
                    ClippingRectangle {
                        anchors.fill: parent; radius: 14; color: wpk.cCard
                        WallThumb { anchors.fill: parent; visible: !th.modelData.wh; file: th.modelData.wh ? "" : th.modelData.file; size: 280 }
                        Image { anchors.fill: parent; visible: th.modelData.wh === true; source: th.modelData.wh ? th.modelData.thumb : ""
                                fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 280 }
                        Rectangle { anchors.fill: parent; color: "#0f1119"; opacity: th.cur ? 0 : tma.containsMouse ? 0.1 : 0.35
                                    Behavior on opacity { NumberAnimation { duration: 160 } } }
                        Rectangle {
                            visible: !th.modelData.wh && wpk.isVideo(th.modelData.file)
                            anchors { left: parent.left; top: parent.top; margins: 6 }
                            width: 18; height: 18; radius: 9; color: "#a60f1119"
                            Text { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; text: ""; font.family: wpk.fIcon; font.pixelSize: 7; color: "#ffffff" }
                        }
                        Rectangle {
                            visible: th.inUse
                            anchors { right: parent.right; top: parent.top; margins: 6 }
                            width: 18; height: 18; radius: 9; color: wpk.cAccent
                            Text { anchors.centerIn: parent; text: ""; font.family: wpk.fIcon; font.pixelSize: 8; color: wpk.cAccFg }
                        }
                    }
                    Rectangle { anchors.fill: parent; radius: 14; color: "transparent"; border.width: th.cur ? 2 : 0; border.color: wpk.cAccent }
                    MouseArea {
                        id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { wpk.sel = th.index; panel.forceActiveFocus(); }
                        onDoubleClicked: wpk.apply(th.modelData)
                    }
                }
            }

            MouseArea {
                anchors.fill: strip
                acceptedButtons: Qt.NoButton
                z: 5
                onWheel: e => {
                    const d = Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y) ? e.angleDelta.x : e.angleDelta.y;
                    const max = strip.originX + Math.max(0, strip.contentWidth - strip.width);
                    stripAnim.to = Math.max(strip.originX, Math.min(max, (stripAnim.running ? stripAnim.to : strip.contentX) - d * 1.5));
                    stripAnim.restart();
                    if (wpk.source === "wallhaven" && stripAnim.to >= max - 300) wpk.whFetch();
                }
            }
            NumberAnimation { id: stripAnim; target: strip; property: "contentX"; duration: 220; easing.type: Easing.OutCubic }

            // ── bottom: apply ────────────────────────
            Item {
                id: r5
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                height: 36
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    visible: wpk.downloading
                    text: Cfg.tr("Downloading…"); color: wpk.cMuted; font.family: wpk.fUi; font.pixelSize: 12
                }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: apRow.implicitWidth + 36; height: 36; radius: 12
                    readonly property bool can: wpk.curShown !== null && !wpk.downloading
                    opacity: can ? 1 : 0.5
                    color: ama.containsMouse && can ? Qt.lighter(wpk.cAccent, 1.08) : wpk.cAccent
                    Row { id: apRow; anchors.centerIn: parent; spacing: 8
                        Text { text: wpk.curShown && wpk.curShown.wh ? "" : ""; font.family: wpk.fIcon; font.pixelSize: 12; color: wpk.cAccFg; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: Cfg.tr(wpk.curShown && wpk.curShown.wh ? "Download & apply" : "Apply"); font.family: wpk.fUi; font.pixelSize: 13; font.weight: Font.Bold; color: wpk.cAccFg; anchors.verticalCenter: parent.verticalCenter } }
                    MouseArea { id: ama; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (parent.can) wpk.apply(wpk.curShown) }
                }
            }
        }
    }
}
