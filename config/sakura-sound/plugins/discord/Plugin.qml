import QtQuick
import "../.."

Item {
    id: pl
    property var api: null
    readonly property string appId: api ? api.get("app", "") : ""
    function push() {
        if (!api || !appId) return;
        const t = api.track;
        if (!t || (!api.playing && api.get("pause", true))) { api.send("discord", { client_id: appId, activity: null }); return; }
        const now = Date.now() / 1000;
        const act = {
            type: 2,
            details: t.title.slice(0, 127),
            state: ("by " + t.artist).slice(0, 127),
            assets: { large_image: t.art || undefined, large_text: t.title.slice(0, 127), small_text: "Sakura Sound" }
        };
        if (api.playing && api.duration > 0) act.timestamps = { start: Math.floor(now - api.position), end: Math.floor(now - api.position + api.duration) };
        if (api.get("button", true) && t.url) act.buttons = [{ label: "Open on SoundCloud", url: t.url }];
        api.send("discord", { client_id: appId, activity: act });
    }
    Timer { id: pushT; interval: 600; onTriggered: pl.push() }
    onApiChanged: if (api) pushT.restart()
    onAppIdChanged: pushT.restart()
    Connections {
        target: pl.api
        function onStarted() { pushT.restart(); }
        function onStateChanged() { pushT.restart(); }
    }
    Component.onDestruction: if (api && appId) api.send("discord", { client_id: appId, activity: null })
}
