// sakura mono - video wallpapers + the desktop right-click catcher (the way iNiR does it).
// awww shows a still frame (hypr/scripts/wallpaper.sh); when the wallpaper in settings.json is a video, this plays it
// on top, on the Background layer (below desktop widgets and windows), muted and looping:
//  - it plays a copy sized to the screen (hypr/scripts/wallplay.sh: the original if it is not bigger than the screen;
//    copies are made one at a time at the lowest priority) - the still shows until that copy is ready;
//  - it pauses (holding the frame) while windows cover the screen, a window is fullscreen, or the screen is locked -
//    Settings > Wallpaper > "Pause the video" (settings.json "videoPause": covered | fullscreen | never).
// Menus, banners and previews never play the video: they show the still (WallThumb.qml).
// The same full-screen surface catches right clicks on the empty desktop -> DesktopMenu.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtMultimedia

Scope {
    id: wp
    property var desktopMenu: null
    property var lock: null
    readonly property string file: Cfg.data.wallpaper || ""
    readonly property bool isVideo: /\.(mp4|webm|mkv|mov)$/i.test(file) && Cfg.data.wallVideo !== false     // off = awww's still frame only
    readonly property string pauseMode: Cfg.data.videoPause || (Cfg.data.wallPause === false ? "never" : "covered")
    function videoFile(f) { return /\.(mp4|webm|mkv|mov)$/i.test(f || ""); }

    // which monitors are covered by windows: re-checked (debounced) on Hyprland window/workspace events
    property var coveredMons: ({})
    Process {
        id: coverProc
        command: ["sh", "-c", "hyprctl monitors -j; echo '@@'; hyprctl clients -j"]
        stdout: StdioCollector { onStreamFinished: {
            const parts = this.text.split("@@");
            let mons = [], cls = [];
            try { mons = JSON.parse(parts[0]); cls = JSON.parse(parts[1]); } catch (e) { return; }
            const out = {};
            for (const m of mons) {
                const ws = m.activeWorkspace ? m.activeWorkspace.id : -1;
                let area = 0, full = false;
                for (const c of cls) {
                    if (!c.mapped || c.hidden || !c.workspace || c.workspace.id !== ws) continue;
                    if (c.fullscreen > 0) full = true;
                    if (c.floating) continue;
                    area += c.size[0] * c.size[1];
                }
                out[m.name] = { full: full, covered: full || area >= 0.8 * m.width * m.height };
            }
            wp.coveredMons = out;
        } }
    }
    Timer { id: coverT; interval: 150; onTriggered: { coverProc.running = false; coverProc.running = true; } }
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (/^(openwindow|closewindow|movewindow|workspace|focusedmon|fullscreen|changefloatingmode|activewindow|resizewindow|minimized)/.test(e.name)) coverT.restart();
        }
    }
    Component.onCompleted: coverT.start()

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: w
            required property var modelData
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "sakura-wallpaper"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property var cov: wp.coveredMons[modelData.name] || ({ full: false, covered: false })
            readonly property bool paused: (wp.lock && wp.lock.locked)
                                           || (wp.pauseMode === "covered" && cov.covered)
                                           || (wp.pauseMode === "fullscreen" && cov.full)

            // the file to play: a copy sized to this screen (or the original when it is small enough)
            property string playFile: ""
            function prepare() {
                playFile = "";
                if (!wp.isVideo) return;
                prep.running = false;
                prep.command = [Quickshell.env("HOME") + "/.config/hypr/scripts/wallplay.sh", wp.file, String(modelData.height)];
                prep.running = true;
            }
            Component.onCompleted: prepare()
            Connections { target: wp; function onFileChanged() { w.prepare(); } function onIsVideoChanged() { w.prepare(); } }
            Process { id: prep; stdout: StdioCollector { onStreamFinished: { const p = this.text.trim(); if (p !== "") w.playFile = p; } } }

            Loader {
                anchors.fill: parent
                active: wp.isVideo && w.playFile !== ""
                sourceComponent: Video {
                    id: vid
                    source: "file://" + w.playFile
                    loops: MediaPlayer.Infinite
                    muted: true
                    fillMode: VideoOutput.PreserveAspectCrop
                    // fade in once; after that it never hides again - at the loop point the player is "stopped" for a moment,
                    // and fading out there flashed the still (and every glass widget over it)
                    property bool shown: false
                    onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) shown = true
                    opacity: shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 400 } }
                    Component.onCompleted: if (!w.paused) play(); else { play(); pause(); }     // paused: still show a frame
                    Connections {
                        target: w
                        function onPausedChanged() { if (w.paused) vid.pause(); else vid.play(); }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: m => { if (wp.desktopMenu) wp.desktopMenu.openAt(w.modelData, m.x, m.y); }
            }
            // rubber-band selection on the empty desktop: just the look (nothing gets selected), in the accent color
            MouseArea {
                id: band
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                property real x0: 0; property real y0: 0; property real x1: 0; property real y1: 0
                onPressed: m => { x0 = x1 = m.x; y0 = y1 = m.y; selRect.opacity = 1; }
                onPositionChanged: m => { if (pressed) { x1 = m.x; y1 = m.y; } }
                onReleased: selRect.opacity = 0
                onCanceled: selRect.opacity = 0
            }
            Rectangle {
                id: selRect
                x: Math.min(band.x0, band.x1); y: Math.min(band.y0, band.y1)
                width: Math.abs(band.x1 - band.x0); height: Math.abs(band.y1 - band.y0)
                visible: opacity > 0 && width > 2 && height > 2
                opacity: 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                radius: 6
                color: Qt.rgba(Cfg.accent.r, Cfg.accent.g, Cfg.accent.b, 0.14)
                border.width: 1; border.color: Qt.rgba(Cfg.accent.r, Cfg.accent.g, Cfg.accent.b, 0.75)
            }
        }
    }
}
