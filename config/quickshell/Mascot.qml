// sakura mono - a little sakura spirit that peeks out from a screen edge now and then (the drawing: MascotArt.qml).
// Shy: hovering makes her flustered and she ducks away; a click = a line (poke her 4 times fast and she pouts off).
// Her pose follows what happens: music → sings, late night → sleepy, notification / mute → surprised, screenshot /
// timer / wallpaper → happy, login / unlock → waves, hours of work → "take a break", back from a game → "GG".
// Never over a fullscreen window or the lock screen. Idea of poses, entrances, click ladder and chaos: iNiR's mascot.
// Chaos mode (off by default): now and then she runs along the bottom edge (hops over the dock, leaves petals),
// and peeks from any edge or corner. Clicks pass through everywhere except her.
// Your own picture: ~/.config/sakura/mascot.png, and optionally mascot-<pose>.png per pose.
// Catch & throw (mascotThrow, on): hold her and drag - she dangles; let go with a flick - she flies, bounces off the
// screen edges, lands dizzy and walks back behind her edge (throw her 4 times in 90 s and she sulks off for 5 min).
// Extras (mascotExtras, all on): dance - bounces to the bass while music plays (cava via Desk.bars); outfit - umbrella /
// scarf / shades from the weather, rain / snow / petals / leaves by weather and season; sit - sometimes sits on a
// window's top edge, falls when it moves / closes; notes - a sticky note on the desktop once a day; friend - a
// second little spirit joins some runs and they chat. System reactions: hot (cpu/gpu temp), disk (≥ 90 %), updates.
// Flex (triple Shift / IPC flex): ~55 s of showing off - shades drop in, gold chain, a fan of bills in your face,
// a money gun, making it rain, counting cash, a dance, then glasses off, a bow, and she strolls off.
// IPC: qs ipc call mascot flex | sit | perch | note | duo |
// IPC: qs ipc call mascot peek | peekat <right|left|top|bottom> | react <event> | pose <name> | chaos | fling <vx> <vy> | hide
//      events: music notify wallpaper screenshot mute timer unlock login break late game
// Settings: Settings > Appearance > Shell (mascot, mascotFreq/Size/Edge/Height/React/Break/Chaos).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import QtMultimedia

