import QtQuick

Item {
    width: 22; height: 22
    Repeater {
        model: 3
        Rectangle {
            required property int index
            x: index * 8; anchors.verticalCenter: parent.verticalCenter
            width: 6; height: 6; radius: 3; color: Theme.accent
            SequentialAnimation on opacity {
                running: visible; loops: Animation.Infinite
                PauseAnimation { duration: index * 140 }
                NumberAnimation { from: 0.25; to: 1; duration: 280 }
                NumberAnimation { from: 1; to: 0.25; duration: 280 }
                PauseAnimation { duration: (2 - index) * 140 }
            }
        }
    }
}
