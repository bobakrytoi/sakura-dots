// One keypad key: soft rounded glass tile, spring press, ripple from the touch point.
import QtQuick

Item {
    id: k
    property string kid: label          // id used for keyboard flashes
    property string label: ""
    property string icon: ""            // Nerd Font codepoint string (wins over label)
    property string kind: "num"         // num | fn | op | eq | sci | on
    property bool small: false
    signal activated()

    readonly property bool down: ma.pressed || flashT.running
    readonly property color base: kind === "eq" ? Theme.accent
        : kind === "op" ? Theme.a(Theme.accent, 0.16)
        : kind === "on" ? Theme.a(Theme.accent, 0.24)
        : kind === "fn" ? Qt.rgba(1, 1, 1, 0.095)
        : kind === "sci" ? Qt.rgba(1, 1, 1, 0.04)
        : Qt.rgba(1, 1, 1, 0.06)
    readonly property color ink: kind === "eq" ? Theme.accFg
        : (kind === "op" || kind === "on") ? Theme.accent
        : kind === "fn" ? Theme.a(Theme.fg, 0.82)
        : kind === "sci" ? Theme.a(Theme.fg, 0.78)
        : Theme.fg

    function flash() { flashT.restart(); ripple.burst(bg.width / 2, bg.height / 2); }

    Timer { id: flashT; interval: 110 }

    Rectangle {
        id: bg
        anchors.fill: parent
        anchors.margins: 4
        radius: Math.min(height / 2.4, 20)
        color: k.down ? Qt.lighter(k.base, k.kind === "eq" ? 1.12 : 1.0) : k.base
        border.width: 1
        border.color: k.kind === "eq" ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, ma.containsMouse ? 0.10 : 0.045)
        scale: k.down ? 0.92 : 1.0
        clip: true
        Behavior on scale { SpringAnimation { spring: 5.5; damping: 0.32; epsilon: 0.002 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        // hover sheen
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "white"
            opacity: k.down ? 0.10 : ma.containsMouse ? 0.045 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.ms(140) } }
        }
        // top highlight
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: parent.height / 2
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, k.kind === "eq" ? 0.16 : 0.035) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
        Rectangle {
            id: ripple
            property real cx: 0
            property real cy: 0
            width: 0; height: width; radius: width / 2
            x: cx - width / 2; y: cy - width / 2
            color: k.kind === "eq" ? "white" : (k.kind === "op" || k.kind === "on") ? Theme.accent : "white"
            opacity: 0
            function burst(px, py) { cx = px; cy = py; rip.restart(); }
            ParallelAnimation {
                id: rip
                NumberAnimation { target: ripple; property: "width"; from: 0; to: Math.max(bg.width, bg.height) * 2.3; duration: Theme.ms(520); easing.type: Easing.OutCubic }
                NumberAnimation { target: ripple; property: "opacity"; from: 0.22; to: 0; duration: Theme.ms(560); easing.type: Easing.OutQuad }
            }
        }

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: k.icon ? 0 : -1
            text: k.icon || k.label
            color: k.ink
            font.family: k.icon ? Theme.fIcon : (k.kind === "num" ? Theme.fDisplay : Theme.fUi)
            font.pixelSize: k.icon ? Math.min(bg.height * 0.36, 22)
                : k.small || k.kind === "sci" || k.kind === "on" ? Math.min(bg.height * 0.3, 17)
                : Math.min(bg.height * 0.42, 28)
            font.weight: k.kind === "num" ? Font.Normal : k.kind === "eq" ? Font.DemiBold : Font.Medium
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.margins: 4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: m => ripple.burst(m.x, m.y)
        onClicked: k.activated()
    }
}
