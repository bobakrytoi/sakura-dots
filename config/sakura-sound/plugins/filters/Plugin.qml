import QtQuick
import "../.."

Item {
    id: pl
    property var api: null
    onApiChanged: if (api) api.addFilter((items, kind) => {
        const c = pl.api.config;
        return items.filter(x => {
            if (!x || x.type !== "track") return true;
            if (c.reposts && kind === "feed" && x.repost) return false;
            if (c.previews && x.snip) return false;
            if (c.min > 0 && (kind === "feed" || kind === "search") && x.dur < c.min) return false;
            return true;
        });
    })
    Connections {
        target: pl.api
        function onStarted(t) { if (t && t.snip && pl.api.get("skip", false) && pl.api.index < pl.api.queue.length - 1) skipT.restart(); }
    }
    Timer { id: skipT; interval: 400; onTriggered: pl.api.next() }
}
