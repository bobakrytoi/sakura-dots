// sakura mono - notification center: flows out of the top bar under the bell (DropPanel.qml).
// Quick toggles (Wi‑Fi, Bluetooth, Do not disturb, night light, microphone) and every notification
// that has not been dismissed yet. Super+N · qs ipc call notifs toggle
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import QtQuick

Scope {
    id: nc
    property var topBar: null
    property var settings: null
    property bool shown: false
    property var screen0: Quickshell.screens[0]
    property real anchorX: -1
    readonly property string covering: drop.covering
    onShownChanged: if (shown) { Notifs.seen(); wifiProc.running = true; }

    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cCard:   "#14ffffff"
    readonly property color cHover:  "#29ffffff"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"

    function toggleAt(screenName, x) {
        if (shown) { shown = false; return; }
        if (drop.justClosed()) return;
        const sc = Quickshell.screens.find(s => s.name === screenName);
        if (sc) screen0 = sc;
        anchorX = x; shown = true;
    }
    IpcHandler {
        target: "notifs-center"
        function toggle(): void { if (nc.shown) nc.shown = false; else { nc.screen0 = Cfg.mainScreen || Quickshell.screens[0]; nc.anchorX = -1; nc.shown = true; } }
    }

    // wifi radio (nmcli)
    property bool wifiOn: false
    Process { id: wifiProc; command: ["nmcli", "radio", "wifi"]; stdout: StdioCollector { onStreamFinished: nc.wifiOn = this.text.trim() === "enabled" } }
    readonly property var bt: Bluetooth.defaultAdapter
    PwObjectTracker { objects: [ Pipewire.defaultAudioSource ] }
    readonly property var mic: Pipewire.defaultAudioSource

    readonly property var toggles: [
        { k: "wifi",  icon: "", t: "Wi-Fi",          on: wifiOn },
        { k: "bt",    icon: "", t: "Bluetooth",      on: !!(bt && bt.enabled), hide: !bt },
        { k: "dnd",   icon: Notifs.dnd ? "" : "", t: "Do not disturb", on: Notifs.dnd },
        { k: "night", icon: "", t: "Night light",    on: !!(settings && (settings.cfg.warmth || 0) > 0) },
        { k: "mic",   icon: mic && mic.audio && mic.audio.muted ? "" : "", t: "Microphone", on: !!(mic && mic.audio && !mic.audio.muted) }
    ].filter(x => !x.hide)
    function flip(k) {
        if (k === "wifi") { Quickshell.execDetached(["nmcli", "radio", "wifi", wifiOn ? "off" : "on"]); wifiOn = !wifiOn; }
        else if (k === "bt" && bt) bt.enabled = !bt.enabled;
        else if (k === "dnd") Notifs.toggleDnd();
        else if (k === "night" && settings) settings.setCfg("warmth", (settings.cfg.warmth || 0) > 0 ? 0 : 0.5);
        else if (k === "mic" && mic && mic.audio) mic.audio.muted = !mic.audio.muted;
    }

    DropPanel {
        id: drop
        topBar: nc.topBar
        shown: nc.shown
        onCloseRequested: nc.shown = false
        screen0: nc.screen0
        anchorX: nc.anchorX
        boxW: 420
        boxH: 580
        ns: "notifcenter"

        Item {
            anchors { fill: parent; margins: 16; topMargin: 14 }

            // header
            Item {
                id: head
                width: parent.width; height: 30
                Row {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Text { text: Cfg.tr("Notifications"); font.family: nc.fUi; font.pixelSize: 16; font.weight: Font.Bold; color: nc.cFg }
                    Rectangle { visible: Notifs.count > 0; anchors.verticalCenter: parent.verticalCenter; width: cntT.implicitWidth + 12; height: 20; radius: 10; color: Cfg.acc(0.2)
                        Text { id: cntT; anchors.centerIn: parent; text: Notifs.count; font.family: nc.fUi; font.pixelSize: 11; font.weight: Font.Bold; color: nc.cAccent } }
                }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    visible: Notifs.count > 0
                    width: clrRow.implicitWidth + 20; height: 28; radius: 9
                    color: clrMa.containsMouse ? nc.cHover : nc.cCard
                    Row { id: clrRow; anchors.centerIn: parent; spacing: 6
                        Text { text: ""; font.family: nc.fIcon; font.pixelSize: 11; color: clrMa.containsMouse ? nc.cAccent : nc.cMuted; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: Cfg.tr("Clear all"); font.family: nc.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: nc.cFg; anchors.verticalCenter: parent.verticalCenter } }
                    MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.clearAll() }
                }
            }

            // quick toggles
            Row {
                id: tg
                anchors { top: head.bottom; topMargin: 12 }
                width: parent.width
                spacing: 8
                Repeater {
                    model: nc.toggles
                    Rectangle {
                        required property var modelData
                        width: (tg.width - 8 * (nc.toggles.length - 1)) / nc.toggles.length; height: 64; radius: 16
                        color: modelData.on ? nc.cAccent : tm.containsMouse ? nc.cHover : nc.cCard
                        scale: tm.pressed ? 0.95 : 1
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        Column { anchors.centerIn: parent; spacing: 6
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; font.family: nc.fIcon; font.pixelSize: 16; color: modelData.on ? nc.cAccFg : nc.cFg }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Cfg.tr(modelData.t); font.family: nc.fUi; font.pixelSize: 10; font.weight: Font.DemiBold
                                   color: modelData.on ? nc.cAccFg : nc.cMuted; width: Math.min(implicitWidth, parent.parent.width - 8); elide: Text.ElideRight } }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nc.flip(parent.modelData.k) }
                    }
                }
            }

            // list
            ListView {
                id: list
                anchors { top: tg.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom }
                clip: true; spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: Notifs.list
                delegate: NotifCard {
                    required property var modelData
                    n: modelData
                    width: list.width
                    onCloseClicked: Notifs.dismiss(modelData)
                }
                add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
                remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 160 } }
                Column {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    spacing: 10
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Notifs.dnd ? "" : ""; font.family: nc.fIcon; font.pixelSize: 34; color: Cfg.acc(0.5) }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Cfg.tr("All caught up"); font.family: nc.fUi; font.pixelSize: 13; color: nc.cMuted }
                }
            }
        }
    }
}
