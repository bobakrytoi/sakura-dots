pragma Singleton
// sakura mono - the big moments as one choreography. Everything that enters or leaves the screen reads these
// numbers, so bar, dock, widgets, greeting and the session screen move as one organism.
//   bar, dock: 0 = tucked into their edge, 1 = in place (TopBar.qml / shell.qml DockWindow shift their content)
//   wt:        ms since the widgets' turn began; widget i rises at i * gap (widgetIn(i)); huge = all in place
//   veil:      0..1 the screen going dark (SessionScreen.qml draws it) before log out / restart / shut down
//   still:     nothing is moving - windows take clicks again (their masks are swapped off while they move)
// Moments:
//   login    first shell start of the session ($XDG_RUNTIME_DIR/sakura-greeted): greeting cascade → bar flows down
//            → dock rises → widgets one by one → mascot waves. < 2.5 s, any click skips (Greeting.qml catches it).
//            Off in Settings > Appearance > Shell ("animLogin"): everything is just there.
//   restart  any other start (qs restart, Quickshell.reload, settings "Reload shell"): bar and dock grow back.
//   unlock   Lock.qml calls enter("unlock") when the lock screen has faded into the wallpaper.
//   leave    leave(id): bar and dock slide back into their edges, the screen dims, then the action runs.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: ch
    property real bar: 0
    property real dock: 0
    property real wt: 0
    property real veil: 0
    property string moment: ""                 // "" | login | restart | unlock | leave
    readonly property bool still: moment === ""
    readonly property bool first: started === "new"
    property string started: ""                // "" until the flag check is back, then new | seen
    signal greet()                             // login: Greeting.qml plays its cascade
    signal skipped()

    readonly property int gap: 90              // between two widgets
    readonly property int wdur: 520
    readonly property real k: Math.max(0.3, Cfg.anim)
    function ease(x) { x = Math.max(0, Math.min(1, x)); return 1 - Math.pow(1 - x, 3); }
    function widgetIn(i) { return ease((wt - i * gap * k) / (wdur * k)); }

    // first start in this session?
    readonly property string flag: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/sakura-greeted"
    Process {
        running: true
        command: ["sh", "-c", "[ -e \"$1\" ] && echo seen || { touch \"$1\"; echo new; }", "sh", ch.flag]
        stdout: StdioCollector { onStreamFinished: {
            ch.started = this.text.trim() === "new" ? "new" : "seen";
            if (ch.first && Cfg.data.animLogin !== false) ch.enter("login");
            else ch.enter(ch.first ? "none" : "restart");
            if (ch.first && Cfg.data.greet !== false) ch.greet();
        } }
    }
    // never stay tucked away if something goes wrong
    Timer { interval: 4000; running: true; onTriggered: if (ch.started === "") ch.enter("restart") }

    function enter(kind) {
        foldA.stop(); awayA.stop(); backT.stop();
        if (veil > 0) unveilA.restart();
        if (kind === "none") { done(); return; }
        moment = kind === "login" ? "login" : kind === "unlock" ? "unlock" : "restart";
        tl = kind === "login" ? login : again;
        bar = 0; dock = 0; wt = 0; clk = 0; calm = 0;
    }
    function done() { tl = null; bar = 1; dock = 1; wt = 1e6; moment = ""; }
    function skip() { if (tl) { done(); skipped(); } }
    // ready for the lock screen to go away: tuck everything so it grows back after unlocking
    function tuck() { tl = null; bar = 0; dock = 0; wt = 0; moment = "unlock"; }

    // ── the timeline: its own clock, advanced frame by frame and never more than ~2 frames at once, so while the
    //    shell is still busy loading (a start, a reload) the moves wait instead of jumping to their end ──
    readonly property var login: ({ bar: 420, dock: 560, w: 780, len: 720, os: 0, end: 2300 })   // after the greeting cascade
    readonly property var again: ({ bar: 160, dock: 250, w: 360, len: 620, os: 0, end: 1700 })
    property var tl: null
    property real calm: 0
    property real clk: 0                       // ms on the timeline (Greeting.qml follows it at login)
    function back(x, s) { x = Math.max(0, Math.min(1, x)); x = x * x * (3 - 2 * x); const c = s + 1; return 1 + c * Math.pow(x - 1, 3) + s * Math.pow(x - 1, 2); }
    FrameAnimation {
        running: ch.tl !== null
        onTriggered: {
            const t = ch.tl, kk = ch.k;
            // wait until the frames come evenly for a moment (a fresh start loads windows in bursts)
            ch.calm = frameTime < 0.04 ? ch.calm + frameTime : 0;
            if (ch.calm < 0.25 && ch.clk === 0) return;
            ch.clk += Math.min(frameTime, 0.034) * 1000;
            ch.bar = ch.back((ch.clk - t.bar * kk) / (t.len * kk), t.os);
            ch.dock = ch.back((ch.clk - t.dock * kk) / (t.len * kk), t.os);
            ch.wt = Math.max(0, ch.clk - t.w * kk);
            if (ch.clk >= t.end * kk) ch.done();
        }
    }

    // ── leaving: fold away, dim, then run ──
    readonly property string sc: Quickshell.env("HOME") + "/.config/hypr/scripts/"
    readonly property string save: sc + "session.py save; "
    readonly property var acts: ({
        lock:     sc + "lock.sh",
        logout:   save + "uwsm stop || hyprctl dispatch 'hl.dsp.exit()'",
        sleep:    "systemctl suspend",
        restart:  save + "systemctl reboot",
        shutdown: save + "systemctl poweroff"
    })
    property string pending: ""
    function leave(id) {
        if (!acts[id]) return;
        if (id === "lock") { Quickshell.execDetached(["sh", "-c", acts.lock]); return; }   // the lock screen fades in itself
        tl = null; backT.stop();
        pending = id; moment = "leave";
        foldA.restart();
    }
    SequentialAnimation {
        id: foldA
        ParallelAnimation {
            NumberAnimation { target: ch; property: "bar"; to: 0; duration: 380 * ch.k; easing.type: Easing.InBack; easing.overshoot: 1.2 }
            SequentialAnimation {
                PauseAnimation { duration: 60 * ch.k }
                NumberAnimation { target: ch; property: "dock"; to: 0; duration: 380 * ch.k; easing.type: Easing.InBack; easing.overshoot: 1.2 }
            }
            NumberAnimation { target: ch; property: "wt"; to: 0; duration: 300 * ch.k }
            NumberAnimation { target: ch; property: "veil"; to: 1; duration: 620 * ch.k; easing.type: Easing.InOutQuad }
        }
        ScriptAction { script: {
            Quickshell.execDetached(["sh", "-c", ch.acts[ch.pending]]);
            backT.interval = ch.pending === "sleep" ? 1800 : 12000;     // still here (cancelled / back from sleep)
            backT.restart();
        } }
    }
    Timer { id: backT; onTriggered: ch.enter("restart") }

    // ── any sleep / shutdown / reboot, however it was started (power button, terminal, hypridle): logind waits a
    //    moment for us (hypr/scripts/leavewatch.sh holds a delay inhibitor) and we fold away the same way ──
    function away() {
        if (moment === "leave") return;            // started from our own buttons: already folding
        tl = null; backT.stop(); pending = ""; moment = "leave";
        awayA.restart();
    }
    ParallelAnimation {
        id: awayA
        NumberAnimation { target: ch; property: "bar"; to: 0; duration: 340; easing.type: Easing.InBack; easing.overshoot: 1.2 }
        SequentialAnimation {
            PauseAnimation { duration: 50 }
            NumberAnimation { target: ch; property: "dock"; to: 0; duration: 340; easing.type: Easing.InBack; easing.overshoot: 1.2 }
        }
        NumberAnimation { target: ch; property: "wt"; to: 0; duration: 280 }
        NumberAnimation { target: ch; property: "veil"; to: 1; duration: 560; easing.type: Easing.InOutQuad }
    }
    Process {
        running: true
        command: [ch.sc + "leavewatch.sh"]
        stdout: SplitParser { onRead: l => {
            if (l.startsWith("away")) ch.away();
            else if (l === "back" && ch.moment === "leave") { awayA.stop(); foldA.stop(); ch.enter("restart"); }
        } }
    }
    NumberAnimation { id: unveilA; target: ch; property: "veil"; to: 0; duration: 500; easing.type: Easing.OutQuad }

    IpcHandler {
        target: "choreo"
        function play(kind: string): void { ch.enter(kind || "restart"); }
        function login(): void { ch.enter("login"); ch.greet(); }
        function away(): void { ch.away(); }
        function back(): void { ch.enter("restart"); }
        function state(): string { return ch.moment + " bar " + ch.bar.toFixed(2) + " dock " + ch.dock.toFixed(2) + " veil " + ch.veil.toFixed(2); }
    }
}
