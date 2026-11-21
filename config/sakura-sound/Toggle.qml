import QtQuick

Rectangle {
    id: tg
    property bool on: false
    signal toggled()
    width: 42; height: 24; radius: 12
    color: on ? Theme.accent : Theme.cardHi
    Behavior on color { ColorAnimation { duration: Theme.dur(140) } }
    Rectangle {
        width: 18; height: 18; radius: 9; y: 3
        x: tg.on ? tg.width - width - 3 : 3
        color: tg.on ? Theme.accFg : Theme.fg
        Behavior on x { NumberAnimation { duration: Theme.dur(140); easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
}
