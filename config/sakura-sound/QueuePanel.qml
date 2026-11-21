// Right panel: current + up next, drag to reorder, × to remove.
import QtQuick

Item {
    id: qp
    property var app: null

    Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Theme.line }

    Item {
        id: head
        width: parent.width; height: 56
        Text { anchors.left: parent.left; anchors.leftMargin: 20; anchors.verticalCenter: parent.verticalCenter
               text: Theme.tr("Queue"); color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 17; font.weight: Font.Bold }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
            visible: Sound.queue.length > 1
            text: Theme.tr("Clear"); color: clMa.containsMouse ? Theme.fg : Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold
            MouseArea { id: clMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Sound.send("clear") }
        }
    }

    Text {
        anchors.centerIn: parent; visible: Sound.queue.length === 0
        text: Theme.tr("Queue is empty"); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 13
    }

    ListView {
        id: lv
        anchors.top: head.bottom; anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Sound.queue.length
        property int dragFrom: -1
        property int dragTo: -1
        Component.onCompleted: positionViewAtIndex(Math.max(0, Sound.idx), ListView.Beginning)
        Connections { target: Sound; function onIdxChanged() { if (!lv.moving) lv.positionViewAtIndex(Math.max(0, Sound.idx - 1), ListView.Beginning); } }

        delegate: Item {
            id: qd
            required property int index
            readonly property var t: (Sound.queueRev, Sound.queue[index])
            readonly property bool cur: index === Sound.idx
            readonly property bool past: index < Sound.idx
            width: lv.width; height: 52
            opacity: past ? 0.45 : 1
            HoverHandler { id: qh }

            Rectangle { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; radius: 10
                        color: qd.cur ? Theme.a(Theme.accent, 0.10) : qh.hovered ? Theme.hover : "transparent" }
            Rectangle { visible: lv.dragTo === index && lv.dragFrom !== index; width: parent.width - 24; x: 12; height: 2; radius: 1; color: Theme.accent
                        y: lv.dragFrom < index ? parent.height - 1 : -1 }
            Cover { id: qc; x: 16; anchors.verticalCenter: parent.verticalCenter; width: 38; height: 38; forceRounded: true; src: qd.t ? Theme.small(qd.t.art, 80) : "" }
            Column {
                anchors.left: qc.right; anchors.leftMargin: 10; anchors.right: rm.left; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter; spacing: 2
                Text { width: parent.width; text: qd.t ? qd.t.title : ""; elide: Text.ElideRight; color: qd.cur ? Theme.accent : Theme.fg
                       font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Medium }
                Text { width: parent.width; text: qd.t ? qd.t.artist : ""; elide: Text.ElideRight; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11 }
            }
            Btn { id: rm; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                  size: 26; icon: "close"; opacity: qh.hovered ? 1 : 0; onClicked: Sound.remove(qd.index) }
            MouseArea {
                id: qMa
                anchors.fill: parent; anchors.rightMargin: 40
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: lv.dragFrom >= 0 ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                property real pressY: 0
                onPressed: m => { pressY = m.y; }
                onPositionChanged: m => {
                    if (!pressed) return;
                    if (lv.dragFrom < 0 && Math.abs(m.y - pressY) > 8) { lv.dragFrom = qd.index; lv.interactive = false; }
                    if (lv.dragFrom >= 0) {
                        const p = mapToItem(lv.contentItem, m.x, m.y);
                        lv.dragTo = Math.max(0, Math.min(Sound.queue.length - 1, Math.floor(p.y / qd.height)));
                    }
                }
                onReleased: m => {
                    if (lv.dragFrom >= 0) {
                        if (lv.dragTo >= 0 && lv.dragTo !== lv.dragFrom) Sound.move(lv.dragFrom, lv.dragTo);
                        lv.dragFrom = -1; lv.dragTo = -1; lv.interactive = true;
                    }
                }
                onClicked: m => {
                    if (m.button === Qt.RightButton) { if (qp.app) qp.app.menuFor(qd.t, mapToItem(qp.app, m.x, m.y), qd.index); }
                    else if (qd.cur) Sound.toggle(); else Sound.jump(qd.index);
                }
            }
        }
    }
}
