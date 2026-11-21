// Row of choice chips. options: [{v, t}] ; value ; changed(v)
import QtQuick

Flow {
    id: sg
    property var options: []
    property var value
    signal picked(var v)
    spacing: 6
    Repeater {
        model: sg.options
        Rectangle {
            required property var modelData
            readonly property bool on: sg.value === modelData.v
            width: st.implicitWidth + 24; height: 30; radius: 15
            color: on ? Theme.accent : sMa.containsMouse ? Theme.cardHi : Theme.card
            Text { id: st; anchors.centerIn: parent; text: Theme.tr(modelData.t); color: parent.on ? Theme.accFg : Theme.fg
                   font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
            MouseArea { id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sg.picked(modelData.v) }
        }
    }
}
