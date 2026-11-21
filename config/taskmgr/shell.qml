// sakura mono - task manager
// standalone window:  qs -n -p ~/.config/taskmgr     (or just `taskmgr`)
// design: one sidebar (pages + live resources), a quiet process table, plain graphs.
// type scale 24 / 15 / 13 / 11, spacing on an 8 px grid, accent only for live data and selection.
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick

ShellRoot {
    id: tm

    // ── palette ────────────────────────────────────────────────
    readonly property color cBg:     "#8c0f1119"          // glass rgba(15,17,25,0.55)
    readonly property color cSide:   "#1f05060a"
    readonly property color cLine:   "#12ffffff"          // hairlines
    readonly property color cHover:  "#0bffffff"
    readonly property color cActive: "#14ffffff"
    readonly property color cField:  "#0fffffff"
    readonly property color cPop:    Qt.rgba(0.075, 0.082, 0.11, 0.97)
    readonly property color cFg:     "#e6e8ef"
    readonly property color cMuted:  "#8b90a0"
    readonly property color cFaint:  "#5c6172"
    property color cAccent: "#f2b8d0"   // from ~/.config/sakura/settings.json "accent"
    FileView { path: Quickshell.env("HOME") + "/.config/sakura/settings.json"; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { const a = JSON.parse(text()).accent; if (/^#[0-9a-fA-F]{6}$/.test(a || "")) tm.cAccent = a; } catch (e) {} } }
    readonly property color cSel:    Qt.rgba(cAccent.r, cAccent.g, cAccent.b, 0.14)
    readonly property color cSecond: Qt.rgba(0.9, 0.91, 0.94, 0.45)   // 2nd series (write / send)
    readonly property color cRed:    "#ff8fa3"
    readonly property string fUi:    "Inter"
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string fMono:  "JetBrainsMono Nerd Font"
    readonly property int fsBig:   24
    readonly property int fsTitle: 15
    readonly property int fsBody:  13
    readonly property int fsSmall: 11
    readonly property string dir:    Quickshell.env("HOME") + "/.config/taskmgr"
    function ic(cp) { return String.fromCodePoint(cp); }

    // ── state ──────────────────────────────────────────────────
    property var sys: null
    property var apps: []
    property var bg: []
    property string page: "processes"
    property string perf: "cpu"
    property string query: ""
    property string sortKey: "cpu"
    property bool sortDesc: true
    property var expanded: ({})
    property string selKey: ""
    property var byKey: ({})
    readonly property var sel: byKey[selKey] || null
    property bool frozen: false     // stop re-sorting while the mouse is over the list

    readonly property int histLen: 60
    property var hCpu: []
    property var hMem: []
    property var hGpu: []
    property var hDiskR: []
    property var hDiskW: []
    property var hNetRx: []
    property var hNetTx: []

    // column widths
    readonly property int cwPid: 80
    readonly property int cwCpu: 112
    readonly property int cwMem: 120
    readonly property int cwDisk: 96
    readonly property int cellsW: cwPid + cwCpu + cwMem + cwDisk

    // ── data ───────────────────────────────────────────────────
    Process {
        id: collector
        running: true
        command: ["python3", tm.dir + "/collect.py", "1"]
        stdout: SplitParser { onRead: data => tm.ingest(data) }
        onExited: restartT.start()
    }
    Timer { id: restartT; interval: 1500; onTriggered: collector.running = true }

    function push(a, v) { const r = a.length >= histLen ? a.slice(1) : a.slice(); r.push(v); return r; }
    function ingest(line) {
        let d; try { d = JSON.parse(line); } catch (e) { return; }
        const s = d.sys;
        sys = s;
        hCpu = push(hCpu, s.cpu);
        hMem = push(hMem, 100 * s.memUsed / s.memTotal);
        hGpu = push(hGpu, s.gpu && s.gpu.util !== undefined ? s.gpu.util : 0);
        hDiskR = push(hDiskR, s.disk.r); hDiskW = push(hDiskW, s.disk.w);
        hNetRx = push(hNetRx, s.net.rx); hNetTx = push(hNetTx, s.net.tx);
        apps = d.apps; bg = d.bg;
        if (page === "processes") rebuild();
    }
    // while the cursor is over the list, rows keep their place (values still update)
    property var prevOrder: ({})
    onFrozenChanged: if (!frozen) rebuild()
    onQueryChanged: rebuild()
    onSortKeyChanged: rebuild()
    onSortDescChanged: rebuild()

    // desktop entries (name + icon) for window classes / process names
    property var entryCache: ({})
    Timer { interval: 30000; running: true; repeat: true; onTriggered: tm.entryCache = ({}) }
    function entryFor(c) {
        if (!c) return null;
        if (c in entryCache) return entryCache[c];
        let e = null;
        try { e = DesktopEntries.heuristicLookup(c); } catch (err) {}
        // don't remember misses until the app list has actually loaded
        if (e || DesktopEntries.applications.values.length > 0) entryCache[c] = e;
        return e;
    }
    function iconFor(name, cls) {
        if (cls) {   // a real app window: trust the desktop entry, then the icon theme
            const e = entryFor(cls);
            if (e && e.icon) { const p = Quickshell.iconPath(e.icon, true); if (p) return p; }
            return Quickshell.iconPath(cls.toLowerCase(), true) || "";
        }
        // background process: only use an icon when a desktop entry clearly is this program
        const e = entryFor(name), n = name.toLowerCase();
        if (e && e.icon && e.id && e.id.toLowerCase().split(".").pop() === n)
            return Quickshell.iconPath(e.icon, true) || "";
        return "";
    }

    function cmp(a, b) {
        if (frozen) {
            const pa = prevOrder[a.key], pb = prevOrder[b.key];
            if (pa !== undefined && pb !== undefined) return pa - pb;
            if (pa !== undefined) return -1;
            if (pb !== undefined) return 1;
        }
        let x, y;
        if (sortKey === "name") { x = a.dn.toLowerCase(); y = b.dn.toLowerCase(); }
        else if (sortKey === "pid") { x = a.pid; y = b.pid; }
        else { x = a[sortKey]; y = b[sortKey]; }
        const c = x < y ? -1 : x > y ? 1 : 0;
        return sortDesc ? -c : c;
    }

    function blank() {
        return { type: "", key: "", name: "", sub: "", icon: "", cpu: 0, mem: 0, disk: 0, count: 0,
                 pid: 0, pids: "", depth: 0, expandable: false, open: false, own: true, susp: false, kind: "", user: "" };
    }
    function rebuild() {
        const q = query.trim().toLowerCase();
        const rows = []; const keys = {};
        const sections = [["sec:apps", "Apps", apps], ["sec:bg", "Background", bg]];
        for (const [skey, sname, list] of sections) {
            const groups = [];
            for (const g of list) {
                const dn = g.kind === "app" ? ((entryFor(g.cls) || {}).name || g.cls) : g.name;
                let kids = g.children; let open = !!expanded[g.key];
                if (q) {
                    const self = (dn + " " + g.name + " " + g.title).toLowerCase().includes(q);
                    const km = kids.filter(c => (c.name + " " + c.cmd + " " + c.pid).toLowerCase().includes(q));
                    if (!self && km.length === 0) continue;
                    if (!self) { kids = km; open = true; }
                }
                groups.push({ key: g.key, g: g, dn: dn, kids: kids, open: open, cpu: g.cpu, mem: g.mem, disk: g.disk, pid: g.pids[0] || 0 });
            }
            if (groups.length === 0) continue;
            const sr = blank(); sr.type = "section"; sr.key = skey; sr.name = sname; sr.count = groups.length;
            rows.push(sr);
            groups.sort(cmp);
            for (const G of groups) {
                const g = G.g;
                const r = blank();
                const single = g.count === 1;
                r.type = "group"; r.key = g.key; r.kind = g.kind; r.name = G.dn;
                r.sub = g.kind === "app" ? (g.title || "") : (single ? (g.children[0].cmd || "") : "");
                r.icon = g.kind === "app" ? iconFor(g.name, g.cls) : iconFor(g.name, "");
                r.cpu = g.cpu; r.mem = g.mem; r.disk = g.disk; r.count = g.count;
                r.pid = single ? g.pids[0] : 0; r.pids = g.pids.join(",");
                r.expandable = !single; r.open = G.open && !single; r.own = g.own;
                r.susp = g.children.length > 0 && g.children.every(c => c.state === "T");
                r.user = g.user || "";
                rows.push(r); keys[r.key] = r;
                if (r.open) {
                    const ks = G.kids.map(c => ({ key: "pid:" + c.pid, c: c, dn: c.name, cpu: c.cpu, mem: c.mem, disk: c.disk, pid: c.pid }));
                    ks.sort(cmp);
                    for (const K of ks) {
                        const c = K.c, p = blank();
                        p.type = "proc"; p.key = "pid:" + c.pid; p.kind = "proc"; p.name = c.name; p.sub = c.cmd;
                        p.cpu = c.cpu; p.mem = c.mem; p.disk = c.disk; p.pid = c.pid; p.pids = String(c.pid);
                        p.depth = 1; p.own = c.own; p.susp = c.state === "T"; p.user = c.user;
                        rows.push(p); keys[p.key] = p;
                    }
                }
            }
        }
        byKey = keys;
        const po = {}; rows.forEach((r, i) => po[r.key] = i); prevOrder = po;
        // push only what changed, so delegates don't re-evaluate every binding every second
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            r.cpu = Math.round(r.cpu * 10) / 10;
            if (i < shownRows.length) {
                const o = shownRows[i];
                for (const k in r) if (o[k] !== r[k]) rowModel.setProperty(i, k, r[k]);
            } else rowModel.append(r);
        }
        if (rowModel.count > rows.length) rowModel.remove(rows.length, rowModel.count - rows.length);
        shownRows = rows;
    }
    property var shownRows: []
    onPageChanged: if (page === "processes") rebuild()
    function toggleOpen(key) {
        const e = Object.assign({}, expanded);
        if (e[key]) delete e[key]; else e[key] = true;
        expanded = e; rebuild();
    }
    function setSort(k) {
        if (sortKey === k) sortDesc = !sortDesc;
        else { sortKey = k; sortDesc = k !== "name" && k !== "pid"; }
    }
    // keyboard selection (↑ / ↓), skipping section rows
    function moveSel(d) {
        const rows = shownRows;
        let i = rows.findIndex(r => r.key === selKey);
        if (i < 0) i = d > 0 ? -1 : rows.length;
        for (i += d; i >= 0 && i < rows.length; i += d) {
            if (rows[i].type !== "section") { selKey = rows[i].key; list.positionViewAtIndex(i, ListView.Contain); return; }
        }
    }
    ListModel { id: rowModel }

    // qs -p ~/.config/taskmgr ipc call taskmgr page performance
    IpcHandler {
        target: "taskmgr"
        function page(p: string): void { if (p === "processes" || p === "performance") tm.page = p; }
        function perf(id: string): void { tm.page = "performance"; tm.perf = id; }
        function search(q: string): void { tm.page = "processes"; searchInput.text = q; }
    }

    // ── actions ────────────────────────────────────────────────
    Process {
        id: sigProc
        property string label: ""
        property var pids: []
        property string sig: ""
        stderr: StdioCollector { id: sigErr }
        onExited: code => {
            if (code === 0) tm.toast(label, "", null);
            else if (sigErr.text.indexOf("not permitted") >= 0)
                tm.toast("No permission to touch " + pids.length + (pids.length === 1 ? " process" : " processes"), "Run as admin",
                         () => Quickshell.execDetached(["pkexec", "kill", "-" + sig].concat(pids)), true);
            else tm.toast("Could not signal: " + sigErr.text.trim().split("\n")[0], "", null, true);
        }
    }
    function signal(key, sig, verb) {
        const r = byKey[key]; if (!r || !r.pids) return;
        if (sigProc.running) return;
        sigProc.pids = r.pids.split(",");
        sigProc.sig = sig;
        sigProc.label = verb + " " + r.name;
        sigProc.command = ["kill", "-" + sig].concat(sigProc.pids);
        sigProc.running = true;
    }
    function endTask(key) { signal(key, "TERM", "Ended"); }
    function forceKill(key) { signal(key, "KILL", "Killed"); }
    function suspend(key) { const r = byKey[key]; if (r) signal(key, r.susp ? "CONT" : "STOP", r.susp ? "Resumed" : "Suspended"); }
    function copy(text, what) { Quickshell.execDetached(["wl-copy", text]); toast("Copied " + what, "", null); }
    function focusApp(key) {
        const r = byKey[key]; if (!r) return;
        const pid = r.pids.split(",")[0];
        Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.focus({ window = 'pid:" + pid + "' })); hl.dispatch(hl.dsp.window.bring_to_top())"]);
    }
    function cmdOf(key) {
        const r = byKey[key]; if (!r) return "";
        const pid = Number(r.pids.split(",")[0]);
        for (const L of [apps, bg]) for (const g of L) for (const c of g.children) if (c.pid === pid) return c.cmd;
        return "";
    }

    // toast
    property string toastText: ""
    property string toastAct: ""
    property var toastFn: null
    property bool toastErr: false
    function toast(t, act, fn, err) { toastText = t; toastAct = act; toastFn = fn; toastErr = !!err; toastT.restart(); }
    Timer { id: toastT; interval: 4000; onTriggered: tm.toastText = "" }

    // ── formatting ─────────────────────────────────────────────
    function fmtBytes(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576) return (b / 1048576).toFixed(b < 10485760 ? 1 : 0) + " MB";
        if (b >= 1024) return Math.round(b / 1024) + " KB";
        return Math.round(b) + " B";
    }
    function fmtRate(b) {
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s";
        if (b >= 1024) return Math.round(b / 1024) + " KB/s";
        return "0 KB/s";
    }
    function fmtBits(b) {
        const v = b * 8;
        if (v >= 1e6) return (v / 1e6).toFixed(1) + " Mbps";
        if (v >= 1e3) return Math.round(v / 1e3) + " Kbps";
        return "0 Kbps";
    }
    function fmtPct(v) { return v < 0.05 ? "0%" : (v < 10 ? v.toFixed(1) : Math.round(v)) + "%"; }
    function fmtUp(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
    }
    function niceMax(v) {
        v = Math.max(v * 1.15, 102400);
        const p = Math.pow(10, Math.floor(Math.log10(v)));
        for (const m of [1, 2, 5, 10]) if (m * p >= v) return m * p;
        return 10 * p;
    }
    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function peakOf(a) { let m = 0; for (const v of a) if (v > m) m = v; return m; }

    // ── performance definitions ────────────────────────────────
    // models are static lists of ids; live values are read by id inside delegates,
    // so nothing gets rebuilt on every tick.
    readonly property bool hasGpu: !!(sys && sys.gpu && sys.gpu.name)
    readonly property var resIds: hasGpu ? ["cpu", "mem", "gpu", "disk", "net"] : ["cpu", "mem", "disk", "net"]
    readonly property var resTitle: ({ cpu: "CPU", mem: "Memory", gpu: "GPU", disk: "Disk", net: "Network" })
    readonly property var perfBig: ({
        cpu:  [["cpu", "Utilization"], ["freq", "Speed"], ["temp", "Temperature"]],
        mem:  [["memUsed", "In use"], ["memAvail", "Available"], ["memPct", "Load"]],
        gpu:  [["gpuUtil", "Utilization"], ["gpuTemp", "Temperature"], ["gpuPower", "Power"]],
        disk: [["diskR", "Read"], ["diskW", "Write"]],
        net:  [["netRx", "Receive"], ["netTx", "Send"]]
    })
    readonly property var perfDet: ({
        cpu:  [["ncpu", "Logical cores"], ["procs", "Processes"], ["threads", "Threads"], ["uptime", "Up time"]],
        mem:  [["memTotal", "Total"], ["memCached", "Cached"], ["swap", "Swap"]],
        gpu:  [["gpuMem", "Memory"], ["gpuClock", "Core clock"], ["gpuFan", "Fan"]],
        disk: [["diskPeakR", "Peak read"], ["diskPeakW", "Peak write"]],
        net:  [["netPeakRx", "Peak receive"], ["netPeakTx", "Peak send"]]
    })
    function val(k) {
        const s = sys; if (!s) return "-";
        const g = s.gpu || {};
        switch (k) {
        case "cpu": return Math.round(s.cpu) + "%";
        case "freq": return s.freq.toFixed(2) + " GHz";
        case "temp": return s.temp !== null && s.temp !== undefined ? Math.round(s.temp) + " °C" : "-";
        case "ncpu": return String(s.ncpu);
        case "procs": return String(s.procs);
        case "threads": return String(s.threads);
        case "uptime": return fmtUp(s.uptime);
        case "memUsed": return fmtBytes(s.memUsed);
        case "memAvail": return fmtBytes(s.memTotal - s.memUsed);
        case "memPct": return Math.round(100 * s.memUsed / s.memTotal) + "%";
        case "memTotal": return fmtBytes(s.memTotal);
        case "memCached": return fmtBytes(s.memCached);
        case "swap": return s.swapTotal ? fmtBytes(s.swapUsed) + " / " + fmtBytes(s.swapTotal) : "off";
        case "gpuUtil": return g.util !== undefined ? Math.round(g.util) + "%" : "-";
        case "gpuTemp": return g.temp !== undefined ? Math.round(g.temp) + " °C" : "-";
        case "gpuPower": return g.power !== undefined ? g.power.toFixed(0) + " W" : "-";
        case "gpuMem": return g.memTotal ? fmtBytes(g.memUsed) + " / " + fmtBytes(g.memTotal) : "-";
        case "gpuClock": return g.clock !== undefined ? Math.round(g.clock) + " MHz" : "-";
        case "gpuFan": return g.fan !== undefined ? Math.round(g.fan) + "%" : "-";
        case "diskR": return fmtRate(s.disk.r);
        case "diskW": return fmtRate(s.disk.w);
        case "diskPeakR": return fmtRate(peakOf(hDiskR));
        case "diskPeakW": return fmtRate(peakOf(hDiskW));
        case "netRx": return fmtBits(s.net.rx);
        case "netTx": return fmtBits(s.net.tx);
        case "netPeakRx": return fmtBits(peakOf(hNetRx));
        case "netPeakTx": return fmtBits(peakOf(hNetTx));
        }
        return "-";
    }
    // one short line under each resource in the sidebar
    function resLine(id) {
        const s = sys; if (!s) return "";
        if (id === "cpu") return Math.round(s.cpu) + "%  ·  " + s.freq.toFixed(2) + " GHz";
        if (id === "mem") return (s.memUsed / 1073741824).toFixed(1) + " / " + (s.memTotal / 1073741824).toFixed(1) + " GB  ·  " + Math.round(100 * s.memUsed / s.memTotal) + "%";
        if (id === "gpu") return Math.round(s.gpu.util) + "%  ·  " + Math.round(s.gpu.temp) + " °C";
        if (id === "disk") return "R " + fmtRate(s.disk.r) + "  W " + fmtRate(s.disk.w);
        if (id === "net") return "↓ " + fmtBits(s.net.rx) + "  ↑ " + fmtBits(s.net.tx);
        return "";
    }
    function resSeries(id) {
        if (id === "cpu") return [hCpu];
        if (id === "mem") return [hMem];
        if (id === "gpu") return [hGpu];
        if (id === "disk") return [hDiskR, hDiskW];
        return [hNetRx, hNetTx];
    }
    function resAuto(id) { return id === "disk" || id === "net"; }

    // ── components ─────────────────────────────────────────────
    component Graph: Canvas {
        id: g
        property var series: []
        property var colors: [tm.cAccent, tm.cSecond]
        property real maxV: 100
        property bool autoScale: false
        property bool fit: false       // sparklines: zoom percent series to their range
        property bool grid: true
        property real lineW: 1.5
        property real fillA: 0.14
        readonly property real peak: { let m = 0; for (const s of series) for (const v of s) m = Math.max(m, v); return m; }
        readonly property real scaleTop: autoScale ? tm.niceMax(peak) : fit ? Math.min(maxV, Math.max(20, Math.ceil(peak * 1.25 / 10) * 10)) : maxV
        onSeriesChanged: if (visible) requestPaint()
        onColorsChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d"); ctx.reset();
            const w = width, h = height;
            if (grid) {
                ctx.lineWidth = 1;
                for (let i = 0; i <= 4; i++) {
                    const y = i === 4 ? h - 0.5 : Math.round(h * i / 4) + 0.5;
                    ctx.strokeStyle = i === 4 ? "rgba(255,255,255,0.10)" : "rgba(255,255,255,0.045)";
                    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
                }
            }
            const step = w / (tm.histLen - 1);
            for (let si = series.length - 1; si >= 0; si--) {
                const s = series[si]; if (!s || s.length < 2) continue;
                const c = colors[si % colors.length];
                const x0 = w - (s.length - 1) * step;
                const ys = s.map(v => h - Math.min(1, Math.max(0, v) / scaleTop) * (h - lineW) - lineW / 2);
                ctx.beginPath(); ctx.moveTo(x0, ys[0]);
                for (let i = 1; i < s.length; i++) {
                    const xa = x0 + (i - 1) * step, xb = x0 + i * step, xm = (xa + xb) / 2;
                    ctx.bezierCurveTo(xm, ys[i - 1], xm, ys[i], xb, ys[i]);
                }
                ctx.lineWidth = si === 0 ? lineW : Math.max(1, lineW - 0.25);
                ctx.strokeStyle = c; ctx.lineJoin = "round"; ctx.stroke();
                if (si === 0 && fillA > 0) {   // only the main series gets a fill
                    ctx.lineTo(w, h); ctx.lineTo(x0, h); ctx.closePath();
                    const gr = ctx.createLinearGradient(0, 0, 0, h);
                    gr.addColorStop(0, tm.rgba(c, fillA)); gr.addColorStop(1, tm.rgba(c, 0.0));
                    ctx.fillStyle = gr; ctx.fill();
                }
            }
        }
    }

    component Label: Text {
        font.family: tm.fUi; font.pixelSize: tm.fsBody; color: tm.cFg
        verticalAlignment: Text.AlignVCenter
    }
    component Num: Label { font.features: { "tnum": 1 } }

    // flat text button, background only on hover
    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool enabledB: true
        property bool strong: false
        signal clicked()
        implicitWidth: bT.implicitWidth + 24
        implicitHeight: 32
        radius: 8
        opacity: enabledB ? 1 : 0.35
        color: !enabledB ? (strong ? tm.cField : "transparent")
             : bMa.pressed ? tm.cActive
             : bMa.containsMouse ? tm.cActive
             : strong ? tm.cField : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
        Label { id: bT; anchors.centerIn: parent; text: b.label; font.weight: Font.Medium
                color: b.strong ? tm.cFg : tm.cMuted }
        MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true; cursorShape: b.enabledB ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (b.enabledB) b.clicked() }
    }

    // numeric table cell with an optional micro-bar (share of the column total)
    component Cell: Item {
        id: cell
        property string text: ""
        property real frac: -1
        property bool dim: false
        height: parent ? parent.height : 32
        Rectangle {
            visible: cell.frac >= 0
            x: 16; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 3; radius: 1.5; color: "#0dffffff"
            Rectangle {
                height: parent.height; radius: 1.5
                width: Math.max(cell.frac > 0.005 ? 2 : 0, Math.min(1, cell.frac) * parent.width)
                color: tm.rgba(tm.cAccent, 0.8)
            }
        }
        Num {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: cell.text
            color: cell.dim ? tm.cFaint : tm.cFg
        }
    }

    component HeadCell: Item {
        id: hc
        property string key: ""
        property string title: ""
        property string total: ""
        property bool alignLeft: false
        height: 48
        readonly property bool active: tm.sortKey === key
        Rectangle { anchors { fill: parent; topMargin: 4; bottomMargin: 4 } radius: 6; color: hcMa.containsMouse ? tm.cHover : "transparent" }
        Column {
            anchors { verticalCenter: parent.verticalCenter
                      right: hc.alignLeft ? undefined : parent.right; rightMargin: 16
                      left: hc.alignLeft ? parent.left : undefined; leftMargin: 12 }
            spacing: 2
            Num { anchors.right: hc.alignLeft ? undefined : parent.right
                  text: hc.total || " "; font.weight: Font.Medium; color: hc.total ? tm.cFg : "transparent" }
            Row {
                anchors.right: hc.alignLeft ? undefined : parent.right; spacing: 4
                Text { visible: hc.active; text: tm.ic(tm.sortDesc ? 0xf0d7 : 0xf0d8); font.family: tm.fIcon; font.pixelSize: 9
                       color: tm.cFg; anchors.verticalCenter: parent.verticalCenter }
                Label { text: hc.title; font.pixelSize: tm.fsSmall; font.weight: Font.Medium
                        color: hc.active ? tm.cFg : tm.cMuted }
            }
        }
        MouseArea { id: hcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tm.setSort(hc.key) }
    }

    // ── window ─────────────────────────────────────────────────
    FloatingWindow {
        id: win
        visible: true
        title: "Task Manager"
        implicitWidth: 1140
        implicitHeight: 740
        color: tm.cBg
        onVisibleChanged: if (!visible) Qt.quit()

        Item {
            id: rootItem
            anchors.fill: parent
            focus: true
            Keys.onPressed: ev => {
                const ctrl = ev.modifiers & Qt.ControlModifier;
                if (ev.key === Qt.Key_F && ctrl) { tm.page = "processes"; searchInput.forceActiveFocus(); ev.accepted = true; }
                else if (ev.key === Qt.Key_Delete && tm.sel) { if (ev.modifiers & Qt.ShiftModifier) tm.forceKill(tm.selKey); else tm.endTask(tm.selKey); ev.accepted = true; }
                else if (ev.key === Qt.Key_Escape) { if (menu.visible) menu.visible = false; else if (tm.query !== "") searchInput.text = ""; else tm.selKey = ""; ev.accepted = true; }
                else if (ev.key === Qt.Key_1 && ctrl) { tm.page = "processes"; ev.accepted = true; }
                else if (ev.key === Qt.Key_2 && ctrl) { tm.page = "performance"; ev.accepted = true; }
                else if (tm.page === "processes" && (ev.key === Qt.Key_Down || ev.key === Qt.Key_Up)) { tm.moveSel(ev.key === Qt.Key_Down ? 1 : -1); ev.accepted = true; }
                else if (tm.page === "processes" && tm.sel && (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter)) {
                    if (tm.sel.expandable) tm.toggleOpen(tm.selKey); else if (tm.sel.kind === "app") tm.focusApp(tm.selKey);
                    ev.accepted = true;
                }
                else if (tm.page === "processes" && tm.sel && tm.sel.expandable && (ev.key === Qt.Key_Right || ev.key === Qt.Key_Left)) {
                    if ((ev.key === Qt.Key_Right) !== tm.sel.open) tm.toggleOpen(tm.selKey);
                    ev.accepted = true;
                }
            }

            // ── sidebar ────────────────────────────────────────
            Rectangle {
                id: side
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 224
                color: tm.cSide
                Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: tm.cLine }

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8; topMargin: 16 }
                    spacing: 0

                    // Processes
                    Rectangle {
                        readonly property bool on: tm.page === "processes"
                        width: parent.width; height: 40; radius: 8
                        color: on ? tm.cActive : pMa.containsMouse ? tm.cHover : "transparent"
                        Label { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: "Processes"; font.weight: Font.Medium; color: parent.on ? tm.cFg : tm.cMuted }
                        Num { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                              text: tm.sys ? tm.sys.procs : ""; font.pixelSize: tm.fsSmall; color: tm.cFaint }
                        MouseArea { id: pMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tm.page = "processes" }
                    }

                    Item { width: 1; height: 16 }
                    Label { leftPadding: 12; height: 24; text: "Performance"; font.pixelSize: tm.fsSmall; font.weight: Font.Medium; color: tm.cFaint }

                    Repeater {
                        model: tm.resIds
                        Rectangle {
                            id: res
                            required property string modelData
                            readonly property bool on: tm.page === "performance" && tm.perf === modelData
                            width: parent.width; height: 56; radius: 8
                            color: on ? tm.cActive : rMa.containsMouse ? tm.cHover : "transparent"
                            Column {
                                anchors { left: parent.left; leftMargin: 12; right: spark.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Label { text: tm.resTitle[res.modelData]; font.weight: Font.Medium; color: res.on ? tm.cFg : tm.cMuted }
                                Num { width: parent.width; elide: Text.ElideRight; text: tm.resLine(res.modelData)
                                      font.pixelSize: tm.fsSmall; color: res.on ? tm.cMuted : tm.cFaint }
                            }
                            Graph {
                                id: spark
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                width: 48; height: 24; grid: false; lineW: 1.25; fillA: res.on ? 0.18 : 0.08
                                colors: res.on ? [tm.cAccent, tm.cSecond] : [tm.rgba(tm.cFg, 0.45), tm.rgba(tm.cFg, 0.22)]
                                series: tm.resSeries(res.modelData); autoScale: tm.resAuto(res.modelData); fit: true
                            }
                            MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { tm.perf = res.modelData; tm.page = "performance"; } }
                        }
                    }
                }

                Num {
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 20; bottomMargin: 16 }
                    text: tm.sys ? tm.sys.threads + " threads  ·  up " + tm.fmtUp(tm.sys.uptime) : ""
                    font.pixelSize: tm.fsSmall; color: tm.cFaint
                }
            }

            // ── content ────────────────────────────────────────
            Item {
                id: content
                anchors { left: side.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 24; topMargin: 16; bottomMargin: 16 }

                // ── PROCESSES ─────────────────────────────────
                Item {
                    id: procPage
                    anchors.fill: parent
                    visible: tm.page === "processes"

                    Item {
                        id: topBar
                        width: parent.width; height: 40
                        Label { anchors.verticalCenter: parent.verticalCenter; text: "Processes"; font.pixelSize: tm.fsTitle; font.weight: Font.DemiBold }
                        Row {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter } spacing: 8
                            Rectangle {
                                width: 256; height: 32; radius: 8; color: tm.cField
                                border.width: 1; border.color: searchInput.activeFocus ? tm.rgba(tm.cAccent, 0.45) : "transparent"
                                Text { id: sIcon; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                       text: tm.ic(0xf002); font.family: tm.fIcon; font.pixelSize: 11; color: tm.cFaint }
                                TextInput {
                                    id: searchInput
                                    anchors { left: sIcon.right; leftMargin: 8; right: sClear.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    color: tm.cFg; font.family: tm.fUi; font.pixelSize: tm.fsBody; clip: true
                                    selectionColor: tm.cSel; selectedTextColor: tm.cFg
                                    onTextChanged: tm.query = text
                                    Keys.onEscapePressed: { if (text !== "") text = ""; else rootItem.forceActiveFocus(); }
                                    Keys.onDownPressed: { rootItem.forceActiveFocus(); tm.moveSel(1); }
                                    Label { anchors.verticalCenter: parent.verticalCenter; visible: !parent.text; text: "Search"; color: tm.cFaint }
                                }
                                Text { id: sClear; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                       visible: searchInput.text !== ""; text: tm.ic(0xf00d); font.family: tm.fIcon; font.pixelSize: 11; color: tm.cMuted
                                       MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: searchInput.text = "" } }
                            }
                            Btn { label: tm.sel && tm.sel.susp ? "Resume" : "Suspend"; enabledB: !!tm.sel; onClicked: tm.suspend(tm.selKey) }
                            Btn { label: "End task"; strong: true; enabledB: !!tm.sel; onClicked: tm.endTask(tm.selKey) }
                        }
                    }

                    // table (no card: header, hairline, rows)
                    Item {
                        id: table
                        anchors { left: parent.left; right: parent.right; top: topBar.bottom; topMargin: 8; bottom: parent.bottom }

                        Item {
                            id: head
                            anchors { left: parent.left; right: parent.right; top: parent.top; rightMargin: 8 }
                            height: 48
                            HeadCell { anchors.left: parent.left; width: parent.width - tm.cellsW; key: "name"; title: "Name"; alignLeft: true }
                            Row {
                                anchors.right: parent.right
                                HeadCell { width: tm.cwPid;  key: "pid";  title: "PID" }
                                HeadCell { width: tm.cwCpu;  key: "cpu";  title: "CPU";    total: tm.sys ? Math.round(tm.sys.cpu) + "%" : "" }
                                HeadCell { width: tm.cwMem;  key: "mem";  title: "Memory"; total: tm.sys ? Math.round(100 * tm.sys.memUsed / tm.sys.memTotal) + "%" : "" }
                                HeadCell { width: tm.cwDisk; key: "disk"; title: "Disk";   total: tm.sys ? tm.fmtRate(tm.sys.disk.r + tm.sys.disk.w) : "" }
                            }
                            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: tm.cLine }
                        }

                        ListView {
                            id: list
                            anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: 4; bottom: parent.bottom; rightMargin: 8 }
                            clip: true
                            model: rowModel
                            boundsBehavior: Flickable.StopAtBounds
                            maximumFlickVelocity: 4000
                            cacheBuffer: 320

                            HoverHandler { id: listHover; onHoveredChanged: tm.frozen = hovered && tm.page === "processes" }

                            delegate: Item {
                                id: rowItem
                                width: list.width
                                height: isSec ? (index === 0 ? 32 : 40) : 32
                                readonly property bool isSec: model.type === "section"
                                readonly property bool isProc: model.type === "proc"
                                readonly property bool selected: !isSec && tm.selKey === model.key

                                // section header: small muted label + count
                                Row {
                                    visible: rowItem.isSec
                                    anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 6 }
                                    spacing: 8
                                    Label { text: model.name; font.pixelSize: tm.fsSmall; font.weight: Font.DemiBold; color: tm.cMuted }
                                    Num { text: model.count; font.pixelSize: tm.fsSmall; color: tm.cFaint }
                                }

                                Rectangle {
                                    visible: !rowItem.isSec && (rowItem.selected || rowMa.containsMouse)
                                    anchors.fill: parent
                                    radius: 6
                                    color: rowItem.selected ? tm.cSel : tm.cHover
                                }

                                // name area
                                Item {
                                    visible: !rowItem.isSec
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: parent.width - tm.cellsW
                                    clip: true

                                    Text {
                                        id: chev
                                        x: 8; anchors.verticalCenter: parent.verticalCenter
                                        width: 12; horizontalAlignment: Text.AlignHCenter
                                        visible: model.expandable
                                        text: tm.ic(0xf054); font.family: tm.fIcon; font.pixelSize: 8; color: tm.cFaint
                                        rotation: model.open ? 90 : 0
                                        Behavior on rotation { NumberAnimation { duration: 120 } }
                                        MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: tm.toggleOpen(model.key) }
                                    }
                                    Item {
                                        id: ico
                                        x: 28; anchors.verticalCenter: parent.verticalCenter
                                        width: 18; height: 18
                                        visible: !rowItem.isProc
                                        IconImage { anchors.fill: parent; visible: model.icon !== ""; source: model.icon; asynchronous: true }
                                        Text { anchors.centerIn: parent; visible: model.icon === ""
                                               text: tm.ic(0xf013); font.family: tm.fIcon; font.pixelSize: 12; color: tm.cFaint }
                                    }
                                    Row {
                                        anchors { left: parent.left; leftMargin: rowItem.isProc ? 56 : 56; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        spacing: 8
                                        Label {
                                            text: model.name
                                            font.weight: rowItem.isProc ? Font.Normal : Font.Medium
                                            color: rowItem.isProc ? tm.cMuted : tm.cFg
                                            elide: Text.ElideRight; width: Math.min(implicitWidth, parent.width * 0.5)
                                        }
                                        Num { visible: model.expandable; text: model.count; color: tm.cFaint }
                                        Rectangle {
                                            visible: model.susp; anchors.verticalCenter: parent.verticalCenter
                                            height: 18; width: suspT.implicitWidth + 12; radius: 4; color: tm.cField
                                            Label { id: suspT; anchors.centerIn: parent; text: "Suspended"; font.pixelSize: tm.fsSmall; color: tm.cMuted }
                                        }
                                        Rectangle {
                                            visible: !model.own && !rowItem.isSec; anchors.verticalCenter: parent.verticalCenter
                                            height: 18; width: usrT.implicitWidth + 12; radius: 4; color: tm.cField
                                            Label { id: usrT; anchors.centerIn: parent; text: model.user; font.pixelSize: tm.fsSmall; color: tm.cMuted }
                                        }
                                        Text {
                                            text: model.sub; visible: text !== ""
                                            font.family: rowItem.isProc ? tm.fMono : tm.fUi
                                            font.pixelSize: rowItem.isProc ? tm.fsSmall : tm.fsBody; color: tm.cFaint
                                            elide: Text.ElideRight
                                            width: Math.max(0, parent.width - x)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                Row {
                                    visible: !rowItem.isSec
                                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                    Cell { width: tm.cwPid;  text: model.pid ? model.pid : ""; dim: true }
                                    Cell { width: tm.cwCpu;  text: tm.fmtPct(model.cpu); dim: model.cpu < 0.05
                                           frac: rowItem.isProc || !tm.sys ? -1 : model.cpu / Math.max(1, tm.sys.cpu) }
                                    Cell { width: tm.cwMem;  text: tm.fmtBytes(model.mem); dim: model.mem < 1048576
                                           frac: rowItem.isProc || !tm.sys ? -1 : model.mem / Math.max(1, tm.sys.memUsed) }
                                    Cell { width: tm.cwDisk; text: tm.fmtRate(model.disk); dim: model.disk < 1024 }
                                }

                                MouseArea {
                                    id: rowMa
                                    anchors.fill: parent
                                    enabled: !rowItem.isSec
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    z: -1
                                    onPressed: mouse => {
                                        tm.selKey = model.key;
                                        rootItem.forceActiveFocus();
                                        if (mouse.button === Qt.RightButton) {
                                            const p = rowItem.mapToItem(rootItem, mouse.x, mouse.y);
                                            menu.open(model.key, p.x, p.y);
                                        }
                                    }
                                    onDoubleClicked: mouse => {
                                        if (model.expandable) tm.toggleOpen(model.key);
                                        else if (model.kind === "app") tm.focusApp(model.key);
                                    }
                                }
                            }

                            // slim scroll indicator
                            Rectangle {
                                visible: list.contentHeight > list.height
                                anchors.right: parent.right; anchors.rightMargin: -6
                                width: 3; radius: 1.5; color: tm.rgba(tm.cFg, 0.16)
                                y: list.visibleArea.yPosition * list.height
                                height: Math.max(32, list.visibleArea.heightRatio * list.height)
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: rowModel.count === 0
                            text: tm.sys ? "Nothing matches “" + tm.query + "”" : "Loading…"
                            color: tm.cMuted
                        }
                    }
                }

                // ── PERFORMANCE ───────────────────────────────
                Item {
                    id: perfPage
                    anchors.fill: parent
                    visible: tm.page === "performance"
                    readonly property bool two: tm.resAuto(tm.perf)

                    Item {
                        id: dHead; width: parent.width; height: 40
                        Label { anchors.verticalCenter: parent.verticalCenter
                                text: tm.resTitle[tm.perf]; font.pixelSize: tm.fsTitle; font.weight: Font.DemiBold }
                        Label { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: !tm.sys ? "" : tm.perf === "cpu" ? tm.sys.cpuName
                                    : tm.perf === "mem" ? tm.fmtBytes(tm.sys.memTotal)
                                    : tm.perf === "gpu" ? (tm.sys.gpu.name || "")
                                    : tm.perf === "disk" ? "All disks" : "All adapters"
                                color: tm.cMuted }
                    }

                    // primary readouts
                    Row {
                        id: big
                        anchors { left: parent.left; top: dHead.bottom; topMargin: 8 }
                        spacing: 48
                        Repeater {
                            model: tm.perfBig[tm.perf]
                            Column {
                                required property var modelData
                                required property int index
                                spacing: 4
                                Row {
                                    spacing: 8
                                    Rectangle { visible: perfPage.two; width: 12; height: 2; radius: 1; anchors.verticalCenter: parent.verticalCenter
                                                color: index === 0 ? tm.cAccent : tm.cSecond }
                                    Label { text: modelData[1]; font.pixelSize: tm.fsSmall; color: tm.cMuted }
                                }
                                Num { text: tm.val(modelData[0]); font.pixelSize: tm.fsBig; font.weight: Font.Medium }
                            }
                        }
                    }

                    // graph with value axis on the right and a time axis below
                    Item {
                        id: gArea
                        anchors { left: parent.left; right: parent.right; top: big.bottom; topMargin: 24 }
                        height: Math.max(176, perfPage.height * 0.44)
                        Graph {
                            id: bigG
                            anchors { left: parent.left; right: parent.right; rightMargin: 56; top: parent.top; bottom: parent.bottom; bottomMargin: 24 }
                            series: tm.resSeries(tm.perf); autoScale: perfPage.two
                        }
                        Repeater {
                            model: 3
                            Num {
                                required property int index
                                x: bigG.width + 8; y: bigG.height * index / 2 - height / 2
                                font.pixelSize: tm.fsSmall; color: tm.cFaint
                                text: {
                                    const v = bigG.scaleTop * (1 - index / 2);
                                    if (!perfPage.two) return Math.round(v) + "%";
                                    if (v === 0) return "0";
                                    return tm.perf === "net" ? tm.fmtBits(v) : tm.fmtRate(v);
                                }
                            }
                        }
                        Num { anchors { left: parent.left; bottom: parent.bottom } font.pixelSize: tm.fsSmall; color: tm.cFaint; text: "60 s" }
                        Num { anchors { right: bigG.right; bottom: parent.bottom } font.pixelSize: tm.fsSmall; color: tm.cFaint; text: "now" }
                    }

                    // per-resource strip: cores / memory composition / vram
                    Item {
                        id: extra
                        anchors { left: parent.left; right: parent.right; rightMargin: 56; top: gArea.bottom; topMargin: 24 }
                        height: tm.perf === "cpu" ? 72 : (tm.perf === "mem" || tm.perf === "gpu") ? 48 : 0
                        visible: height > 0

                        Column {
                            visible: tm.perf === "cpu"
                            width: parent.width; spacing: 8
                            Label { height: 16; text: "Cores"; font.pixelSize: tm.fsSmall; color: tm.cMuted }
                            Row {
                                id: cores
                                readonly property int n: tm.sys ? tm.sys.cores.length : 0
                                width: parent.width; spacing: 4
                                Repeater {
                                    model: cores.n
                                    Column {
                                        required property int index
                                        readonly property real v: tm.sys && tm.sys.cores[index] !== undefined ? tm.sys.cores[index] : 0
                                        width: (cores.width - (cores.n - 1) * cores.spacing) / Math.max(1, cores.n)
                                        spacing: 4
                                        Rectangle {
                                            width: parent.width; height: 32; radius: 3; color: "#0affffff"
                                            Rectangle {
                                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                                height: Math.max(1, parent.height * parent.parent.v / 100); radius: 3
                                                color: tm.rgba(tm.cAccent, 0.75)
                                                // no Behavior here: 16 bars animating every second keep the
                                                // render loop running at monitor refresh (≈10x the app's CPU)
                                            }
                                        }
                                        Num { width: parent.width; horizontalAlignment: Text.AlignHCenter
                                              text: Math.round(parent.v); font.pixelSize: tm.fsSmall; color: tm.cFaint }
                                    }
                                }
                            }
                        }

                        Column {
                            visible: tm.perf === "mem" || tm.perf === "gpu"
                            width: parent.width; spacing: 8
                            Item {
                                width: parent.width; height: 16
                                Label { text: tm.perf === "mem" ? "Composition" : "Dedicated memory"; font.pixelSize: tm.fsSmall; color: tm.cMuted }
                                Row {
                                    anchors.right: parent.right; spacing: 16
                                    Repeater {
                                        model: tm.perf === "mem" ? 2 : 1
                                        Row {
                                            required property int index
                                            spacing: 8
                                            Rectangle { width: 8; height: 8; radius: 2; anchors.verticalCenter: parent.verticalCenter
                                                        color: index === 0 ? tm.cAccent : tm.rgba(tm.cAccent, 0.35) }
                                            Label { text: index === 0 ? "In use" : "Cached"; font.pixelSize: tm.fsSmall; color: tm.cMuted }
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                width: parent.width; height: 6; radius: 3; color: "#0affffff"
                                readonly property real a: !tm.sys ? 0 : tm.perf === "mem" ? tm.sys.memUsed / tm.sys.memTotal
                                                         : (tm.sys.gpu.memTotal ? tm.sys.gpu.memUsed / tm.sys.gpu.memTotal : 0)
                                readonly property real b: !tm.sys || tm.perf !== "mem" ? 0
                                                         : Math.min(tm.sys.memCached, tm.sys.memTotal - tm.sys.memUsed) / tm.sys.memTotal
                                Rectangle { x: parent.width * parent.a; width: parent.width * parent.b; height: parent.height; radius: 3; color: tm.rgba(tm.cAccent, 0.35) }
                                Rectangle { width: parent.width * parent.a; height: parent.height; radius: 3; color: tm.cAccent }
                            }
                        }
                    }

                    // details: two columns of label / value rows with hairlines
                    Grid {
                        id: det
                        anchors { left: parent.left; right: parent.right; rightMargin: 56; top: extra.visible ? extra.bottom : gArea.bottom; topMargin: 16 }
                        columns: 2; columnSpacing: 32
                        Repeater {
                            model: tm.perfDet[tm.perf]
                            Item {
                                required property var modelData
                                width: (det.width - det.columnSpacing) / 2; height: 32
                                Label { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: tm.cMuted }
                                Num { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: tm.val(modelData[0]) }
                                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: tm.cLine }
                            }
                        }
                    }
                }
            }

            // ── context menu ───────────────────────────────────
            MouseArea {
                anchors.fill: parent
                visible: menu.visible
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: menu.visible = false
            }
            Rectangle {
                id: menu
                visible: false
                property string key: ""
                readonly property var row: tm.byKey[key] || null
                onRowChanged: if (!row) visible = false
                function open(k, px, py) {
                    key = k;
                    x = Math.min(px, rootItem.width - width - 8);
                    y = Math.min(py, rootItem.height - height - 8);
                    visible = true;
                }
                width: 208; height: mCol.implicitHeight + 8
                radius: 10; color: tm.cPop; border.width: 1; border.color: tm.cLine
                Column {
                    id: mCol
                    anchors { fill: parent; margins: 4 }
                    Repeater {
                        model: {
                            const r = menu.row; if (!r) return [];
                            const items = [];
                            if (r.kind === "app") items.push({ t: "Switch to", k: "", f: () => tm.focusApp(menu.key) });
                            if (r.expandable) items.push({ t: r.open ? "Collapse" : "Expand", k: "", f: () => tm.toggleOpen(menu.key) });
                            if (items.length) items.push({ sep: true });
                            items.push({ t: "End task", k: "Del", f: () => tm.endTask(menu.key) });
                            items.push({ t: "Force kill", k: "Shift Del", danger: true, f: () => tm.forceKill(menu.key) });
                            items.push({ t: r.susp ? "Resume" : "Suspend", k: "", f: () => tm.suspend(menu.key) });
                            items.push({ sep: true });
                            items.push({ t: r.expandable ? "Copy PIDs" : "Copy PID", k: "", f: () => tm.copy(r.pids.split(",").join(" "), "PID") });
                            items.push({ t: "Copy command line", k: "", f: () => tm.copy(tm.cmdOf(menu.key), "command line") });
                            return items;
                        }
                        Item {
                            required property var modelData
                            width: mCol.width; height: modelData.sep ? 9 : 32
                            Rectangle { visible: !!modelData.sep; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: tm.cLine }
                            Rectangle {
                                visible: !modelData.sep; anchors.fill: parent; radius: 6
                                color: miMa.containsMouse ? (modelData.danger ? tm.rgba(tm.cRed, 0.12) : tm.cActive) : "transparent"
                                Label { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                        text: modelData.t || ""; color: modelData.danger ? tm.cRed : tm.cFg }
                                Label { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                        text: modelData.k || ""; font.pixelSize: tm.fsSmall; color: tm.cFaint }
                                MouseArea { id: miMa; anchors.fill: parent; hoverEnabled: true; enabled: !modelData.sep; cursorShape: Qt.PointingHandCursor
                                            onClicked: { menu.visible = false; modelData.f(); } }
                            }
                        }
                    }
                }
            }

            // ── toast ──────────────────────────────────────────
            Rectangle {
                id: toastBox
                anchors { horizontalCenter: content.horizontalCenter; bottom: parent.bottom; bottomMargin: tm.toastText ? 24 : -56 }
                Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                opacity: tm.toastText ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                height: 40; width: tRow.implicitWidth + 32; radius: 10
                color: tm.cPop; border.width: 1; border.color: tm.toastErr ? tm.rgba(tm.cRed, 0.35) : tm.cLine
                Row {
                    id: tRow; anchors.centerIn: parent; spacing: 16
                    Label { text: tm.toastText; color: tm.toastErr ? tm.cRed : tm.cFg; anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        visible: tm.toastAct !== ""; anchors.verticalCenter: parent.verticalCenter
                        text: tm.toastAct; font.weight: Font.DemiBold; color: tm.cAccent
                        MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                                    onClicked: { const f = tm.toastFn; tm.toastText = ""; if (f) f(); } }
                    }
                }
            }
        }
    }
}
