// sakura mono - what is not in use, for one or more DropSlots (ModHub): drag a chip up (or click it) to add it,
// drag one from a list down here to take it away
import QtQuick

Rectangle {
    id: mp
    property var hub: null
    property var slots: []
    readonly property bool hot: !!hub && !!hub.overPalette && hub.overPalette === mp
    readonly property int count: { let n = 0; for (const s of slots) n += s.unused.length; return n; }
    height: Math.max(52, fl.implicitHeight + 20)
    radius: 14
    color: hot ? Cfg.acc(0.12) : "#0dffffff"
    border.width: 1
    border.color: hot ? Cfg.acc(0.6) : "#14ffffff"
    Behavior on color { ColorAnimation { duration: 120 } }
    Component.onCompleted: if (hub) hub.registerPalette(mp)
    onHubChanged: if (hub) hub.registerPalette(mp)

    Text { visible: mp.count === 0; anchors.centerIn: parent; text: ""; font.family: "Symbols Nerd Font"; font.pixelSize: 14; color: "#8a8fa3" }
    Flow {
        id: fl
        x: 10; y: 10; width: parent.width - 20
        spacing: 6
        Repeater {
            model: mp.slots.length
            delegate: Repeater {
                id: inner
                required property int index
                readonly property var slot: mp.slots[index]
                model: slot ? slot.unused : []
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool dim: inner.slot.full
                    width: pr.implicitWidth + 26; height: 34; radius: 11
                    opacity: dim ? 0.4 : 1
                    color: pa.containsMouse && !dim ? Cfg.acc(0.22) : "#14ffffff"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                        id: pr; anchors.centerIn: parent; spacing: 7
                        Text { visible: text !== ""; text: inner.slot.look ? (inner.slot.look(modelData).glyph || "") : inner.slot.iconOf(modelData)
                               font.family: "Symbols Nerd Font"; font.pixelSize: 13; color: Cfg.accent; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: inner.slot.nameOf(modelData); color: "#eceef4"; font.family: Cfg.fontUi; font.pixelSize: 12; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                    }
                    DragArea { id: pa; anchors.fill: parent; hub: mp.hub; slot: inner.slot; mid: modelData; pal: true; enabled: !parent.dim }
                }
            }
        }
    }
}
