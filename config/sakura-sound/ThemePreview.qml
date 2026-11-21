// Live miniature of the player for the theme editor: same components, same Theme → updates as you edit.
import QtQuick
import QtQuick.Effects

Rectangle {
    id: pv
    radius: Theme.radius
    color: Theme.glass
    border.width: 1; border.color: Theme.line
    clip: true
    readonly property var t: Sound.track
    readonly property var rows: (Sound.queueRev, Sound.queue.slice(Math.max(0, Sound.idx), Math.max(0, Sound.idx) + 3))

    // background style
    Image { id: bi; anchors.fill: parent; visible: false; fillMode: Image.PreserveAspectCrop; sourceSize.width: 200
            source: Theme.background === "wallpaper" ? (Theme.sys.wallpaper && !/\.(mp4|webm|mkv|mov)$/i.test(Theme.sys.wallpaper) ? "file://" + Theme.sys.wallpaper : "")
                  : Theme.background !== "glass" && pv.t ? Theme.small(pv.t.art, 300) : "" }
    MultiEffect { anchors.fill: parent; source: bi; visible: Theme.background !== "glass" && bi.status === Image.Ready
                  blurEnabled: Theme.bgBlur > 0.01; blur: Theme.background === "gradient" ? 1 : Theme.bgBlur; blurMax: 48
                  saturation: Theme.background === "gradient" ? 0.6 : 0; opacity: 0.55 * (1 - Theme.bgDim * 0.6) }
    Rectangle { anchors.fill: parent; color: Theme.background === "glass" ? "transparent" : Theme.a("#0f1119", Theme.bgDim) }
    Particles { anchors.fill: parent }

    Column {
        x: 18; y: 18; width: parent.width - 36
        spacing: 12
        Text { text: Theme.tr("Preview"); color: Theme.accent; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.1; font.capitalization: Font.AllUppercase }
        Item {
            width: parent.width; height: 150
            Cover {
                id: pc
                width: 140; height: 140; anchors.horizontalCenter: parent.horizontalCenter
                src: pv.t ? Theme.small(pv.t.art, 300) : ""
                spinning: true
                layer.enabled: Theme.glow
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.accent; shadowBlur: 1; shadowOpacity: 0.7; shadowScale: 1.05 }
                SequentialAnimation on scale {
                    running: Theme.pulse && pv.visible; loops: Animation.Infinite
                    NumberAnimation { to: 1.05; duration: 240; easing.type: Easing.OutQuad }
                    NumberAnimation { to: 1.0; duration: 360; easing.type: Easing.InQuad }
                }
            }
        }
        Column {
            width: parent.width; spacing: 2
            Marquee { width: parent.width; text: pv.t ? pv.t.title : "Sakura Sound"; color: Theme.fg
                      font.family: Theme.fontHead; font.pixelSize: 18; font.weight: Font.ExtraBold }
            Text { width: parent.width; text: pv.t ? pv.t.artist : ""; elide: Text.ElideRight; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12 }
        }
        Wave { width: parent.width; height: 30; style: Theme.waveStyle }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Btn { icon: "shuffle"; size: 30; on: true; tint: Theme.muted }
            Btn { icon: "prev"; size: 32 }
            Btn { icon: Sound.playing ? "pause" : "play"; size: Theme.player === "big" ? 42 : 34; strong: true; onClicked: Sound.toggle() }
            Btn { icon: "next"; size: 32 }
            Btn { icon: "heart"; size: 30; on: true; tint: Theme.muted }
        }
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Repeater {
            model: pv.rows.length
            Item {
                required property int index
                readonly property var it: pv.rows[index]
                width: parent.width; height: Theme.rowH - 8
                Rectangle { anchors.fill: parent; anchors.margins: -4; radius: 10; color: index === 0 ? Theme.a(Theme.accent, 0.10) : "transparent" }
                Cover { id: rc; width: parent.height - 8; height: width; anchors.verticalCenter: parent.verticalCenter; forceRounded: true; src: it ? Theme.small(it.art, 80) : "" }
                Column {
                    anchors.left: rc.right; anchors.leftMargin: 10; anchors.right: rd.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    Text { width: parent.width; text: it ? it.title : ""; elide: Text.ElideRight; color: index === 0 ? Theme.accent : Theme.fg; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.Medium }
                    Text { width: parent.width; text: it ? it.artist : ""; elide: Text.ElideRight; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11 }
                }
                Text { id: rd; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: it ? Theme.time(it.dur) : ""; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11 }
            }
        }
        // bottom visualizer sample
        Row {
            visible: Theme.vizStyle === "bars" || Theme.vizStyle === "mirror"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3; height: 34
            Repeater {
                model: 18
                Rectangle {
                    required property int index
                    property real v: 0.2
                    width: 6; radius: 3; anchors.bottom: parent.bottom
                    height: 4 + 30 * v; color: Theme.a(Theme.accent, 0.4 + 0.5 * v)
                    Behavior on height { NumberAnimation { duration: 160 } }
                    Timer { running: pv.visible; repeat: true; interval: 180 + index * 7; onTriggered: parent.v = Math.random() * (1 - Math.abs(index - 8) / 12) }
                }
            }
        }
    }
}
