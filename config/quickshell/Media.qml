// sakura mono — media card (click the track on the top bar)
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick

Scope {
    id: md

    readonly property color cBg:     "#f00f1119"
    readonly property color cCard:   "#14ffffff"
    readonly property color cHover:  "#22ffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: "#f2b8d0"
    readonly property color cAccFg:  "#1a121a"
    readonly property string fUi:    "Inter"
    readonly property string fIcon:  "Symbols Nerd Font"

    property bool shown: false
    property int pick: 0
    readonly property var players: Mpris.players.values.filter(p => !String(p.dbusName || "").includes("playerctld"))
    readonly property var player: players.length > 0 ? players[Math.min(pick, players.length - 1)] : null

    property var screen0: Quickshell.screens[0]
    function toggle() {
        if (!shown) {
            const m = Hyprland.focusedMonitor;
            const sc = m ? Quickshell.screens.find(s => s.name === m.name) : null;
            if (sc) screen0 = sc;
            // prefer the player that is actually playing
            const i = players.findIndex(p => p.isPlaying);
            if (i >= 0) pick = i;
        }
        shown = !shown;
    }
    IpcHandler {
        target: "media"
        function toggle(): void { md.toggle(); }
    }

    function fmt(s) {
        if (!s || s < 0 || !isFinite(s)) return "0:00";
        s = Math.floor(s);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    // position is not pushed live by players: refresh it while the card is open
    Timer { interval: 500; running: md.shown && md.player !== null; repeat: true
        onTriggered: if (md.player) md.player.positionChanged() }

    PanelWindow {
        id: win
        visible: md.shown
        screen: md.screen0
        anchors.top: true
        margins.top: 54
        implicitWidth: 460
        implicitHeight: 230
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "media"

        HyprlandFocusGrab { windows: [ win ]; active: md.shown; onCleared: md.shown = false }

        Rectangle {
            anchors.fill: parent
            radius: 24
            color: md.cBg
            border.width: 1; border.color: md.cBorder
            opacity: md.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            Text {
                visible: md.player === null
                anchors.centerIn: parent
                text: "Nothing is playing"
                color: md.cMuted; font.family: md.fUi; font.pixelSize: 14
            }

            Item {
                visible: md.player !== null
                anchors { fill: parent; margins: 18 }

                // cover
                ClippingRectangle {
                    id: cover
                    width: 120; height: 120; radius: 16
                    color: md.cCard
                    Image {
                        id: art
                        anchors.fill: parent
                        source: md.player ? (md.player.trackArtUrl || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: ""; font.family: md.fIcon; font.pixelSize: 40; color: md.cAccent
                    }
                }

                // text
                Column {
                    anchors { left: cover.right; leftMargin: 16; right: parent.right; top: parent.top; topMargin: 6 }
                    spacing: 4
                    Text { width: parent.width; elide: Text.ElideRight
                        text: md.player ? (md.player.trackTitle || "Unknown title") : ""
                        color: md.cFg; font.family: md.fUi; font.pixelSize: 16; font.weight: Font.Bold }
                    Text { width: parent.width; elide: Text.ElideRight
                        text: md.player ? (md.player.trackArtist || "") : ""
                        color: md.cAccent; font.family: md.fUi; font.pixelSize: 13 }
                    Text { width: parent.width; elide: Text.ElideRight
                        text: md.player ? (md.player.trackAlbum || "") : ""
                        color: md.cMuted; font.family: md.fUi; font.pixelSize: 12 }
                    // player switcher
                    Row {
                        spacing: 6; topPadding: 6
                        visible: md.players.length > 1
                        Repeater {
                            model: md.players
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: pt.implicitWidth + 16; height: 22; radius: 8
                                color: index === md.pick ? md.cAccent : md.cCard
                                Text { id: pt; anchors.centerIn: parent; text: modelData.identity || "player"
                                    color: index === md.pick ? md.cAccFg : md.cFg; font.family: md.fUi; font.pixelSize: 10; font.weight: Font.DemiBold }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: md.pick = index }
                            }
                        }
                    }
                }

                // progress + seek
                Item {
                    id: prog
                    anchors { left: parent.left; right: parent.right; top: cover.bottom; topMargin: 14 }
                    height: 20
                    readonly property real len: md.player ? md.player.length : 0
                    readonly property real pos: md.player ? md.player.position : 0
                    readonly property real frac: len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0
                    Text { id: tPos; anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: md.fmt(prog.pos)
                        color: md.cMuted; font.family: md.fUi; font.pixelSize: 11; width: 38 }
                    Text { id: tLen; anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: md.fmt(prog.len)
                        color: md.cMuted; font.family: md.fUi; font.pixelSize: 11; width: 38; horizontalAlignment: Text.AlignRight }
                    Item {
                        anchors { left: tPos.right; right: tLen.left; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
                        height: 14
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 5; radius: 3; color: "#26ffffff" }
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * prog.frac; height: 5; radius: 3; color: md.cAccent }
                        Rectangle { x: parent.width * prog.frac - 6; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: "#ffffff"
                            visible: md.player && md.player.canSeek }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            enabled: md.player !== null && md.player.canSeek && prog.len > 0
                            onClicked: m => { md.player.position = prog.len * Math.max(0, Math.min(1, m.x / width)); }
                        }
                    }
                }

                // controls
                Row {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    spacing: 10
                    Repeater {
                        model: [
                            { id: "shuffle", icon: "\uf074" },
                            { id: "prev",    icon: "\uf048" },
                            { id: "play",    icon: "\uf04b" },
                            { id: "next",    icon: "\uf051" },
                            { id: "loop",    icon: "\uf01e" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool big: modelData.id === "play"
                            readonly property bool lit: md.player !== null && (
                                (modelData.id === "shuffle" && md.player.shuffle) ||
                                (modelData.id === "loop" && md.player.loopState !== MprisLoopState.None))
                            width: big ? 46 : 38; height: big ? 46 : 38; radius: big ? 23 : 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: big ? md.cAccent : (cb.containsMouse ? md.cHover : "transparent")
                            scale: cb.pressed ? 0.9 : 1
                            Behavior on scale { NumberAnimation { duration: 90 } }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.id === "play" ? (md.player && md.player.isPlaying ? "\uf04c" : "\uf04b") : modelData.icon
                                font.family: md.fIcon; font.pixelSize: big ? 17 : 14
                                color: big ? md.cAccFg : (lit ? md.cAccent : md.cFg)
                            }
                            MouseArea {
                                id: cb; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const p = md.player; if (!p) return;
                                    if (modelData.id === "play") p.togglePlaying();
                                    else if (modelData.id === "prev") p.previous();
                                    else if (modelData.id === "next") p.next();
                                    else if (modelData.id === "shuffle" && p.shuffleSupported) p.shuffle = !p.shuffle;
                                    else if (modelData.id === "loop" && p.loopSupported)
                                        p.loopState = p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                                    : (p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
