pragma Singleton
// sakura mono - live data for desktop widgets (time, weather cache, player, cpu/ram)
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: dk
    readonly property string home: Quickshell.env("HOME")

    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: dk.now = new Date() }

    // weather cache (written by ~/.config/hypr/scripts/weather.sh; Settings rewrites it when the location changes)
    property var weather: null
    FileView {
        path: dk.home + "/.cache/sakura-weather.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { dk.weather = JSON.parse(text()); } catch (e) {} }
    }
    // refresh the weather every 20 min (also creates the cache on a fresh install)
    Timer {
        interval: (Cfg.data.weatherEvery || 20) * 60 * 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: Quickshell.execDetached(["sh", "-c", "f=$HOME/.cache/sakura-weather.json; [ -z \"$(find \"$f\" -mmin -" + Math.max(4, (Cfg.data.weatherEvery || 20) - 5) + " 2>/dev/null)\" ] && $HOME/.config/hypr/scripts/weather.sh"])
    }

    readonly property var player: Players.player

    // cpu / ram - only polled while a system-monitor widget (or its preview) is visible
    property int users: 0
    property real cpu: 0
    property real ram: 0
    property real ramUsed: 0
    property real ramTotal: 0
    property real disk: 0
    property var _prev: null
    Process {
        id: sys
        command: ["sh", "-c", "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; df -P / | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const L = this.text.split("\n");
                const c = L[0].trim().split(/\s+/).slice(1).map(Number);
                const idle = c[3] + (c[4] || 0), total = c.reduce((a, b) => a + b, 0);
                if (dk._prev) { const dt = total - dk._prev.t, di = idle - dk._prev.i; if (dt > 0) dk.cpu = Math.max(0, Math.min(1, 1 - di / dt)); }
                dk._prev = { t: total, i: idle };
                const mt = parseInt(L[1].split(/\s+/)[1]), ma = parseInt(L[2].split(/\s+/)[1]);
                dk.ramTotal = mt / 1048576; dk.ramUsed = (mt - ma) / 1048576; dk.ram = (mt - ma) / mt;
                const d = L[3].trim().split(/\s+/); dk.disk = parseInt(d[4]) / 100;
            }
        }
    }
    Timer { interval: 2000; running: dk.users > 0; repeat: true; triggeredOnStart: true; onTriggered: sys.running = true }

    // ── desktop editor (right-click menu > Edit widgets) ─────
    property bool editing: false
    property string editScreen: ""        // the monitor the editor was opened on: its editor takes the keyboard (Esc)
    function edit(scr) { editScreen = scr ? scr.name : Cfg.mainName; editing = true; }
    readonly property int grid: Cfg.data.deskGrid || 0          // snap step in px, 0 = off
    IpcHandler {
        target: "widgets"
        function edit(): void { if (dk.editing) dk.editing = false; else dk.edit(null); }
        // the editor without taking the keyboard (for screenshots / scripts)
        function peek(): void { if (dk.editing) dk.editing = false; else { dk.editScreen = ""; dk.editing = true; } }
    }

    // ── visualizer: cava, only while a visualizer widget is visible ──
    property int vizUsers: 0
    property var bars: []
    // cava.conf is written from Settings > Desktop widgets > Visualizer (bars, sensitivity, smoothing, fps)
    readonly property string cavaConf:
        "[general]\nbars = " + (Cfg.data.vizBars || 48) + "\nframerate = " + (Cfg.data.vizFps || 60) +
        "\nautosens = " + (Cfg.data.vizAutosens === false ? 0 : 1) + "\nsensitivity = " + (Cfg.data.vizSens || 100) +
        "\n[input]\nmethod = pipewire\nsource = " + (Players.stream.replace(/[\n=]/g, " ") || "auto") + "\n[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\nascii_max_range = 100\nbar_delimiter = 59\nframe_delimiter = 10\n" +
        "[smoothing]\nnoise_reduction = " + (typeof Cfg.data.vizSmooth === "number" ? Cfg.data.vizSmooth : 70) + "\nmonstercat = " + (Cfg.data.vizMonstercat === true ? 1 : 0) + "\n"
    onCavaConfChanged: if (Cfg.loaded) cavaWrite.restart()
    readonly property bool cfgReady: Cfg.loaded          // write it once on start too (the source follows the player)
    onCfgReadyChanged: if (cfgReady) cavaWrite.restart()
    Timer { id: cavaWrite; interval: 400; onTriggered: { cavaFile.setText(dk.cavaConf); cava.running = false; cavaRun.restart(); } }
    Timer { id: cavaRun; interval: 300; onTriggered: cava.running = Qt.binding(() => dk.vizUsers > 0) }   // keep it a binding (the notch joins / leaves too)
    FileView { id: cavaFile; path: dk.home + "/.config/sakura/cava.conf" }
    Process {
        id: cava
        running: dk.vizUsers > 0
        command: ["cava", "-p", dk.home + "/.config/sakura/cava.conf"]
        stdout: SplitParser { onRead: l => { const a = l.split(";").filter(x => x !== "").map(x => parseInt(x) / 100); if (a.length) dk.bars = a; } }
        onRunningChanged: if (!running) dk.bars = []
    }

    // ── hardware (cpu/gpu load + temps): hypr/scripts/perf.sh ──
    property int hwUsers: 0
    property var hw: null
    Process {
        id: hwProc
        command: [dk.home + "/.config/hypr/scripts/perf.sh"]
        stdout: StdioCollector { onStreamFinished: { try { dk.hw = JSON.parse(this.text); } catch (e) {} } }
    }
    Timer { interval: 2000; running: dk.hwUsers > 0; repeat: true; triggeredOnStart: true; onTriggered: hwProc.running = true }

    // ── world clock: utc offsets of the cities (refreshed hourly, DST) ──
    property var tzOff: ({})
    Process {
        id: tzProc
        command: ["sh", "-c", "for z in \"$@\"; do printf '%s %s\\n' \"$z\" \"$(TZ=$z date +%z)\"; done", "sh"].concat(Cfg.worldClocks.map(c => c.tz))
        stdout: StdioCollector { onStreamFinished: {
            const o = {};
            this.text.trim().split("\n").forEach(l => { const p = l.split(" "); const s = p[1] || "+0000";
                o[p[0]] = (s[0] === "-" ? -1 : 1) * (parseInt(s.slice(1, 3)) * 60 + parseInt(s.slice(3, 5))); });
            dk.tzOff = o;
        } }
    }
    Timer { interval: 3600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: tzProc.running = true }
    function timeIn(tz) {
        const off = tzOff[tz]; if (off === undefined) return null;
        return new Date(now.getTime() + now.getTimezoneOffset() * 60000 + off * 60000);
    }

    // ── sticky note + to-do (~/.config/sakura/desknote.txt, todo.json) ──
    property string note: ""
    FileView {
        id: noteFile
        path: dk.home + "/.config/sakura/desknote.txt"
        onLoaded: dk.note = text()
        onLoadFailed: dk.note = ""
    }
    Timer { id: noteSave; interval: 600; onTriggered: noteFile.setText(dk.note) }
    function setNote(s) { note = s; noteSave.restart(); }

    property var todos: []          // [{ t: "text", done: false }]
    FileView {
        id: todoFile
        path: dk.home + "/.config/sakura/todo.json"
        onLoaded: { try { dk.todos = JSON.parse(text()); } catch (e) { dk.todos = []; } }
    }
    function saveTodos(l) { todos = l; todoFile.setText(JSON.stringify(l, null, 1)); }
    function addTodo(s) { s = s.trim(); if (s !== "") saveTodos(todos.concat([{ t: s, done: false }])); }
    function toggleTodo(i) { saveTodos(todos.map((x, k) => k === i ? { t: x.t, done: !x.done } : x)); }
    function removeTodo(i) { saveTodos(todos.filter((x, k) => k !== i)); }
    function clearDone() { saveTodos(todos.filter(x => !x.done)); }

    // ── wallpaper brightness (hypr/scripts/wallluma.sh: 32×18 grid) → dark text on light spots ──
    property var luma: []
    Process {
        id: lumaProc
        command: [dk.home + "/.config/hypr/scripts/wallluma.sh", Cfg.data.wallpaper || ""]
        stdout: StdioCollector { onStreamFinished: dk.luma = this.text.trim().split(/\s+/).map(Number).filter(x => !isNaN(x)) }
    }
    Connections { target: Cfg; function onDataChanged() { if (Cfg.data.wallpaper !== dk.lumaFor) { dk.lumaFor = Cfg.data.wallpaper || ""; lumaT.restart(); } } }
    property string lumaFor: ""
    Timer { id: lumaT; interval: 300; onTriggered: { lumaProc.running = false; lumaProc.running = true; } }
    Component.onCompleted: { lumaFor = Cfg.data.wallpaper || ""; lumaT.start(); }
    // average brightness (0..255) of the wallpaper under a rectangle of the main screen
    function lumaAt(x, y, w, h) {
        if (luma.length !== 576) return 0;
        const sw = Cfg.mainScreen ? Cfg.mainScreen.width : 1920, sh = Cfg.mainScreen ? Cfg.mainScreen.height : 1080;
        const c0 = Math.max(0, Math.floor(x / sw * 32)), c1 = Math.min(31, Math.floor((x + w) / sw * 32));
        const r0 = Math.max(0, Math.floor(y / sh * 18)), r1 = Math.min(17, Math.floor((y + h) / sh * 18));
        let s = 0, n = 0;
        for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) { s += luma[r * 32 + c]; n++; }
        return n ? s / n : 0;
    }

    function greeting() {
        const h = now.getHours();
        return Cfg.tr(h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening");
    }
}
