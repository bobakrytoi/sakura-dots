// Round icon button: hover = soft fill, `on` = accent, `strong` = filled accent disc.
import QtQuick

Item {
    id: b
    property string icon: ""
    property int size: 36
    property int iconSize: Math.round(size * 0.5)
    property bool on: false
    property bool strong: false
    property bool dim: false
    property string tip: ""
    property color tint: Theme.fg
    signal clicked()
    signal wheel(int dy)
    implicitWidth: size; implicitHeight: size
    opacity: dim ? 0.35 : 1

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: b.strong ? Theme.accent : ma.containsMouse ? Theme.hover : "transparent"
        scale: ma.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Theme.dur(90) } }
        Behavior on color { ColorAnimation { duration: Theme.dur(120) } }
    }
    Ico {
        anchors.centerIn: parent
        // optical centre: a play triangle looks left-heavy when its box is centred
        anchors.horizontalCenterOffset: b.icon === "play" ? Math.round(b.iconSize * 0.09) : 0
        anchors.verticalCenterOffset: b.icon === "play" ? Math.round(b.iconSize * 0.03) : 0
        name: b.icon; size: b.iconSize
        color: b.strong ? Theme.accFg : b.on ? Theme.accent : (ma.containsMouse ? Theme.fg : b.tint)
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !b.dim
        onClicked: b.clicked()
        onWheel: w => b.wheel(w.angleDelta.y)
    }
}