Scope {
    id: ms
    property var lock: null                  // Lock.qml (shell.qml passes it): "welcome back" after unlocking
    readonly property bool on: Cfg.data.mascot !== false
    readonly property bool chaos: Cfg.data.mascotChaos === true

    // ── your own pictures ──
    property var pics: []
    readonly property string dir: Quickshell.env("HOME") + "/.config/sakura/"
    readonly property string custom: pics.includes("mascot-" + pose + ".png") ? dir + "mascot-" + pose + ".png"
                                   : pics.includes("mascot.png") ? dir + "mascot.png" : ""
    Process {
        id: picsP; running: true
        command: ["sh", "-c", "cd \"$HOME/.config/sakura\" 2>/dev/null && ls mascot*.png 2>/dev/null; true"]
        stdout: StdioCollector { onStreamFinished: ms.pics = text.split("\n").filter(s => s !== "") }
    }

    // ── where and how she is ──
    property real out: 0                     // 0 = hidden behind the edge, 1 = peeking
    property int outMs: 650
    property int outEase: Easing.OutBack
    Behavior on out { NumberAnimation { duration: Math.max(1, ms.outMs * Cfg.anim); easing.type: ms.outEase } }
    property real depth: 0.62                // how far she leans out
    property string edge: "right"            // right | left | top | bottom
    property real along: 0.28                // right/left: height from the bottom; top/bottom: x (0-1)
    property bool lean: false                // top/bottom: she's on the right half (leans and talks toward the middle)
    property string pose: "idle"             // idle happy sleepy surprised sing shy wave pout run
    property string say: ""
    readonly property real size: Cfg.data.mascotSize || 1.0
    readonly property real bw: 120 * size
    readonly property real bh: 150 * size
    readonly property bool side: edge === "left" || edge === "right"
    readonly property var hmon: Cfg.mainScreen ? Hyprland.monitorFor(Cfg.mainScreen) : null
    readonly property bool fullscreen: hmon && hmon.activeWorkspace ? hmon.activeWorkspace.hasFullscreen === true : false
    readonly property bool locked: !!(lock && lock.locked)
    property bool ready: false               // no reactions to the state we find at startup
    Timer { interval: 8000; running: true; onTriggered: ms.ready = true }

    property int hour: new Date().getHours()
    readonly property bool late: hour < 5
    readonly property string rest: late ? "sleepy" : (Desk.player && Desk.player.isPlaying ? "sing" : "idle")

    readonly property var freq: ({ rare: [600, 600], normal: [180, 240], often: [60, 120] })[Cfg.data.mascotFreq || "normal"] || [180, 240]
    readonly property var idleLines: ["Hi!", "Drink some water", "Take a short break?", "Looking good today", "Don't forget to stretch", "What are we listening to?", "Nice wallpaper", "Boo!", "Peekaboo!"]
    readonly property var lateLines: ["It's late… time for bed?", "Yawn… still up?"]
    readonly property var patLines: ["Hehe, that tickles", "Okay, pats are allowed", "…again?"]
    readonly property var poutLines: ["Hey! Enough poking!", "I'm off!"]
    readonly property var stareLines: ["…What?", "Staring is rude", "Hehe, hi"]
    readonly property var runLines: ["Catch me!", "Can't stop, busy!", "Wheee!"]
    readonly property var cardLines: ["Just passing by", "Boo!", "Wheee!", "Peekaboo!"]

    // reactions: key = switch in Settings ("Reacts to"), pose, lines, cooldown
    readonly property var reactKeys: ["music", "notify", "wallpaper", "screenshot", "mute", "timer", "unlock", "break", "late", "game", "hot", "disk", "updates"]
    readonly property var extraKeys: ["dance", "outfit", "sit", "notes", "friend"]
    readonly property var extras: Cfg.data.mascotExtras || extraKeys
    function has(k) { return extras.includes(k); }
    readonly property var reactOn: Cfg.data.mascotReact || reactKeys
    readonly property var reactions: ({
        music:      { pose: "sing", lines: ["Nice song!", "♪ La-la-la…", "This one's a bop"], cool: 90000 },
        notify:     { pose: "surprised", lines: ["You've got a message"], cool: 120000 },
        wallpaper:  { pose: "happy", lines: ["Nice wallpaper", "Ooh, pretty!"], cool: 20000 },
        screenshot: { pose: "happy", lines: ["Say cheese!", "Did you get my good side?"], cool: 15000 },
        mute:       { pose: "surprised", lines: ["Shh… the sound is off"], cool: 30000 },
        timer:      { pose: "happy", lines: ["Time's up!"], cool: 5000 },
        unlock:     { pose: "wave", lines: ["Welcome back!", "Missed you!"], cool: 30000 },
        login:      { key: "unlock", pose: "wave", lines: ["Hi!", "Hello again!"], cool: 30000 },
        "break":    { pose: "wave", lines: ["You've been at it a while - time for a little break?", "Stretch time!", "Your eyes need a rest too"], cool: 600000 },
        late:       { pose: "sleepy", lines: ["It's late… time for bed?", "Yawn… still up?"], cool: 1800000 },
        game:       { pose: "happy", lines: ["GG!", "Good game?"], cool: 300000 },
        hot:        { pose: "hot", lines: ["It's getting hot in here!", "Your computer is melting…"], cool: 1200000 },
        disk:       { pose: "box", lines: ["Your disk is almost full!", "Where do I put all this?"], cool: 21600000 },
        updates:    { pose: "wave", lines: ["Updates are waiting - maybe update?"], cool: 21600000 }
    })
    property var lastReact: ({})
    property real lastShow: 0

    function pick(l) { return l[Math.floor(Math.random() * l.length)]; }

    // where she comes out this time + how (sometimes she zips out, sometimes she creeps, mostly a soft bounce)
    property string forceEdge: ""            // IPC peekat: try one edge
    function place() {
        if (forceEdge !== "") {
            edge = forceEdge; forceEdge = "";
            along = side ? 0.3 : (Math.random() < 0.5 ? 0.18 : 0.8); lean = along > 0.5;
        } else if (!chaos) {
            edge = Cfg.data.mascotEdge === "left" ? "left" : "right"; lean = false;
            along = typeof Cfg.data.mascotHeight === "number" ? Cfg.data.mascotHeight : 0.28;
        } else {
            const r = Math.random();
            if (r < 0.3)       { edge = "right"; along = 0.08 + Math.random() * 0.6; }
            else if (r < 0.54) { edge = "left"; along = 0.08 + Math.random() * 0.6; }
            else if (r < 0.84) { edge = "bottom"; along = Math.random() < 0.5 ? 0.04 + Math.random() * 0.2 : 0.76 + Math.random() * 0.2; }
            else               { edge = "top"; along = Math.random() < 0.5 ? 0.1 + Math.random() * 0.2 : 0.6 + Math.random() * 0.15; }
            lean = along > 0.5;
        }
        const e = Math.random();
        if (e < 0.18)      { outMs = 1500; outEase = Easing.InOutSine; depth = 0.52; }
        else if (e < 0.36) { outMs = 300; outEase = Easing.OutCubic; depth = 0.66; }
        else               { outMs = 650; outEase = Easing.OutBack; depth = 0.58 + Math.random() * 0.08; }
    }
    function show(p, line) {
        if (sitting && !sitAway && on && !fullscreen && !locked) {        // sitting on a window: she just says it from there
            pose = p; say = line || ""; if (say === "") pose = "sit"; sayT.restart(); lastShow = Date.now(); return true;
        }
        if (!on || fullscreen || locked || running || caught || flexing) return false;
        if (out < 0.02 && !win.visible) place();
        pose = p; say = line || ""; out = 1;
        hideT.interval = say !== "" ? 9000 : 7000; hideT.restart();
        settleT.restart(); lastShow = Date.now();
        return true;
    }
    function hide(now) {
        outMs = now ? 1 : 420; outEase = Easing.InBack; out = 0; say = ""; hideT.stop(); duck.stop();
    }
    function peek() {
        if (on && has("notes") && note.day !== today && hour >= 9 && !fullscreen && !locked && !caught && !running) {
            leaveNote(); show("wave", "I left you a note on the desktop"); return;
        }
        const p = rest === "idle" ? pick(["idle", "idle", "happy", "wave"]) : rest;
        show(p, Math.random() < 0.35 ? pick(late ? lateLines : idleLines) : "");
    }
    function react(kind, line) {
        const r = reactions[kind];
        if (!r || !reactOn.includes(r.key || kind)) return false;
        const now = Date.now();
        if (now - (lastReact[kind] || 0) < r.cool) return false;
        if (out > 0.5 && say !== "" && now - lastShow < 2500) return false;   // let the current line be read
        if (!show(r.pose, line || pick(r.lines))) return false;
        lastReact[kind] = now;
        return true;
    }
    // poke ladder: 1 = a line, 2-3 = pats, 4 = she pouts and leaves for a while
    property int clicks: 0
    Timer { id: clickReset; interval: 1600; onTriggered: ms.clicks = 0 }
    function poked() {
        clicks++; clickReset.restart(); duck.stop();
        if (clicks >= 4) {
            pose = "pout"; say = pick(poutLines); clicks = 0;
            hideT.interval = 1800; nextT.interval = 300000; nextT.restart();
        } else if (clicks >= 2) {
            pose = pick(["happy", "shy"]); say = pick(patLines); hideT.interval = 7000;
        } else {
            pose = late ? "sleepy" : pick(["happy", "wave", "idle"]); say = pick(late ? lateLines : idleLines); hideT.interval = 9000;
        }
        out = 1; hideT.restart(); settleT.restart(); lastShow = Date.now();
    }

    Timer { id: hideT; interval: 9000; onTriggered: ms.hide(false) }
    // surprise / shyness / a wave last a moment, then she relaxes (keeps talking)
    Timer { id: settleT; interval: 2400
            onTriggered: if (["surprised", "shy", "wave"].includes(ms.pose) && ms.out > 0.5) ms.pose = ms.rest }
    Timer { id: duck; interval: 650; onTriggered: if (ms.say === "") ms.hide(false) }
    Timer { id: stareT; interval: 4000; onTriggered: if (ms.out > 0.5) { ms.pose = "shy"; ms.say = ms.pick(ms.stareLines); hideT.restart(); settleT.restart(); } }

    // now and then; the first time shortly after login (a wave)
    property bool first: true
    // login choreography (Choreo.qml): she waves as the last widget settles
    Connections { target: Choreo; function onMomentChanged() { if (Choreo.moment === "" && Choreo.first && ms.first && ms.on) { ms.first = false; ms.react("login"); } } }
    Timer {
        id: nextT; running: ms.on; repeat: false; interval: 25000
        onTriggered: {
            if (ms.first) { ms.first = false; if (!ms.react("login")) ms.peek(); }
            else if (ms.chaos && Math.random() < 0.4) ms.romp();
            else if (ms.has("sit") && Math.random() < 0.3) ms.trySit();
            else ms.peek();
            interval = (ms.freq[0] + Math.random() * ms.freq[1]) * 1000; restart();
        }
    }

    // ── what she reacts to ──
    Connections {
        target: Desk.player
        function onIsPlayingChanged() {
            if (!Desk.player || !Desk.player.isPlaying) return;
            if (!ms.react("music") && ms.out > 0.5 && ms.pose === "idle") ms.pose = "sing";
        }
    }
    property int unreadWas: 0
    property real selfNote: 0
    Connections {
        target: Notifs
        function onUnreadChanged() {
            if (Notifs.unread > ms.unreadWas && !Notifs.silent && ms.ready && Date.now() - ms.selfNote > 4000) ms.react("notify");
            ms.unreadWas = Notifs.unread;
        }
    }
    property string wallWas: Cfg.data.wallpaper || ""
    Connections { target: Cfg; function onDataChanged() { const w = Cfg.data.wallpaper || ""; if (w !== ms.wallWas) { if (ms.wallWas !== "") ms.react("wallpaper"); ms.wallWas = w; } } }
    Connections {
        target: Timers
        function onRang(title) {
            ms.react("timer", !Timers.pomo ? "Time's up!" : Timers.pomoPhase === "focus" ? "Back to focus - you've got this" : "Break time! Stretch a little");
        }
    }
    PwObjectTracker { objects: [ Pipewire.defaultAudioSink ] }
    readonly property bool muted: !!(Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted)
    onMutedChanged: if (muted && ready) react("mute")
    onLockedChanged: if (locked) { hide(true); stopRomp(); if (!sitting) dropAll(); flexAbort(); } else if (ready) unlockT.restart()
    Timer { id: unlockT; interval: 1500; onTriggered: ms.react("unlock") }
    property real fsFrom: 0
    onFullscreenChanged: {
        if (fullscreen) { fsFrom = Date.now(); hide(true); stopRomp(); if (!sitting) dropAll(); flexAbort(); }
        else if (fsFrom > 0 && Date.now() - fsFrom > 180000) gameT.restart();   // back from a game / film
    }
    Timer { id: gameT; interval: 2500; onTriggered: ms.react("game") }
    // late night + long work without a pause (5 min idle = a pause)
    property string lateDay: ""
    property real workFrom: Date.now()
    property real breakAt: 0
    readonly property int breakMin: Cfg.data.mascotBreak || 90
    IdleMonitor { id: idle; enabled: ms.on; timeout: 300; respectInhibitors: true; onIsIdleChanged: if (!isIdle) ms.workFrom = Date.now() }
    Timer {
        interval: 60000; running: ms.on; repeat: true
        onTriggered: {
            const d = new Date(), now = d.getTime();
            ms.hour = d.getHours(); ms.month = d.getMonth(); ms.today = d.toDateString();
            if (ms.late && ms.lateDay !== d.toDateString() && ms.react("late")) ms.lateDay = d.toDateString();
            if (!idle.isIdle && now - ms.workFrom >= ms.breakMin * 60000 && now - ms.breakAt >= ms.breakMin * 60000 && ms.react("break")) ms.breakAt = now;
        }
    }

    IpcHandler {
        target: "mascot"
        function peek(): void { ms.peek(); }
        function react(event: string): void { ms.react(event); }
        function pose(name: string): void { ms.show(name, ({ sing: "♪ La-la-la…", sleepy: "Yawn… still up?", surprised: "You've got a message", wave: "Hi!", happy: "Say cheese!", pout: "Hey! Enough poking!", shy: "…What?" })[name] || ""); }
        function chaos(): void { ms.romp(); }
        function duo(): void { ms.romp(true); }
        function flex(): void { ms.flex(); }
        function flexstop(): void { ms.flexAbort(); }
        function flexfrom(sec: real): void {          // test: start the flex mid-way (earlier cues apply at once)
            ms.flex(); if (!ms.flexing) return; ms.pendingSeek = sec * 1000; ms.songStart = Date.now() - sec * 1000; ms.trySeek();
        }
        function flexinfo(): string { return "song " + ms.songT.toFixed(3) + " s, player " + (flexSnd.position / 1000).toFixed(3) + " s, cue " + ms.cue + "/" + ms.cues.length; }
        function sit(): void { if (!ms.trySit()) ms.peek(); }
        function perch(): void {             // test: as if you put her down on the newest window here
            const w = ms.ipcWins()[0]; if (!w || ms.grabSrc !== "") return;
            ms.hide(true); ms.dropAll(); ms.fx = w.x + w.w / 2 - ms.bw / 2; ms.fy = w.y - ms.boxH - 20; ms.sitOn(w, true);
        }
        function note(): void { ms.note = ({}); ms.leaveNote(); }
        function fling(vx: real, vy: real): void { ms.fling(vx, vy); }
        function peekat(edge: string): void { if (ms.out < 0.02) ms.forceEdge = edge; ms.peek(); }
        function hide(): void { ms.hide(false); }
    }

    // ── peeking ──
    PanelWindow {
        id: win
        visible: ms.on && (ms.out > 0.004 || ms.grabSrc === "peek")
        screen: Cfg.mainScreen
        // this window's top-left on the screen (a drag that starts here is reported here until the button is up)
        readonly property real wx: ms.edge === "right" ? sw - implicitWidth : ms.edge === "left" ? 0 : margins.left
        readonly property real wy: ms.edge === "top" ? 0 : sh - margins.bottom - implicitHeight
        readonly property real sw: screen ? screen.width : 1920
        readonly property real sh: screen ? screen.height : 1080
        anchors { right: ms.edge === "right"; left: ms.edge !== "right"; top: ms.edge === "top"; bottom: ms.edge !== "top" }
        margins {
            bottom: ms.side ? Math.round(win.sh * ms.along) : 0
            left: ms.side ? 0 : Math.round(Math.max(0, Math.min(win.sw - win.implicitWidth,
                      win.sw * ms.along - ms.bw / 2 - (ms.lean ? win.implicitWidth - ms.bw - 20 : 20))))
        }
        implicitWidth: Math.round(ms.bw + 260); implicitHeight: Math.round(ms.bh + 50)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "mascot"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: body }

        Item {
            id: body
            width: ms.bw; height: ms.bh
            opacity: ms.caught ? 0 : 1
            x: ms.edge === "right" ? parent.width - width * ms.depth * ms.out
             : ms.edge === "left" ? -width + width * ms.depth * ms.out
             : (ms.lean ? parent.width - width - 20 : 20)
            y: ms.edge === "top" ? -height + height * ms.depth * ms.out
             : ms.edge === "bottom" ? parent.height - height * ms.depth * ms.out
             : parent.height - height
            rotation: ms.edge === "right" ? -12 * ms.out : ms.edge === "left" ? 12 * ms.out
                    : ms.edge === "top" ? 180 + (ms.lean ? 10 : -10) : (ms.lean ? -8 : 8) * ms.out
            transformOrigin: ms.edge === "right" ? Item.BottomRight : ms.edge === "left" ? Item.BottomLeft : Item.Center
            MascotArt {
                id: art
                pose: ms.pose; talking: ms.say !== ""; active: win.visible && ms.out > 0.3
                beat: ms.beat; outfit: ms.outfit; particles: ms.particles
                flip: ms.edge === "left"; textRot: ms.edge === "top" ? 180 : 0
                custom: ms.custom
                transform: [ Scale { xScale: ms.size * (art.flip ? -1 : 1); yScale: ms.size }, Translate { x: art.flip ? ms.bw : 0 } ]
            }
            MouseArea {
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                property point at
                property bool dragged: false
                onEntered: { if (ms.say === "") { ms.pose = "shy"; duck.restart(); } else stareT.restart(); }
                onExited: { duck.stop(); stareT.stop(); if (ms.pose === "shy" && ms.say === "" && ms.out > 0.5) ms.pose = ms.rest; }
                onPressed: m => { at = Qt.point(m.x, m.y); dragged = false; duck.stop(); }
                onPositionChanged: m => {
                    if (!pressed) return;
                    const p = mapToItem(null, m.x, m.y), gx = p.x + win.wx, gy = p.y + win.wy;
                    if (ms.grabSrc === "peek") ms.grabMove(gx, gy);
                    else if (!dragged && Math.hypot(m.x - at.x, m.y - at.y) > 6 && ms.grabStart("peek", gx, gy, ms.bw / 2, ms.bh * 0.3)) dragged = true;
                }
                onReleased: if (ms.grabSrc === "peek") ms.grabEnd()
                onCanceled: if (ms.grabSrc === "peek") ms.grabEnd()
                onClicked: { if (dragged) return; stareT.stop(); ms.poked(); }
            }
        }

        Bubble {
            shown: ms.say !== "" && ms.out > 0.5 && !ms.caught
            text: ms.say
            x: ms.edge === "right" ? body.x - width + 6 : ms.edge === "left" ? body.x + body.width - 6
             : (ms.lean ? body.x - width + 14 : body.x + body.width - 14)
            y: ms.side ? 10 : ms.edge === "top" ? Math.max(4, ms.bh * ms.depth * 0.5 - height / 2)
             : Math.max(4, parent.height - ms.bh * ms.depth)
        }
    }

    // ── chaos: a run along the bottom edge ──
    property bool running: false
    property real runX: 0
    property bool runLeft: false
    property real runFrom: 0
    property real runStop: 0
    property real runTo: 0
    property var petals: []                  // [{x, born}] the trail she leaves (calling card)
    property real lastPetal: -9999
    property real clock: 0
    function romp(duo) {
        if (!on || fullscreen || locked || running || caught || flexing) return;
        friend = duo === true || (has("friend") && Math.random() < 0.45);
        friendColor = pick(["#b9a4ee", "#9fdcc0", "#f5c08a"]); friendSay = ""; friendPose = "run";
        if (out > 0.02) hide(true);          // peeking right now: she ducks and runs
        const sw = Cfg.mainScreen ? Cfg.mainScreen.width : 1920, r = Math.random();
        runLeft = Math.random() < 0.5;
        const extra = friend ? bw * 1.1 : 0;          // the friend runs behind her
        runFrom = runLeft ? sw + 10 + extra : -bw - 10 - extra;
        runTo = runLeft ? -bw - 10 - extra : sw + 10 + extra;
        runStop = (Math.random() < 0.5 ? 0.1 + 0.18 * r : 0.72 + 0.18 * r) * sw - bw / 2;   // never above the dock
        runX = runFrom; petals = []; lastPetal = -9999; clock = Date.now();
        running = true; runA.restart();
    }
    function stopRomp() { if (!running) return; runA.stop(); running = false; say = ""; pose = rest; friendSay = ""; friendT.stop(); }
    function endRomp() { running = false; say = ""; pose = rest; friendSay = ""; }
    // ── the friend (joins some runs; they chat at the stop) ──
    property bool friend: false
    property color friendColor: "#b9a4ee"
    property string friendSay: ""
    property string friendPose: "run"
    property string duetNext: ""
    readonly property var duets: [["Did you see that window?", "Shh, they're watching!"], ["Race you!", "No fair, you started first!"],
        ["Is it lunch yet?", "It's always lunch somewhere"], ["Look, a cursor!", "Don't make eye contact"], ["Nice desktop, huh?", "Could use more petals"]]
    Timer { id: friendT; interval: 1700; onTriggered: { ms.friendSay = ms.duetNext; ms.friendPose = "happy"; ms.pose = "happy"; } }
    function stopTalk() {
        if (friend) { const d = pick(duets); say = d[0]; duetNext = d[1]; pose = "wave"; friendPose = "idle"; friendT.restart(); }
        else { pose = pick(["wave", "happy"]); say = pick(cardLines); }
    }
    onRunXChanged: {
        if (!running || pose !== "run" || Math.abs(runX - lastPetal) < 150) return;
        lastPetal = runX;
        petals = petals.concat([{ x: runX + bw / 2, born: Date.now() }]).slice(-8);
    }
    Timer { interval: 60; repeat: true; running: ms.running; onTriggered: ms.clock = Date.now() }
    SequentialAnimation {
        id: runA
        ScriptAction { script: { ms.pose = "run"; ms.say = ""; } }
        NumberAnimation { target: ms; property: "runX"; from: ms.runFrom; to: ms.runStop; duration: Math.abs(ms.runStop - ms.runFrom) / 0.55 }
        ScriptAction { script: ms.stopTalk() }
        PauseAnimation { duration: ms.friend ? 4400 : 2600 }
        ScriptAction { script: { ms.pose = "run"; ms.say = ""; ms.friendSay = ""; ms.friendPose = "run"; } }
        NumberAnimation { target: ms; property: "runX"; from: ms.runStop; to: ms.runTo; duration: Math.abs(ms.runTo - ms.runStop) / 0.6 }
        ScriptAction { script: ms.endRomp() }
    }

    PanelWindow {
        id: runWin
        visible: ms.on && (ms.running || ms.grabSrc === "run")
        screen: Cfg.mainScreen
        anchors { left: true; right: true; bottom: true }
        implicitHeight: Math.round(ms.bh + 140)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "mascot-run"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: runner }
        // a hop over the dock in the middle
        readonly property real lift: {
            const d = Math.abs(ms.runX + ms.bw / 2 - width / 2), r = 330;
            return d < r ? 100 * (1 - d * d / (r * r)) : 0;
        }

        Repeater {
            model: 8
            Rectangle {
                required property int index
                readonly property var p: ms.petals[index]
                readonly property real age: p ? Math.min(1, (ms.clock - p.born) / 2600) : 1
                visible: !!p && age < 1
                x: p ? p.x + Math.sin(index * 1.7) * 18 : 0; y: runWin.height - 18 - age * 6 + (index % 3) * 4
                width: 9; height: 13; radius: 6; rotation: index * 47 + age * 60
                color: Cfg.accent; opacity: (1 - age) * 0.9
            }
        }
        Item {
            id: buddy
            visible: ms.friend && ms.running
            readonly property real fs: 0.85
            width: ms.bw * fs; height: ms.bh * fs
            x: ms.runX + (ms.runLeft ? 1 : -1) * ms.bw * 1.05 + (ms.bw - width) / 2
            readonly property real lift: { const d = Math.abs(x + width / 2 - runWin.width / 2), r = 330; return d < r ? 100 * (1 - d * d / (r * r)) : 0; }
            y: parent.height - height * 136 / 150 - lift
            rotation: ms.friendPose === "run" ? (ms.runLeft ? -8 : 8) : 0
            transformOrigin: Item.Bottom
            MascotArt {
                id: buddyArt
                pose: ms.friendPose; talking: ms.friendSay !== ""; active: buddy.visible
                flip: ms.runLeft; tint: ms.friendColor; beat: ms.beat
                transform: [ Scale { xScale: ms.size * buddy.fs * (buddyArt.flip ? -1 : 1); yScale: ms.size * buddy.fs }, Translate { x: buddyArt.flip ? buddy.width : 0 } ]
            }
        }
        Bubble {
            shown: ms.friendSay !== "" && !ms.caught && ms.running
            text: ms.friendSay
            x: Math.max(4, Math.min(parent.width - width - 4, buddy.x + buddy.width / 2 - width / 2))
            y: Math.max(4, buddy.y - height + 8)
        }
        Item {
            id: runner
            width: ms.bw; height: ms.bh
            opacity: ms.caught ? 0 : 1
            x: ms.runX; y: parent.height - ms.bh * 136 / 150 - runWin.lift
            rotation: ms.pose === "run" ? (ms.runLeft ? -8 : 8) : 0
            transformOrigin: Item.Bottom
            MascotArt {
                id: runArt
                pose: ms.pose; talking: ms.say !== ""; active: runWin.visible
                flip: ms.pose === "run" || !ms.friend ? ms.runLeft : !ms.runLeft; custom: ms.custom
                beat: ms.beat; outfit: ms.outfit === "umbrella" ? "" : ms.outfit
                transform: [ Scale { xScale: ms.size * (runArt.flip ? -1 : 1); yScale: ms.size }, Translate { x: runArt.flip ? ms.bw : 0 } ]
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                property point at
                property bool dragged: false
                onPressed: m => { at = Qt.point(m.x, m.y); dragged = false; }
                onPositionChanged: m => {
                    const p = mapToItem(null, m.x, m.y), gx = p.x, gy = p.y + ms.sh - runWin.height;
                    if (ms.grabSrc === "run") ms.grabMove(gx, gy);
                    else if (!dragged && Math.hypot(m.x - at.x, m.y - at.y) > 6 && ms.grabStart("run", gx, gy, ms.bw / 2, ms.bh * 0.3)) dragged = true;
                }
                onReleased: if (ms.grabSrc === "run") ms.grabEnd()
                onCanceled: if (ms.grabSrc === "run") ms.grabEnd()
                onClicked: if (!dragged) ms.say = ms.pick(ms.runLines)
            }
        }
        Bubble {
            shown: ms.say !== "" && !ms.caught
            text: ms.say
            x: Math.max(4, Math.min(parent.width - width - 4, runner.x + runner.width / 2 - width / 2))
            y: Math.max(4, runner.y - height + 8)
        }
    }

    // ── catch & throw ──
    readonly property bool throwOn: Cfg.data.mascotThrow !== false
    property string grabSrc: ""              // "" | peek | run | fly - which window holds the mouse right now
    property bool flying: false              // she's in the fly window: falling, bouncing, sitting, walking off
    property bool resting: false             // landed (physics off)
    readonly property bool caught: grabSrc !== "" || flying
    property real fx: 0                      // her top-left on the main screen
    property real fy: 0
    property real vx: 0                      // px/s
    property real vy: 0
    property real ang: 0
    property real shake: 0
    property real squash: 0                  // impact squish, 1 → 0
    property bool squashSide: false          // squished sideways (hit a wall)
    property var trail: []                   // [{t, x, y}] the last ~100 ms of the drag
    property real grabDX: 0
    property real grabDY: 0
    property real lastHit: 0
    property real restFor: 0
    property var tosses: []
    property bool sulky: false
    property bool walkLeft: false
    readonly property real sw: Cfg.mainScreen ? Cfg.mainScreen.width : 1920
    readonly property real sh: Cfg.mainScreen ? Cfg.mainScreen.height : 1080
    readonly property real boxH: bh * 124 / 150      // the drawing ends at the bottom of the head
    readonly property var grabLines: ["Hey! Let go!", "Where are you taking me?"]
    readonly property var flyLines: ["Aaaaa!", "Whoosh!"]
    readonly property var hitLines: ["Ouch!", "That hurts…"]
    readonly property var landLines: ["My head is spinning…", "Again!"]
    readonly property var sulkLines: ["That's it, I'm offended", "No more throwing!"]

    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
    // gx/gy: the cursor on the screen; ox/oy: where on her she is held
    function grabStart(src, gx, gy, ox, oy) {
        if (!throwOn || fullscreen || locked || flexing) return false;
        if (running) { runA.stop(); running = false; }
        walkA.stop(); leaveT.stop(); hideT.stop(); duck.stop(); settleT.stop(); stareT.stop(); hitT.stop(); sitT.stop(); sitInA.stop(); sitting = false; sitManual = false; sitAway = false; selfJump = false;
        Hyprland.refreshToplevels(); refreshedAt = Date.now(); perch = null;
        grabSrc = src; flying = false; resting = false;
        grabDX = ox; grabDY = oy; vx = 0; vy = 0; ang = 0; shake = 0;
        trail = [];
        grabMove(gx, gy);
        pose = "held"; say = pick(grabLines);
        return true;
    }
    function grabMove(gx, gy) {
        fx = clamp(gx - grabDX, -bw * 0.2, sw - bw * 0.8);
        fy = clamp(gy - grabDY, -boxH * 0.2, sh - boxH * 0.6);
        const now = Date.now();
        grabMoved = now;
        trail = trail.concat([{ t: now, x: gx, y: gy }]).filter(p => now - p.t <= 100);
        ang = trail.length > 1 ? clamp((gx - trail[0].x) * 0.2, -28, 28) : 0;     // she swings with the motion
        if (now - refreshedAt > 400) { refreshedAt = now; Hyprland.refreshToplevels(); }
        perch = findPerch();                 // over a window's top edge: she looks forward to sitting there
        if (pose === "held" || pose === "happy") pose = perch ? "happy" : "held";
    }
    // safety: if the button-up never arrives (lost grab), she slips out of the hand after a while
    property real grabMoved: 0
    Timer { interval: 1000; repeat: true; running: ms.grabSrc !== ""
            onTriggered: if (Date.now() - ms.grabMoved > 8000) ms.grabEnd() }
    function grabEnd() {
        const now = Date.now(), tr = trail.filter(p => now - p.t <= 80);
        let x = 0, y = 0;
        if (tr.length >= 2) {
            const a = tr[0], b = tr[tr.length - 1], dt = Math.max(16, b.t - a.t) / 1000;
            x = (b.x - a.x) / dt; y = (b.y - a.y) / dt;
        }
        const src = grabSrc;
        grabSrc = "";
        if (src === "peek") { outMs = 1; out = 0; }
        if (perch && Math.hypot(x, y) < 650) { sitOn(perch, true); perch = null; return; }   // put down gently on a window
        perch = null;
        launch(x, y);
    }
    function launch(x, y) {
        vx = clamp(x, -4500, 4500); vy = clamp(y, -4500, 4500);
        restFor = 0; resting = false; flying = true; newFlight();
        if (Math.hypot(vx, vy) > 700) {
            const now = Date.now();
            tosses = tosses.filter(t => now - t < 90000).concat([now]);
            sulky = tosses.length >= 4;
            pose = "fly"; say = pick(flyLines);
        } else { pose = "held"; say = ""; }
    }
    function fling(x, y) {                   // IPC: throw her from where she is (or from the right side)
        if (!on || !throwOn || fullscreen || locked || grabSrc !== "") return;
        if (!flying) {
            if (running) { fx = runX; fy = sh - bh * 136 / 150 - runWin.lift; runA.stop(); running = false; }
            else if (out > 0.3) { fx = clamp(win.wx + body.x, 0, sw - bw); fy = clamp(win.wy + body.y, 0, sh - boxH); }
            else { fx = sw - bw - 60; fy = sh * 0.35; }
            hide(true);
        }
        walkA.stop(); leaveT.stop(); sitT.stop(); sitting = false; selfJump = false;
        launch(x, y);
    }
    // umbrella: a fall that hasn't touched the screen's sides or top glides down under an umbrella
    property bool touched: false
    property bool gliding: false
    property real airT: 0
    readonly property var glideLines: ["Wheee~", "Gently does it", "Mary Poppins mode"]
    readonly property var softLines: ["Soft landing!", "Ta-da!"]
    function newFlight() { touched = false; gliding = false; airT = 0; }
    function step(dt) {
        dt = Math.min(dt, 0.033);
        const g = 2600, e = 0.55, maxX = sw - bw, maxY = sh - boxH;
        airT += dt;
        if (!gliding && !touched && airT > 0.22 && vy > 120) {          // falling, clean so far: open the umbrella
            gliding = true; pose = "glide"; say = pick(glideLines); hitT.stop();
        }
        if (gliding) {
            vy += (170 - vy) * (1 - Math.exp(-dt * 4));                 // slows to a gentle 170 px/s
            vx *= Math.exp(-dt * 1.6);                                  // air drag
        } else vy += g * dt;
        fx += vx * dt; fy += vy * dt;
        let hit = 0, side = false;
        if (fx < 0) { fx = 0; hit = Math.abs(vx); side = true; vx = Math.abs(vx) * e; touched = true; }
        else if (fx > maxX) { fx = maxX; hit = Math.abs(vx); side = true; vx = -Math.abs(vx) * e; touched = true; }
        if (fy < 0) { fy = 0; if (Math.abs(vy) > hit) { hit = Math.abs(vy); side = false; } vy = Math.abs(vy) * e; touched = true; }
        if (gliding && touched) { gliding = false; pose = "fly"; }     // bumped into the edge: umbrella closes
        const floor = fy >= maxY;
        if (floor) {
            fy = maxY;
            if (vy > 260) { if (vy > hit) { hit = vy; side = false; } vy = -vy * e; }
            else vy = 0;
            vx *= Math.max(0, 1 - 5 * dt);   // friction on the floor
        }
        if (hit > 450) bump(hit, side);
        if (floor && vy === 0) ang *= Math.max(0, 1 - 10 * dt);       // settles upright
        else if (gliding) ang += (Math.sin(airT * 2.4) * 7 + clamp(vx * 0.02, -12, 12) - ang) * (1 - Math.exp(-dt * 5));   // sways under it
        else ang = clamp(ang + vx * dt * 0.12, -40, 40);              // a little spin from the speed
        if (floor && vy === 0 && Math.abs(vx) < 25) { restFor += dt; if (restFor > 0.25) landed(); }
        else restFor = 0;
    }
    function bump(speed, side) {
        squashSide = side; squash = Math.min(1, speed / 2200); squashA.restart();
        const now = Date.now();
        if (speed > 1100 && now - lastHit > 1200) { lastHit = now; pose = "shy"; say = pick(hitLines); hitT.restart(); }
    }
    NumberAnimation { id: squashA; target: ms; property: "squash"; to: 0; duration: 420; easing.type: Easing.OutElastic }
    Timer { id: hitT; interval: 500; onTriggered: if (ms.flying && !ms.resting && ms.pose === "shy") ms.pose = ms.gliding ? "glide" : "fly" }
    function landed() {
        resting = true; vx = 0; vy = 0; ang = 0;
        if (selfJump) { selfJump = false; gliding = false; pose = "happy"; say = ""; leaveT.interval = 900; leaveT.restart(); return; }
        if (gliding && !sulky) { gliding = false; pose = "happy"; say = pick(softLines); leaveT.interval = 1800; leaveT.restart(); return; }
        gliding = false;
        pose = sulky ? "pout" : "dizzy"; say = pick(sulky ? sulkLines : landLines);
        shakeA.restart();                    // shakes herself off
        leaveT.interval = sulky ? 2000 : 2800; leaveT.restart();
    }
    SequentialAnimation {
        id: shakeA
        PauseAnimation { duration: 250 }
        NumberAnimation { target: ms; property: "shake"; to: 10; duration: 70 }
        NumberAnimation { target: ms; property: "shake"; to: -9; duration: 90 }
        NumberAnimation { target: ms; property: "shake"; to: 6; duration: 80 }
        NumberAnimation { target: ms; property: "shake"; to: -3; duration: 70 }
        NumberAnimation { target: ms; property: "shake"; to: 0; duration: 60 }
    }
    Timer { id: leaveT; onTriggered: ms.walkOff() }
    function walkOff() {                     // back behind her edge (in chaos mode: the nearest side)
        const right = chaos || sulky ? fx + bw / 2 > sw / 2 : Cfg.data.mascotEdge !== "left";
        walkLeft = !right;
        pose = "run"; say = "";
        walkA.to = right ? sw + 10 : -bw - 10;
        walkA.duration = Math.abs(walkA.to - fx) / 0.35;
        walkA.restart();
    }
    NumberAnimation { id: walkA; target: ms; property: "fx"; onFinished: ms.flyDone() }
    function flyDone() {
        flying = false; resting = false; say = ""; pose = rest; ang = 0;
        if (sulky) { sulky = false; tosses = []; nextT.interval = 300000; nextT.restart(); }
    }
    function dropAll() {
        if (!caught) return;
        walkA.stop(); leaveT.stop(); squashA.stop(); shakeA.stop(); sitT.stop(); sitInA.stop(); sitting = false; sitManual = false; sitAway = false; perch = null;
        grabSrc = ""; flying = false; resting = false; say = ""; pose = rest; ang = 0; shake = 0; squash = 0;
    }
    FrameAnimation { running: ms.flying && !ms.resting && ms.grabSrc === ""; onTriggered: ms.step(frameTime) }

    // the whole main screen while she's held or flying - input only on her
    PanelWindow {
        id: flyWin
        visible: ms.on && ms.caught && !(ms.sitting && (ms.sitAway || ms.fullscreen || ms.locked))
        screen: Cfg.mainScreen
        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "mascot-fly"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: flyer }

        Item {
            id: flyer
            x: ms.fx; y: ms.fy; width: ms.bw; height: ms.bh
            rotation: ms.ang + ms.shake
            transformOrigin: ms.sitting ? Item.Bottom : Item.Center
            transform: Scale {
                origin.x: ms.bw / 2; origin.y: ms.boxH
                xScale: 1 + (ms.squashSide ? -0.24 : 0.24) * ms.squash
                yScale: 1 + (ms.squashSide ? 0.24 : -0.24) * ms.squash
            }
            MascotArt {
                id: flyArt
                pose: ms.pose; talking: ms.say !== ""; active: flyWin.visible
                beat: ms.beat; outfit: ms.outfit
                flip: ms.pose === "run" ? ms.walkLeft : ms.vx < -40
                custom: ms.custom
                transform: [ Scale { xScale: ms.size * (flyArt.flip ? -1 : 1); yScale: ms.size }, Translate { x: flyArt.flip ? ms.bw : 0 } ]
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: ms.grabSrc === "fly" ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property point at
                property bool dragged: false
                onPressed: m => {           // mid-air: caught at once; sitting / landed: only once it's dragged
                    at = Qt.point(m.x, m.y); dragged = false;
                    if (ms.flying && !ms.resting) { const p = mapToItem(null, m.x, m.y); dragged = ms.grabStart("fly", p.x, p.y, p.x - ms.fx, p.y - ms.fy); }
                }
                onPositionChanged: m => {
                    const p = mapToItem(null, m.x, m.y);
                    if (ms.grabSrc === "fly") ms.grabMove(p.x, p.y);
                    else if (pressed && !dragged && Math.hypot(m.x - at.x, m.y - at.y) > 6) dragged = ms.grabStart("fly", p.x, p.y, p.x - ms.fx, p.y - ms.fy);
                }
                onClicked: if (!dragged && ms.sitting) { ms.say = ms.pick(ms.sitLines); sayT.restart(); }
                onReleased: if (ms.grabSrc === "fly") ms.grabEnd()
                onCanceled: if (ms.grabSrc === "fly") ms.grabEnd()
            }
        }
        Bubble {
            shown: ms.say !== ""
            text: ms.say
            x: ms.clamp(ms.fx + ms.bw / 2 - width / 2, 4, parent.width - width - 4)
            y: ms.fy > height + 12 ? ms.fy - height - 4 : ms.fy + ms.boxH + 8
        }
    }

    // ── dance: bounce to the bass while music plays and she's on screen (cava runs only then) ──
    readonly property bool dancing: on && has("dance") && !!Desk.player && Desk.player.isPlaying && (win.visible || runWin.visible || flyWin.visible)
    property bool vizHeld: false
    onDancingChanged: {
        if (dancing && !vizHeld) { Desk.vizUsers += 1; vizHeld = true; }
        else if (!dancing && vizHeld) { Desk.vizUsers = Math.max(0, Desk.vizUsers - 1); vizHeld = false; }
    }
    readonly property real beat: {
        const b = Desk.bars;
        if (!dancing || !b || !b.length) return 0;
        const n = Math.max(1, Math.round(b.length / 8));
        let t = 0; for (let i = 0; i < n; i++) t += b[i];
        return Math.min(1, t / n);
    }

    // ── weather & season ──
    readonly property var wcur: Desk.weather && Desk.weather.current ? Desk.weather.current : null
    readonly property int wcode: wcur ? wcur.weather_code : -1
    readonly property real wtemp: wcur ? wcur.temperature_2m : 10
    readonly property bool rainy: (wcode >= 51 && wcode <= 67) || (wcode >= 80 && wcode <= 82) || wcode >= 95
    readonly property bool snowy: (wcode >= 71 && wcode <= 77) || wcode === 85 || wcode === 86
    property int month: new Date().getMonth()
    readonly property string outfit: !has("outfit") ? "" : rainy ? "umbrella" : (snowy || wtemp <= 2) ? "scarf"
        : (wcode >= 0 && wcode <= 1 && wtemp >= 22 && wcur && wcur.is_day) ? "shades" : ""
    readonly property string particles: !has("outfit") ? "" : rainy ? "rain" : snowy ? "snow"
        : (month >= 2 && month <= 4) ? "petals" : (month >= 8 && month <= 10) ? "leaves" : (month === 11 || month <= 1) ? "snow" : ""

    // ── sitting on a window's top edge ──
    // She sits on one by herself now and then (hops off after 20-40 s), or you drop her there: carry her to a
    // window's top edge and let go gently - she stays until you pick her up. Moving the window carries her along
    // (followed ~30×/s while it moves, 4×/s otherwise, via Hyprland.refreshToplevels - no processes); on another
    // workspace / minimized she waits there, hidden; closing the window drops her.
    property bool sitting: false
    property bool sitManual: false
    property bool sitAway: false
    property bool selfJump: false
    property string sitAddr: ""
    property var sitGeo: [0, 0, 0, 0]
    property real sitOff: 0                  // her x from the window's left edge
    property real sitFast: 0                 // follow closely until (ms): the window is moving
    property real sitTX: 0                   // where she should be on the window; she glides there (no jumps)
    property real sitTY: 0
    property var perch: null                 // while held: the window edge under her
    property real refreshedAt: 0
    readonly property var sitLines: ["Nice view from up here", "Mind if I sit here?", "Comfy!"]
    readonly property var perchLines: ["Comfy!", "Thanks for the lift!", "I'll wait here"]
    readonly property var fallLines: ["Whoa!", "Hey, I was sitting there!"]
    Process { id: sitFind; command: ["hyprctl", "-j", "clients"]; stdout: StdioCollector { onStreamFinished: ms.sitPick(this.text) } }
    Timer { id: sitTrack; repeat: true; running: ms.sitting; interval: 250; onTriggered: { ms.sitFollow(); Hyprland.refreshToplevels(); } }
    Timer { id: sitT; onTriggered: ms.hopOff() }
    Timer { id: sayT; interval: 4500; onTriggered: if (ms.sitting) { ms.say = ""; ms.pose = "sit"; } }
    NumberAnimation { id: sitInA; target: ms; property: "fy"; duration: 600; easing.type: Easing.OutBounce }
    function norm(a) { return String(a).replace(/^0x/, "").toLowerCase(); }
    function clientsOk(text) { try { return JSON.parse(text); } catch (e) { return null; } }
    // windows on this workspace of the main monitor, in its coordinates (from the last refreshToplevels)
    function ipcWins() {
        const ws = hmon && hmon.activeWorkspace ? hmon.activeWorkspace.id : -1;
        const sx = Cfg.mainScreen ? Cfg.mainScreen.x : 0, sy = Cfg.mainScreen ? Cfg.mainScreen.y : 0;
        return Hyprland.toplevels.values.map(t => ({ t: t, o: t.lastIpcObject || {} }))
            .filter(k => k.o.at && k.o.size && !k.o.hidden && k.o.workspace && k.o.workspace.id === ws && !k.o.fullscreen)
            .map(k => ({ addr: norm(k.t.address), x: k.o.at[0] - sx, y: k.o.at[1] - sy, w: k.o.size[0], h: k.o.size[1] }))
            .filter(w => w.x + w.w > 0 && w.x < sw && w.y >= 0 && w.y < sh);
    }
    function findPerch() {                   // a top edge right under her (center over the window, ±50 px)
        const cx = fx + bw / 2, by = fy + boxH;
        let best = null;
        for (const w of ipcWins()) {
            const d = Math.abs(by - w.y);
            if (cx > w.x + 16 && cx < w.x + w.w - 16 && w.w >= bw * 1.3 && d < 50 && (!best || d < best.d)) best = Object.assign({ d: d }, w);
        }
        return best;
    }
    function sitOn(w, manual) {
        sitAddr = w.addr; sitGeo = [w.x, w.y, w.w, w.h];
        sitOff = clamp(fx - w.x, -bw * 0.3, w.w - bw * 0.7);
        fx = w.x + sitOff;
        vx = 0; vy = 0; ang = 0; shake = 0; squash = 0;
        flying = true; resting = true; sitting = true; sitManual = manual; sitAway = false; selfJump = false;
        pose = "sit"; say = manual ? pick(perchLines) : (Math.random() < 0.6 ? pick(sitLines) : "");
        if (say !== "") sayT.restart();
        sitInA.stop();
        sitTX = fx; sitTY = w.y - boxH + 8;
        sitInA.from = manual ? fy : w.y - boxH - 70; sitInA.to = sitTY; sitInA.duration = manual ? 380 : 600;
        sitInA.restart();
        if (manual) sitT.stop(); else { sitT.interval = 20000 + Math.random() * 20000; sitT.restart(); }
        sitTrack.interval = 100;
    }
    function trySit() {
        if (!on || fullscreen || locked || running || caught || out > 0.02 || sitFind.running) return false;
        sitFind.running = true; return true;
    }
    function sitPick(text) {
        const ws = hmon && hmon.activeWorkspace ? hmon.activeWorkspace.id : -1;
        const sx = Cfg.mainScreen ? Cfg.mainScreen.x : 0, sy = Cfg.mainScreen ? Cfg.mainScreen.y : 0;
        const cl = (clientsOk(text) || []).filter(c => c.mapped && !c.hidden && c.workspace && c.workspace.id === ws && !c.fullscreen
            && c.size[0] >= bw * 2 && c.at[1] - sy >= boxH * 0.8 && c.at[0] - sx >= 0 && c.at[0] - sx + c.size[0] <= sw)
            .sort((a, b) => a.focusHistoryID - b.focusHistoryID);
        if (caught || running || out > 0.02 || fullscreen || locked) return;
        if (!cl.length) { peek(); return; }
        const c = cl[0], w = { addr: norm(c.address), x: c.at[0] - sx, y: c.at[1] - sy, w: c.size[0], h: c.size[1] };
        fx = w.x + 30 + Math.random() * (w.w - bw - 60);
        sitOn(w, false);
    }
    function sitFollow() {
        if (!sitting) return;
        const t = Hyprland.toplevels.values.find(k => norm(k.address) === sitAddr);
        if (!t) { sitAway = false; fallOff(); return; }               // the window is gone
        const o = t.lastIpcObject || {};
        if (!o.at || !o.size) return;
        const ws = hmon && hmon.activeWorkspace ? hmon.activeWorkspace.id : -1;
        const sx = Cfg.mainScreen ? Cfg.mainScreen.x : 0, sy = Cfg.mainScreen ? Cfg.mainScreen.y : 0;
        const x = o.at[0] - sx, y = o.at[1] - sy, w = o.size[0];
        const here = !o.hidden && !!o.workspace && o.workspace.id === ws && !o.fullscreen && x + w > 0 && x < sw && y > -boxH && y < sh;
        sitAway = !here;
        if (!here) return;
        if (Math.abs(x - sitGeo[0]) > 0.5 || Math.abs(y - sitGeo[1]) > 0.5 || Math.abs(w - sitGeo[2]) > 0.5) {
            if (sitInA.running) { sitInA.stop(); fy = sitTY; }
            sitGeo = [x, y, w, o.size[1]];
            sitOff = clamp(sitOff, -bw * 0.3, w - bw * 0.7);
            sitTX = x + sitOff; sitTY = y - boxH + 8;
            sitFast = Date.now() + 1500;
        }
        sitTrack.interval = Date.now() < sitFast ? 33 : 100;
    }
    // glide after the window (eases in, leans back a little while it's carried)
    FrameAnimation {
        running: ms.sitting && !ms.sitAway && !sitInA.running && (Math.abs(ms.fx - ms.sitTX) > 0.3 || Math.abs(ms.fy - ms.sitTY) > 0.3 || Math.abs(ms.ang) > 0.2)
        onTriggered: {
            const k = 1 - Math.exp(-Math.min(frameTime, 0.05) * 14);
            ms.fx += (ms.sitTX - ms.fx) * k; ms.fy += (ms.sitTY - ms.fy) * k;
            ms.ang = ms.clamp((ms.fx - ms.sitTX) * 0.25, -14, 14);
            if (Math.abs(ms.fx - ms.sitTX) <= 0.3 && Math.abs(ms.fy - ms.sitTY) <= 0.3) { ms.fx = ms.sitTX; ms.fy = ms.sitTY; ms.ang = 0; }
        }
    }
    function fallOff() {
        sitting = false; sitManual = false; sitT.stop(); sitInA.stop(); sayT.stop(); selfJump = false;
        resting = false; restFor = 0; vx = (Math.random() - 0.5) * 300; vy = -250; newFlight();
        pose = "fly"; say = pick(fallLines);
    }
    function hopOff() {
        if (!sitting) return;
        if (sitAway) { sitting = false; sitAway = false; flyDone(); return; }    // left on another workspace: just go
        sitting = false; sitInA.stop(); sayT.stop(); selfJump = true;
        resting = false; restFor = 0; vx = (fx + bw / 2 > sw / 2 ? 1 : -1) * 520; vy = -950; newFlight();
        pose = "fly"; say = pick(["Wheee!", "Bye!"]);
    }

    // ── a sticky note on the desktop, once a day ──
    property var note: ({})                  // { day, text, x, y, rot, done }
    property string today: new Date().toDateString()
    readonly property var noteLines: ["You're doing great today", "Drink some water", "Rest your eyes for a minute", "Proud of you",
        "Today is a good day", "Have you eaten?", "Stretch your back", "I believe in you"]
    FileView {
        id: noteFile; printErrors: false; path: Quickshell.env("HOME") + "/.cache/sakura/mascot-note.json"
        onLoaded: { try { ms.note = JSON.parse(text()); } catch (e) { ms.note = ({}); } }
    }
    // a free spot: away from the desktop widgets (roughly 380×230 each) and the windows on this workspace
    Process { id: noteP; command: ["hyprctl", "-j", "clients"]; stdout: StdioCollector { onStreamFinished: ms.placeNote(this.text) } }
    function leaveNote() { noteP.running = true; }
    function placeNote(text) {
        const wsId = hmon && hmon.activeWorkspace ? hmon.activeWorkspace.id : -1;
        const sx = Cfg.mainScreen ? Cfg.mainScreen.x : 0, sy = Cfg.mainScreen ? Cfg.mainScreen.y : 0;
        const rects = (Cfg.data.widgets || []).filter(w => w.on !== false && typeof w.x === "number" && Cfg.onMain(w))
            .map(w => [w.x, w.y, 380 * (w.scale || 1), 230 * (w.scale || 1)])
            .concat((clientsOk(text) || []).filter(c => c.mapped && !c.hidden && c.workspace && c.workspace.id === wsId)
            .map(c => [c.at[0] - sx, c.at[1] - sy, c.size[0], c.size[1]]));
        const free = (x, y) => !rects.some(r => x + 210 > r[0] && x < r[0] + r[2] && y + 170 > r[1] && y < r[1] + r[3]);
        let pos = null;
        for (let i = 0; i < 120 && !pos; i++) {
            const x = 30 + Math.random() * (sw - 270), y = 80 + Math.random() * (sh - 320);
            if (free(x, y)) pos = [x, y];
        }
        if (!pos) pos = Math.random() < 0.5 ? [60, sh * 0.45] : [sw - 280, sh * 0.45];
        note = { day: today, text: pick(noteLines), x: pos[0] / sw, y: pos[1] / sh, rot: (Math.random() - 0.5) * 9, done: false };
        noteFile.setText(JSON.stringify(note));
    }
    function noteDone() { note = Object.assign({}, note, { done: true }); noteFile.setText(JSON.stringify(note)); }
    PanelWindow {
        id: noteWin
        visible: ms.on && ms.has("notes") && ms.note.day === ms.today && ms.note.done === false
        screen: Cfg.mainScreen
        anchors { left: true; top: true }
        margins { left: Math.round(ms.sw * (ms.note.x || 0.1)); top: Math.round(ms.sh * (ms.note.y || 0.3)) }
        implicitWidth: 210; implicitHeight: 170
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "mascot-note"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: paper }
        Rectangle {
            id: paper
            x: 18; y: 22; width: 174; height: 126; radius: 6
            rotation: ms.note.rot || 0
            color: "#fff3f7"; border.width: 1; border.color: Qt.darker(Cfg.accent, 1.15)
            Rectangle { x: 62; y: -9; width: 50; height: 18; rotation: -4; color: Cfg.acc(0.55) }
            Text {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 16; bottomMargin: 26 }
                text: Cfg.tr(ms.note.text || ""); wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                font.family: Cfg.fontUi; font.pixelSize: 16; font.weight: Font.DemiBold; color: "#3a2a38"
            }
            Row {               // signed: - and a tiny her (static: no animations on a note that stays all day)
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 8; bottomMargin: 5 }
                spacing: 3
                Text { anchors.verticalCenter: parent.verticalCenter; text: "-"; font.pixelSize: 13; font.weight: Font.Bold; color: Qt.darker(Cfg.accent, 1.3) }
                Item {
                    width: 22; height: 26
                    MascotArt { pose: "happy"; active: false; transform: Scale { xScale: 0.19; yScale: 0.19 } }
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: noteGone.start() }
        }
        SequentialAnimation {
            id: noteGone
            ParallelAnimation {
                NumberAnimation { target: paper; property: "scale"; to: 0; duration: 280; easing.type: Easing.InBack }
                NumberAnimation { target: paper; property: "rotation"; to: (ms.note.rot || 0) + 25; duration: 280 }
            }
            ScriptAction { script: { ms.noteDone(); paper.scale = 1; paper.rotation = Qt.binding(() => ms.note.rot || 0); } }
        }
    }

    // ── system: overheating, a full disk, pending updates ──
    Process {
        id: perfP; command: [Quickshell.env("HOME") + "/.config/hypr/scripts/perf.sh"]
        stdout: StdioCollector { onStreamFinished: {
            try { const j = JSON.parse(this.text); if ((j.cpuTemp || 0) >= 88 || (j.gpu && (j.gpu.temp || 0) >= 83)) ms.react("hot"); } catch (e) {}
        } }
    }
    Timer { interval: 120000; repeat: true; running: ms.on && ms.ready && ms.reactOn.includes("hot"); onTriggered: perfP.running = true }
    Process {
        id: diskP; command: ["sh", "-c", "df -P / /home 2>/dev/null | tail -n +2 | awk '{print $5}' | tr -d % | sort -n | tail -1"]
        stdout: StdioCollector { onStreamFinished: if (parseInt(this.text) >= 90) ms.react("disk") }
    }
    Process {          // counts from the package db updates.sh already synced (no network)
        id: updP; command: ["sh", "-c", "pacman -Qu --dbpath \"$HOME/.cache/sakura-updates/db\" 2>/dev/null | wc -l"]
        stdout: StdioCollector { onStreamFinished: {
            const n = parseInt(this.text) || 0;
            if (n >= 10) ms.react("updates", Cfg.tr("%1 updates are waiting - maybe update?").replace("%1", n));
        } }
    }
    Timer {
        interval: 600000; repeat: true; running: ms.on && ms.ready
        property int n: 0
        onTriggered: { n++; if (n % 12 === 1) { if (ms.reactOn.includes("disk")) diskP.running = true; if (ms.reactOn.includes("updates")) updP.running = true; } }
    }

    // ── flex mode: triple Shift (mascot-shift.sh) / qs ipc call mascot flex ──
    property bool flexing: false
    property real flx: 0                     // her left edge on the main screen
    property real flexX0: 0
    property real flexZoom: 1                // leans into the camera
    property real flexLean: 0
    property real flexBow: 0
    property real flexBeat: 0
    property string flexProp: ""
    property bool flexBling: false
    property bool flexShades: false
    property bool flexGun: false
    property bool flexRain: false
    property bool flexSky: false
    property bool flexDance: false
    property real glassY: -80                // the "deal with it" glasses dropping in
    property real glassOp: 0
    property bool billsFade: false
    property int billNext: 0
    property int billsAlive: 0
    readonly property int billMax: 60
    readonly property real fs: 1.5 * size
    readonly property real fw: 120 * fs
    readonly property real fh: 150 * fs
    readonly property real flexTop: sh - fh * 132 / 150          // her box top when standing on the bottom edge
    readonly property real glassTarget: flexTop + 66 * fs
    readonly property var flexClickLines: ["Autographs later", "No photos!"]
    // the soundtrack: ~/.config/sakura/sounds/mascot-flex.m4a, fades out as she strolls off (source is set only while playing)
    readonly property string flexSound: Quickshell.env("HOME") + "/.config/sakura/sounds/mascot-flex.m4a"
    property real flexVol: 0
    MediaPlayer {
        id: flexSnd
        audioOutput: AudioOutput { volume: ms.flexVol }
        onPlaybackStateChanged: if (playbackState === MediaPlayer.StoppedState && !ms.flexing) source = ""
        onSeekableChanged: ms.trySeek()
        onMediaStatusChanged: ms.trySeek()
    }
    NumberAnimation { id: flexFade; target: ms; property: "flexVol"; to: 0; duration: 3400; easing.type: Easing.InQuad
                      onFinished: flexSnd.stop() }
    property real pendingSeek: 0             // flexfrom: seek once the track is loaded
    function trySeek() { if (pendingSeek > 0 && flexSnd.seekable && flexSnd.playbackState === MediaPlayer.PlayingState && flexSnd.position > 0) { flexSnd.position = pendingSeek; pendingSeek = 0; } }
    function fadeFlexSound(ms_) { flexFade.stop(); flexFade.duration = ms_; flexFade.start(); }
    function flex() {
        if (!on || fullscreen || locked || flexing) return;
        hide(true); stopRomp(); dropAll();
        flexEnd(); flexing = true; billsFade = false; flexAmp = 0; halfIdx = -1;
        flexX0 = sw * 0.24 - fw / 2; flx = -fw - 20;
        buildCues(); cue = 0;
        songStart = Date.now() + 120;            // until the player reports where it is
        flexFade.stop(); flexVol = 0.9; flexSnd.stop(); flexSnd.source = "file://" + flexSound; flexSnd.play();
    }
    function flexEnd() {
        for (const a of [moveA, zoomA, glassA, leanA, bowA, girlLA, girlRA]) a.stop();
        girlsOn = false; girlsAttached = false; girlSay = ""; girlPose = "idle";
        flexing = false; flexProp = ""; flexBling = false; flexShades = false; flexGun = false; flexRain = false; flexSky = false;
        flexDance = false; flexZoom = 1; flexLean = 0; flexBow = 0; flexBeat = 0; flexPulse = 0; flexAmp = 0; flexSway = 0; glassOp = 0; cues = [];
        say = ""; pose = rest; billsFade = true;
    }
    function flexAbort() {
        if (!flexing && billsAlive === 0) return;
        flexEnd(); fadeFlexSound(400);
        for (let i = 0; i < billMax; i++) { const b = bills.itemAt(i); if (b) b.alive = false; }
        billsAlive = 0;
    }

    // ── synced to the track (Internet Swiping - Punchmadedev, from 0:16 on): 133.2 bpm → a beat every 450.5 ms
    //    (grid from 84 ms), the beat kicks in at 1.44 s = bar 0, bars of 4 beats (1.802 s), a break at 40.0-41.0 s and
    //    the drop on bar 22 (41.1 s). Everything runs off the track's position: cues on bars, the head-nod on each beat,
    //    the money gun / rain on the 8th notes.
    readonly property real beatMs: 450.5
    readonly property real beat0: 84
    readonly property real bar0: 1436
    property real songT: 0                   // seconds into the track
    property real songStart: 0               // Date.now() at the track's 0
    property int cue: 0
    property var cues: []
    property real flexAmp: 0                 // how hard she nods (only in the dance and on the drop)
    property real flexPulse: 0
    property int halfIdx: -1
    property real flexSway: 0
    FrameAnimation {
        running: ms.flexing
        onTriggered: {
            ms.songT = (Date.now() - ms.songStart) / 1000;
            while (ms.cue < ms.cues.length && ms.songT >= ms.cues[ms.cue][0]) ms.cues[ms.cue++][1]();
            if (!ms.flexing) return;
            const b = (ms.songT * 1000 - ms.beat0) / ms.beatMs, ph = b - Math.floor(b);
            const nod = ph < 0.16 ? Math.sin(ph / 0.16 * Math.PI / 2) : Math.pow(Math.cos((ph - 0.16) / 0.84 * Math.PI / 2), 2);
            ms.flexPulse = ms.songT * 1000 < ms.bar0 - 60 ? 0 : nod;                     // props keep time all along
            ms.flexBeat = ms.flexAmp * ms.flexPulse;                                     // the body nods only when she dances
            ms.flexSway = ms.flexDance ? Math.sin(b * Math.PI) * 5 : 0;                          // side to side over two beats
            const h = Math.floor(b * 2);
            if (h !== ms.halfIdx) { ms.halfIdx = h; ms.onEighth(h); }
        }
    }
    Connections {                            // keep the clock on the player (it starts with some latency)
        target: flexSnd
        function onPositionChanged() {
            if (ms.pendingSeek > 0) { ms.trySeek(); return; }
            if (!ms.flexing || flexSnd.playbackState !== MediaPlayer.PlayingState || flexSnd.position <= 0) return;
            const s = Date.now() - flexSnd.position;
            if (Math.abs(s - ms.songStart) > 40) ms.songStart = s;
        }
    }
    function onEighth(h) {
        if (flexGun) {
            const m = fromArt(flexArt.muzzle.x, flexArt.muzzle.y);
            spawnBill(m.x, m.y, 600 + Math.random() * 500, -520 + Math.random() * 380);
            if (h % 2 === 0) spawnBill(m.x, m.y, 700 + Math.random() * 500, -420 + Math.random() * 380);
        }
        if (flexRain) { const m = fromArt(56, 30); spawnBill(m.x, m.y, (Math.random() - 0.5) * 700, -900 + Math.random() * 350); }
        if (flexSky) { spawnBill(Math.random() * sw, -24, (Math.random() - 0.5) * 80, 60); if (h % 2) spawnBill(Math.random() * sw, -24, (Math.random() - 0.5) * 80, 40); }
    }
    NumberAnimation { id: moveA; target: ms; property: "flx" }
    // the finale's girls: smaller, tinted, a bow and lashes; once they're under her arms they move with her
    property bool girlsOn: false
    property bool girlsAttached: false
    property real girlLX: 0
    property real girlRX: 0
    property string girlPose: "idle"
    property string girlSay: ""
    readonly property real gs: fs * 0.82
    readonly property real gw: 120 * gs
    readonly property real gh: 150 * gs
    readonly property real girlLAt: flx - 15 * fs - gw / 2          // under her left arm
    readonly property real girlRAt: flx + 135 * fs - gw / 2         // under her right arm
    NumberAnimation { id: girlLA; target: ms; property: "girlLX" }
    NumberAnimation { id: girlRA; target: ms; property: "girlRX" }
    NumberAnimation { id: zoomA; target: ms; property: "flexZoom"; easing.type: Easing.InOutQuad }
    NumberAnimation { id: glassA; target: ms; property: "glassY" }
    NumberAnimation { id: leanA; target: ms; property: "flexLean"; easing.type: Easing.OutBack }
    SequentialAnimation {
        id: bowA                             // down on the beat, up on the next
        NumberAnimation { target: ms; property: "flexBow"; to: 22; duration: 200; easing.type: Easing.OutQuad }
        PauseAnimation { duration: 250 }
        NumberAnimation { target: ms; property: "flexBow"; to: 0; duration: 300; easing.type: Easing.InOutQuad }
    }
    function anim(a, to, dur, ease) { a.stop(); a.to = to; a.duration = Math.max(1, dur); if (ease !== undefined) a.easing.type = ease; a.start(); }
    function buildCues() {
        const bar = 4 * beatMs, c = [];
        const at = (n, f) => c.push([(bar0 + n * bar) / 1000, f]);          // on bar n
        const atS = (s, f) => c.push([s, f]);                               // at s seconds
        // intro: runs in, stops right as the beat kicks in
        atS(0, () => { pose = "run"; say = ""; anim(moveA, flexX0, bar0 - 80, Easing.OutQuad); });
        // the glasses fall for a whole bar and land on the downbeat
        at(0, () => { pose = "idle"; glassY = -80; glassOp = 1; anim(glassA, glassTarget, bar, Easing.InQuad); });
        at(1, () => { glassOp = 0; flexShades = true; pose = "happy"; say = "Deal with it"; });
        at(3, () => { flexBling = true; say = "Who's rich? I'm rich"; });
        // a fan of bills, right in your face, shaken on every beat
        at(5, () => { flexProp = "fan"; pose = "idle"; say = ""; anim(moveA, sw / 2 - fw / 2, bar, Easing.InOutQuad); anim(zoomA, 2.4, bar); });
        at(6, () => { say = "Money talks"; });
        at(9, () => { say = ""; anim(moveA, flexX0, bar, Easing.InOutQuad); anim(zoomA, 1, bar); });
        // money gun on the 8ths
        at(10, () => { flexProp = "gun"; pose = "happy"; say = "Make it rain!"; flexGun = true; });
        at(12, () => { flexGun = false; say = ""; });
        at(13, () => { flexGun = true; say = "Pew pew"; });
        at(15, () => { flexGun = false; say = ""; });
        // counting, a flip on every beat
        at(16, () => { flexProp = "count"; pose = "idle"; say = "Ten, twenty, thirty… a lot"; });
        // cocky dance
        at(18, () => { flexProp = ""; pose = "sing"; say = "Petals? No - cash"; flexDance = true; flexAmp = 0.8; });
        at(20, () => { say = ""; });
        // the break: she holds it…
        atS(40.0, () => { flexDance = false; pose = "surprised"; say = "Wait for it…"; flexAmp = 0; anim(leanA, 8, 400, Easing.OutQuad); });
        // …the drop: everything at once
        at(22, () => { pose = "happy"; say = "Catch!"; flexAmp = 0.6; flexProp = "gun"; flexGun = true; flexRain = true; flexSky = true; anim(leanA, 0, 300, Easing.OutBack); });
        at(24, () => { flexGun = false; flexRain = false; flexProp = ""; flexAmp = 0; say = "Don't touch, it's limited edition"; anim(leanA, -12, 450, Easing.OutBack); });
        at(26, () => { flexSky = false; say = ""; anim(leanA, 0, 450, Easing.OutQuad); flexProp = "fan"; });
        // the finale: she whistles, two girls run in from both sides and get under her arms…
        at(27, () => { flexProp = ""; pose = "whistle"; say = "Fiu-fiu!"; girlsOn = true; girlsAttached = false; girlPose = "run";
                       girlLX = -gw - 30; girlRX = sw + 30;
                       anim(girlLA, girlLAt, bar, Easing.OutQuad); anim(girlRA, girlRAt, bar, Easing.OutQuad); });
        at(28, () => { girlsAttached = true; girlPose = "happy"; flexProp = "hug"; pose = "happy"; say = "Ladies…"; });
        atS((bar0 + 28.5 * bar) / 1000, () => { girlSay = "Hiii~"; });
        at(29, () => { girlSay = ""; say = "We're out"; });
        // …and off they go together; the money fades, the track fades out
        at(30, () => { say = ""; pose = "run"; girlPose = "run"; billsFade = true; anim(moveA, sw + 40, 5500, Easing.InQuad); });
        atS(56.8, () => fadeFlexSound(5300));
        atS(62.2, () => flexEnd());
        cues = c.sort((x, y) => x[0] - y[0]);
    }
    function spawnBill(x, y, vx, vy) {
        const b = bills.itemAt(billNext);
        billNext = (billNext + 1) % billMax;
        if (!b) return;
        b.px = x - 18; b.py = y - 9; b.pvx = vx; b.pvy = vy; b.pr = Math.random() * 360; b.pvr = (Math.random() - 0.5) * 720;
        b.age = 0; b.rest = false; b.restAt = 0; b.fade = 1; b.alive = true;
    }
    function billStep(dt) {
        let n = 0;
        const floor = sh - 20;
        for (let i = 0; i < billMax; i++) {
            const b = bills.itemAt(i);
            if (!b || !b.alive) continue;
            n++; b.age += dt;
            if (!b.rest) {
                b.pvy = Math.min(b.pvy + 900 * dt, 150);                 // flutters down at ≤ 150 px/s
                b.pvx *= Math.exp(-dt * 1.4);
                b.px += (b.pvx + Math.sin(b.age * 4 + i) * 60) * dt; b.py += b.pvy * dt;
                b.pr += b.pvr * dt; b.pvr *= Math.exp(-dt * 0.8);
                const fl = floor - (i % 5) * 3;                          // a little pile
                if (b.py >= fl) { b.py = fl; b.rest = true; b.restAt = b.age; b.pr = (Math.random() - 0.5) * 30; }
                if (b.px < -60 || b.px > sw + 60) b.alive = false;
            }
            if (billsFade || (b.rest && b.age - b.restAt > 5)) { b.fade -= dt * 1.2; if (b.fade <= 0) b.alive = false; }
        }
        billsAlive = n;
    }
    function fromArt(x, y) { return flexArt.mapToItem(flexWin.contentItem, x, y); }
    FrameAnimation { running: flexWin.visible && ms.billsAlive + (ms.flexGun || ms.flexRain || ms.flexSky ? 1 : 0) > 0; onTriggered: ms.billStep(Math.min(frameTime, 0.05)) }

    PanelWindow {
        id: flexWin
        visible: ms.on && (ms.flexing || ms.billsAlive > 0) && !ms.fullscreen && !ms.locked
        screen: Cfg.mainScreen
        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "mascot-flex"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: flexer }

        Repeater {          // the bills: a fixed pool, recycled (no arrays rebuilt per frame)
            id: bills
            model: ms.billMax
            MascotArt.Bill {
                id: bill
                required property int index
                property bool alive: false
                property real px: 0
                property real py: 0
                property real pvx: 0
                property real pvy: 0
                property real pr: 0
                property real pvr: 0
                property real age: 0
                property bool rest: false
                property real restAt: 0
                property real fade: 1
                visible: alive
                x: px; y: py; rotation: pr; opacity: Math.max(0, fade)
                transform: Scale { origin.x: 18; origin.y: 9; xScale: bill.rest ? 1 : Math.cos(bill.age * 7 + bill.index) }   // flutters
            }
        }
        Repeater {          // the two girls (behind her, so her arms go over their shoulders)
            model: 2
            Item {
                id: girl
                required property int index
                readonly property bool lft: index === 0
                visible: ms.girlsOn && ms.flexing
                width: ms.gw; height: ms.gh
                x: ms.girlsAttached ? (lft ? ms.girlLAt : ms.girlRAt) : (lft ? ms.girlLX : ms.girlRX)
                y: ms.sh - ms.gh * 132 / 150
                transformOrigin: Item.Bottom
                rotation: ms.girlPose === "run" ? 8 : (lft ? 7 : -7)        // leaning in to her
                MascotArt {
                    id: girlArt
                    pose: ms.girlPose; active: girl.visible; stand: ms.girlPose !== "run"
                    girl: true; hearts: ms.girlPose === "happy"; talking: !girl.lft && ms.girlSay !== ""
                    tint: girl.lft ? "#ffb3d1" : "#c9b6f2"
                    flip: !girl.lft && !ms.girlsAttached                        // the right one runs in leftwards
                    transform: [ Scale { xScale: ms.gs * (girlArt.flip ? -1 : 1); yScale: ms.gs }, Translate { x: girlArt.flip ? ms.gw : 0 } ]
                }
            }
        }
        Item {
            id: flexer
            visible: ms.flexing
            width: ms.fw; height: ms.fh
            x: ms.flx; y: ms.flexTop
            transformOrigin: Item.Bottom
            scale: ms.flexZoom
            rotation: ms.flexLean + ms.flexBow + ms.flexSway
            MascotArt {
                id: flexArt
                pose: ms.pose; talking: ms.say !== ""; active: ms.flexing; pulse: ms.flexPulse
                stand: ms.pose !== "run"; prop: ms.flexProp; bling: ms.flexBling
                outfit: ms.flexShades ? "shades" : ""; beat: ms.flexBeat; custom: ms.custom
                transform: Scale { xScale: ms.fs; yScale: ms.fs }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ms.say = ms.pick(ms.flexClickLines) }
        }
        Item {              // the glasses dropping in (and lifting off at the end), same shape as her shades
            visible: ms.flexing && ms.glassOp > 0.01
            opacity: ms.glassOp
            x: flexer.x + 26 * ms.fs; y: ms.glassY
            width: 61; height: 16; scale: ms.fs; transformOrigin: Item.TopLeft
            Rectangle { x: 0; y: 0; width: 26; height: 16; radius: 6; color: "#221a26"
                Rectangle { x: 5; y: 3; width: 8; height: 2.5; radius: 1.2; color: "#ffffff"; opacity: 0.6; rotation: -15 } }
            Rectangle { x: 35; y: 0; width: 26; height: 16; radius: 6; color: "#221a26"
                Rectangle { x: 5; y: 3; width: 8; height: 2.5; radius: 1.2; color: "#ffffff"; opacity: 0.6; rotation: -15 } }
            Rectangle { x: 24; y: 4; width: 13; height: 3; radius: 1.5; color: "#221a26" }
        }
        Bubble {
            shown: ms.girlSay !== "" && ms.flexing
            text: ms.girlSay
            x: ms.clamp(ms.girlRAt + ms.gw / 2 - width / 2 + 40, 4, parent.width - width - 4)
            y: Math.max(8, ms.sh - ms.gh * 132 / 150 - height + 4)
        }
        Bubble {
            shown: ms.say !== "" && ms.flexing
            text: ms.say
            x: ms.clamp(flexer.x + ms.fw / 2 - width / 2, 4, parent.width - width - 4)
            y: Math.max(8, flexer.y + ms.fh - ms.fh * ms.flexZoom - height + 6)
        }
    }

    component Bubble: Rectangle {
        id: bub
        property bool shown: false
        property string text: ""
        visible: opacity > 0.01
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.7
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
        width: Math.min(tm.advanceWidth + 2, 230) + 26; height: bt.implicitHeight + 18; radius: Math.min(19, height / 2)
        color: Cfg.glass; border.width: 1; border.color: "#1fffffff"
        TextMetrics { id: tm; text: bt.text; font: bt.font }
        Text {
            id: bt; x: 13; y: 9; width: bub.width - 26
            text: Cfg.tr(bub.text); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
            font.family: Cfg.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: "#ffffff"
        }
    }
}
