// Endless queue like SoundCloud: near the end of the queue the current track's station is added;
// if the queue already ran out, the station starts playing right away.
import QtQuick
import "../.."

Item {
    id: pl
    property var api: null
    property var asked: ({})
    readonly property bool auto: api ? api.get("auto", true) : false
    onApiChanged: if (api) api.addPlayerButton({ icon: "radio", on: () => pl.auto, act: () => pl.api.set("auto", !pl.auto) })
    function mark(id) { const m = Object.assign({}, asked); m[id] = true; asked = m; }
    Connections {
        target: pl.api
        function onPositionChanged() {
            const a = pl.api;
            if (!pl.auto || !a.track || a.repeat !== "off" || a.position < 8) return;
            if (a.index < a.queue.length - 2 || pl.asked[a.track.id]) return;     // last two tracks
            pl.mark(a.track.id);
            a.send("radio", { tid: a.track.id, enqueue: true });
        }
        function onEnded() {
            const a = pl.api, t = a.queue[a.queue.length - 1];
            if (!pl.auto || !t || a.repeat !== "off") return;
            pl.mark(t.id);
            a.send("radio", { tid: t.id, play: true });
        }
    }
}
