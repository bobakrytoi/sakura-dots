// sakura mono - the session screen: the wallpaper slowly blurs in over everything, the clock and uptime on top,
// big round buttons in a row (lock · sleep · log out · restart · shut down). Esc or a click outside cancels,
// arrows + Enter work too. Choosing plays the leave choreography (Choreo.leave: the screen clears, bar and dock
// slide back into their edges, the screen dims) and then runs it, saving the session first like PowerMenu.
// Also draws Choreo.veil (the dimming) on every monitor, so the start menu / PowerMenu actions fade out the same way.
// Open: qs ipc call session open | toggle | close · qs ipc call session act <id> · Super+M (powermenu.sh) ·
//       the expand button in PowerMenu.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

Scope {
    id: ss
    property bool opened: false
    property bool leaving: false
    property real p: 0                   // 0 → 1 the screen coming in (blur, dim, cascade of buttons)
    property int sel: -1                 // keyboard selection
    readonly property string fIcon: "Symbols Nerd Font"
    readonly property var actions: [
        { id: "lock",     icon: "", name: "Lock" },
        { id: "sleep",    icon: "", name: "Sleep" },
        { id: "logout",   icon: "", name: "Log out" },
        { id: "restart",  icon: "", name: "Restart" },
        { id: "shutdown", icon: "", name: "Shut down" }
    ]

    function open() {
        if (opened || Choreo.moment === "leave") return;
        leaving = false; sel = -1; upProc.running = true;
        opened = true; inA.restart();
    }
    function close() { if (!opened || leaving) return; inA.stop(); outA.restart(); }
    function toggle() { opened ? close() : open(); }
    function choose(id) {
        if (leaving) return;
        if (!opened) { Choreo.leave(id); return; }
        leaving = true; inA.stop();
        if (id === "lock") { outA.restart(); Choreo.leave("lock"); return; }
        clearA.restart();                       // the screen clears so the fold away is seen
        Choreo.leave(id);
    }
    NumberAnimation { id: inA; target: ss; property: "p"; to: 1; duration: 900 * Cfg.anim; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: outA
        NumberAnimation { target: ss; property: "p"; to: 0; duration: 320 * Cfg.anim; easing.type: Easing.InCubic }
        ScriptAction { script: { ss.opened = false; ss.leaving = false; } }
    }
    SequentialAnimation {
        id: clearA
        NumberAnimation { target: ss; property: "p"; to: 0; duration: 260 * Cfg.anim; easing.type: Easing.InQuad }
        ScriptAction { script: ss.opened = false }
    }
    Connections { target: Choreo; function onMomentChanged() { if (Choreo.moment !== "leave") ss.leaving = false; } }

    IpcHandler {
        target: "session"
        function open(): void { ss.open(); }
        function close(): void { ss.close(); }
        function toggle(): void { ss.toggle(); }
        function act(id: string): void { ss.choose(id); }
    }

    property string uptime: ""
    Process {
        id: upProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector { onStreamFinished: {
            const t = Math.floor(parseFloat(this.text)), d = Math.floor(t / 86400), h = Math.floor(t % 86400 / 3600), m = Math.floor(t % 3600 / 60);
            ss.uptime = (d > 0 ? d + " " + Cfg.tr("d") + " " : "") + (d > 0 || h > 0 ? h + " " + Cfg.tr("h") + " " : "") + m + " " + Cfg.tr("min");
        } }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: sw
            required property var modelData
            readonly property bool main: modelData.name === Cfg.mainName
            screen: modelData
            visible: ss.opened || Choreo.veil > 0
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "session"
            WlrLayershell.keyboardFocus: ss.opened && !ss.leaving && main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: Region { item: ss.opened && !ss.leaving ? full : null }
            Item { id: full; anchors.fill: parent }

            // the wallpaper, blurring in slowly over everything
            WallThumb {
                id: wall
                anchors.fill: parent
                file: Cfg.data.wallpaper || ""
                size: 1920
                opacity: Math.min(1, ss.p * 2.2)
                layer.enabled: ss.opened
                layer.effect: MultiEffect {
                    blurEnabled: true; blurMax: 64
                    blur: 0.15 + 0.85 * ss.p
                    brightness: -0.16 * ss.p
                }
            }
            Rectangle { anchors.fill: parent; opacity: ss.p
                gradient: Gradient { GradientStop { position: 0.0; color: "#550e0e10" } GradientStop { position: 0.55; color: "#200e0e10" } GradientStop { position: 1.0; color: "#880e0e10" } } }
            MouseArea { anchors.fill: parent; enabled: ss.opened; onClicked: ss.close() }

            Item {
                id: content
                anchors.fill: parent
                visible: sw.main && ss.opened
                focus: true
                Keys.onPressed: e => {
                    const n = ss.actions.length;
                    if (e.key === Qt.Key_Escape) ss.close();
                    else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab || e.key === Qt.Key_L) ss.sel = (ss.sel + 1 + n) % n;
                    else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab || e.key === Qt.Key_H) ss.sel = ss.sel < 0 ? n - 1 : (ss.sel - 1 + n) % n;
                    else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) && ss.sel >= 0) ss.choose(ss.actions[ss.sel].id);
                    else return;
                    e.accepted = true;
                }

                // clock + date + uptime, coming down a little
                Column {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: row.top; bottomMargin: 70 }
                    spacing: 2
                    opacity: Choreo.ease((ss.p - 0.1) / 0.6)
                    transform: Translate { y: (1 - Choreo.ease(ss.p / 0.8)) * -18 }
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#a0000000"; shadowBlur: 1.0; blurMax: 40 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Cfg.timeStr(Desk.now, false).replace(/ [AP]M$/, "")
                           font.family: "Inter Display"; font.pixelSize: 120; font.weight: Font.Black; color: "#ffffff" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Cfg.dateLong(Desk.now)
                           font.family: Cfg.fontUi; font.pixelSize: 20; font.weight: Font.DemiBold; color: "#e6ffffff" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; topPadding: 8; visible: ss.uptime !== ""
                           text: Cfg.tr("up") + " " + ss.uptime
                           font.family: Cfg.fontUi; font.pixelSize: 14; color: "#b3ffffff" }
                }

                Row {
                    id: row
                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: 90 }
                    spacing: 34
                    Repeater {
                        model: ss.actions
                        delegate: Item {
                            id: b
                            required property var modelData
                            required property int index
                            readonly property bool hot: ba.containsMouse || ss.sel === index
                            // one after another, rising
                            readonly property real e: Choreo.ease((ss.p - 0.18 - index * 0.07) / 0.5)
                            width: 104; height: 104 + 34
                            opacity: e
                            transform: Translate { y: (1 - b.e) * 40 }
                            Rectangle {
                                id: disc
                                width: 104; height: 104; radius: 52
                                color: b.hot ? Cfg.accent : Cfg.glass
                                border.width: 1; border.color: b.hot ? "transparent" : "#26ffffff"
                                scale: ba.pressed ? 0.93 : (b.hot ? 1.06 : 1)
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text { anchors.centerIn: parent; text: b.modelData.icon; font.family: ss.fIcon; font.pixelSize: 32
                                       color: b.hot ? Cfg.accFg : "#eceef4" }
                            }
                            Text { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                                   text: Cfg.tr(b.modelData.name); font.family: Cfg.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold
                                   color: b.hot ? "#ffffff" : "#ccffffff" }
                            MouseArea { id: ba; width: 104; height: 104; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: if (containsMouse) ss.sel = -1
                                onClicked: ss.choose(b.modelData.id) }
                        }
                    }
                }
            }

            // the screen going dark before leaving (Choreo.leave)
            Rectangle { anchors.fill: parent; color: "#000000"; opacity: Choreo.veil }
        }
    }
}
