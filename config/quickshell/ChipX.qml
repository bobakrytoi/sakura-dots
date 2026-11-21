// sakura mono - the little × on a chip in a list (ModHub): takes it off
import QtQuick

Rectangle {
    id: cx
    property var hub: null
    property var slot: null
    property string mid: ""
    property bool show: false
    property real size: 14
    visible: (show || xm.containsMouse) && !!hub && hub.dragId === "" && !!slot && slot.value.length > slot.min
    width: size; height: size; radius: size / 2
    x: parent.width - size * 0.65; y: -size * 0.35; z: 5
    color: xm.containsMouse ? "#f28fad" : "#3a3d4a"
    Text { anchors.centerIn: parent; text: ""; font.family: "Symbols Nerd Font"; font.pixelSize: cx.size * 0.55; color: "#ffffff" }
    MouseArea { id: xm; anchors.fill: parent; anchors.margins: -2; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cx.slot.remove(cx.mid) }
}
