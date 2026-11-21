import QtQuick
import "../.."

Item {
    id: pl
    property var api: null
    property var cur: null
    property real startedAt: 0
    property bool done: false
    readonly property bool ready: api && api.get("sk", "") && api.get("key", "")
    function call(method, params, post, cb) {
        api.send("lastfm", { method: method, params: params, key: api.get("key", ""), secret: api.get("secret", ""), sk: api.get("sk", "") || null, post: post },
                 r => { if (cb) cb(r); });
    }
    function action(k) {
        if (k === "connect") {
            if (!api.get("key", "") || !api.get("secret", "")) { api.set("status", "API key + secret first"); return; }
            api.send("lastfm", { method: "auth.getToken", params: {}, key: api.get("key", ""), secret: api.get("secret", "") }, r => {
                const tok = r.data && r.data.token;
                if (!tok) { api.set("status", r.err || "token error"); return; }
                api.set("token", tok);
                Sound.openUrl("https://www.last.fm/api/auth/?api_key=" + api.get("key", "") + "&token=" + tok);
                api.set("status", "Allow access in the browser, then Done");
            });
        } else if (k === "finish") {
            api.send("lastfm", { method: "auth.getSession", params: { token: api.get("token", "") }, key: api.get("key", ""), secret: api.get("secret", "") }, r => {
                const s = r.data && r.data.session;
                if (!s) { api.set("status", r.err || (r.data && r.data.message) || "session error"); return; }
                api.set("sk", s.key); api.set("status", "Connected · " + s.name);
            });
        }
    }
    function meta(t) {
        // "Artist - Title" inside SoundCloud titles
        const m = (t.title || "").match(/^\s*(.+?)\s+[---]\s+(.+)$/);
        return m ? { artist: m[1], track: m[2] } : { artist: t.artist, track: t.title };
    }
    Connections {
        target: pl.api
        function onStarted(t) {
            pl.cur = t; pl.done = false; pl.startedAt = Math.floor(Date.now() / 1000);
            if (pl.ready && t) { const m = pl.meta(t); pl.call("track.updateNowPlaying", { artist: m.artist, track: m.track, duration: Math.round(t.dur) }, true); }
        }
        function onPositionChanged() {
            const t = pl.cur;
            if (!pl.ready || !t || pl.done || t.dur < 30) return;
            if (pl.api.position >= Math.min(240, t.dur / 2)) {
                pl.done = true;
                const m = pl.meta(t);
                pl.call("track.scrobble", { artist: m.artist, track: m.track, timestamp: pl.startedAt, duration: Math.round(t.dur) }, true);
            }
        }
    }
}
