// Settings row: label (+ sub) on the left, control on the right.
import QtQuick

Item {
    id: sr
    property string label: ""
    property string sub: ""
    default property alias control: holder.data
    width: parent ? parent.width : 400
    // wide controls (long chip rows) go under the label instead of over it
    readonly property bool stack: holder.implicitWidth > width * 0.56
    height: stack ? col.implicitHeight + holder.implicitHeight + 26 : Math.max(46, col.implicitHeight + 16, holder.implicitHeight + 12)
    Column {
        id: col
        anchors.left: parent.left
        y: sr.stack ? 10 : (parent.height - implicitHeight) / 2
        width: sr.stack ? parent.width : parent.width * 0.42
        spacing: 2
        Text { width: parent.width; text: sr.label; color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Medium; wrapMode: Text.WordWrap }
        Text { visible: sr.sub !== ""; width: parent.width; text: sr.sub; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11; wrapMode: Text.WordWrap }
    }
    Row {
        id: holder
        x: sr.stack ? 0 : parent.width - width
        y: sr.stack ? col.y + col.implicitHeight + 8 : (parent.height - height) / 2
        layoutDirection: sr.stack ? Qt.LeftToRight : Qt.RightToLeft
        spacing: 8
    }
}
