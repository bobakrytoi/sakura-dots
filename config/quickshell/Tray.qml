// sakura mono - system tray: "^" flyout with hidden icons + pinned icons on the top bar
// waybar draws the pinned ones (image#tray0..7 via ~/.config/waybar/scripts/tray-slot.py),
// everything else lives in this flyout. Pinned list: ~/.config/sakura/tray.json
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick
import QtQml

Scope {
    id: tr

    // palette
    readonly property color cBg:     Cfg.glass
    readonly property color cCard:   "#14ffffff"
    readonly property color cCard2:  "#1fffffff"
    readonly property color cHover:  "#29ffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cFaint:  "#5d6275"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"
    function ic(cp) { return String.fromCodePoint(cp); }

    readonly property string home: Quickshell.env("HOME")
    readonly property string cfgPath: home + "/.config/sakura/tray.json"
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") + "/sakura-tray"
    readonly property int maxSlots: 8
    readonly property int waybarSignal: 11

    // ── pinned list ───────────────────────────────────────────
    property var pinned: []
    FileView {
        path: tr.cfgPath; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { const j = JSON.parse(text()); tr.pinned = Array.isArray(j.pinned) ? j.pinned : []; } catch (e) {} }
    }
    Process { id: saver }
    function setPinned(p) {
        pinned = p;
        saver.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1.tmp" && mv "$1.tmp" "$1"',
                         "sh", cfgPath, JSON.stringify({ pinned: p }, null, 2)];
        saver.running = true;
    }
    function isPinned(it) { return pinned.indexOf(it.id) >= 0; }
    function togglePin(it) {
        const p = pinned.filter(x => x !== it.id);
        if (!isPinned(it)) { if (slots.length >= maxSlots) return; p.push(it.id); }
        setPinned(p);
    }

    // ── items ─────────────────────────────────────────────────
    property int rev: 0
    readonly property var items: { rev; return SystemTray.items.values.slice(); }
    readonly property var slots: {
        const out = [];
        for (const id of pinned) {
            const it = items.find(i => i.id === id);
            if (it && it.status !== Status.Passive) out.push(it);
            if (out.length >= maxSlots) break;
        }
        return out;
    }
    readonly property var hidden: items.filter(i => slots.indexOf(i) < 0)

    function nameOf(it) {
        if (!it) return "";
        const tt = it.tooltipTitle || "", flat = x => String(x).toLowerCase().replace(/[^a-z0-9а-я]/g, "");
        if (tt && (flat(tt) === flat(it.title) || flat(tt) === flat(it.id))) return tt;   // "AyuGramDesktop" -> "AyuGram Desktop"
        if (it.title && it.title !== it.id) return it.title;
        let n = (it.id || "").replace(/_status_icon_\d+$/, "").replace(/[-_]icon$/i, "").replace(/[-_]applet$/i, "");
        if (n === "nm") n = "Network";
        return n.charAt(0).toUpperCase() + n.slice(1);
    }
    function subOf(it) {
        const t = it.tooltipTitle || "";
        return t && t !== nameOf(it) ? t : "";
    }

    // keep waybar's pinned slots in sync
    Instantiator {
        model: SystemTray.items
        delegate: Connections {
            required property var modelData
            target: modelData
            function onIconChanged() { tr.bump(); }
            function onStatusChanged() { tr.rev++; tr.bump(); }
            function onIdChanged() { tr.rev++; tr.bump(); }
            function onTooltipTitleChanged() { tr.bump(); }
        }
    }
    // Mullvad's tray icon does not come back by itself when the tray restarts (Discord etc. do):
    // shortly after the tray starts, if Mullvad's window process runs but has no icon, revive it quietly
    Timer {
        interval: 9000; running: true
        onTriggered: if (!SystemTray.items.values.some(i => /mullvad/i.test(i.id || "")))
            Quickshell.execDetached(["sh", "-c", "pgrep -f '^/opt/Mullvad VPN/mullvad-gui' >/dev/null && exec \"$HOME/.local/bin/sakura-tray-app\" revive"])
    }
    onSlotsChanged: bump()
    onItemsChanged: bump()
    Component.onCompleted: bump()
    Timer { id: pushT; interval: 120; onTriggered: tr.pushSlots() }
    function bump() { pushT.restart(); }
    Process { id: pusher }
    function pushSlots() {
        if (pusher.running) { pushT.restart(); return; }
        const data = slots.map(i => ({ id: i.id, title: nameOf(i) }));
        pusher.command = ["sh", "-c",
            'mkdir -p "$1" && printf "%s" "$2" > "$1/slots.tmp" && mv "$1/slots.tmp" "$1/slots.json"; python3 -I "$3"',
            "sh", runDir, JSON.stringify(data), home + "/.config/waybar/scripts/tray-slot.py"];
        pusher.running = true;
    }

    // ── where to open (under the cursor, on its monitor) ──────
    property var screen0: Quickshell.screens[0]
    // the bar can sit next to the dock (barpos.sh) - then open above it instead of under the top bar
    property bool barDown: false
    FileView { path: Quickshell.env("HOME") + "/.config/sakura/barpos"; watchChanges: true; onFileChanged: reload()
        onLoaded: tr.barDown = text().trim() === "bottom"; onLoadFailed: tr.barDown = false }
    readonly property bool atBottom: barDown && !!screen0 && screen0.name === Cfg.mainName
    property real cx: 0
    property real screenW: 1920
    Process {
        id: cur
        property var after: null
        command: ["sh", "-c", "hyprctl cursorpos -j; echo '@@'; hyprctl monitors -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parts = this.text.split("@@");
                    const c = JSON.parse(parts[0]), ms = JSON.parse(parts[1]);
                    const m = ms.find(m => c.x >= m.x && c.x < m.x + m.width / m.scale && c.y >= m.y && c.y < m.y + m.height / m.scale)
                              || ms.find(m => m.focused) || ms[0];
                    const sc = Quickshell.screens.find(s => s.name === m.name);
                    if (sc) tr.screen0 = sc;
                    tr.cx = c.x - m.x; tr.screenW = m.width / m.scale;
                } catch (e) {}
                const f = cur.after; cur.after = null;
                if (f) f();
            }
        }
    }
    function atCursor(f) { cur.after = f; cur.running = true; }

    // ── flyout state ──────────────────────────────────────────
    property bool shown: false
    property string mode: "grid"          // grid | edit | menu
    property var menuItem: null
    property var menuStack: []
    property real closedAt: 0
    onShownChanged: {
        if (!shown) { closedAt = Date.now(); menuStack = []; hoverCell = null; }
        if (topBar && !atBottom && screen0) fromGeo = shown ? topBar.geoFor(screen0.name) : topBar.restGeoFor(screen0.name);
    }
    function justClosed() { return Date.now() - closedAt < 350; }
    function open(m) { atCursor(() => { tr.mode = m; tr.shown = true; }); }
    // right click: our own menu - "pin / unpin" first, then the app's own entries (if it has any)
    function openMenu(it) {
        if (!it) return;
        atCursor(() => { tr.menuItem = it; tr.menuStack = it.hasMenu && it.menu ? [it.menu] : []; tr.mode = "menu"; tr.shown = true; });
    }
    // Mullvad's Electron window can't always come back from its tray-hide on Wayland:
    // left click and its "Open Mullvad VPN" entry go through ~/.local/bin/mullvad-open (focus / restart GUI only)
    function isMullvad(it) { return !!it && /mullvad/i.test(it.id || ""); }
    function openMullvad() { Quickshell.execDetached([home + "/.local/bin/mullvad-open"]); }
    function click(it) {
        if (!it) return;
        if (it.onlyMenu && it.hasMenu) { openMenu(it); return; }
        if (isMullvad(it)) { openMullvad(); shown = false; return; }
        it.activate(); shown = false;
    }

    IpcHandler {
        target: "tray"
        function toggle(): void { if (tr.shown || tr.justClosed()) { tr.shown = false; return; } tr.open("grid"); }
        function edit(): void { if (tr.shown && tr.mode === "edit") { tr.shown = false; return; } tr.open("edit"); }
        function activate(n: int): void { tr.click(tr.slots[n]); }
        function secondary(n: int): void { const it = tr.slots[n]; if (it) it.secondaryActivate(); }
        function menu(n: int): void { tr.openMenu(tr.slots[n]); }
        function scroll(n: int, d: int): void { const it = tr.slots[n]; if (it) it.scroll(d * 120, false); }
    }

    QsMenuOpener { id: menuOpener; menu: tr.menuStack.length ? tr.menuStack[tr.menuStack.length - 1] : null }
    readonly property bool menuRoot: menuStack.length <= 1
    readonly property bool menuItemPinned: { pinned; return !!menuItem && pinned.indexOf(menuItem.id) >= 0; }
    readonly property bool barFull: slots.length >= maxSlots

    // ── pieces ────────────────────────────────────────────────
    component Icon: Text { font.family: tr.fIcon; color: tr.cMuted; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }

    component Toggle: Rectangle {
        property bool on: false
        width: 36; height: 20; radius: 10
        color: on ? tr.cAccent : tr.cCard2
        border.width: on ? 0 : 1; border.color: tr.cBorder
        Behavior on color { ColorAnimation { duration: 140 } }
        Rectangle {
            width: 14; height: 14; radius: 7; anchors.verticalCenter: parent.verticalCenter
            x: parent.on ? parent.width - width - 3 : 3
            color: parent.on ? tr.cAccFg : tr.cMuted
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
    }

    readonly property int gridCols: Math.max(3, Math.min(5, hidden.length))

    // with the bar at the top, the flyout IS the top bar morphed, like the dashboard: it takes the bar's shape over
    // (TopBar.drawShape) and turns it into its own box under the "^" button - and back into the collapsed bar
    // when it closes. Meanwhile TopBar hides itself on this screen (covering), so only one shape is on screen.
    property var topBar: null
    readonly property int boxW: mode === "grid" ? gridCols * 50 + 24 : mode === "edit" ? 330 : 270
    readonly property real dropX: Math.round(Math.max(30, Math.min(screenW - boxW - 30, cx - boxW / 2)))   // 30: room for the ears
    property var fromGeo: null                      // the bar's shape it starts from / ends in (set in onShownChanged)
    readonly property string covering: win.visible && !atBottom && screen0 ? screen0.name : ""

    PanelWindow {
        id: win
        visible: tr.shown || grow > 0.001          // stays up while it morphs back into the bar
        screen: tr.screen0
        anchors { top: !tr.atBottom; bottom: tr.atBottom; left: true; right: true }    // the bar's shape is wider than the box
        margins.bottom: 76
        implicitHeight: body.implicitHeight + 24
        mask: Region { item: panel }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "trayflyout"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        HyprlandFocusGrab { windows: [ win ]; active: tr.shown; onCleared: tr.shown = false }

        // 0 = the bar's shape, 1 = the whole box; the content fades in at the end (and out first on close)
        property real grow: tr.shown ? 1 : 0
        Behavior on grow { NumberAnimation { duration: 340 * Cfg.anim; easing.type: Easing.OutCubic } }

        Canvas {
            anchors.fill: parent
            readonly property string key: [win.grow, width, height, panel.x, panel.width, tr.fromGeo ? tr.fromGeo.xl : 0, Cfg.glass].join(",")
            onKeyChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                if (!tr.atBottom && tr.topBar && tr.fromGeo) {
                    // the box's own notch spot: its middle (the bar's notch may be off to the side of it)
                    const mid = panel.x + panel.width / 2;
                    const box = { xl: panel.x, xr: panel.x + panel.width, x0: mid - 10, x1: mid + 10, wh: height, d: height, r: 20 };
                    tr.topBar.drawShape(ctx, tr.topBar.lerpGeo(tr.fromGeo, box, win.grow));
                } else {      // above the dock (bar at the bottom): a rounded card growing up from the bottom
                    const h = 30 + (height - 30) * win.grow;
                    ctx.beginPath();
                    ctx.roundedRect(panel.x, height - h, panel.width, h, 20, 20);
                    ctx.fillStyle = tr.cBg;
                    ctx.fill();
                }
            }
        }

        Rectangle {
            id: panel
            x: tr.dropX; width: tr.boxW
            anchors { top: parent.top; bottom: parent.bottom }
            radius: 20; color: "transparent"
            opacity: Math.max(0, (win.grow - 0.55) / 0.45)
            focus: tr.shown
            Keys.onEscapePressed: { if (tr.mode === "menu" && tr.menuStack.length > 1) tr.menuStack = tr.menuStack.slice(0, -1); else tr.shown = false; }

            Column {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8

                // ── GRID: hidden icons ───────────────────────
                Item {
                    visible: tr.mode === "grid"
                    width: parent.width; height: 26
                    Text { anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                           text: Cfg.tr("Hidden icons"); font.family: tr.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: tr.cFg }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 26; height: 26; radius: 9
                        color: editMa.containsMouse ? tr.cCard2 : "transparent"
                        Icon { anchors.centerIn: parent; text: tr.ic(0xf1de); color: editMa.containsMouse ? tr.cAccent : tr.cMuted }
                        MouseArea { id: editMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tr.mode = "edit" }
                    }
                }
                Flow {
                    visible: tr.mode === "grid" && tr.hidden.length > 0
                    width: tr.gridCols * 50
                    anchors.horizontalCenter: parent.horizontalCenter
                    Repeater {
                        model: tr.mode === "grid" ? tr.hidden : []
                        Rectangle {
                            id: cell
                            required property var modelData
                            width: 50; height: 46; radius: 12
                            color: cMa.containsMouse ? tr.cCard2 : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                            IconImage {
                                anchors.centerIn: parent; implicitSize: 20
                                source: cell.modelData.icon
                                opacity: cell.modelData.status === Status.Passive ? 0.45 : 1
                            }
                            Rectangle {
                                visible: cell.modelData.status === Status.NeedsAttention
                                width: 7; height: 7; radius: 4; color: tr.cAccent
                                anchors { right: parent.right; top: parent.top; margins: 9 }
                            }
                            MouseArea {
                                id: cMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                // moving straight onto the neighbour can deliver its "entered" before our "exited":
                                // only clear the caption if it still belongs to this icon
                                onEntered: tr.hoverCell = cell
                                onExited: if (tr.hoverCell === cell) tr.hoverCell = null
                                onClicked: m => {
                                    if (m.button === Qt.RightButton) tr.openMenu(cell.modelData);
                                    else if (m.button === Qt.MiddleButton) cell.modelData.secondaryActivate();
                                    else tr.click(cell.modelData);
                                }
                                onWheel: w => cell.modelData.scroll(w.angleDelta.y, false)
                            }
                        }
                    }
                }
                Text {
                    visible: tr.mode === "grid" && tr.hidden.length === 0
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; topPadding: 6; bottomPadding: 6
                    text: Cfg.tr("Everything is on the bar"); font.family: tr.fUi; font.pixelSize: 12; color: tr.cMuted
                }
                Text {
                    visible: tr.mode === "grid" && tr.hidden.length > 0
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: tr.hoverName              // the hovered icon's name; empty otherwise
                    font.family: tr.fUi; font.pixelSize: 11; color: tr.cFg
                }

                // ── EDIT: choose what goes on the bar ────────
                Item {
                    visible: tr.mode === "edit"
                    width: parent.width; height: 40
                    Column {
                        anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text { text: Cfg.tr("Tray icons"); font.family: tr.fUi; font.pixelSize: 15; font.weight: Font.ExtraBold; color: tr.cFg }
                        Text { text: Cfg.tr("On the bar") + ": " + tr.slots.length + " / " + tr.maxSlots + " · " + Cfg.tr("the rest hide behind ^")
                               font.family: tr.fUi; font.pixelSize: 11; color: tr.cMuted }
                    }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: doneT.implicitWidth + 22; height: 28; radius: 10; color: doneMa.containsMouse ? Qt.lighter(tr.cAccent, 1.08) : tr.cAccent
                        Text { id: doneT; anchors.centerIn: parent; text: Cfg.tr("Done"); font.family: tr.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: tr.cAccFg }
                        MouseArea { id: doneMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tr.mode = "grid" }
                    }
                }
                Rectangle { visible: tr.mode === "edit"; width: parent.width; height: 1; color: tr.cBorder }
                Repeater {
                    model: tr.mode === "edit" ? tr.items : []
                    Rectangle {
                        id: er
                        required property var modelData
                        readonly property bool on: tr.isPinned(modelData)
                        readonly property bool full: !on && tr.slots.length >= tr.maxSlots
                        width: body.width; height: 46; radius: 12
                        color: erMa.containsMouse ? tr.cCard : "transparent"
                        opacity: full ? 0.5 : 1
                        IconImage { id: erIcon; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } implicitSize: 20; source: er.modelData.icon }
                        Column {
                            anchors { left: erIcon.right; leftMargin: 12; right: tog.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text { width: parent.width; elide: Text.ElideRight; text: tr.nameOf(er.modelData)
                                   font.family: tr.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: tr.cFg }
                            Text { width: parent.width; elide: Text.ElideRight; visible: text !== ""
                                   text: er.modelData.status === Status.Passive ? Cfg.tr("idle - hidden by the app") : tr.subOf(er.modelData)
                                   font.family: tr.fUi; font.pixelSize: 11; color: tr.cMuted }
                        }
                        Toggle { id: tog; on: er.on; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } }
                        MouseArea { id: erMa; anchors.fill: parent; hoverEnabled: true; cursorShape: er.full ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: if (!er.full) tr.togglePin(er.modelData) }
                    }
                }

                // ── MENU: the app's own context menu ─────────
                Item {
                    visible: tr.mode === "menu"
                    width: parent.width; height: 30
                    IconImage { id: mIcon; anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter } implicitSize: 16
                                source: tr.menuItem ? tr.menuItem.icon : ""; visible: tr.menuStack.length <= 1 }
                    Icon { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } visible: tr.menuStack.length > 1
                           text: tr.ic(0xf053); color: tr.cAccent
                           MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: tr.menuStack = tr.menuStack.slice(0, -1) } }
                    Text { anchors { left: parent.left; leftMargin: 34; right: parent.right; verticalCenter: parent.verticalCenter }
                           elide: Text.ElideRight
                           text: tr.menuStack.length > 1 ? (tr.menuStack[tr.menuStack.length - 1].text || "") : tr.nameOf(tr.menuItem)
                           font.family: tr.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: tr.cFg }
                }
                Rectangle { visible: tr.mode === "menu"; width: parent.width; height: 1; color: tr.cBorder }
                // pin / unpin on the bar
                Rectangle {
                    id: pinRow
                    visible: tr.mode === "menu" && tr.menuRoot
                    readonly property bool can: tr.menuItemPinned || !tr.barFull
                    width: body.width; height: 34; radius: 9
                    color: pinMa.containsMouse && can ? tr.cCard2 : "transparent"
                    opacity: can ? 1 : 0.45
                    Icon { id: pinIc; anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                           text: tr.ic(0xf08d); font.pixelSize: 13; color: tr.cAccent
                           rotation: tr.menuItemPinned ? 0 : 45 }
                    Text { anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                           elide: Text.ElideRight
                           text: tr.menuItemPinned ? Cfg.tr("Unpin from bar") : (tr.barFull ? Cfg.tr("Bar is full") + " (" + tr.maxSlots + ")" : Cfg.tr("Pin to bar"))
                           font.family: tr.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: tr.cFg }
                    MouseArea { id: pinMa; anchors.fill: parent; hoverEnabled: true; enabled: pinRow.can
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { tr.togglePin(tr.menuItem); tr.shown = false; } }
                }
                Rectangle { visible: tr.mode === "menu" && tr.menuRoot && menuOpener.children.values.length > 0
                            width: parent.width; height: 1; color: tr.cBorder }
                Repeater {
                    model: tr.mode === "menu" && tr.menuStack.length ? menuOpener.children : []
                    Item {
                        id: me
                        required property var modelData
                        width: body.width
                        height: modelData.isSeparator ? 9 : 34
                        Rectangle { visible: me.modelData.isSeparator; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: tr.cBorder }
                        Rectangle {
                            visible: !me.modelData.isSeparator
                            anchors.fill: parent; radius: 9
                            color: meMa.containsMouse && me.modelData.enabled ? tr.cCard2 : "transparent"
                            opacity: me.modelData.enabled ? 1 : 0.4
                            Item {
                                id: lead
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                width: 16; height: 16
                                IconImage { anchors.fill: parent; source: me.modelData.icon || ""; visible: (me.modelData.icon || "") !== "" && me.modelData.buttonType === QsMenuButtonType.None }
                                Rectangle {   // checkbox / radio
                                    visible: me.modelData.buttonType !== QsMenuButtonType.None
                                    anchors.centerIn: parent; width: 14; height: 14
                                    radius: me.modelData.buttonType === QsMenuButtonType.RadioButton ? 7 : 4
                                    color: me.modelData.checkState === Qt.Checked ? tr.cAccent : "transparent"
                                    border.width: me.modelData.checkState === Qt.Checked ? 0 : 1.5; border.color: tr.cMuted
                                    Icon { anchors.centerIn: parent; visible: me.modelData.checkState === Qt.Checked && me.modelData.buttonType === QsMenuButtonType.CheckBox
                                           text: tr.ic(0xf00c); font.pixelSize: 9; color: tr.cAccFg }
                                }
                            }
                            Text {
                                anchors { left: lead.right; leftMargin: 10; right: chev.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                text: (me.modelData.text || "").replace(/_(?!_)/g, "").replace(/__/g, "_")
                                elide: Text.ElideRight
                                font.family: tr.fUi; font.pixelSize: 13; color: tr.cFg
                            }
                            Icon { id: chev; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                   visible: me.modelData.hasChildren; text: tr.ic(0xf054); font.pixelSize: 9 }
                            MouseArea {
                                id: meMa; anchors.fill: parent; hoverEnabled: true; enabled: me.modelData.enabled
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const e = me.modelData;
                                    if (e.hasChildren) tr.menuStack = tr.menuStack.concat([e]);
                                    else if (tr.isMullvad(tr.menuItem) && /^open\b/i.test(e.text || "")) { tr.openMullvad(); tr.shown = false; }
                                    else { e.triggered(); tr.shown = false; }
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: tr.mode === "menu" && !tr.menuRoot && menuOpener.children.values.length === 0
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; topPadding: 4; bottomPadding: 4
                    text: Cfg.tr("Empty"); font.family: tr.fUi; font.pixelSize: 12; color: tr.cMuted
                }
            }
        }
    }
    property var hoverCell: null
    readonly property string hoverName: {
        const it = hoverCell ? hoverCell.modelData : null;
        if (!it) return "";
        const s = subOf(it);
        return nameOf(it) + (s ? " · " + s : "");
    }
}
