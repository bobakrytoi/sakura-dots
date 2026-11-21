import QtQuick

Item {
    id: c
    property var item: null
    signal activated()
    signal menu(real x, real y)
    height: width + 52
    readonly property bool isUser: item && item.type === "user"
    HoverHandler { id: hh }
    readonly property bool hot: hh.hovered
    readonly property bool current: item && item.type === "track" && Sound.track && Sound.track.id === item.id

    Cover {
        id: art
        width: c.width; height: width
        src: c.item ? Theme.small(c.item.art || c.item.avatar || "", 300) : ""
        forceRounded: !c.isUser
        style: c.isUser ? "circle" : "rounded"
        scale: c.hot ? 1.03 : 1
        Behavior on scale { NumberAnimation { duration: Theme.dur(160); easing.type: Easing.OutCubic } }
    }
    Rectangle {
        visible: !c.isUser && (c.hot || c.current)
        anchors.right: art.right; anchors.bottom: art.bottom; anchors.margins: 10
        width: 40; height: 40; radius: 20; color: Theme.accent
        Ico { anchors.centerIn: parent; name: c.current && Sound.playing ? "pause" : "play"; size: 20; color: Theme.accFg }
    }
    Column {
        anchors.top: art.bottom; anchors.topMargin: 8
        width: parent.width; spacing: 2
        Text { width: parent.width; text: c.item ? (c.isUser ? c.item.name : c.item.title) : ""; elide: Text.ElideRight
               color: c.current ? Theme.accent : Theme.fg; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold
               horizontalAlignment: c.isUser ? Text.AlignHCenter : Text.AlignLeft }
        Text { width: parent.width; elide: Text.ElideRight; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12
               horizontalAlignment: c.isUser ? Text.AlignHCenter : Text.AlignLeft
               text: !c.item ? "" : c.isUser ? Theme.num(c.item.followers) + " " + Theme.tr("followers")
                     : c.item.type === "playlist" ? (c.item.album ? Theme.tr("Album") : Theme.tr("Playlist")) + " · " + c.item.artist : c.item.artist }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: m => { if (m.button === Qt.RightButton) c.menu(m.x, m.y); else if (c.current) Sound.toggle(); else c.activated(); }
    }
}
