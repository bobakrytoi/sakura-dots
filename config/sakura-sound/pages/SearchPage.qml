import QtQuick
import ".."

Item {
    id: sp
    property var app: null
    property var page: ({})
    property string type: app ? app.searchType : "tracks"
    function run() {
        const q = field.text.trim();
        if (app) { app.searchQ = q; }
        if (!q) { list.loader = null; list.reset([], ""); return; }
        list.loader = (next, cb) => Sound.search(q, sp.type, cb, next);
    }
    function focusField() { field.forceActiveFocus(); field.selectAll(); }
    Component.onCompleted: Qt.callLater(() => { field.text = app ? app.searchQ : ""; if (field.text) run(); focusTimer.start(); })
    Timer { id: focusTimer; interval: 50; onTriggered: sp.focusField() }
    Timer { id: debounce; interval: 350; onTriggered: sp.run() }
    onTypeChanged: run()

    Column {
        id: head
        x: 28; y: 24; width: parent.width - 56
        spacing: 14
        Rectangle {
            width: Math.min(560, parent.width); height: 46; radius: 23
            color: Theme.card
            border.width: 1; border.color: field.activeFocus ? Theme.a(Theme.accent, 0.5) : "transparent"
            Ico { id: sIco; x: 16; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: Theme.muted }
            TextInput {
                id: field
                anchors.left: sIco.right; anchors.leftMargin: 10; anchors.right: clr.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg; selectionColor: Theme.a(Theme.accent, 0.4); selectedTextColor: Theme.fg
                font.family: Theme.fontUi; font.pixelSize: 15
                clip: true
                onTextEdited: debounce.restart()
                onAccepted: { debounce.stop(); sp.run(); }
                Keys.onEscapePressed: { if (text) { text = ""; sp.run(); } else focus = false; }
                Text { visible: !field.text; text: Theme.tr("Search SoundCloud"); color: Theme.faint; font: field.font; anchors.verticalCenter: parent.verticalCenter }
            }
            Btn { id: clr; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                  size: 30; icon: "close"; visible: field.text !== ""; onClicked: { field.text = ""; sp.run(); field.forceActiveFocus(); } }
        }
        Row {
            spacing: 8
            Repeater {
                model: [{ v: "tracks", t: "Tracks" }, { v: "users", t: "Artists" }, { v: "playlists", t: "Playlists" }, { v: "albums", t: "Albums" }]
                Rectangle {
                    required property var modelData
                    readonly property bool on: sp.type === modelData.v
                    width: ct.implicitWidth + 28; height: 32; radius: 16
                    color: on ? Theme.accent : cMa.containsMouse ? Theme.cardHi : Theme.card
                    Text { id: ct; anchors.centerIn: parent; text: Theme.tr(modelData.t); color: parent.on ? Theme.accFg : Theme.fg
                           font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                    MouseArea { id: cMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: if (sp.app) sp.app.searchType = modelData.v }
                }
            }
        }
    }

    ItemList {
        id: list
        app: sp.app
        anchors.top: head.bottom; anchors.topMargin: 14
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 16; anchors.rightMargin: 16
        emptyText: field.text ? Theme.tr("Nothing found") : ""
        kind: "search"
    }
}
