// sakura mono - power menu: flows out of the top bar under the power button (DropPanel.qml).
// Same actions as the session screen (SessionScreen.qml, the button top right opens it full screen); they run
// through the leave choreography (Choreo.leave: bar and dock fold away, the screen dims, the session is saved).
import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: pm
    property var topBar: null
    property var session: null             // SessionScreen.qml
    property bool shown: false
    property var screen0: Quickshell.screens[0]
    property real anchorX: -1
    readonly property string covering: drop.covering

    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cCard:   "#14ffffff"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"

    readonly property var actions: [
        { id: "lock",     icon: "\uf023", name: "Lock" },
        { id: "logout",   icon: "\uf08b", name: "Log out" },
        { id: "sleep",    icon: "\uf186", name: "Sleep" },
        { id: "restart",  icon: "\uf01e", name: "Restart" },
        { id: "shutdown", icon: "\uf011", name: "Shut down" }
    ]
    function run(id) { shown = false; Choreo.leave(id); }
    function full() { shown = false; if (session) session.open(); }

    property string uptime: ""
    Process {
        id: upProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector { onStreamFinished: {
            const t = Math.floor(parseFloat(this.text)), d = Math.floor(t / 86400), h = Math.floor(t % 86400 / 3600), m = Math.floor(t % 3600 / 60);
            pm.uptime = (d > 0 ? d + " " + Cfg.tr("d") + " " : "") + (d > 0 || h > 0 ? h + " " + Cfg.tr("h") + " " : "") + m + " " + Cfg.tr("min");
        } }
    }

    // from the top bar: open under that button (x: its middle on that screen)
    function toggleAt(screenName, x) {
        if (shown) { shown = false; return; }
        if (drop.justClosed()) return;
        const sc = Quickshell.screens.find(s => s.name === screenName);
        if (sc) screen0 = sc;
        anchorX = x; upProc.running = true; shown = true;
    }
    IpcHandler { target: "power"; function toggle(): void { if (pm.shown) pm.shown = false; else { pm.anchorX = -1; upProc.running = true; pm.shown = true; } } }

    DropPanel {
        id: drop
        topBar: pm.topBar
        shown: pm.shown
        onCloseRequested: pm.shown = false
        screen0: pm.screen0
        anchorX: pm.anchorX
        boxW: 5 * 60 + 4 * 8 + 32
        boxH: 140
        ns: "power"

        Column {
            anchors { fill: parent; margins: 16 }
            spacing: 12
            Item {
                width: parent.width; height: 16
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Cfg.tr("up") + " " + pm.uptime
                    color: pm.cMuted; font.family: pm.fUi; font.pixelSize: 12
                }
                // the same, full screen (SessionScreen.qml)
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 26; height: 26; radius: 13
                    color: fa.containsMouse ? pm.cAccent : "transparent"
                    Behavior on color { ColorAnimation { duration: 130 } }
                    Text { anchors.centerIn: parent; text: "\uf065"; font.family: pm.fIcon; font.pixelSize: 11
                           color: fa.containsMouse ? pm.cAccFg : pm.cMuted }
                    MouseArea { id: fa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pm.full() }
                }
            }
            Row {
                spacing: 8
                Repeater {
                    model: pm.actions
                    delegate: Rectangle {
                        required property var modelData
                        width: 60; height: 70; radius: 16
                        color: pa.containsMouse ? pm.cAccent : pm.cCard
                        scale: pa.pressed ? 0.94 : 1
                        Behavior on color { ColorAnimation { duration: 130 } }
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 7
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon
                                font.family: pm.fIcon; font.pixelSize: 17; color: pa.containsMouse ? pm.cAccFg : pm.cFg }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Cfg.tr(modelData.name)
                                font.family: pm.fUi; font.pixelSize: 10; font.weight: Font.DemiBold; color: pa.containsMouse ? pm.cAccFg : pm.cMuted }
                        }
                        MouseArea { id: pa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: pm.run(modelData.id) }
                    }
                }
            }
        }
    }
}
