// Bottom player: cover · title/artist · controls + waveform · volume / queue / lyrics / expand.
import QtQuick

Item {
    id: pb
    property var app: null
    height: Theme.playerH
    readonly property var t: Sound.track
    readonly property bool big: Theme.player === "big"

    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }

    // left: now playing
    Item {
        id: nowBox
        anchors.left: parent.left; anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(300, pb.width * 0.26); height: parent.height - 24
        Cover {
            id: art
            width: parent.height; height: width
            src: pb.t ? Theme.small(pb.t.art, 80) : ""
            forceRounded: true
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (pb.app) pb.app.nowPlaying = true }
        }
        Btn {
            id: heart
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            size: 32; visible: !!pb.t
            icon: pb.t && Sound.isLiked(pb.t.id) ? "heart" : "heartO"
            on: pb.t && Sound.isLiked(pb.t.id); tint: Theme.muted
            onClicked: Sound.like(pb.t)
        }
        Column {
            anchors.left: art.right; anchors.leftMargin: 12
            anchors.right: heart.left; anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Marquee { width: parent.width; text: pb.t ? pb.t.title : ""; color: Theme.fg
                      font.family: Theme.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text {
                width: Math.min(parent.width, implicitWidth); text: pb.t ? pb.t.artist : ""; elide: Text.ElideRight
                color: arMa.containsMouse ? Theme.fg : Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12
                font.underline: arMa.containsMouse
                MouseArea { id: arMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: if (pb.app && pb.t) pb.app.openArtist(pb.t.artistId) }
            }
            Row {
                visible: pb.t && pb.t.snip
                Text { text: Theme.tr("Preview"); color: Theme.accent; font.family: Theme.fontUi; font.pixelSize: 10; font.weight: Font.DemiBold }
            }
        }
    }

    // centre: controls + wave
    Column {
        id: mid
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(620, pb.width - nowBox.width - rightBox.width - 80)
        spacing: pb.big ? 4 : 2
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Btn { icon: "shuffle"; size: 32; on: Sound.shuffle; tint: Theme.muted; onClicked: Sound.setShuffle(); anchors.verticalCenter: parent.verticalCenter }
            Btn { icon: "prev"; size: 36; onClicked: Sound.prev(); anchors.verticalCenter: parent.verticalCenter }
            Btn { icon: Sound.playing ? "pause" : "play"; size: pb.big ? 44 : 38; strong: true; onClicked: Sound.toggle(); anchors.verticalCenter: parent.verticalCenter
                  Spinner { anchors.centerIn: parent; visible: Sound.buffering; scale: 0.6; opacity: 0.8 } }
            Btn { icon: "next"; size: 36; onClicked: Sound.next(); anchors.verticalCenter: parent.verticalCenter }
            Btn { icon: Sound.repeat === "one" ? "repeatOne" : "repeat"; size: 32; on: Sound.repeat !== "off"; tint: Theme.muted
                  onClicked: Sound.cycleRepeat(); anchors.verticalCenter: parent.verticalCenter }
        }
        Row {
            width: parent.width
            spacing: 10
            Text { width: 40; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                   text: Theme.time(Sound.livePos); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11; font.features: { "tnum": 1 } }
            Wave {
                width: parent.width - 100; height: pb.big ? 30 : 18
                anchors.verticalCenter: parent.verticalCenter
                style: pb.big ? Theme.waveStyle : "off"
                comments: pb.app ? pb.app.comments : []
            }
            Text { width: 40; anchors.verticalCenter: parent.verticalCenter
                   text: Theme.time(Sound.dur); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11; font.features: { "tnum": 1 } }
        }
    }

    // right: extras
    Row {
        id: rightBox
        anchors.right: parent.right; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Repeater {
            model: pb.app ? pb.app.playerButtons : []
            Btn {
                required property var modelData
                size: 32; icon: modelData.icon; on: modelData.on ? modelData.on() : false; tint: Theme.muted
                onClicked: modelData.act()
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Btn { icon: "lyrics"; size: 32; tint: Theme.muted; visible: pb.app && pb.app.hasLyrics; on: pb.app && pb.app.side === "lyrics"
              iconSize: 14; onClicked: pb.app.toggleSide("lyrics"); anchors.verticalCenter: parent.verticalCenter }
        Btn { icon: "queue"; size: 32; tint: Theme.muted; on: pb.app && pb.app.side === "queue"
              onClicked: pb.app.toggleSide("queue"); anchors.verticalCenter: parent.verticalCenter }
        Btn { icon: Sound.muted || Sound.vol === 0 ? "volOff" : Sound.vol < 34 ? "volLow" : Sound.vol < 67 ? "volMid" : "vol"
              size: 32; tint: Theme.muted; onClicked: Sound.send("mute"); anchors.verticalCenter: parent.verticalCenter
              onWheel: dy => Sound.setVolume(Math.max(0, Math.min(100, Sound.vol + (dy > 0 ? 5 : -5)))) }
        Item {
            width: 96; height: 32; anchors.verticalCenter: parent.verticalCenter
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.a(Theme.fg, 0.2) }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * Math.min(1, Sound.vol / 100); height: 4; radius: 2
                        color: vMa.containsMouse ? Theme.accent : Theme.fg }
            Rectangle { visible: vMa.containsMouse; x: parent.width * Math.min(1, Sound.vol / 100) - 6; anchors.verticalCenter: parent.verticalCenter
                        width: 12; height: 12; radius: 6; color: Theme.fg }
            MouseArea {
                id: vMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onPressed: m => Sound.setVolume(Math.round(Math.max(0, Math.min(1, m.x / width)) * 100))
                onPositionChanged: m => { if (pressed) Sound.setVolume(Math.round(Math.max(0, Math.min(1, m.x / width)) * 100)); }
                onWheel: w => Sound.setVolume(Math.max(0, Math.min(100, Sound.vol + (w.angleDelta.y > 0 ? 5 : -5))))
            }
        }
        Btn { icon: "expand"; size: 32; tint: Theme.muted; iconSize: 14; onClicked: if (pb.app) pb.app.nowPlaying = true; anchors.verticalCenter: parent.verticalCenter }
    }
}
