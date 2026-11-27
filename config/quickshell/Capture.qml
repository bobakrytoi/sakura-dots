// sakura mono - Capture panel (Alt+Z): flows out of the top notch (DropPanel.qml), like the Mixer.
// Top: Instant Replay - how full the buffer is and one big "Save last N min". Below: Record (+ mic / system sound
// in clips), Screenshot (area · screen · in 3 s - the area editor also picks a window with a click), the last four
// captures (click opens). The gear turns the same shape into the settings page (replay, video, audio, folder,
// hotkeys - the same ~/.config/capture/config.json as Settings > Screenshots & recording); ← / Esc goes back.
// Shortcuts show only while you hover / pick a button (in the section's label). Arrows move, Enter/Space act, Esc closes.
// Backend: hypr/scripts/capture.sh (gpu-screen-recorder) and screenshot.sh - untouched by this panel.
// Checks: qs ipc call capture test [MONITOR] (shows it without taking the keyboard) · nav left|right|up|down · press · state · close
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

Scope {
    id: cap
    property var topBar: null

    readonly property color cCard:   "#12ffffff"
    readonly property color cHover:  "#24ffffff"
    readonly property color cLine:   "#14ffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property color cRed:    "#f28fad"
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string home:   Quickshell.env("HOME")
    readonly property string scripts: home + "/.config/hypr/scripts/"
    readonly property string script: scripts + "capture.sh"
    function t(s) { return Cfg.tr(s); }

    property bool shown: false
    property bool test: false            // shown without the keyboard (checks)
    property bool replayOn: false
    property bool recordOn: false
    property int recordSecs: 0
    property real replayStart: 0         // epoch s (replay.pid mtime)
    property real now: Date.now() / 1000
    property string flash: ""            // "saved" for a moment after Save
    property string page: "main"         // main | settings
    property string note: ""             // settings: "replay restarted" for a moment
    readonly property string covering: drop.covering
    // the shape grows / shrinks between the pages (DropPanel redraws it on every height)
    readonly property real mainH: 22 + 84 + 36 + 67 + 24
    readonly property real setH: 22 + setPage.implicitHeight + 24
    property real panelH: page === "settings" ? setH : mainH
    Behavior on panelH { NumberAnimation { duration: 300 * Cfg.anim; easing.type: Easing.OutCubic } }

    function open(asTest) {
        test = !!asTest; pickScreen(); refresh(); listRecent();
        flash = ""; kb = false; cur = null; hot = null; page = "main"; shown = true;
    }
    function close() { shown = false; }
    function toggle() { if (shown) close(); else open(false); }
    function run(args) { Quickshell.execDetached([script].concat(args)); refreshSoon.restart(); }
    function later(cmd, ms) { Quickshell.execDetached(["sh", "-c", "sleep " + (ms / 1000) + "; " + cmd]); }
    function openSettings() { if (!shown) open(false); cur = null; hot = null; page = "settings"; }
    function back() { cur = null; hot = null; page = "main"; }

    IpcHandler {
        target: "capture"
        function toggle(): void { cap.toggle(); }
        function open(): void { if (!cap.shown) cap.open(false); }
        function close(): void { cap.close(); }
        function settings(): void { cap.openSettings(); }
        // checks
        function page(p: string): void { if (p === "settings") cap.openSettings(); else cap.back(); }
        function test(scr: string): void { cap.open(true); const sc = Quickshell.screens.find(x => x.name === scr); if (sc) cap.screen0 = sc; }
        function nav(dir: string): string { cap.move(dir); return cap.cur ? cap.cur.name : "none"; }
        function press(): string { const c = cap.cur || cap.navList()[0]; if (c) c.act(); return c ? c.name : "none"; }
        function state(): string {
            return JSON.stringify({ shown: cap.shown, replay: cap.replayOn, fill: Math.round(cap.filled), of: cap.total,
                record: cap.recordOn, secs: cap.recordSecs, audio: cap.cfg.audio, page: cap.page, note: cap.note, cur: cap.cur ? cap.cur.name : "",
                tip: cap.tipItem ? cap.tipItem.tip : "", recent: cap.recent.map(r => r.f.split("/").pop()) });
        }
    }

    // ── config (~/.config/capture/config.json; Settings edits the rest) ──
    property var cfg: ({ replaySeconds: 60, audio: "desktop", folder: "~/Videos/Clips",
                         hotkeys: { menu: "ALT + Z", replaySave: "ALT + SHIFT + F10", replayToggle: "ALT + SHIFT + F9", record: "ALT + F9", screenshot: "ALT + F1" } })
    FileView {
        id: cfgFile
        path: cap.home + "/.config/capture/config.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { cap.cfg = Object.assign({}, cap.cfg, JSON.parse(text())); } catch (e) {} }
    }
    readonly property bool sysOn: cfg.audio === "desktop" || cfg.audio === "desktop+mic"
    readonly property bool micOn: cfg.audio === "mic" || cfg.audio === "desktop+mic"
    function setAudio(sys, mic) { setCfg("audio", sys && mic ? "desktop+mic" : sys ? "desktop" : mic ? "mic" : "none"); }
    // every change is written at once; what the recorder reads restarts the replay (its buffer starts over)
    readonly property var restartKeys: ["fps", "quality", "codec", "monitor", "audio", "replaySeconds", "folder"]
    function setCfg(k, v) {
        const c = Object.assign({}, cfg); c[k] = v; cfg = c;
        cfgFile.setText(JSON.stringify(c, null, 2));
        if (restartKeys.indexOf(k) >= 0 && replayOn) applyT.restart();
    }
    Timer { id: applyT; interval: 700
        onTriggered: { Quickshell.execDetached([cap.script, "apply"]); cap.note = cap.t("Replay restarted · buffer cleared"); noteT.restart(); } }
    Timer { id: noteT; interval: 3500; onTriggered: cap.note = "" }
    // hotkeys: config.json + hypr/capture-binds.lua (sourced by hyprland.lua), then hyprctl reload
    function setKey(k, v) {
        const c = Object.assign({}, cfg); c.hotkeys = Object.assign({}, cfg.hotkeys || {}); c.hotkeys[k] = v; cfg = c;
        cfgFile.setText(JSON.stringify(c, null, 2));
        const h = c.hotkeys, cs = script;
        const b = (key, cmd, desc) => key ? "hl.bind(\"" + key + "\", hl.dsp.exec_cmd(\"" + cmd + "\"), { desc = \"" + desc + "\", dont_inhibit = true })\n" : "";
        const lua = "-- generated by the Capture panel (Alt+Z) / Settings - change hotkeys there\n" +
            b(h.menu, "qs ipc call capture toggle", "Capture overlay") +
            b(h.replaySave, cs + " replay-save", "Save instant replay") +
            b(h.replayToggle, cs + " replay-toggle", "Instant replay on/off") +
            b(h.record, cs + " record-toggle", "Start/stop recording") +
            b(h.screenshot, scripts + "screenshot.sh screen", "Screenshot of the monitor");
        bindProc.command = ["sh", "-c", "cat > \"$HOME/.config/hypr/capture-binds.lua\" <<'EOF'\n" + lua + "EOF\nhyprctl reload >/dev/null"];
        bindProc.running = true;
    }
    Process { id: bindProc }
    function hk(k) { const h = cfg.hotkeys || {}; return h[k] ? "  ·  " + h[k] : ""; }

    // ── live status ──
    Process {
        id: statProc
        command: ["sh", "-c", "\"$0\" json; p=\"${XDG_RUNTIME_DIR:-/tmp}/capture/replay.pid\"; [ -f \"$p\" ] && stat -c %Y \"$p\" || echo 0", cap.script]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const l = this.text.trim().split("\n"), j = JSON.parse(l[0]);
                    cap.replayOn = j.replay; cap.recordOn = j.record; cap.recordSecs = j.recordSeconds;
                    cap.replayStart = parseInt(l[1] || "0") || 0;
                } catch (e) {}
            }
        }
    }
    function refresh() { now = Date.now() / 1000; if (!statProc.running) statProc.running = true; }
    Timer { interval: 1000; running: cap.shown; repeat: true; onTriggered: cap.refresh() }
    Timer { id: refreshSoon; interval: 700; onTriggered: cap.refresh() }

    readonly property real total: Math.max(1, cfg.replaySeconds || 60)
    readonly property real filled: replayOn && replayStart > 0 ? Math.max(0, Math.min(total, now - replayStart)) : 0
    readonly property bool full: filled >= total - 0.5
    function fmt(s) { s = Math.floor(s); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
    function mins(s) { return s % 60 === 0 ? (s / 60) + " " + t("min") : s >= 60 ? fmt(s) : s + " " + t("s"); }

    // ── recent captures: newest 4 of Replays, Recordings and the screenshot folder; video frames cached ──
    // (files written in the last 2 s are skipped: that is the recording in progress, it has no frame yet)
    readonly property string vidDir: String(cfg.folder || "~/Videos/Clips").replace(/^~/, home)
    readonly property string shotDir: String(Cfg.data.shotDir || "~/Pictures/Screenshots").replace(/^~/, home)
    property var recent: []
    Process {
        id: recentProc
        command: ["sh", "-c", "v=\"$1\"; s=\"$2\"; c=\"$HOME/.cache/sakura/capture-thumbs\"; mkdir -p \"$c\"\n" +
            "find \"$v/Replays\" \"$v/Recordings\" \"$s\" -maxdepth 1 -type f ! -newermt '2 seconds ago' \\( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.png' -o -iname '*.jpg' \\) " +
            "-printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -4 | cut -f2- | while IFS= read -r f; do\n" +
            " case \"$f\" in *.mp4|*.mkv|*.MP4|*.MKV) t=\"$c/$(printf %s \"$f\" | md5sum | cut -c1-16).jpg\"\n" +
            "  [ -s \"$t\" ] || timeout 8 ffmpeg -loglevel error -y -ss 1 -i \"$f\" -frames:v 1 -vf scale=240:-1 \"$t\" </dev/null\n" +
            "  printf 'v\\t%s\\t%s\\n' \"$f\" \"$t\" ;;\n *) printf 'i\\t%s\\t%s\\n' \"$f\" \"$f\" ;; esac; done", "sh", cap.vidDir, cap.shotDir]
        stdout: StdioCollector {
            onStreamFinished: cap.recent = this.text.trim().split("\n").filter(x => x).map(l => { const p = l.split("\t"); return { v: p[0] === "v", f: p[1], t: p[2] }; })
        }
    }
    function listRecent() { if (!recentProc.running) recentProc.running = true; }
    Timer { id: recentSoon; interval: 3500; onTriggered: cap.listRecent() }

    property var screen0: Quickshell.screens[0]
    function pickScreen() {
        const m = Hyprland.focusedMonitor;
        const sc = m ? Quickshell.screens.find(s => s.name === m.name) : null;
        if (sc) screen0 = sc;
    }

    // ── actions ──
    function saveReplay() {
        if (!replayOn) { run(["replay-toggle"]); return; }
        run(["replay-save"]); flash = "saved"; closeSoon.restart(); recentSoon.restart();
    }
    Timer { id: closeSoon; interval: 650; onTriggered: { cap.close(); cap.flash = ""; } }
    function record() {
        if (recordOn) { run(["record-toggle"]); recentSoon.restart(); }
        else { close(); later(script + " record-toggle", 350); }      // after the panel has folded away
    }
    function shot(mode) {
        close();
        later(scripts + "screenshot.sh " + mode, 450);
    }
    function openFile(f) { close(); Quickshell.execDetached(["xdg-open", f]); }

    // ── keyboard: the buttons in order; row 0 = replay, row 1 = the rest ──
    property bool kb: false              // the focus ring shows once the keyboard is used
    property var cur: null               // the picked button (keyboard)
    property var hot: null               // under the mouse
    readonly property var tipItem: hot || (kb ? cur : null)     // its tip goes into its section's label
    function navList() {
        const l = [swBtn, saveBtn, recBtn, micBtn, sysBtn, areaBtn, screenBtn, delayBtn];
        for (let i = 0; i < thumbRep.count; i++) l.push(thumbRep.itemAt(i));
        l.push(folderBtn, gearBtn);
        return l.filter(x => x && x.visible);
    }
    property var setItems: []            // the settings page's buttons (they register themselves)
    function centre(x) { return x.mapToItem(null, x.width / 2, x.height / 2); }
    function setList() {
        return setItems.filter(x => x && x.visible).map(x => ({ x: x, c: centre(x) }))
                       .sort((a, b) => Math.abs(a.c.y - b.c.y) > 10 ? a.c.y - b.c.y : a.c.x - b.c.x);
    }
    function moveSet(dir) {
        const l = setList();
        if (!l.length) return;
        const i = l.findIndex(e => e.x === cur);
        if (!kb || i < 0) { kb = true; cur = l[0].x; return; }
        if (dir === "right") { cur = l[(i + 1) % l.length].x; return; }
        if (dir === "left") { cur = l[(i - 1 + l.length) % l.length].x; return; }
        const c = l[i].c, down = dir === "down", sp = setPage.split();
        const cand = l.filter(e => down ? e.c.y > c.y + 10 : e.c.y < c.y - 10);
        if (!cand.length) return;
        const ry = down ? Math.min(...cand.map(e => e.c.y)) : Math.max(...cand.map(e => e.c.y));
        // the next row; in two columns: stay in the same column if it has one
        const row = cand.filter(e => Math.abs(e.c.y - ry) <= 10);
        const sameCol = cand.filter(e => (e.c.x > sp) === (c.x > sp));
        let pool = row;
        if (!row.some(e => (e.c.x > sp) === (c.x > sp)) && sameCol.length) {
            const ry2 = down ? Math.min(...sameCol.map(e => e.c.y)) : Math.max(...sameCol.map(e => e.c.y));
            pool = sameCol.filter(e => Math.abs(e.c.y - ry2) <= 10);
        }
        let best = pool[0];
        for (const e of pool) if (Math.abs(e.c.x - c.x) < Math.abs(best.c.x - c.x)) best = e;
        cur = best.x;
    }
    function move(dir) {
        if (page === "settings") { moveSet(dir); return; }
        const l = navList();
        if (!l.length) return;
        if (!kb || !cur || l.indexOf(cur) < 0) { kb = true; cur = saveBtn; return; }
        const i = l.indexOf(cur);
        if (dir === "right") cur = l[(i + 1) % l.length];
        else if (dir === "left") cur = l[(i - 1 + l.length) % l.length];
        else {
            const row = dir === "down" ? 1 : 0;
            if (cur.row === row) return;
            const cx = cur.mapToItem(null, cur.width / 2, 0).x;
            let best = null, bd = 1e9;
            for (const x of l) if (x.row === row) { const d = Math.abs(x.mapToItem(null, x.width / 2, 0).x - cx); if (d < bd) { bd = d; best = x; } }
            if (best) cur = best;
        }
    }

    // ── bits ──
    component Ico: Text { font.family: cap.fIcon; color: cap.cFg; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
    component Lbl: Text { font.family: cap.fUi; color: cap.cFg; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
    // a button: hover / keyboard pick light it; its tip goes into the label of its section (sec)
    // kind: "" (anything inside) | "chip" (text) | "switch" | "key" (hotkey field: act, then press a combination; Esc cancels)
    // (one component on purpose: a second inline component derived from Ctl fails to load - "X is not a type")
    component Ctl: Rectangle {
        id: ctl
        property string kind: ""
        property string text: ""
        property string key: ""
        property bool listening: false
        readonly property string keyValue: (cap.cfg.hotkeys || {})[key] || ""
        property string name: kind !== "" ? kind + ":" + (text || key) : ""
        property string tip: ""
        property string sec: ""
        property int row: 1
        property bool on: false
        property color base: cap.cCard
        property color onColor: kind === "chip" || kind === "switch" ? cap.cAccent : Cfg.acc(0.16)
        property color ring: on && (kind === "chip" || kind === "switch") ? "#ffffff" : cap.cAccent
        property string pg: "main"          // "set": a settings page button (keyboard order)
        Component.onCompleted: if (pg === "set") cap.setItems.push(ctl)
        Component.onDestruction: { const i = cap.setItems.indexOf(ctl); if (i >= 0) cap.setItems.splice(i, 1); }
        readonly property bool picked: cap.kb && cap.cur === ctl
        readonly property bool lit: ma.containsMouse || picked
        signal act()
        implicitWidth: kind === "chip" ? chipT.implicitWidth + 18 : kind === "switch" ? 40 : kind === "key" ? 180 : 0
        implicitHeight: kind === "switch" ? 22 : kind !== "" ? 28 : 0
        radius: height / 2
        color: on ? onColor : lit ? cap.cHover : base
        border.width: picked ? 2 : 0; border.color: ring
        scale: ma.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 90 } }
        MouseArea {
            id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: { if (containsMouse) cap.hot = ctl; else if (cap.hot === ctl) cap.hot = null; }
            onClicked: { cap.cur = ctl; ctl.act(); }
        }
        // chip
        Lbl { id: chipT; visible: ctl.kind === "chip"; anchors.centerIn: parent; text: ctl.text; font.pixelSize: 12; font.weight: Font.DemiBold
              color: ctl.on ? cap.cAccFg : cap.cFg }
        // switch knob
        Rectangle {
            visible: ctl.kind === "switch"
            width: 16; height: 16; radius: 8; y: 3
            x: ctl.on ? ctl.width - width - 3 : 3
            color: ctl.on ? cap.cAccFg : "#ffffff"
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        // hotkey field
        Lbl { visible: ctl.kind === "key"; anchors.centerIn: parent; text: ctl.listening ? cap.t("Press keys…") : (ctl.keyValue || "-")
              color: ctl.listening ? cap.cAccent : cap.cFg; font.pixelSize: 12; font.weight: Font.DemiBold }
        onAct: if (kind === "key") { listening = true; ctl.forceActiveFocus(); }
        onActiveFocusChanged: if (!activeFocus) listening = false
        Keys.onPressed: e => {
            if (ctl.kind !== "key" || !ctl.listening) return;
            e.accepted = true;
            if (e.key === Qt.Key_Escape) { ctl.listening = false; panel.forceActiveFocus(); return; }
            const mods = [];
            if (e.modifiers & Qt.MetaModifier) mods.push("SUPER");
            if (e.modifiers & Qt.ControlModifier) mods.push("CTRL");
            if (e.modifiers & Qt.AltModifier) mods.push("ALT");
            if (e.modifiers & Qt.ShiftModifier) mods.push("SHIFT");
            let k = "";
            if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F24) k = "F" + (e.key - Qt.Key_F1 + 1);
            else if (e.key === Qt.Key_Print) k = "Print";
            else if (e.key === Qt.Key_Space) k = "SPACE";
            else if (e.key === Qt.Key_Home) k = "Home";
            else if (e.key === Qt.Key_End) k = "End";
            else if (e.key === Qt.Key_Insert) k = "Insert";
            else if (e.key === Qt.Key_PageUp) k = "Prior";
            else if (e.key === Qt.Key_PageDown) k = "Next";
            else if (e.key >= Qt.Key_A && e.key <= Qt.Key_Z) k = String.fromCharCode(e.key);
            else if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) k = String.fromCharCode(e.key);
            if (!k) return;                       // only modifiers so far
            ctl.listening = false;
            panel.forceActiveFocus();
            cap.setKey(ctl.key, mods.concat([k]).join(" + "));
        }
    }
    component SecLabel: Lbl {      // "Record" - or the tip of the button hovered / picked in this section
        property string title: ""
        property string sec: ""
        readonly property bool tipHere: !!cap.tipItem && cap.tipItem.sec === sec
        text: tipHere ? cap.tipItem.tip : title
        color: tipHere ? cap.cFg : cap.cMuted
        font.pixelSize: 11; font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    // ── settings page bits ──
    component Group: Lbl { color: cap.cAccent; font.pixelSize: 11; font.weight: Font.Bold; topPadding: 10; bottomPadding: 4; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
    component SRow: Item {
        id: srow
        property string label: ""
        default property alias content: holder.data
        width: parent ? parent.width : 0; height: 36
        Lbl { anchors { left: parent.left; verticalCenter: parent.verticalCenter } width: parent.width - holder.width - 8; text: srow.label; elide: Text.ElideRight }
        Row { id: holder; anchors { right: parent.right; verticalCenter: parent.verticalCenter } spacing: 4 }
    }

    DropPanel {
        id: drop
        topBar: cap.topBar
        shown: cap.shown
        onCloseRequested: cap.close()
        screen0: cap.screen0
        anchorX: -1
        boxW: 760
        boxH: Math.round(cap.panelH)
        radius: 26
        ns: "capture"
        grabFocus: !cap.test

        FocusScope {
            id: panel
            anchors { fill: parent; leftMargin: 26; rightMargin: 26; topMargin: 22; bottomMargin: 24 }
            focus: true
            Keys.onPressed: e => {
                const d = e.key === Qt.Key_Left || e.key === Qt.Key_Backtab ? "left" : e.key === Qt.Key_Right || e.key === Qt.Key_Tab ? "right"
                        : e.key === Qt.Key_Up ? "up" : e.key === Qt.Key_Down ? "down" : "";
                if (d) { cap.move(d); e.accepted = true; return; }
                if ((e.key === Qt.Key_Escape || e.key === Qt.Key_Backspace) && cap.page === "settings") { cap.back(); e.accepted = true; return; }
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                    if (cap.page === "settings") { if (cap.cur && cap.cur.pg === "set") cap.cur.act(); }
                    else (cap.cur && cap.cur.visible ? cap.cur : saveBtn).act();
                    e.accepted = true;
                }
            }

            Item {
            id: mainPage
            width: parent.width; height: cap.mainH - 46
            opacity: cap.page === "main" ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 200 * Cfg.anim } }
            transform: Translate { x: cap.page === "main" ? 0 : -40; Behavior on x { NumberAnimation { duration: 300 * Cfg.anim; easing.type: Easing.OutCubic } } }

            // ═════ Instant Replay ═════
            Item {
                id: hero
                width: parent.width; height: 84

                Row {
                    spacing: 10
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4
                        color: cap.replayOn ? cap.cAccent : cap.cMuted
                        SequentialAnimation on opacity {
                            running: cap.replayOn && cap.shown; loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 800 } NumberAnimation { to: 1; duration: 800 }
                        }
                    }
                    Lbl { text: cap.t("Instant Replay"); font.pixelSize: 17; font.weight: Font.Bold }
                    Item { width: 2; height: 1 }
                    // on / off
                    Ctl {
                        id: swBtn; name: "replay-toggle"; row: 0; sec: "replay"
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36; height: 20
                        on: cap.replayOn; onColor: cap.cAccent; base: "#26ffffff"
                        tip: (cap.replayOn ? cap.t("Turn replay off") : cap.t("Turn replay on")) + cap.hk("replayToggle")
                        onAct: cap.run(["replay-toggle"])
                        Rectangle {
                            width: 14; height: 14; radius: 7; y: 3
                            x: cap.replayOn ? parent.width - width - 3 : 3
                            color: cap.replayOn ? cap.cAccFg : "#ffffff"
                            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                    }
                }
                SecLabel {
                    y: 30; width: bufBar.width; sec: "replay"
                    font.pixelSize: 12; font.weight: Font.Normal
                    title: !cap.replayOn ? cap.t("Off - nothing is kept")
                         : cap.full ? cap.t("Keeping the last") + " " + cap.mins(cap.total)
                         : cap.t("Filling up") + " · " + cap.fmt(cap.filled) + " / " + cap.fmt(cap.total)
                }
                // the buffer
                Item {
                    id: bufBar
                    y: 58; width: parent.width - saveBtn.width - 32; height: 6
                    opacity: cap.replayOn ? 1 : 0.4
                    readonly property real frac: cap.filled / cap.total
                    Rectangle { anchors.fill: parent; radius: 3; color: "#1affffff" }
                    Rectangle {
                        width: Math.max(parent.frac > 0 ? 6 : 0, parent.width * parent.frac); height: parent.height; radius: 3
                        Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Cfg.acc(0.35) } GradientStop { position: 1; color: cap.cAccent } }
                        Rectangle {        // the live head
                            visible: cap.replayOn
                            x: parent.width - 5; y: -2; width: 10; height: 10; radius: 5; color: cap.cAccent
                            SequentialAnimation on opacity {
                                running: cap.replayOn && cap.shown && !cap.full; loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: 700 } NumberAnimation { to: 1; duration: 700 }
                            }
                        }
                    }
                }
                Lbl { y: 72; text: cap.fmt(cap.filled); color: cap.replayOn ? cap.cAccent : cap.cMuted; font.pixelSize: 11; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
                Lbl { y: 72; x: bufBar.width - width; text: cap.fmt(cap.total); color: cap.cMuted; font.pixelSize: 11; font.features: { "tnum": 1 } }

                // the one big action
                Ctl {
                    id: saveBtn; name: "save"; row: 0; sec: "replay"
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 224; height: 54
                    color: lit ? Qt.lighter(cap.cAccent, 1.08) : cap.cAccent
                    border.color: "#ffffff"
                    tip: cap.replayOn ? cap.t("Save the replay") + cap.hk("replaySave") : cap.t("Turn replay on") + cap.hk("replayToggle")
                    onAct: cap.saveReplay()
                    Row {
                        anchors.centerIn: parent; spacing: 9
                        Ico { text: cap.flash === "saved" ? "" : cap.replayOn ? "" : ""; color: cap.cAccFg; anchors.verticalCenter: parent.verticalCenter }
                        Lbl {
                            color: cap.cAccFg; font.pixelSize: 14; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                            text: cap.flash === "saved" ? cap.t("Saved") : !cap.replayOn ? cap.t("Turn replay on")
                                : cap.t("Save last") + " " + (cap.full ? cap.mins(cap.total) : cap.fmt(cap.filled))
                        }
                    }
                }
            }

            Rectangle { y: hero.height + 17; width: parent.width; height: 1; color: cap.cLine }

            // ═════ Record · Screenshot · Recent ═════
            Item {
                y: hero.height + 36; width: parent.width; height: 67

                // record
                Column {
                    spacing: 10
                    SecLabel { title: cap.t("Record"); sec: "record"; width: 236 }
                    Row {
                        spacing: 8
                        Ctl {
                            id: recBtn; name: "record"; sec: "record"
                            width: Math.max(108, recRow.implicitWidth + 34); height: 44
                            on: cap.recordOn; onColor: Qt.rgba(242 / 255, 143 / 255, 173 / 255, 0.18)
                            tip: (cap.recordOn ? cap.t("Stop and save") : cap.t("Start recording")) + cap.hk("record")
                            onAct: cap.record()
                            Row {
                                id: recRow; anchors.centerIn: parent; spacing: 9
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: cap.recordOn ? 3 : 6; color: cap.cRed
                                    Behavior on radius { NumberAnimation { duration: 160 } }
                                    SequentialAnimation on opacity {
                                        running: cap.recordOn && cap.shown; loops: Animation.Infinite
                                        NumberAnimation { to: 0.35; duration: 600 } NumberAnimation { to: 1; duration: 600 }
                                    }
                                }
                                Lbl { text: cap.recordOn ? cap.fmt(cap.recordSecs) : cap.t("Record"); font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                                      color: cap.recordOn ? cap.cRed : cap.cFg }
                            }
                        }
                        Ctl {
                            id: micBtn; name: "mic"; sec: "record"; width: 44; height: 44; on: cap.micOn
                            tip: cap.t(cap.micOn ? "Microphone in clips: on" : "Microphone in clips: off") + (cap.replayOn ? " · " + cap.t("replay restarts") : "")
                            onAct: cap.setAudio(cap.sysOn, !cap.micOn)
                            Ico { anchors.centerIn: parent; text: cap.micOn ? "" : ""; color: cap.micOn ? cap.cAccent : cap.cMuted }
                        }
                        Ctl {
                            id: sysBtn; name: "system-sound"; sec: "record"; width: 44; height: 44; on: cap.sysOn
                            tip: cap.t(cap.sysOn ? "System sound in clips: on" : "System sound in clips: off") + (cap.replayOn ? " · " + cap.t("replay restarts") : "")
                            onAct: cap.setAudio(!cap.sysOn, cap.micOn)
                            Ico { anchors.centerIn: parent; text: cap.sysOn ? "" : ""; color: cap.sysOn ? cap.cAccent : cap.cMuted }
                        }
                    }
                }

                // screenshot
                Column {
                    x: 256; spacing: 10
                    SecLabel { title: cap.t("Screenshot"); sec: "shot"; width: 170 }
                    Rectangle {
                        width: segRow.implicitWidth + 8; height: 44; radius: 22; color: cap.cCard
                        Row {
                            id: segRow; anchors.centerIn: parent; spacing: 2
                            Ctl { id: areaBtn; name: "shot-area"; sec: "shot"; width: 40; height: 36; base: "transparent"
                                tip: cap.t("Area or a window")
                                onAct: cap.shot("region")
                                Ico { anchors.centerIn: parent; text: ""; color: parent.lit ? cap.cAccent : cap.cFg } }
                            Ctl { id: screenBtn; name: "shot-screen"; sec: "shot"; width: 40; height: 36; base: "transparent"
                                tip: cap.t("Whole screen") + cap.hk("screenshot")
                                onAct: cap.shot("screen")
                                Ico { anchors.centerIn: parent; text: ""; color: parent.lit ? cap.cAccent : cap.cFg } }
                            Ctl { id: delayBtn; name: "shot-delay"; sec: "shot"; width: 40; height: 36; base: "transparent"
                                tip: cap.t("Area in 3 seconds")
                                onAct: cap.shot("delay 3")
                                Ico { anchors.centerIn: parent; text: ""; color: parent.lit ? cap.cAccent : cap.cFg } }
                        }
                    }
                }

                // recent
                Column {
                    anchors.right: parent.right; spacing: 10
                    Item {
                        width: thumbs.width; height: 13
                        SecLabel { title: cap.t("Recent"); sec: "recent"; width: parent.width - 54; anchors.verticalCenter: parent.verticalCenter }
                        Row {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter } spacing: 2
                            Ctl { id: folderBtn; name: "folder"; sec: "recent"; width: 26; height: 22; base: "transparent"
                                tip: cap.t("Open the folder")
                                onAct: { cap.close(); Quickshell.execDetached(["sh", "-c", "mkdir -p \"$1\" && xdg-open \"$1\"", "sh", cap.vidDir]); }
                                Ico { anchors.centerIn: parent; text: ""; font.pixelSize: 12; color: parent.lit ? cap.cFg : cap.cMuted } }
                            Ctl { id: gearBtn; name: "settings"; sec: "recent"; width: 26; height: 22; base: "transparent"
                                tip: cap.t("Capture settings")
                                onAct: cap.openSettings()
                                Ico { anchors.centerIn: parent; text: ""; font.pixelSize: 12; color: parent.lit ? cap.cFg : cap.cMuted } }
                        }
                    }
                    Item {
                        id: thumbs
                        width: 4 * 68 + 3 * 6; height: 44
                        Lbl { visible: cap.recent.length === 0; anchors.centerIn: parent; text: cap.t("Nothing yet"); color: cap.cMuted; font.pixelSize: 12 }
                        Row {
                            anchors.right: parent.right; spacing: 6
                            Repeater {
                                id: thumbRep
                                model: cap.recent
                                delegate: Ctl {
                                    id: th
                                    required property var modelData
                                    name: "recent:" + modelData.f.split("/").pop()
                                    tip: modelData.f.split("/").pop()
                                    sec: "recent"
                                    width: 68; height: 44; radius: 11; base: "#22ffffff"
                                    onAct: cap.openFile(modelData.f)
                                    ClippingRectangle {
                                        anchors.fill: parent; radius: 11; color: "transparent"
                                        Image { id: tImg; anchors.fill: parent; source: "file://" + th.modelData.t; fillMode: Image.PreserveAspectCrop
                                                sourceSize.width: 240; asynchronous: true; cache: false }
                                    }
                                    Rectangle {     // hover / pick ring over the picture
                                        anchors.fill: parent; radius: 11; color: "transparent"
                                        border.width: th.picked || th.lit ? 2 : 0; border.color: th.picked ? cap.cAccent : "#66ffffff"
                                    }
                                    Ico { anchors.centerIn: parent; visible: tImg.status !== Image.Ready; text: th.modelData.v ? "" : ""; color: cap.cMuted }
                                    Rectangle {
                                        visible: th.modelData.v; anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                                        width: 16; height: 16; radius: 8; color: "#99000000"
                                        Ico { anchors.centerIn: parent; text: ""; font.pixelSize: 7 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }      // mainPage

            // ═════ settings: the same shape, second page ═════
            Item {
                id: setPage
                width: parent.width
                implicitHeight: 44 + Math.max(leftCol.implicitHeight, rightCol.implicitHeight)
                height: implicitHeight
                opacity: cap.page === "settings" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 * Cfg.anim } }
                transform: Translate { x: cap.page === "settings" ? 0 : 40; Behavior on x { NumberAnimation { duration: 300 * Cfg.anim; easing.type: Easing.OutCubic } } }
                function split() { return mapToItem(null, width / 2, 0).x; }

                Row {
                    spacing: 10; height: 30
                    Ctl { id: backBtn; name: "back"; pg: "set"; width: 30; height: 30
                        onAct: cap.back()
                        Ico { anchors.centerIn: parent; text: ""; font.pixelSize: 13 } }
                    Lbl { anchors.verticalCenter: parent.verticalCenter; text: cap.t("Capture settings"); font.pixelSize: 17; font.weight: Font.Bold }
                }
                // a change that restarted the replay says so for a moment
                Rectangle {
                    anchors { right: parent.right; top: parent.top; topMargin: 3 }
                    width: noteT2.implicitWidth + 24; height: 24; radius: 12; color: Cfg.acc(0.14)
                    opacity: cap.note !== "" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Lbl { id: noteT2; anchors.centerIn: parent; text: cap.note; color: cap.cAccent; font.pixelSize: 11; font.weight: Font.DemiBold }
                }

                Row {
                    y: 44; spacing: 32
                    Column {
                        id: leftCol
                        width: (setPage.width - 32) / 2; spacing: 0
                        Group { text: cap.t("Instant Replay") }
                        SRow { label: cap.t("On")
                            Ctl { kind: "switch"; pg: "set"; on: cap.replayOn; onAct: cap.run(["replay-toggle"]) } }
                        SRow { label: cap.t("Length")
                            Repeater { model: [30, 60, 120, 300, 600]
                                delegate: Ctl { kind: "chip"; pg: "set"; required property int modelData; text: cap.mins(modelData); on: cap.total === modelData
                                    onAct: cap.setCfg("replaySeconds", modelData) } } }
                        SRow { label: cap.t("On at login")
                            Ctl { kind: "switch"; pg: "set"; on: cap.cfg.replayAutostart === true; onAct: cap.setCfg("replayAutostart", !(cap.cfg.replayAutostart === true)) } }
                        Group { text: cap.t("Video") }
                        SRow { label: cap.t("Frame rate")
                            Repeater { model: [30, 60, 120, 144, 200]
                                delegate: Ctl { kind: "chip"; pg: "set"; required property int modelData; text: String(modelData); on: (cap.cfg.fps || 60) === modelData
                                    onAct: cap.setCfg("fps", modelData) } } }
                        SRow { label: cap.t("Quality")
                            Repeater { model: [ { v: "medium", t: "Medium" }, { v: "high", t: "High" }, { v: "very_high", t: "Very high" }, { v: "ultra", t: "Ultra" } ]
                                delegate: Ctl { kind: "chip"; pg: "set"; required property var modelData; text: cap.t(modelData.t); on: (cap.cfg.quality || "very_high") === modelData.v
                                    onAct: cap.setCfg("quality", modelData.v) } } }
                        SRow { label: cap.t("Codec")
                            Repeater { model: [ { v: "auto", t: "Auto" }, { v: "h264", t: "H.264" }, { v: "hevc", t: "HEVC" } ]
                                delegate: Ctl { kind: "chip"; pg: "set"; required property var modelData; text: cap.t(modelData.t); on: (cap.cfg.codec || "auto") === modelData.v
                                    onAct: cap.setCfg("codec", modelData.v) } } }
                        SRow { label: cap.t("Monitor")
                            Repeater { model: [ { v: "focused", t: cap.t("Active") } ].concat(Quickshell.screens.slice().sort((a, b) => a.x - b.x).map(sc => ({ v: sc.name, t: sc.name })))
                                delegate: Ctl { kind: "chip"; pg: "set"; required property var modelData; text: modelData.t; on: (cap.cfg.monitor || "focused") === modelData.v
                                    onAct: cap.setCfg("monitor", modelData.v) } } }
                        Group { text: cap.t("Sound") }
                        SRow { label: cap.t("In clips")
                            Repeater { model: [ { v: "desktop", t: "System" }, { v: "mic", t: "Mic" }, { v: "desktop+mic", t: "Both" }, { v: "none", t: "None" } ]
                                delegate: Ctl { kind: "chip"; pg: "set"; required property var modelData; text: cap.t(modelData.t); on: (cap.cfg.audio || "desktop") === modelData.v
                                    onAct: cap.setCfg("audio", modelData.v) } } }
                    }
                    Column {
                        id: rightCol
                        width: (setPage.width - 32) / 2; spacing: 0
                        Group { text: cap.t("Save to") }
                        Ctl {
                            id: folderCtl; name: "folder-field"; pg: "set"
                            width: parent.width; height: 34; radius: 12
                            border.width: picked || fin.activeFocus ? 2 : 0
                            onAct: { fin.forceActiveFocus(); fin.selectAll(); }
                            Ico { id: fIco; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: ""; font.pixelSize: 12; color: cap.cAccent }
                            TextInput {
                                id: fin
                                anchors { left: fIco.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                text: String(cap.cfg.folder || "~/Videos/Clips"); color: cap.cFg; font.family: cap.fUi; font.pixelSize: 13
                                selectionColor: cap.cAccent; selectedTextColor: cap.cAccFg; clip: true
                                onEditingFinished: { if (text.trim() !== "" && text.trim() !== cap.cfg.folder) cap.setCfg("folder", text.trim()); panel.forceActiveFocus(); }
                                Keys.onEscapePressed: { text = String(cap.cfg.folder || ""); panel.forceActiveFocus(); }
                            }
                        }
                        Lbl { text: cap.t("Replays") + " → …/Replays  ·  " + cap.t("Recordings") + " → …/Recordings"; color: cap.cMuted; font.pixelSize: 11; topPadding: 6; bottomPadding: 2 }
                        Group { text: cap.t("Hotkeys") }
                        Repeater {
                            model: [ { k: "menu", t: "This panel" }, { k: "replaySave", t: "Save replay" }, { k: "replayToggle", t: "Replay on/off" },
                                     { k: "record", t: "Record" }, { k: "screenshot", t: "Screenshot" } ]
                            delegate: SRow {
                                required property var modelData
                                label: cap.t(modelData.t)
                                Ctl { kind: "key"; pg: "set"; on: listening; key: modelData.k }
                            }
                        }
                    }
                }
            }
        }
    }
}
