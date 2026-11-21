// Artwork with the theme's cover style: square / rounded / circle / vinyl / spin / cd.
import QtQuick
import Quickshell.Widgets

Item {
    id: c
    property string src: ""
    property string style: Theme.cover
    property bool spinning: false          // rotate (style spin/vinyl/cd while playing)
    property bool forceRounded: false      // lists: ignore disc styles, keep it calm
    property int px: Math.max(width, height)
    readonly property bool disc: !forceRounded && (style === "vinyl" || style === "cd" || style === "spin" || style === "circle")
    readonly property real r: forceRounded ? Math.max(4, Math.round(width * 0.12))
                              : style === "square" ? 4 : disc ? width / 2 : Math.max(4, Math.round(width * Theme.radius / 183))

    // vinyl: black record behind, the art is the label
    Rectangle {
        visible: !c.forceRounded && c.style === "vinyl"
        anchors.fill: parent
        radius: width / 2
        color: "#0c0c10"
        Repeater {
            model: 4
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * (0.92 - index * 0.1); height: width; radius: width / 2
                color: "transparent"; border.width: 1; border.color: "#14ffffff"
            }
        }
    }

    Item {
        id: spinner
        anchors.centerIn: parent
        width: !c.forceRounded && c.style === "vinyl" ? parent.width * 0.5 : parent.width
        height: width
        RotationAnimation on rotation {
            running: c.spinning && !c.forceRounded && (c.style === "spin" || c.style === "vinyl" || c.style === "cd") && c.visible
            from: 0; to: 360; duration: c.style === "cd" ? 2400 : 7000; loops: Animation.Infinite
            onRunningChanged: if (!running) spinner.rotation = 0
        }
        ClippingRectangle {
            anchors.fill: parent
            radius: c.style === "vinyl" && !c.forceRounded ? width / 2 : c.r
            color: Theme.card
            Image {
                anchors.fill: parent
                source: c.src
                sourceSize.width: c.px * 1.5
                sourceSize.height: c.px * 1.5
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.dur(160) } }
            }
            Ico { anchors.centerIn: parent; visible: !c.src; name: "album"; size: parent.width * 0.4; color: Theme.faint }
        }
        // CD: shine + hole
        Rectangle {
            visible: !c.forceRounded && c.style === "cd"
            anchors.fill: parent; radius: width / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#00ffffff" }
                GradientStop { position: 0.45; color: "#26ffffff" }
                GradientStop { position: 0.55; color: "#10a0d8ff" }
                GradientStop { position: 1.0; color: "#00ffffff" }
            }
        }
        Rectangle {
            visible: !c.forceRounded && (c.style === "cd" || c.style === "vinyl")
            anchors.centerIn: parent
            width: parent.width * (c.style === "cd" ? 0.16 : 0.12); height: width; radius: width / 2
            color: "#0c0c10"; border.width: c.style === "cd" ? 2 : 0; border.color: "#33ffffff"
        }
    }
}
