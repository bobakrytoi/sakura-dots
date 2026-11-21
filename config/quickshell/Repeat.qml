// sakura mono - "repeat track" for players that can't loop themselves (browsers: YouTube, Yandex Music in Brave/Firefox…)
// state lives in ~/.cache/sakura-repeat ("1" = on) so the player card and the dashboard share it
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

Scope {
    id: rp
    property bool on: false
    FileView {
        id: flag
        path: Quickshell.env("HOME") + "/.cache/sakura-repeat"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: rp.on = text().trim() === "1"
        onLoadFailed: rp.on = false
    }
    IpcHandler {
        target: "repeat"
        function toggle(): void { flag.setText(rp.on ? "0" : "1"); rp.on = !rp.on; }
    }
    readonly property var player: Mpris.players.values.find(p => !String(p.dbusName || "").includes("playerctld") && p.isPlaying) || null
    // near the end of the track: jump back to the start
    Timer {
        interval: 250; repeat: true
        running: rp.on && rp.player !== null && !rp.player.loopSupported
        onTriggered: {
            const p = rp.player; p.positionChanged();
            if (p.length > 3 && p.position >= p.length - 0.8 && p.canSeek) p.position = 0;
        }
    }
}
