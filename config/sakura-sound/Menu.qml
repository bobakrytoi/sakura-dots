// Context menu (inside the window). open(entries, point); entry = {icon, label, act} | {sep: true}
import QtQuick

Item {
    id: mn
    anchors.fill: parent
    visible: entries.length > 0
    property var entries: []
    property point at: Qt.point(0, 0)
    function open(list, p) { entries = list; at = p; }
    function close() { entries = []; }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: mn.close(); onWheel: mn.close() }
    Rectangle {
        id: box
        x: Math.min(mn.at.x, mn.width - width - 8)
        y: Math.min(mn.at.y, mn.height - height - 8)
        width: 230; height: col.implicitHeight + 12; radius: 14
        color: Theme.pop
        border.width: 1; border.color: Theme.popLine
        scale: mn.visible ? 1 : 0.96
        transformOrigin: Item.TopLeft
        Behavior on scale { NumberAnimation { duration: Theme.dur(140); easing.type: Easing.OutCubic } }
        Column {
            id: col
            x: 6; y: 6; width: parent.width - 12
            Repeater {
                model: mn.entries
                Item {
                    required property var modelData
                    width: col.width; height: modelData.sep ? 9 : 34
                    Rectangle { visible: !!modelData.sep; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Theme.popLine }
                    Rectangle {
                        visible: !modelData.sep
                        anchors.fill: parent; radius: 9; color: eMa.containsMouse ? Theme.a(Theme.accent, 0.14) : "transparent"
                        Row {
                            anchors.verticalCenter: parent.verticalCenter; leftPadding: 10; spacing: 10
                            Ico { name: modelData.icon || ""; size: 15; color: eMa.containsMouse ? Theme.accent : Theme.muted; width: 18 }
                            Text { text: modelData.label || ""; color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: eMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { const a = modelData.act; mn.close(); if (a) a(); } }
                    }
                }
            }
        }
    }
}
