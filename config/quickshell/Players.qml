pragma Singleton
// sakura mono - which MPRIS player the shell shows (notch, dashboard Media, media card, desk widget, top bar).
// Rule: the player that last made sound stays picked - a pause doesn't hand the spot to another player.
// It changes only when another player starts playing, or when a chip is clicked (choose()).
// Remembered across shell restarts (~/.cache/sakura/player).
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import QtQuick

Singleton {
    id: ps
    readonly property var list: Mpris.players.values.filter(p => !String(p.dbusName || "").includes("playerctld"))
    property string cur: ""             // dbusName of the picked player
    readonly property var player: list.find(p => p.dbusName === cur) || list.find(p => p.isPlaying) || list[0] || null

    function choose(p) { if (p && p.dbusName) { cur = p.dbusName; save.restart(); } }

    // any player that starts playing takes the spot
    Instantiator {
        model: ps.list
        delegate: Connections {
            required property var modelData
            target: modelData
            function onIsPlayingChanged() { if (modelData.isPlaying) ps.choose(modelData); }
        }
    }
    onListChanged: {
        const p = list.find(x => x.isPlaying);
        if (p && !list.some(x => x.dbusName === cur && x.isPlaying)) choose(p);
    }

    // the picked player's PipeWire playback stream (node.name) - the visualizers (cava) listen to it alone,
    // not to the whole sink (Discord, games, notifications). Kept when the stream goes away on a pause.
    readonly property var outStreams: Pipewire.nodes.values.filter(n => n.isStream && ((n.properties || {})["media.class"] || "") === "Stream/Output/Audio")
    PwObjectTracker { objects: ps.outStreams }
    function normKey(s) { return String(s || "").toLowerCase().replace(/\.(bin|exe)$/, "").replace(/[^a-z0-9]/g, ""); }
    readonly property string streamNow: {
        const p = player; if (!p) return "";
        const bus = String(p.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "");
        const keys = [p.identity, p.desktopEntry, bus.split(".")[0]].map(normKey).filter(k => k.length >= 3);
        const m = outStreams.filter(n => {
            const q = n.properties || {};
            const nk = [q["application.name"], q["application.process.binary"], q["node.name"]].map(normKey).filter(k => k.length >= 3);
            return nk.some(a => keys.some(b => a === b || a.indexOf(b) >= 0 || b.indexOf(a) >= 0));
        });
        const n = m.find(x => x.audio && !x.audio.muted) || m[0];
        return n ? String((n.properties || {})["node.name"] || n.name || "") : "";
    }
    property string stream: ""          // what cava listens to; "" → the whole output (auto)
    onStreamNowChanged: if (streamNow !== "") stream = streamNow
    onPlayerChanged: stream = streamNow

    IpcHandler { target: "players"; function info(): string { return (ps.player ? ps.player.dbusName : "-") + " | now=" + ps.streamNow + " | stream=" + ps.stream + " | streams=" + ps.outStreams.length; } }

    readonly property string file: Quickshell.env("HOME") + "/.cache/sakura/player"
    FileView { id: fv; path: ps.file; onLoaded: if (ps.cur === "") ps.cur = text().trim() }
    Timer { id: save; interval: 400; onTriggered: fv.setText(ps.cur) }
}
