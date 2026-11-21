pragma Singleton
// Player state + the backend process (backend/backend.py, JSON lines over stdin/stdout).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: s

    readonly property string dir: Quickshell.env("HOME") + "/.config/sakura-sound"

    // ── state (mirrors backend events) ──────────────────────────
    property bool ready: false
    property bool playing: false
    property real pos: 0
    property real dur: 0
    property real vol: 70
    property bool muted: false
    property bool buffering: false
    property bool shuffle: false
    property string repeat: "off"
    property int idx: -1
    property var track: null
    property var queue: []
    property int queueRev: 0
    property var wave: []
    property var auth: ({ ok: false, user: null })
    readonly property bool signedIn: auth.ok === true
    readonly property var me: auth.user || null
    property string lastError: ""
    property color coverColor: "transparent"     // saturated tone of the current artwork (palette event)
    property real bass: 0                        // 0..1, fed by the visualizer while it runs (effects)

    // likes / follows (ids → true); optimistic, rolled back on error
    property var liked: ({})
    property var following: ({})
    property int mineRev: 0
    function loadMine() {
        send("mine", {}, r => {
            if (r.err) return;
            const l = {}, f = {};
            for (const i of r.likes || []) l[i] = true;
            for (const i of r.following || []) f[i] = true;
            liked = l; following = f; mineRev += 1;
        });
    }
    function isLiked(id) { return (mineRev, !!liked[id]); }
    function isFollowing(id) { return (mineRev, !!following[id]); }
    function like(t, on) {
        if (!t || !t.id) return;
        const want = on === undefined ? !liked[t.id] : on;
        const m = Object.assign({}, liked); if (want) m[t.id] = true; else delete m[t.id]; liked = m; mineRev += 1;
        // saved in the player and merged with SoundCloud likes (SoundCloud rejects writes from outside its site)
        send("like", { tid: t.id, on: want, track: t }, r => {
            if (!r.err) { likesRev += 1; return; }
            const b = Object.assign({}, liked); if (want) delete b[t.id]; else b[t.id] = true; liked = b; mineRev += 1;
            error(r.err);
        });
    }
    property int likesRev: 0      // bumps after a like/unlike was saved (lists refresh)
    property int followRev: 0
    function follow(uid, on, user) {
        if (!uid) return;
        const want = on === undefined ? !following[uid] : on;
        const m = Object.assign({}, following); if (want) m[uid] = true; else delete m[uid]; following = m; mineRev += 1;
        send("follow", { uid: uid, on: want, user: (user && user.type === "user") ? user : null }, r => {
            if (!r.err) { followRev += 1; return; }
            const b = Object.assign({}, following); if (want) delete b[uid]; else b[uid] = true; following = b; mineRev += 1;
            error(r.err);
        });
    }
    onSignedInChanged: loadMine()
    onReadyChanged: if (ready) loadMine()

    signal error(string msg)
    signal started(var track)     // a new track became current
    signal ended()                // queue ran out
    signal event(var ev)          // every raw event (plugins)

    // smooth position between backend updates (only while visible+playing)
    property real _posAt: 0
    property bool smooth: false
    readonly property real livePos: _livePos
    property real _livePos: 0
    Timer {
        interval: 100; repeat: true
        running: s.smooth && s.playing && !s.buffering
        onTriggered: s._livePos = Math.min(s.dur, s.pos + (Date.now() - s._posAt) / 1000)
    }
    onPosChanged: { _posAt = Date.now(); _livePos = pos; }

    // ── backend process ─────────────────────────────────────────
    property var _cbs: ({})
    property int _id: 0
    property var _pending: []

    function send(cmd, args, cb) {
        // "cmd" and "id" are the protocol's own fields (command name, request id): never use them as arguments
        if (args && (args.cmd !== undefined || args.id !== undefined)) console.warn("[sound] send(" + cmd + "): 'cmd'/'id' are reserved argument names");
        const o = Object.assign({ cmd: cmd }, args || {});
        if (cb) { _id += 1; o.id = _id; _cbs[_id] = cb; }
        const line = JSON.stringify(o) + "\n";
        if (proc.running && ready) proc.write(line);
        else _pending.push(line);
    }

    Process {
        id: proc
        running: true
        stdinEnabled: true
        command: ["python3", s.dir + "/backend/backend.py"].concat(Quickshell.env("SAKURA_SOUND_TEST") ? ["--test"] : [])
        stdout: SplitParser { splitMarker: "\n"; onRead: d => s.ingest(d) }
        stderr: SplitParser { onRead: d => console.log("[sound backend] " + d) }
        onExited: (code, st) => { s.ready = false; s.playing = false; restartT.start(); }
    }
    Timer { id: restartT; interval: 1500; onTriggered: proc.running = true }

    function ingest(line) {
        let e;
        try { e = JSON.parse(line); } catch (x) { return; }
        switch (e.ev) {
        case "ready":
            ready = true;
            for (const l of _pending) proc.write(l);
            _pending = [];
            break;
        case "state":
            playing = e.playing; dur = e.dur; vol = e.vol; muted = e.muted; buffering = e.buffering;
            shuffle = e.shuffle; repeat = e.repeat; idx = e.idx;
            pos = e.pos;
            break;
        case "track":
            const changed = !track || !e.track || track.id !== e.track.id;
            track = e.track; idx = e.idx;
            if (changed) { wave = []; started(e.track); }
            break;
        case "queue":
            queue = e.items || []; idx = e.idx; queueRev += 1;
            break;
        case "queue_idx":
            idx = e.idx; queueRev += 1;
            break;
        case "wave":
            if (track && e.id === track.id) wave = e.samples || [];
            break;
        case "palette":
            if (track && e.id === track.id && e.color) coverColor = e.color;
            break;
        case "auth":
            auth = e;
            break;
        case "ended":
            ended();
            break;
        case "error":
            lastError = e.msg || "";
            error(lastError);
            break;
        case "reply":
            const cb = _cbs[e.rid];
            if (cb) { delete _cbs[e.rid]; try { cb(e); } catch (x) { console.log("cb: " + x); } }
            break;
        case "log":
            console.log("[sound] " + e.msg);
            break;
        }
        event(e);
    }

    // ── actions ─────────────────────────────────────────────────
    function playList(tracks, i) { send("play", { tracks: tracks.filter(t => t && t.type === "track"), index: i || 0 }); }
    function jump(i) { send("play", { index: i }); }
    function toggle() { send("toggle"); }
    function next() { send("next"); }
    function prev() { send("prev"); }
    function seek(t) { pos = t; send("seek", { t: t }); }
    function setVolume(v) { vol = v; send("volume", { v: v }); }
    function enqueue(t, playNext) { send("enqueue", { tracks: Array.isArray(t) ? t : [t], next: !!playNext }); }
    function remove(i) { send("remove", { i: i }); }
    function move(a, b) { send("move", { from: a, to: b }); }
    function setShuffle() { send("shuffle"); }
    function cycleRepeat() { send("repeat"); }
    function list(kind, arg, cb, next) { send("list", { kind: kind, arg: arg, next: next || null }, cb); }
    function search(q, type, cb, next) { send("search", { q: q, type: type || "tracks", next: next || null }, cb); }
    function radio(tid) { send("radio", { tid: tid, enqueue: true }); }

    function copy(text) { Quickshell.execDetached(["wl-copy", text]); }
    function openUrl(u) { Quickshell.execDetached(["xdg-open", u]); }
}
