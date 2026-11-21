import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../.."

Item {
    id: pl
    property var api: null
    readonly property bool shown: api ? api.get("shown", false) : false
    onApiChanged: if (api) {
        api.addPlayerButton({ icon: "collapse", on: () => pl.shown, act: () => pl.toggle() });
    }
    function toggle() { api.set("shown", !shown); }

    PanelWindow {
        id: win
        visible: pl.shown && !!pl.api
        screen: {
            const want = pl.api && pl.api.get("screen", "main") === "second" ? "DP-1" : (Theme.sys.mainMonitor || "DP-3");
            return Quickshell.screens.find(s => s.name === want) || Quickshell.screens[0];
        }
        anchors.right: true; anchors.bottom: true
        Component.onCompleted: { margins.right = pl.api ? pl.api.get("mx", 24) : 24; margins.bottom = pl.api ? pl.api.get("my", 96) : 96; }
        implicitWidth: 360; implicitHeight: pl.api && pl.api.get("wave", true) ? 112 : 88
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "sakura-sound-mini"
        color: "transparent"

        QtObject { id: drag; property bool on: false; property var start: null; property real r0: 0; property real b0: 0 }
        Process {
            id: cur
            command: ["hyprctl", "cursorpos"]
            stdout: SplitParser {
                onRead: d => {
                    const m = d.match(/(-?\d+),\s*(-?\d+)/);
                    if (!m || !drag.on) return;
                    const x = parseInt(m[1]), y = parseInt(m[2]);
                    if (!drag.start) { drag.start = { x: x, y: y }; return; }
                    const sw = win.screen ? win.screen.width : 1920, sh = win.screen ? win.screen.height : 1080;
                    win.margins.right = Math.max(0, Math.min(sw - win.width, drag.r0 - (x - drag.start.x)));
                    win.margins.bottom = Math.max(0, Math.min(sh - win.height, drag.b0 - (y - drag.start.y)));
                }
            }
            onExited: if (drag.on) curT.start()
        }
        Timer { id: curT; interval: 12; onTriggered: if (drag.on) cur.running = true }

        Rectangle {
            anchors.fill: parent
            radius: 22; color: Theme.glass
            border.width: 1; border.color: Theme.line
            MouseArea {
                // drag to move. Layer-shell gives no global pointer position and local coords lag behind
                // every move (→ jitter), so while dragging we read the cursor from Hyprland and move by its delta.
                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: { drag.on = true; drag.start = null; drag.r0 = win.margins.right; drag.b0 = win.margins.bottom; cur.running = true; }
                onReleased: { drag.on = false; pl.api.set("mx", win.margins.right); pl.api.set("my", win.margins.bottom); }
                onCanceled: drag.on = false
                onDoubleClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/sakura-sound"])
            }
            Cover {
                id: art
                x: 12; y: 12; width: 64; height: 64
                src: Sound.track ? Theme.small(Sound.track.art, 80) : ""
                spinning: Sound.playing
            }
            Column {
                anchors.left: art.right; anchors.leftMargin: 12; anchors.right: ctl.left; anchors.rightMargin: 6
                y: 18; spacing: 3
                Text { width: parent.width; text: Sound.track ? Sound.track.title : "Sakura Sound"; elide: Text.ElideRight; color: Theme.fg
                       font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { width: parent.width; text: Sound.track ? Sound.track.artist : ""; elide: Text.ElideRight; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11 }
                Text { text: Theme.time(Sound.livePos) + " / " + Theme.time(Sound.dur); color: Theme.faint; font.family: Theme.fontUi; font.pixelSize: 10; font.features: { "tnum": 1 } }
            }
            Row {
                id: ctl
                anchors.right: parent.right; anchors.rightMargin: 10; y: 26
                spacing: 2
                Btn { icon: "prev"; size: 30; onClicked: Sound.prev() }
                Btn { icon: Sound.playing ? "pause" : "play"; size: 36; strong: true; onClicked: Sound.toggle() }
                Btn { icon: "next"; size: 30; onClicked: Sound.next() }
            }
            Wave {
                visible: pl.api && pl.api.get("wave", true)
                x: 12; y: 84; width: parent.width - 24; height: 18
                style: "bars"
            }
        }
    }
}
