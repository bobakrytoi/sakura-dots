import QtQuick
import "../.."

Item {
    id: pl
    property var api: null
    property string mode: ""        // "" | min | track | queue
    property real endAt: 0          // ms epoch (min mode)
    property real remain: 0
    onApiChanged: if (api) {
        api.af("fade", "@sleepfade:lavfi=[volume=1]");
        api.addPlayerButton({ icon: "moon", on: () => pl.mode !== "", act: () => pl.menu() });
    }
    function menu() {
        const e = [15, 30, 45, 60, 90].map(m => ({ icon: "timer", label: m + " min", act: () => pl.start("min", m) }));
        e.push({ icon: "album", label: Theme.tr("End of track"), act: () => pl.start("track") });
        e.push({ icon: "queue", label: Theme.tr("End of queue"), act: () => pl.start("queue") });
        if (mode) { e.push({ sep: true }); e.push({ icon: "close", label: Theme.tr("Off") + (mode === "min" ? " · " + Math.ceil(remain / 60) + " min" : ""), act: () => pl.stop() }); }
        api.app.popupAt(e);
    }
    function start(m, minutes) { mode = m; if (m === "min") { endAt = Date.now() + minutes * 60000; remain = minutes * 60; } setVol(1); }
    function stop() { mode = ""; setVol(1); }
    function setVol(v) { api.afCommand("sleepfade", "volume", v.toFixed(3)); }
    function fire() { api.pause(); stop(); }
    Timer {
        running: pl.mode === "min"; interval: 1000; repeat: true
        onTriggered: {
            pl.remain = (pl.endAt - Date.now()) / 1000;
            if (pl.api.get("fade", true) && pl.remain < 30) pl.setVol(Math.max(0, pl.remain / 30));
            if (pl.remain <= 0) pl.fire();
        }
    }
    Connections {
        target: pl.api
        function onStarted() { if (pl.mode === "track") pl.fire(); }
        function onEnded() { if (pl.mode === "queue") pl.stop(); }
        function onPositionChanged() {
            if (pl.mode !== "track" || !pl.api.get("fade", true)) return;
            const r = pl.api.duration - pl.api.position;
            if (r < 30) pl.setVol(Math.max(0.05, r / 30));
        }
    }
    Component.onDestruction: if (api) api.af("fade", "")
}
