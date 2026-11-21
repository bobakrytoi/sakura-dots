// One-line text that scrolls when it doesn't fit (theme `marquee`); otherwise elides.
import QtQuick

Item {
    id: mq
    property alias text: t1.text
    property alias color: t1.color
    property alias font: t1.font
    property bool active: Theme.marquee
    readonly property bool overflow: t1.implicitWidth > width
    implicitHeight: t1.implicitHeight
    clip: true

    Text {
        id: t1
        width: mq.overflow && mq.active ? implicitWidth : mq.width
        elide: mq.overflow && mq.active ? Text.ElideNone : Text.ElideRight
        x: 0
        SequentialAnimation on x {
            id: run
            running: mq.active && mq.overflow && mq.visible
            loops: Animation.Infinite
            PauseAnimation { duration: 2200 }
            NumberAnimation { from: 0; to: -(t1.implicitWidth + 40); duration: Math.max(3000, (t1.implicitWidth + 40) * 28); easing.type: Easing.Linear }
            onRunningChanged: if (!running) t1.x = 0
        }
    }
    Text {
        visible: mq.active && mq.overflow
        x: t1.x + t1.implicitWidth + 40
        text: t1.text; color: t1.color; font: t1.font
    }
}
