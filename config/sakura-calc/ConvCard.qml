// Converter row: unit pill on the left, value on the right.
import QtQuick

Rectangle {
    id: c
    property string unit: ""
    property string unitName: ""
    property string value: ""
    property bool accentValue: false
    default property alias content: slot.data
    signal pick()
    signal valueClicked()

    height: 92
    radius: 20
    color: accentValue ? Theme.a(Theme.accent, 0.07) : Qt.rgba(1, 1, 1, 0.05)
    border.width: 1
    border.color: accentValue ? Theme.a(Theme.accent, 0.16) : Qt.rgba(1, 1, 1, 0.05)

    Rectangle {
        id: pill
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -9
        height: 32
        width: pillRow.implicitWidth + 22
        radius: 11
        color: pma.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
        scale: pma.pressed ? 0.94 : 1
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.002 } }
        Behavior on color { ColorAnimation { duration: 140 } }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: c.unit
                font.family: Theme.fUi; font.pixelSize: 15; font.weight: Font.DemiBold
                color: c.accentValue ? Theme.accent : Theme.fg
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF0140)
                font.family: Theme.fIcon; font.pixelSize: 14
                color: Theme.dim
            }
        }
        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.pick() }
    }
    Text {
        anchors.left: pill.left; anchors.leftMargin: 4
        anchors.top: pill.bottom; anchors.topMargin: 6
        width: Math.min(implicitWidth, c.width * 0.4)
        elide: Text.ElideRight
        text: c.unitName
        font.family: Theme.fUi; font.pixelSize: 12
        color: Theme.faint
    }

    Item {
        id: slot
        anchors { left: pill.right; leftMargin: 14; right: parent.right; rightMargin: 16; top: parent.top; bottom: parent.bottom }
        Text {
            visible: c.value !== "" || c.accentValue
            anchors.fill: parent
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: c.value
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 18
            font.family: Theme.fDisplay; font.weight: Font.Light; font.pixelSize: 40
            font.features: { "tnum": 1 }
            color: c.accentValue ? Theme.accent : Theme.fg
            MouseArea { anchors.fill: parent; enabled: c.accentValue; cursorShape: Qt.PointingHandCursor; onClicked: c.valueClicked() }
        }
    }
}
