// sakura mono - ambient sounds for the edge drum (EdgeTab): rain, campfire, cafe, forest, waves, noise.
// Each one is its own mpv (--loop-file=inf), so they mix with each other and play over the music.
// Files: ~/.local/share/sakura/ambient/<id>.ogg (CC0, sources in the README there); the noise has no file,
// mpv makes it with ffmpeg's lavfi anoisesrc (white / pink / brown).
// Volume changes go to the running mpv over its IPC socket (no restart, no gap). --no-config --load-scripts=no keeps
// the mpris plugin out (otherwise every sound shows up as a "now playing" player in the bar / dashboard).
// settings.json "ambient": { <id>: { on, vol 0..100 }, noiseColor } - what plays comes back after a restart.
import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: amb

    readonly property string dir: Quickshell.env("HOME") + "/.local/share/sakura/ambient/"
    readonly property string sockBase: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/sakura-ambient-"
    // add a sound: drop <id>.ogg into the folder and a line here
    readonly property var sounds: [
        { id: "rain",   icon: "\u{F0597}", label: "Rain" },
        { id: "fire",   icon: "\u{F0238}", label: "Campfire" },
        { id: "cafe",   icon: "\u{F0176}", label: "Cafe" },
        { id: "forest", icon: "\u{F0405}", label: "Forest" },
        { id: "waves",  icon: "\u{F078D}", label: "Waves" },
        { id: "noise",  icon: "\u{F147D}", label: "Noise", noise: true }
    ]
    readonly property var noiseColors: ["white", "pink", "brown"]
    readonly property var noiseAmp: ({ white: 0.10, pink: 0.22, brown: 0.45 })

    // local copy of the saved state: the wheel changes it many times a second, settings.json gets it debounced
    property var st: ({})
    property bool ready: false          // settings read and leftovers of an old shell killed
    property bool cleaned: false
    function load() {
        if (!Cfg.loaded || !cleaned || ready) return;
        const s = Cfg.data.ambient;
        st = s && typeof s === "object" ? JSON.parse(JSON.stringify(s)) : {};
        ready = true;
    }
    Connections { target: Cfg; function onLoadedChanged() { amb.load(); } }
    // mpv players that outlived a previous shell would play twice
    Process {
        running: true
        command: ["pkill", "-f", "--", "--audio-client-name=sakura-ambient"]
        onExited: { amb.cleaned = true; amb.load(); }
    }
    Timer { id: saveT; interval: 700; onTriggered: Cfg.set("ambient", JSON.parse(JSON.stringify(amb.st))) }

    function get(id) {
        const s = st[id] || {};
        return { on: s.on === true, vol: typeof s.vol === "number" ? s.vol : 45 };
    }
    readonly property string noiseColor: noiseColors.includes(st.noiseColor) ? st.noiseColor : "pink"
    readonly property bool playing: { for (const s of sounds) if (get(s.id).on) return true; return false; }
    readonly property int playingCount: { let n = 0; for (const s of sounds) if (get(s.id).on) n++; return n; }

    function patch(id, p) {
        const all = Object.assign({}, st);
        all[id] = Object.assign(get(id), p);
        st = all;
        saveT.restart();
    }
    function toggle(id) { patch(id, { on: !get(id).on }); }
    // wheel: ±step; turning it up on a silent sound starts it
    function nudge(id, d) {
        const g = get(id), v = Math.max(0, Math.min(100, g.vol + d));
        patch(id, { vol: v, on: g.on || d > 0 });
    }
    function stopAll() {
        const all = Object.assign({}, st);
        for (const s of sounds) all[s.id] = Object.assign(get(s.id), { on: false });
        st = all;
        saveT.restart();
    }
    function cycleNoise() {
        const all = Object.assign({}, st);
        all.noiseColor = noiseColors[(noiseColors.indexOf(noiseColor) + 1) % noiseColors.length];
        st = all;
        saveT.restart();
    }

    Variants {
        model: amb.sounds
        Scope {
            id: pl
            required property var modelData
            readonly property string sid: modelData.id
            readonly property bool on: amb.ready && amb.get(sid).on
            readonly property int vol: amb.get(sid).vol
            readonly property string sock: amb.sockBase + sid + ".sock"
            readonly property string src: modelData.noise
                ? "av://lavfi:anoisesrc=color=" + amb.noiseColor + ":amplitude=" + amb.noiseAmp[amb.noiseColor]
                : amb.dir + sid + ".ogg"
            property int startVol: 45

            function sync() {
                if (on && !proc.running) { startVol = vol; proc.running = true; }
                else if (!on && proc.running) proc.running = false;
            }
            onOnChanged: sync()
            onSrcChanged: if (proc.running) { proc.running = false; again.restart(); }
            Timer { id: again; interval: 150; onTriggered: pl.sync() }
            onVolChanged: if (proc.running) send()

            Process {
                id: proc
                command: ["mpv", "--no-config", "--load-scripts=no", "--no-video", "--no-terminal", "--loop-file=inf", "--volume=" + pl.startVol,
                          "--input-ipc-server=" + pl.sock, "--audio-client-name=sakura-ambient",
                          "--force-media-title=Sakura ambient · " + pl.sid, pl.src]
                onRunningChanged: if (!running) { sk.connected = false; if (pl.on) retry.restart(); }
            }
            Timer { id: retry; interval: 3000; onTriggered: pl.sync() }     // mpv died on its own: try again, calmly
            // mpv's IPC: one JSON command per line
            Socket {
                id: sk
                path: pl.sock
                onConnectedChanged: if (connected) pl.send()
            }
            function send() {
                if (!sk.connected) { sk.connected = true; return; }
                sk.write(JSON.stringify({ command: ["set_property", "volume", pl.vol] }) + "\n");
                sk.flush();
            }
        }
    }
}
