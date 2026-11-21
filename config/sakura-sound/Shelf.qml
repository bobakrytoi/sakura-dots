// Horizontal row of cards with a title; click card = play (tracks) / open (others).
import QtQuick

Column {
    id: sh
    property string title: ""
    property var items: []
    property var app: null
    property int cardW: 156
    property string action: ""          // "Show all" link
    signal showAll()
    spacing: 12
    visible: items.length > 0

    Item {
        width: parent.width; height: 26
        Text { text: sh.title; color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 19; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
        Text {
            visible: sh.action !== ""
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: sh.action; color: allMa.containsMouse ? Theme.fg : Theme.muted
            font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold
            MouseArea { id: allMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sh.showAll() }
        }
    }
    ListView {
        id: hl
        width: parent.width
        height: sh.cardW + 52
        orientation: ListView.Horizontal
        spacing: 14
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sh.items.length
        delegate: Card {
            required property int index
            width: sh.cardW
            item: sh.items[index]
            onActivated: {
                if (item.type === "track") {
                    const tr = sh.items.filter(x => x.type === "track");
                    Sound.playList(tr, tr.indexOf(item));
                } else if (sh.app) sh.app.openItem(item);
            }
            onMenu: (x, y) => { if (sh.app) sh.app.menuFor(item, mapToItem(sh.app, x, y)); }
        }
        WheelHandler { orientation: Qt.Vertical; onWheel: e => { hl.contentX = Math.max(0, Math.min(hl.contentWidth - hl.width, hl.contentX - e.angleDelta.y)); } }
    }
}
