// One row: track | playlist | user.
import QtQuick

Item {
    id: r
    property var item: null
    property int num: 0
    property bool showArt: true
    property bool current: !!item && item.type === "track" && !!Sound.track && Sound.track.id === item.id
    signal activated()
    signal menu(real x, real y)
    implicitHeight: Theme.rowH
    height: Theme.rowH
    readonly property bool isTrack: item && item.type === "track"
    readonly property bool isUser: item && item.type === "user"
    readonly property bool hot: hh.hovered
    HoverHandler { id: hh }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 4; anchors.rightMargin: 4
        radius: 10
        color: r.current ? Theme.a(Theme.accent, 0.10) : r.hot ? Theme.hover : "transparent"
    }

    Row {
        id: left
        anchors.left: parent.left; anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        Item {
            visible: r.num > 0
            width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
            Text {
                anchors.centerIn: parent
                visible: !r.current && !(r.hot && r.isTrack)
                text: r.num; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12; font.features: { "tnum": 1 }
            }
            Ico { anchors.centerIn: parent; visible: r.current || (r.hot && r.isTrack)
                  name: r.current && Sound.playing ? "pause" : "play"; size: 16; color: r.current ? Theme.accent : Theme.fg }
        }
        Item {
            visible: r.showArt
            width: Theme.rowH - 14; height: width; anchors.verticalCenter: parent.verticalCenter
            Cover {
                anchors.fill: parent
                src: r.item ? Theme.small(r.item.art || r.item.avatar || "", 80) : ""
                forceRounded: !r.isUser
                style: r.isUser ? "circle" : "rounded"
            }
            Rectangle {
                anchors.fill: parent; radius: 8; color: "#66000000"
                visible: r.num === 0 && r.isTrack && (r.hot || r.current)
                Ico { anchors.centerIn: parent; name: r.current && Sound.playing ? "pause" : "play"; size: 16; color: "white" }
            }
        }
    }

    Column {
        anchors.left: left.right; anchors.leftMargin: 12
        anchors.right: right.left; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            width: parent.width
            text: r.item ? (r.isUser ? r.item.name : r.item.title) : ""
            elide: Text.ElideRight
            color: r.current ? Theme.accent : Theme.fg
            font.family: Theme.fontUi; font.pixelSize: 14; font.weight: Font.Medium
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12
            text: {
                const it = r.item;
                if (!it) return "";
                if (it.type === "user") return Theme.num(it.followers) + " " + Theme.tr("followers") + (it.city ? " · " + it.city : "");
                if (it.type === "playlist") return (it.album ? Theme.tr("Album") : it.system ? Theme.tr("Station") : Theme.tr("Playlist")) + " · " + it.artist + (it.count ? " · " + it.count + " " + Theme.tr("tracks") : "");
                return it.artist + (it.repost ? "  ·  ↻ " + it.repost : "");
            }
        }
    }

    Row {
        id: right
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14
        Btn {
            readonly property bool lk: r.isTrack && Sound.isLiked(r.item.id)
            visible: r.isTrack
            opacity: lk || r.hot ? 1 : 0
            anchors.verticalCenter: parent.verticalCenter
            size: 28; iconSize: 15; icon: lk ? "heart" : "heartO"; on: lk; tint: Theme.muted
            onClicked: Sound.like(r.item)
        }
        Text {
            visible: r.isTrack && !!r.item.drm
            anchors.verticalCenter: parent.verticalCenter
            text: "DRM"; color: Theme.faint; font.family: Theme.fontUi; font.pixelSize: 10; font.weight: Font.Bold
        }
        Rectangle {
            visible: r.isTrack && r.item.snip
            anchors.verticalCenter: parent.verticalCenter
            width: pv.implicitWidth + 12; height: 18; radius: 9; color: Theme.a(Theme.accent, 0.16)
            Text { id: pv; anchors.centerIn: parent; text: Theme.tr("Preview"); color: Theme.accent; font.family: Theme.fontUi; font.pixelSize: 10; font.weight: Font.DemiBold }
        }
        Text {
            visible: r.isTrack && r.width > 560
            anchors.verticalCenter: parent.verticalCenter
            width: 56; horizontalAlignment: Text.AlignRight
            text: r.isTrack ? "▶ " + Theme.num(r.item.plays) : ""
            color: Theme.faint; font.family: Theme.fontUi; font.pixelSize: 11; font.features: { "tnum": 1 }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 44; horizontalAlignment: Text.AlignRight
            text: r.item && r.item.type !== "user" && r.item.dur ? Theme.time(r.isTrack && r.item.snip ? r.item.full : r.item.dur) : ""
            color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12; font.features: { "tnum": 1 }
        }
        Btn {
            size: 28; icon: "more"; anchors.verticalCenter: parent.verticalCenter
            opacity: r.hot ? 1 : 0
            onClicked: r.menu(x + width / 2 + right.x, height + right.y + 4)
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: m => { if (m.button === Qt.RightButton) r.menu(m.x, m.y); else if (r.current && r.isTrack) Sound.toggle(); else r.activated(); }
    }
}
