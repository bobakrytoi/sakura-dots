// The object every plugin gets as `api` (one per plugin).
//   state:   track, position, duration, playing, buffering, queue, index, volume, shuffle, repeat, signedIn, me
//   events:  trackChanged, positionChanged, playingChanged (=stateChanged), queueChanged, started(track), ended()
//   actions: play(trackOrTracks, i), enqueue(t, next), next(), prev(), toggle(), pause(), resume(), seek(s),
//            setVolume(v), search(q, cb, type), list(kind, arg, cb), radio(tid), af(name, value), afCommand(label, cmd, arg),
//            send(cmd, args, cb), notify(text), openArtist(id), go(page)
//   UI:      addPage({p, icon, label, component}), addPlayerButton({icon, act, on}), addMenuItem({icon, label, act(track)}),
//            addNowBlock({component}), addSideTab({id, icon, label, component}), addFilter(fn(items, kind) → items)
//   storage: config (reactive), get(key, def), set(key, value)
import QtQuick

QtObject {
    id: api
    property string pid: ""
    property var host: null
    readonly property var app: host ? host.app : null
    readonly property var config: host ? (host.rev, host.configOf(pid)) : ({})
    readonly property string dir: host ? host.dirOf(pid) : ""

    readonly property var track: Sound.track
    readonly property real position: Sound.livePos
    readonly property real duration: Sound.dur
    readonly property bool playing: Sound.playing
    readonly property bool buffering: Sound.buffering
    readonly property var queue: (Sound.queueRev, Sound.queue)
    readonly property int index: Sound.idx
    readonly property real volume: Sound.vol
    readonly property bool shuffle: Sound.shuffle
    readonly property string repeat: Sound.repeat
    readonly property bool signedIn: Sound.signedIn
    readonly property var me: Sound.me
    signal stateChanged()
    signal started(var track)
    signal ended()
    property var _c: Connections {
        target: Sound
        function onPlayingChanged() { api.stateChanged(); }
        function onBufferingChanged() { api.stateChanged(); }
        function onStarted(t) { api.started(t); }
        function onEnded() { api.ended(); }
    }

    function play(t, i) { Sound.playList(Array.isArray(t) ? t : [t], i || 0); }
    function enqueue(t, playNext) { Sound.enqueue(t, playNext); }
    function next() { Sound.next(); }
    function prev() { Sound.prev(); }
    function toggle() { Sound.toggle(); }
    function pause() { Sound.send("pause"); }
    function resume() { Sound.send("resume"); }
    function seek(s) { Sound.seek(s); }
    function setVolume(v) { Sound.setVolume(v); }
    function search(q, cb, type) { Sound.search(q, type || "tracks", cb); }
    function list(kind, arg, cb, next) { Sound.list(kind, arg, cb, next); }
    function radio(tid) { Sound.radio(tid || (Sound.track && Sound.track.id)); }
    function af(name, value) { Sound.send("af", { name: pid + "-" + name, value: value || "" }); }
    // target = filter name inside the lavfi graph, e.g. af("x", "@lbl:lavfi=[volume=1]") → afCommand("lbl", "volume", 0.5, "volume")
    function afCommand(label, cmd, arg, target) { Sound.send("afcmd", { label: label, op: cmd, arg: arg, target: target || cmd }); }
    function send(cmd, args, cb) { Sound.send(cmd, args, cb); }
    function notify(text) { Sound.error(text); }
    function openArtist(id) { if (app) app.openArtist(id); }
    function go(p) { if (app) app.go(p); }
    function like(t) { /* write actions are P6 */ }

    function addPage(o) { host.register(pid, "pages", o); }
    function addPlayerButton(o) { host.register(pid, "buttons", o); }
    function addMenuItem(o) { host.register(pid, "menu", o); }
    function addNowBlock(o) { host.register(pid, "blocks", o); }
    function addSideTab(o) { host.register(pid, "tabs", o); }
    function addFilter(fn) { host.register(pid, "filters", fn); }

    function get(key, def) { const v = config[key]; return v === undefined ? def : v; }
    function set(key, value) { host.setConfig(pid, key, value); }
}
