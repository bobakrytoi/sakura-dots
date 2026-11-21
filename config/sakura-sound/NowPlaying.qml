// Full-window "Now playing". Theme knobs: npLayout side|center, glow, pulse (bass), vizStyle bars|mirror|circle|off,
// particles, background blur/dim/motion. cava runs only while this is shown and playing.
import QtQuick
import QtQuick.Effects
import Quickshell.Io

Item {
    id: np
    property var app: null
    property bool shown: false
    readonly property var t: Sound.track
    readonly property bool center: Theme.npLayout === "center"
    property bool lyricsOn: false
    readonly property var lyricsTab: app ? app.sideTabs.find(t => t.id === "lyrics") : null
    readonly property real availW: width - (lyricsOn && lyricsTab ? 420 : 0)   // room left of the lyrics panel
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.dur(220); easing.type: Easing.OutCubic } }

    // ── backdrop ────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: Theme.a("#0b0c12", 0.92) }
    Item {
        id: bgBox
        anchors.fill: parent
        clip: true
        Image {
            id: bgImg
            width: parent.width * 1.25; height: parent.height * 1.25
            x: -parent.width * 0.125; y: -parent.height * 0.125
            source: np.t ? Theme.small(np.t.art, 300) : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 300; sourceSize.height: 300
            visible: false
        }
        MultiEffect {
            id: bgFx
            anchors.fill: bgImg
            source: bgImg
            visible: np.visible && bgImg.status === Image.Ready
            blurEnabled: true; blur: Math.max(0.2, Theme.bgBlur + 0.2); blurMax: 64
            saturation: 0.3
            opacity: 0.75 - Theme.bgDim * 0.5
            // slow drift (theme bgMotion)
            SequentialAnimation on x {
                running: Theme.bgMotion && np.visible; loops: Animation.Infinite
                NumberAnimation { to: 40; duration: 14000; easing.type: Easing.InOutSine }
                NumberAnimation { to: -40; duration: 14000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on scale {
                running: Theme.bgMotion && np.visible; loops: Animation.Infinite
                NumberAnimation { to: 1.12; duration: 19000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 19000; easing.type: Easing.InOutSine }
            }
        }
    }
    Rectangle { anchors.fill: parent
        gradient: Gradient { GradientStop { position: 0; color: Theme.a("#000000", 0.15 + Theme.bgDim * 0.3) } GradientStop { position: 1; color: Theme.a("#05060a", 0.5 + Theme.bgDim * 0.4) } } }
    Particles { anchors.fill: parent; visible: np.visible }

    MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: w => {} }   // eat input below

    Btn { anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 18; icon: "down"; size: 38; z: 5
          onClicked: if (np.app) np.app.nowPlaying = false }

    // ── cover (shared by both layouts) ──────────────────────────
    readonly property real coverW: center ? Math.min(np.height - 330, np.availW * 0.42, 380) : Math.min(np.height - 260, np.availW * 0.36, 440)
    Item {
        id: coverBox
        width: np.coverW; height: width
        x: np.center ? (np.availW - width) / 2 : body.x
        y: np.center ? 64 : (np.height - height) / 2 - 30
        Behavior on x { NumberAnimation { duration: Theme.dur(260); easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: Theme.dur(260); easing.type: Easing.OutCubic } }

        // circular visualizer around the cover
        Repeater {
            model: Theme.vizStyle === "circle" && np.shown ? 64 : 0
            Rectangle {
                required property int index
                readonly property real v: viz.bars[Math.floor(index / 64 * 48)] || 0
                width: 3; height: 6 + 40 * v; radius: 1.5
                color: Theme.a(Theme.accent, 0.45 + 0.5 * v)
                x: coverBox.width / 2 - width / 2
                y: -height - 10
                transform: Rotation { origin.x: 1.5; origin.y: coverBox.height / 2 + 10 + height; angle: index * 360 / 64 }
                Behavior on height { NumberAnimation { duration: 60 } }
            }
        }
        Cover {
            id: big
            anchors.fill: parent
            src: np.t ? np.t.art : ""
            spinning: Sound.playing
            scale: Theme.pulse ? 1 + Sound.bass * 0.06 : 1
            Behavior on scale { NumberAnimation { duration: 80 } }
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.glow ? Theme.accent : "#000000"
                shadowBlur: 1.0
                shadowOpacity: Theme.glow ? 0.55 + Sound.bass * 0.4 : 0.55
                shadowVerticalOffset: Theme.glow ? 0 : 12
                shadowScale: Theme.glow ? 1.04 : 1.0
            }
        }
    }

    // ── text + controls ─────────────────────────────────────────
    Item {
        id: body
        readonly property real colW: np.center ? Math.min(560, np.availW - 120) : Math.min(520, np.availW - np.coverW - 160)
        width: np.center ? colW : np.coverW + 48 + colW
        height: np.center ? info.implicitHeight : np.coverW
        x: (np.availW - width) / 2
        Behavior on x { NumberAnimation { duration: Theme.dur(260); easing.type: Easing.OutCubic } }
        y: np.center ? coverBox.y + coverBox.height + 28 : (np.height - np.coverW) / 2 - 30
        Column {
            id: info
            x: np.center ? 0 : np.coverW + 48
            anchors.verticalCenter: np.center ? undefined : parent.verticalCenter
            width: body.colW
            spacing: np.center ? 10 : 14
            Text { visible: !np.center; text: Theme.tr("Now playing"); color: Theme.accent; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.2; font.capitalization: Font.AllUppercase }
            Text { width: parent.width; text: np.t ? np.t.title : ""; wrapMode: Text.WordWrap; maximumLineCount: np.center ? 2 : 3; elide: Text.ElideRight
                   horizontalAlignment: np.center ? Text.AlignHCenter : Text.AlignLeft
                   color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: np.center ? 30 : 34; font.weight: Font.ExtraBold; lineHeight: 0.95 }
            Text {
                width: parent.width; horizontalAlignment: np.center ? Text.AlignHCenter : Text.AlignLeft
                text: np.t ? np.t.artist : ""; color: aMa.containsMouse ? Theme.fg : Theme.a(Theme.fg, 0.7); font.family: Theme.fontUi; font.pixelSize: 17
                MouseArea { id: aMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (np.app && np.t) np.app.openArtist(np.t.artistId); } }
            }
            Item { width: 1; height: np.center ? 2 : 8 }
            Wave { width: parent.width; height: np.center ? 44 : 56; style: Theme.waveStyle === "off" ? "bars" : Theme.waveStyle; comments: np.app ? np.app.comments : [] }
            Row {
                width: parent.width
                Text { width: parent.width / 2; text: Theme.time(Sound.livePos); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12; font.features: { "tnum": 1 } }
                Text { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: Theme.time(Sound.dur); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12; font.features: { "tnum": 1 } }
            }
            Row {
                anchors.horizontalCenter: np.center ? parent.horizontalCenter : undefined
                spacing: 14
                Btn { icon: "shuffle"; size: 40; on: Sound.shuffle; tint: Theme.muted; onClicked: Sound.setShuffle(); anchors.verticalCenter: parent.verticalCenter }
                Btn { icon: "prev"; size: 46; onClicked: Sound.prev(); anchors.verticalCenter: parent.verticalCenter }
                Btn { icon: Sound.playing ? "pause" : "play"; size: 62; strong: true; onClicked: Sound.toggle(); anchors.verticalCenter: parent.verticalCenter }
                Btn { icon: "next"; size: 46; onClicked: Sound.next(); anchors.verticalCenter: parent.verticalCenter }
                Btn { icon: Sound.repeat === "one" ? "repeatOne" : "repeat"; size: 40; on: Sound.repeat !== "off"; tint: Theme.muted; onClicked: Sound.cycleRepeat(); anchors.verticalCenter: parent.verticalCenter }
                Btn { visible: !!np.t; icon: np.t && Sound.isLiked(np.t.id) ? "heart" : "heartO"; on: np.t && Sound.isLiked(np.t.id)
                      size: 40; tint: Theme.muted; onClicked: Sound.like(np.t); anchors.verticalCenter: parent.verticalCenter }
            }
            // lyrics + volume
            Row {
                anchors.horizontalCenter: np.center ? parent.horizontalCenter : undefined
                spacing: 6
                Btn { visible: !!np.lyricsTab; icon: "lyrics"; iconSize: 14; size: 34; on: np.lyricsOn; tint: Theme.muted
                      onClicked: np.lyricsOn = !np.lyricsOn; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 10; height: 1 }
                Btn { icon: Sound.muted || Sound.vol === 0 ? "volOff" : Sound.vol < 34 ? "volLow" : Sound.vol < 67 ? "volMid" : "vol"
                      size: 34; tint: Theme.muted; onClicked: Sound.send("mute"); anchors.verticalCenter: parent.verticalCenter
                      onWheel: dy => Sound.setVolume(Math.max(0, Math.min(100, Sound.vol + (dy > 0 ? 5 : -5)))) }
                Item {
                    width: 150; height: 34; anchors.verticalCenter: parent.verticalCenter
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.a(Theme.fg, 0.2) }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * Math.min(1, Sound.vol / 100); height: 4; radius: 2
                                color: nvMa.containsMouse ? Theme.accent : Theme.fg }
                    Rectangle { visible: nvMa.containsMouse; x: parent.width * Math.min(1, Sound.vol / 100) - 6; anchors.verticalCenter: parent.verticalCenter
                                width: 12; height: 12; radius: 6; color: Theme.fg }
                    MouseArea {
                        id: nvMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onPressed: m => Sound.setVolume(Math.round(Math.max(0, Math.min(1, m.x / width)) * 100))
                        onPositionChanged: m => { if (pressed) Sound.setVolume(Math.round(Math.max(0, Math.min(1, m.x / width)) * 100)); }
                        onWheel: w => Sound.setVolume(Math.max(0, Math.min(100, Sound.vol + (w.angleDelta.y > 0 ? 5 : -5))))
                    }
                }
            }
            Repeater {
                model: np.app && !np.lyricsOn ? np.app.nowBlocks : []     // the lyrics line is redundant next to the open lyrics panel
                Loader { required property var modelData; width: parent.width; sourceComponent: modelData.component
                         onLoaded: { if (item && item.hasOwnProperty("api")) item.api = np.app.api; } }
            }
        }
    }

    // ── lyrics panel (the lyrics plugin's tab, shown inside Now playing) ─
    Rectangle {
        id: lyrBox
        visible: opacity > 0
        opacity: np.lyricsOn && np.lyricsTab ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(220) } }
        anchors.right: parent.right; anchors.rightMargin: 24
        anchors.top: parent.top; anchors.topMargin: 64
        anchors.bottom: parent.bottom; anchors.bottomMargin: 110
        width: 380; radius: 22
        color: Theme.a("#0b0c12", 0.35)
        clip: true
        Loader {
            anchors.fill: parent
            active: np.lyricsOn && !!np.lyricsTab && np.shown
            sourceComponent: np.lyricsTab ? np.lyricsTab.component : null
            onLoaded: if (item && item.hasOwnProperty("api")) item.api = np.app.api
        }
    }

    // ── bottom visualizer (bars / mirror) ───────────────────────
    Item {
        id: viz
        property var bars: []
        visible: (Theme.vizStyle === "bars" || Theme.vizStyle === "mirror") && np.shown
        anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.vizStyle === "mirror" ? 60 : 26
        x: (np.availW - width) / 2
        width: np.availW * 0.7; height: 70
        Row {
            anchors.bottom: parent.bottom
            spacing: 3
            Repeater {
                model: 48
                Rectangle {
                    required property int index
                    readonly property real v: viz.bars[index] || 0
                    width: Math.max(3, viz.width / 48 - 3); radius: width / 2
                    anchors.bottom: parent.bottom
                    height: 4 + 66 * v
                    color: Theme.a(Theme.accent, 0.35 + 0.5 * v)
                    Behavior on height { NumberAnimation { duration: 60 } }
                    Rectangle {   // reflection
                        visible: Theme.vizStyle === "mirror"
                        anchors.top: parent.bottom; anchors.topMargin: 3
                        width: parent.width; height: parent.height * 0.5; radius: parent.radius
                        color: parent.color; opacity: 0.25
                    }
                }
            }
        }
    }
    Process {
        id: cava
        running: np.shown && Sound.playing && (Theme.vizStyle !== "off" || Theme.pulse || Theme.glow)
        command: ["cava", "-p", Theme.dir + "/cava.conf"]
        stdout: SplitParser {
            onRead: d => {
                const p = d.split(";"); const out = [];
                for (let i = 0; i < 48; i++) out.push((parseInt(p[i]) || 0) / 1000);
                viz.bars = out;
                Sound.bass = (out[0] + out[1] + out[2] + out[3] + out[4] + out[5]) / 6;
            }
        }
        onRunningChanged: if (!running) { viz.bars = []; Sound.bass = 0; }
    }
}
