// Settings → Plugins: on/off, version, settings built from manifest.json, reload.
import QtQuick

Column {
    id: pm
    property var host: null
    spacing: 10
    property string open: ""

    Repeater {
        model: pm.host ? pm.host.list.length : 0
        Rectangle {
            id: card
            required property int index
            readonly property var m: pm.host.list[index]
            readonly property bool on: (pm.host.rev, pm.host.enabled(m.id))
            readonly property bool expanded: pm.open === m.id
            readonly property var cfg: (pm.host.rev, pm.host.configOf(m.id))
            width: pm.width
            height: head.height + (expanded ? body.implicitHeight + 8 : 0)
            radius: 18; color: Theme.card
            clip: true
            Behavior on height { NumberAnimation { duration: Theme.dur(160); easing.type: Easing.OutCubic } }

            Item {
                id: head
                width: parent.width; height: 66
                MouseArea { anchors.fill: parent; cursorShape: (card.m.settings || []).length ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if ((card.m.settings || []).length) pm.open = card.expanded ? "" : card.m.id }
                Rectangle { x: 16; anchors.verticalCenter: parent.verticalCenter; width: 36; height: 36; radius: 12
                            color: card.on ? Theme.a(Theme.accent, 0.16) : Theme.cardHi
                            Ico { anchors.centerIn: parent; name: card.m.icon || "plug"; size: 17; color: card.on ? Theme.accent : Theme.muted } }
                Column {
                    x: 66; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 160; spacing: 2
                    Row { spacing: 8
                        Text { text: Theme.tr(card.m.name || card.m.id); color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { text: card.m.version || ""; color: Theme.faint; font.family: Theme.fontUi; font.pixelSize: 11; anchors.baseline: parent.children[0].baseline } }
                    Text { width: parent.width; text: Theme.tr(card.m.description || ""); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11; elide: Text.ElideRight }
                }
                Ico { visible: (card.m.settings || []).length > 0; anchors.right: tg.left; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                      name: "down"; size: 16; color: Theme.muted; rotation: card.expanded ? 180 : 0
                      Behavior on rotation { NumberAnimation { duration: Theme.dur(160) } } }
                Toggle { id: tg; anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                         on: card.on; onToggled: pm.host.setEnabled(card.m.id, !card.on) }
            }
            Column {
                id: body
                y: head.height; x: 16; width: parent.width - 32
                Repeater {
                    model: card.m.settings || []
                    SetRow {
                        id: row
                        required property var modelData
                        readonly property var s: modelData
                        readonly property var val: card.cfg[s.key]
                        label: Theme.tr(s.label || s.key || "")
                        sub: Theme.tr(s.sub || "")
                        Toggle { visible: row.s.type === "toggle"; on: !!row.val; onToggled: pm.host.setConfig(card.m.id, row.s.key, !row.val) }
                        Slider2 { visible: row.s.type === "slider"; from: row.s.min || 0; to: row.s.max || 1; step: row.s.step || 0
                                  decimals: row.s.decimals || 0; suffix: row.s.suffix || ""; value: Number(row.val || 0)
                                  onMoved: v => pm.host.setConfig(card.m.id, row.s.key, v) }
                        Seg { visible: row.s.type === "choice"; options: (row.s.options || []).map(o => typeof o === "object" ? o : ({ v: o, t: String(o) }))
                              value: row.val; onPicked: v => pm.host.setConfig(card.m.id, row.s.key, v) }
                        Rectangle {
                            visible: row.s.type === "text" || row.s.type === "secret"
                            width: 260; height: 32; radius: 16; color: Theme.cardHi
                            TextInput { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; verticalAlignment: TextInput.AlignVCenter
                                        text: row.val || ""; echoMode: row.s.type === "secret" ? TextInput.Password : TextInput.Normal
                                        color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 12; clip: true
                                        onEditingFinished: if (text !== (row.val || "")) pm.host.setConfig(card.m.id, row.s.key, text) }
                        }
                        Rectangle {
                            visible: row.s.type === "action"
                            width: aT.implicitWidth + 26; height: 32; radius: 16; color: aMa.containsMouse ? Theme.cardHi : Theme.accent
                            Text { id: aT; anchors.centerIn: parent; text: Theme.tr(row.s.button || row.s.label || ""); color: aMa.containsMouse ? Theme.fg : Theme.accFg
                                   font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea { id: aMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pm.host.action(card.m.id, row.s.key) }
                        }
                        Text { visible: row.s.type === "info"; text: String(row.val || ""); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12 }
                    }
                }
            }
        }
    }
    Rectangle {
        width: rT.implicitWidth + 26; height: 32; radius: 16; color: rMa.containsMouse ? Theme.cardHi : Theme.card
        Text { id: rT; anchors.centerIn: parent; text: Theme.tr("Reload"); color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
        MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pm.host.reload() }
    }
}
