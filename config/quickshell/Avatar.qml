// sakura mono - your picture (Cfg.avatar) as a circle with a ring around it.
// The picture itself is cut to a circle and fills it without stretching, so any picture works:
// square or not, already round-cut or not. ring: its width, ringColor: "transparent" to show what is under it.
import Quickshell.Widgets
import QtQuick

Rectangle {
    id: av
    property int ring: 2
    property color ringColor: Cfg.accent
    radius: width / 2
    color: ringColor
    ClippingRectangle {
        anchors.fill: parent
        anchors.margins: av.ring
        radius: width / 2
        color: "transparent"
        Image {
            anchors.fill: parent
            source: Cfg.avatar
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 256
            mipmap: true; smooth: true; asynchronous: true
        }
    }
}
