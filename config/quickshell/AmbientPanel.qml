// sakura mono - the ambient sounds card next to the edge drum: a tile per sound.
// Click = on / off, wheel over a tile = its volume, right click on Noise = white → pink → brown.
import QtQuick

Item {
    id: ap
    required property var amb
    readonly property color cFg: "#eceef4"
    readonly property color cMuted: "#8a8fa3"
    readonly property int tileW: 92
    readonly property int tileH: 100
    implicitWidth: grid.width + 28
    implicitHeight: head.height + grid.height + 14 + 12 + 14

    Item {
        id: head
        x: 14; y: 14; width: parent.width - 28; height: 24
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Cfg.tr("Ambient sounds"); color: ap.cFg
            font.family: Cfg.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold
        }
        Rectangle {        // stop all
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            visible: ap.amb.playing
            width: stopRow.implicitWidth + 16; height: 24; radius: 12
            color: sa.containsMouse ? Cfg.acc(0.28) : Cfg.acc(0.14)
            Behavior on color { ColorAnimation { duration: 120 } }
            Row {
                id: stopRow; anchors.centerIn: parent; spacing: 5
                Text { text: ""; font.family: "Symbols Nerd Font"; font.pixelSize: 9; color: Cfg.accent; anchors.verticalCenter: parent.verticalCenter }
                Text { text: Cfg.tr("Stop all"); font.family: Cfg.fontUi; font.pixelSize: 11; color: ap.cFg; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: sa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ap.amb.stopAll() }
        }
    }

    Grid {
        id: grid
        x: 14; y: head.y + head.height + 12
        columns: 3; spacing: 8
        Repeater {
            model: ap.amb.sounds
            Rectangle {
                id: tile
                required property var modelData
                readonly property var g: ap.amb.get(modelData.id)
                readonly property bool on: g.on
                readonly property bool hot: ta.containsMouse
                property bool showVol: false
                width: ap.tileW; height: ap.tileH; radius: 16
                color: on ? Cfg.acc(hot ? 0.30 : 0.20) : hot ? "#16ffffff" : "#0bffffff"
                border.width: 1; border.color: on ? Cfg.acc(0.55) : "#14ffffff"
                scale: ta.pressed ? 0.95 : 1
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 90 } }
                Timer { id: volT; interval: 900; onTriggered: tile.showVol = false }

                Text {
                    id: ic
                    anchors.horizontalCenter: parent.horizontalCenter; y: 16
                    text: tile.modelData.icon; font.family: "Symbols Nerd Font"; font.pixelSize: 26
                    color: tile.on ? Cfg.accent : tile.hot ? ap.cFg : ap.cMuted
                    Behavior on color { ColorAnimation { duration: 140 } }
                    // breathes while it plays
                    SequentialAnimation on opacity {
                        running: tile.on; loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.55; duration: 1400; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 52
                    text: tile.showVol ? tile.g.vol + "%"
                        : Cfg.tr(tile.modelData.label) + (tile.modelData.noise ? " · " + Cfg.tr(ap.amb.noiseColor) : "")
                    color: tile.on ? ap.cFg : ap.cMuted
                    font.family: Cfg.fontUi; font.pixelSize: 11; font.weight: tile.showVol ? Font.Bold : Font.Normal
                    width: parent.width - 8; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                }
                // volume
                Rectangle {
                    x: 14; y: parent.height - 18; width: parent.width - 28; height: 4; radius: 2
                    color: "#1effffff"
                    Rectangle {
                        width: parent.width * tile.g.vol / 100; height: parent.height; radius: 2
                        color: Cfg.accent; opacity: tile.on ? 1 : 0.35
                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                }
                MouseArea {
                    id: ta; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: m => {
                        if (m.button === Qt.RightButton) { if (tile.modelData.noise) ap.amb.cycleNoise(); }
                        else ap.amb.toggle(tile.modelData.id);
                    }
                    property real acc: 0
                    onWheel: w => {
                        acc += w.angleDelta.y;
                        while (Math.abs(acc) >= 120) {
                            const s = acc > 0 ? 1 : -1;
                            ap.amb.nudge(tile.modelData.id, 5 * s);
                            acc -= 120 * s;
                        }
                        tile.showVol = true; volT.restart();
                    }
                }
            }
        }
    }
}
