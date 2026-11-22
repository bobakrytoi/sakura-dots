pragma Singleton
// sakura mono - what the top bar's notch says for a moment (TopBar.qml draws it, iRiS-style: the notch itself
// grows deeper and wider, shows it, and folds back into the clock).
//  · OSD: volume / mic / brightness level - icon + level bar + percent, ~1.5 s after the last change.
//    Volume and mute are caught right here from Pipewire, so keys, the headset wheel, the bar wheel, the mixer
//    and pavucontrol all show it. vol.sh also calls `qs ipc call osd volume` (it shows at the ceiling, where
//    nothing changes); when the shell is down vol.sh falls back to swayosd.
//  · Notices: a short line for ~2.5 s - screenshot saved, DND, timer done, clip saved, wallpaper, VPN…
//    QML: Notch.notice("shot", "Screenshot saved")   shell: qs ipc call notice say shot "Screenshot saved"
//    kinds (icon): cam shot clip timer dnd dndoff wall vpn vpnoff mute unmute mic micoff copy info battery batterylow
//    The text goes through Cfg.tr when shown, so scripts send English.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: nt

    // what is showing: "" | "osd" | "notice"
    property string mode: ""
    property string screen: ""          // the monitor it shows on (the focused one)
    property string osdKind: "volume"   // volume | mic | brightness
    property real level: 0              // 0..1 (volume may go over 1 with volMax > 100)
    property bool off: false            // muted
    property string kind: "info"        // notice icon
    property string text: ""
    property string path: ""            // a file the notice is about (click opens it)
    property int serial: 0              // bumps on every show (TopBar restarts its fold-back on it)
    readonly property bool active: mode !== ""

    readonly property var glyphs: ({
        shot: "\u{F0100}", clip: "\u{F0567}", timer: "\u{F051B}", dnd: "\u{F009B}", dndoff: "\u{F009A}",
        wall: "\u{F02E9}", vpn: "\u{F0582}", vpnoff: "\u{F099D}", mute: "\u{F075F}", unmute: "\u{F057E}",
        mic: "\u{F036C}", micoff: "\u{F036D}", copy: "\u{F018F}", info: "\u{F02FC}", battery: "\u{F0079}", batterylow: "\u{F0083}",
        music: "\u{F075A}", cam: "\u{F0567}", rec: "\u{F044A}", replay: "\u{F0459}", share: "\u{F1483}", stopwatch: "\u{F13AB}"
    })
    function glyph(k) { return glyphs[k] || glyphs.info; }
    function osdGlyph() {
        if (osdKind === "mic") return off ? glyphs.micoff : glyphs.mic;
        if (osdKind === "brightness") return "\u{F00E0}";
        if (off || level <= 0.001) return "\u{F075F}";
        return level < 0.34 ? "\u{F057F}" : level < 0.67 ? "\u{F0580}" : "\u{F057E}";
    }

    function focusedScreen() {
        const m = Hyprland.focusedMonitor;
        return m && m.name ? m.name : Cfg.mainName;
    }

    // ── OSD ──
    PwObjectTracker { objects: [ Pipewire.defaultAudioSink, Pipewire.defaultAudioSource ] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: !!(sink && sink.audio && sink.audio.muted)
    readonly property bool micMuted: !!(source && source.audio && source.audio.muted)
    readonly property real micVol: source && source.audio ? source.audio.volume : 0

    // nothing pops while the shell starts or the default device switches (its first values aren't changes)
    property bool armed: false
    Timer { id: armT; interval: 2500; running: true; onTriggered: nt.armed = true }
    onSinkChanged: { armed = false; armT.restart(); }
    onSourceChanged: { armed = false; armT.restart(); }
    onVolChanged: if (armed) osd("volume")
    onMutedChanged: if (armed) osd("volume")
    onMicMutedChanged: if (armed) osd("mic")

    function osd(k) {
        osdKind = k || "volume";
        if (osdKind === "mic") { level = micVol; off = micMuted; }
        else if (osdKind === "volume") { level = vol; off = muted; }
        // OSD wins over a notice, but a notice that just came keeps the line a little (mute is both: the OSD shows it)
        mode = "osd"; screen = focusedScreen(); serial++;
        bump(1500);
        return shownHere() ? "ok" : "hidden";
    }
    function brightness(pct) { osdKind = "brightness"; level = pct / 100; off = false; mode = "osd"; screen = focusedScreen(); serial++; bump(1500); return shownHere() ? "ok" : "hidden"; }

    // ── notices ──
    property var queue: []
    property string img: ""             // a picture instead of the icon (the cover on a track change)
    function notice(k, t, p, im) {
        if (mode === "osd") { queue = queue.concat([{ k: k, t: t, p: p || "", im: im || "" }]).slice(-2); return; }   // only the last two wait
        kind = k || "info"; text = t || ""; path = p || ""; img = im || "";
        mode = "notice"; screen = focusedScreen(); serial++;
        bump(2600);
    }
    // Folding back: one watchdog instead of restarting a timer from every event (a spinning wheel, IPC calls,
    // hover in/out raced it and the OSD could stay). Every event only moves `until`; the watchdog (4 Hz, runs
    // only while something shows) folds once now > until. The mouse on it holds it, but never longer than
    // maxHold after the last event - so it always folds, even if a hover-out never arrives.
    property real until: 0
    property real lastEvent: 0
    property bool hovered: false
    readonly property int maxHold: 6000
    function bump(ms) { lastEvent = Date.now(); until = lastEvent + ms; }
    function fold() {
        if (queue.length) { const n = queue[0]; queue = queue.slice(1); mode = ""; notice(n.k, n.t, n.p, n.im); }
        else { mode = ""; hovered = false; }
    }
    Timer {
        interval: 250; repeat: true; running: nt.active
        onTriggered: {
            const now = Date.now();
            if (now < nt.until) return;
            if (nt.hovered && now - nt.lastEvent < nt.maxHold) return;
            nt.fold();
        }
    }
    function hold(on) { hovered = on; if (!on && active) until = Math.max(until, Date.now() + 1000); }   // mouse over it
    function dismiss() { queue = []; mode = ""; hovered = false; }

    // the top bar on that screen is hidden in bottom mode: vol.sh then uses swayosd
    function shownHere() {
        try { if (barposFile.text().trim() === "bottom" && screen === Cfg.mainName) return false; } catch (e) {}
        return true;
    }
    FileView { id: barposFile; path: Quickshell.env("HOME") + "/.config/sakura/barpos"; watchChanges: true; onFileChanged: reload() }

    // ── events the shell knows itself ──
    readonly property bool dnd: Notifs.dnd
    onDndChanged: if (armed) notice(dnd ? "dnd" : "dndoff", dnd ? "Do not disturb on" : "Do not disturb off")
    readonly property string wall: String(Cfg.data.wallpaper || "")
    property string lastWall: ""
    onWallChanged: {
        if (armed && lastWall !== "" && wall !== lastWall) notice("wall", "Wallpaper changed", wall);
        lastWall = wall;
    }
    // timers: Timers.ring() calls notice("timer", title) itself

    // Mullvad: streams its state on every change; the first block is the state now, not a change
    property string vpnState: ""
    Process {
        id: vpnProc
        running: true
        command: ["mullvad", "status", "listen"]
        stdout: SplitParser { onRead: l => {
            const m = /^(Connected|Disconnected)\b/.exec(l);
            if (!m) return;
            if (nt.vpnState !== "" && nt.vpnState !== m[1] && nt.armed) nt.notice(m[1] === "Connected" ? "vpn" : "vpnoff", m[1] === "Connected" ? "VPN on" : "VPN off");
            nt.vpnState = m[1];
        } }
        onRunningChanged: if (!running) vpnRestart.start()
    }
    Timer { id: vpnRestart; interval: 30000; onTriggered: vpnProc.running = true }

    // ── live activities: what is going on right now, in the collapsed notch beside the clock (TopBar.qml) ──
    // Order = importance: rec · timer · music · share · mic · replay. The first that is on shows, the others as
    // "+N" (a click on it steps through). An OSD / notice takes the notch over for a moment, then it comes back.
    // On/off per kind: Settings > Taskbar > Live activities (liveRec, liveTimer, liveMusic, liveShare, liveMic,
    // liveReplay - off by default, Instant Replay is on all the time - and liveTrack: title/artist on a track change).
    function liveOn(k) { const v = Cfg.data["live" + k]; return k === "Replay" ? v === true : v !== false; }
    property string fake: ""            // qs ipc call live fake <kind> - for checks only, nothing really runs

    // music: the playing player (else the last one); after a pause it stays 20 s, then folds
    readonly property var player: Players.player
    readonly property bool playing: !!player && player.isPlaying
    property bool musicLinger: false
    onPlayingChanged: { if (playing) { musicLinger = true; lingerT.stop(); } else lingerT.restart(); }
    Timer { id: lingerT; interval: 20000; onTriggered: nt.musicLinger = false }
    readonly property bool music: liveOn("Music") && !!player && (playing || musicLinger)
    readonly property string art: player ? String(player.trackArtUrl || "") : ""
    readonly property string track: player ? [player.trackTitle, player.trackArtist].filter(x => x).join(" - ") : ""
    // a track change says title - artist for a moment (debounced: players send metadata in pieces)
    readonly property string trackKey: player ? (player.trackTitle || "") + "\u0001" + (player.trackArtist || "") : ""
    property string lastTrack: ""
    property int trackWait: 0          // streams (e.g. Sakura Sound / mpv HLS) send the title first, the artist ~1-2 s later
    onTrackKeyChanged: trackT.restart()
    Timer {
        id: trackT; interval: 700
        onTriggered: {
            const k = nt.trackKey, was = nt.lastTrack;
            if (k === was) return;
            if (nt.player && !nt.player.trackArtist && nt.trackWait < 3) { nt.trackWait += 1; trackT.restart(); return; }   // wait for the artist, ≤ 2.8 s
            nt.trackWait = 0;
            nt.lastTrack = k;
            if (nt.armed && nt.playing && nt.track !== "" && nt.liveOn("Track") && nt.liveOn("Music")) nt.notice("music", nt.track, "", nt.art);
        }
    }
    // the dancing bars: exactly like the desktop visualizer widget (DeskWidget cViz) - the same cava (Desk.bars,
    // ~/.config/sakura/cava.conf, 0..1), the values straight as they come, no smoothing of our own. While music
    // shows and plays the notch counts as a visualizer user (Desk.vizUsers), so that cava runs.
    // Desk's cava is stereo (left mirrored, then right low → high): 6 bars from the right half.
    readonly property int nBars: 7
    readonly property bool barsLive: ((music && playing) || fake === "music") && act === "music"   // fake: checks only
    property bool vizHeld: false
    onBarsLiveChanged: {
        if (barsLive && !vizHeld) { vizHeld = true; Desk.vizUsers++; }
        else if (!barsLive && vizHeld) { vizHeld = false; Desk.vizUsers--; }
        if (!barsLive) bars = [];
    }
    // Dynamic Island look: 7 sticks, mirrored (3 · centre · 3), the energy lights up from the edges to the middle -
    // quiet ▁▁▁▂▁▁▁, medium ▁▂▄▅▄▂▁, loud ▃▅▇█▇▅▃. Height = overall level × a centre-peaked profile, plus a bit of
    // life from the real bands (centre: bass, then low-mid, mid, edges: highs); always symmetric, never higher than
    // the one nearer the centre. Pause: [] → equal still dots; silence slides down to them.
    function rawSym() {
        const b = Desk.bars;
        if (b.length < 12) return [];
        const r = b.slice(Math.floor(b.length / 2)), n = r.length;          // right channel, bass → highs
        const band = (a, z) => { let m = 0; for (let k = Math.floor(a * n); k < Math.floor(z * n); k++) m = Math.max(m, r[k] || 0); return m; };
        let sum = 0, pk = 0;
        for (const x of r) { sum += x; pk = Math.max(pk, x); }
        // the values straight from cava (its autosens already normalizes) - no gain of our own: a gain parked the bars
        // at the top on loud parts.
        // separate cava bands, no overlap (of the 24 right-channel bars; 0-1 are nearly empty sub-bass, 22-23 hiss):
        // centre (4) = bass 2-4, pair 3/5 = low-mid 5-8, pair 2/6 = mid 9-14, pair 1/7 = highs 15-21. Each moves on
        // its own - the centre is not lifted to its neighbours (that made 3-4-5 one thick bar).
        // edges 1/7: the MEAN of 15-20, not the peak of 15-21 - the peak hopped between noisy high bands
        const avg = (a, z) => { let t = 0, c = 0; for (let k = Math.floor(a * n); k < Math.floor(z * n); k++) { t += r[k] || 0; c++; } return c ? t / c : 0; };
        const v = [band(2 / 24, 5 / 24), band(5 / 24, 9 / 24), band(9 / 24, 15 / 24), avg(15 / 24, 21 / 24)];
        return [v[3], v[2], v[1], v[0], v[1], v[2], v[3]];
    }
    // a narrow cava band alone is noisy: each cava frame (60 Hz) eases it - quick up (α 0.5), soft down (α 0.18)
    property var bars: []
    Connections {
        target: Desk
        enabled: nt.barsLive
        function onBarsChanged() {
            const r = nt.rawSym();
            if (!r.length) { if (nt.bars.length) nt.bars = []; return; }
            const p = nt.bars.length === r.length ? nt.bars : r.map(() => 0), o = [];
            // calmer than raw cava: softer easing, a cap on how far a bar may jump up or fall per frame (a drop-out
            // or cava's autosens kicking back in after a quiet bit no longer slams them to the bottom / the top)
            for (let i = 0; i < r.length; i++) {
                const edge = i === 0 || i === r.length - 1;
                const t = edge && r[i] < 0.06 ? 0 : r[i];           // edges: tiny highs = the dot, still
                let d = (t - p[i]) * (t > p[i] ? (edge ? 0.2 : 0.28) : (edge ? 0.06 : 0.09));
                d = Math.max(-0.035, Math.min(0.07, d));
                const x = p[i] + d;
                o.push(edge && x < 0.02 ? 0 : x);
            }
            nt.bars = o;
        }
    }

    // timer / pomodoro / stopwatch (Timers.qml)
    readonly property bool timerOn: liveOn("Timer") && (Timers.tRunning || Timers.swRunning)
    readonly property string timerGlyph: Timers.tRunning ? glyphs.timer : glyphs.stopwatch
    readonly property string timerText: Timers.tRunning ? Timers.fmt(Timers.tRemain) : Timers.fmtSw(Timers.swElapsed(Timers.now)).replace(/\.\d+$/, "")
    readonly property string timerTip: Timers.tRunning ? (Timers.pomo ? Cfg.tr(Timers.pomoPhase === "focus" ? "Focus" : "Break") : Cfg.tr("Timer")) : Cfg.tr("Stopwatch")

    // recording / Instant Replay: TopBar binds its capture.sh poll here ({text, cls}); the time runs locally
    property var capture: ({})
    property real recStart: 0
    onCaptureChanged: {
        if (capture.cls !== "rec") { recStart = 0; return; }
        const m = /(\d+):(\d\d)/.exec(capture.text || ""), secs = m ? parseInt(m[1]) * 60 + parseInt(m[2]) : 0, t = Date.now();
        if (recStart === 0 || Math.abs((t - recStart) / 1000 - secs) > 3) recStart = t - secs * 1000;
    }
    readonly property bool rec: liveOn("Rec") && capture.cls === "rec"
    readonly property bool replay: liveOn("Replay") && capture.cls === "replay"
    readonly property string recText: recStart > 0 ? Timers.fmt(Math.max(0, Timers.now - recStart)) : "00:00"

    // mic in use / screen share: Pipewire streams (privacy) - which app
    function appName(n) {
        const p = n.properties || {}, b = String(p["application.process.binary"] || p["application.name"] || n.name || "");
        const e = DesktopEntries.heuristicLookup(b);
        return e && e.name ? e.name : b.charAt(0).toUpperCase() + b.slice(1);
    }
    function uniq(a) { return a.filter((x, i) => x !== "" && a.indexOf(x) === i); }
    readonly property var micApps: uniq(Pipewire.nodes.values.filter(n => {
        const p = n.properties || {};
        if (p["media.class"] !== "Stream/Input/Audio" || p["stream.monitor"] === "true") return false;
        const who = String(p["application.process.binary"] || p["application.name"] || n.name || "");
        return !/^(cava|gpu-screen-recorder|gsr-.*)$/i.test(who);     // our visualizers + Instant Replay (records the mic all the time)
    }).map(n => nt.appName(n)))
    PwObjectTracker { objects: Pipewire.nodes.values.filter(n => !n.audio) }     // video nodes carry their properties only when bound
    readonly property bool sharing:Pipewire.nodes.values.some(n => (n.properties || {})["media.class"] === "Video/Source" && /desktop-portal/.test(String(n.name || "")))
    readonly property var shareApps: uniq(Pipewire.nodes.values.filter(n => (n.properties || {})["media.class"] === "Stream/Input/Video").map(n => nt.appName(n)))
    readonly property bool mic: liveOn("Mic") && micApps.length > 0
    readonly property bool share: liveOn("Share") && sharing
    // a new privacy activity says so once (which app), then sits in the notch
    onMicChanged: if (mic && armed) notice("mic", Cfg.tr("Microphone") + " · " + micApps.join(", "))
    onShareChanged: if (share && armed) notice("share", Cfg.tr("Screen sharing") + (shareApps.length ? " · " + shareApps.join(", ") : ""))

    // Sakura Cam (CamLink.qml): the iPhone streams as a webcam
    readonly property bool cam: liveOn("Cam") && CamLink.streaming
    readonly property string camText: CamLink.since > 0 ? Timers.fmt(Math.max(0, Timers.now - CamLink.since)) : ""
    onCamChanged: if (armed) notice("cam", cam ? Cfg.tr("Camera on") + " · iPhone" : Cfg.tr("Camera off"))

    readonly property var acts: {
        const a = [];
        if (rec || fake === "rec") a.push("rec");
        if (cam || fake === "cam") a.push("cam");
        if (timerOn || fake === "timer") a.push("timer");
        if (music || fake === "music") a.push("music");
        if (share || fake === "share") a.push("share");
        if (mic || fake === "mic") a.push("mic");
        if (replay || fake === "replay") a.push("replay");
        return a;
    }
    property string pickId: ""          // stepped to with the "+N" pill (until it ends)
    onActsChanged: if (pickId !== "" && acts.indexOf(pickId) < 0) pickId = ""
    readonly property string act: acts.indexOf(pickId) >= 0 ? pickId : (acts[0] || "")
    function cycle() { if (acts.length > 1) pickId = acts[(acts.indexOf(act) + 1) % acts.length]; }
    // what the activity shows: left (an icon; music: the cover) and right (a value; music: the bars)
    function actGlyph(a) { return a === "timer" ? timerGlyph : a === "mic" && micMuted ? glyphs.micoff : glyphs[a] || glyphs.info; }
    function actText(a) {
        return a === "rec" ? recText : a === "cam" ? camText : a === "timer" ? timerText : a === "mic" ? (micApps[0] || "") : a === "share" ? (shareApps[0] || "")
             : a === "replay" ? Cfg.tr("Replay") : "";
    }
    function actTip(a) {
        return a === "music" ? track : a === "rec" ? Cfg.tr("Recording") : a === "cam" ? "Sakura Cam · " + CamLink.resText : a === "timer" ? timerTip
             : a === "mic" ? Cfg.tr("Microphone") + " · " + micApps.join(", ") : a === "share" ? Cfg.tr("Screen sharing") + " · " + shareApps.join(", ")
             : a === "replay" ? Cfg.tr("Instant Replay") : "";
    }
    IpcHandler {
        target: "live"
        function state(): string { return nt.acts.length ? nt.act + (nt.acts.length > 1 ? " (+" + (nt.acts.length - 1) + ": " + nt.acts.join(",") + ")" : "") : "none"; }
        function fake(kind: string): void { nt.fake = kind === "off" ? "" : kind; }
        function next(): void { nt.cycle(); }
        function bars(): string { return "vizUsers " + Desk.vizUsers + " playing " + nt.playing + " live " + nt.barsLive + " bars " + nt.bars.map(x => x.toFixed(2)).join(" ") + " raw " + Desk.bars.slice(Math.floor(Desk.bars.length / 2)).map(x => Math.round(x * 100)).join(","); }
        function track(): void { if (nt.track !== "") nt.notice("music", nt.track, "", nt.art); }     // replays the track-change slide
        function nodes(): string { return Pipewire.nodes.values.map(n => n.id + " " + n.name + " [" + ((n.properties || {})["media.class"] || "?") + "]").join("\n"); }
    }

    // ── IPC ──
    IpcHandler {
        target: "osd"
        function volume(): string { return nt.osd("volume"); }
        function mic(): string { return nt.osd("mic"); }
        function brightness(pct: int): string { return nt.brightness(pct); }
        function state(): string { return nt.mode === "" ? "rest" : nt.mode + " on " + nt.screen + (nt.hovered ? " (hovered)" : ""); }   // for checks
    }
    IpcHandler {
        target: "notice"
        function say(kind: string, text: string): void { nt.notice(kind, text, ""); }
        function file(kind: string, text: string, path: string): void { nt.notice(kind, text, path); }
        function hide(): void { nt.dismiss(); }
    }
}
