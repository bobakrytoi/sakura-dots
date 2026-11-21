import QtQuick

Rectangle {
    id: b
    property int glyph: 0
    property bool on: false
    property int size: 34
    signal clicked()
    width: size; height: size; radius: size / 2.6
    color: on ? Theme.a(Theme.accent, 0.2) : ma.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.0)
    border.width: 1
    border.color: on ? Theme.a(Theme.accent, 0.25) : Qt.rgba(1, 1, 1, ma.containsMouse ? 0.06 : 0)
    scale: ma.pressed ? 0.9 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.002 } }
    Behavior on color { ColorAnimation { duration: 160 } }
    Text {
        anchors.centerIn: parent
        text: String.fromCodePoint(b.glyph)
        font.family: Theme.fIcon
        font.pixelSize: Math.round(b.size * 0.52)
        color: b.on ? Theme.accent : ma.containsMouse ? Theme.fg : Theme.dim
        Behavior on color { ColorAnimation { duration: 160 } }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}
