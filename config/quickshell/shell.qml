//@ pragma UseQApplication
// sakura mono - start menu (opens on the Win key)
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

ShellRoot {
    id: root

    // ── palette ─────────────────────────────────────────────
    readonly property color cBg:      root.glassNow
    // over a fullscreen game hyprland game mode turns blur off, so the see-through glass would show the game: go near-solid then
    readonly property color glassNow: fsUnder ? Qt.rgba(15 / 255, 17 / 255, 25 / 255, Math.max(0.94, Cfg.glassAlpha)) : Cfg.glass
    readonly property color cCard:    "#14ffffff"
    readonly property color cHover:   "#22ffffff"
    readonly property color cBorder:  "#1fffffff"
    readonly property color cFg:      "#eceef4"
    readonly property color cMuted:   "#8a8fa3"
    readonly property color cAccent:  Cfg.accent
    readonly property color cAccFg:   Cfg.accFg
    readonly property string fUi:     Cfg.fontUi
    readonly property string fIcon:   "Symbols Nerd Font"
    readonly property string home:    Quickshell.env("HOME")
    readonly property string user:    Quickshell.env("USER")

    Settings { id: settings }
    readonly property var screenTime: ScreenTime      // starts counting (ScreenTime.qml)
    readonly property var devices: Devices            // polls wireless device batteries, says low / connect in the notch (Devices.qml)
    Switcher { id: switcher }
    Capture { id: capture }
    Media { id: media }
    Dashboard { id: dashboard; topBar: topBar }
    Mixer { id: mixer; topBar: topBar }
    DesktopWidgets { id: desktopWidgets }
    Snap { id: snap }
    Autoscroll { id: autoscroll }
    LyricsOverlay { id: lyricsOverlay }
    Repeat { id: repeatHelper }
    Mic { id: micStudio }
    Tray { id: trayFlyout; topBar: topBar }
    Sketch { id: sketchPad }
    Notes { id: notesPad }
    EdgeTab { sketch: sketchPad; notes: notesPad }
    NetMenu { id: netMenu; topBar: topBar }
    PowerMenu { id: powerMenu; topBar: topBar; session: sessionScreen }
    SessionScreen { id: sessionScreen }
    Wallpaper { id: wallpaper; desktopMenu: desktopMenu; lock: lockScreen }
    WallPicker { id: wallPicker; settings: settings }
    DesktopMenu { id: desktopMenu; settings: settings; picker: wallPicker }
    Clipboard { id: clipboard }
    Archive { id: archiveDlg }
    Shot { id: shotEditor }               // screenshot editor (HolyScreen-style), opened by hypr/scripts/screenshot.sh
    Convert { id: converter }             // radial file converter (drag files to a screen edge), hypr/scripts/convert.py
    PasswordHelper { id: pwHelper; lock: lockScreen }   // radial password helper (Ctrl+Shift+P), PwVault.qml + hypr/scripts/pwhelper.py
    SakuraCam { id: sakuraCam; topBar: topBar }         // iPhone as a webcam: panel from the notch (Super+Alt+C), CamLink.qml + hypr/scripts/sakura-cam
    NotifPopups { id: notifPopups }
    Lock { id: lockScreen; topBar: topBar }
    Mascot { id: mascot; lock: lockScreen }
    HotCorners { id: hotCorners; converter: converter }
    Greeting { id: greeting }
    NotifCenter { id: notifCenter; topBar: topBar; settings: settings }
    TopBar { id: topBar; genie: genie; tray: trayFlyout; dashboard: dashboard; mixer: mixer; netMenu: netMenu; powerMenu: powerMenu; notifCenter: notifCenter; camPanel: sakuraCam }
    Genie { id: genie; topBar: topBar }
    CornerIsland { id: cornerIsland; topBar: topBar; settings: settings }

    property bool open: false
    // the dock the open start menu grows out of (its top corners go square meanwhile)
    readonly property var menuFlowsInto: win.attached && win.grow > 0.02 ? (menuOnMain ? mainDock : overlayDock) : null
    // the monitor the menu opens on: the one you are using right now
    property var menuScreen: Cfg.mainScreen
    property bool fsUnder: false     // a fullscreen app (game) is under the menu
    function pickScreen() {
        const m = Hyprland.focusedMonitor;
        const sc = m ? Quickshell.screens.find(s => s.name === m.name) : null;
        if (sc) menuScreen = sc;
        fsProc.running = true;
    }
    Process {
        id: fsProc
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { root.fsUnder = JSON.parse(this.text).hasfullscreen === true; } catch (e) { root.fsUnder = false; } } }
    }
    // keep fsUnder fresh (the dock's glass goes solid over a game, back to see-through after it)
    Connections { target: Hyprland
        function onRawEvent(e) { if (/^(fullscreen|workspace|focusedmon|activewindow|closewindow)/.test(e.name)) fsT.restart(); } }
    Timer { id: fsT; interval: 300; onTriggered: fsProc.running = true }
    readonly property bool menuOnMain: menuScreen && menuScreen.name === Cfg.mainName
    property bool allApps: false

    // start-menu building blocks (chosen in Settings > Start menu, see Cfg.qml)
    function toggleDef(id) {
        const sc = root.home + "/.config/hypr/scripts/";
        const src = Pipewire.defaultAudioSource;
        switch (id) {
        case "vpn": return Cfg.has.mullvad ? { icon: "\uf023", label: Cfg.tr(root.vpnText), on: root.vpnOn, act: root.vpnOn ? "mullvad disconnect" : "mullvad connect", keep: true } : null;
        case "dnd": return { icon: Notifs.dnd ? "\uf1f6" : "\uf0f3", label: Cfg.tr(Notifs.dnd ? "Silent" : "Alerts"), on: Notifs.dnd, keep: true, fn: () => Notifs.toggleDnd() };
        case "screenshot": return { icon: "\uf030", label: Cfg.tr("Screenshot"), on: false, act: "sleep 0.4; " + sc + "screenshot.sh region" };
        case "color": return Cfg.has.hyprpicker ? { icon: "\uf1fb", label: Cfg.tr("Color"), on: false, act: "sleep 0.3; hyprpicker -a -n" } : null;
        case "clipboard": return { icon: "\uf0ea", label: Cfg.tr("Clipboard"), on: false, act: sc + "clipboard.sh" };
        case "mic": return { icon: src && src.audio && src.audio.muted ? "\uf131" : "\uf130", label: Cfg.tr("Microphone"), on: !!(src && src.audio && !src.audio.muted),
                             keep: true, fn: () => { if (src && src.audio) src.audio.muted = !src.audio.muted; } };
        case "night": return { icon: "\uf186", label: Cfg.tr("Night light"), on: (settings.cfg.warmth || 0) > 0, keep: true,
                               fn: () => settings.setCfg("warmth", (settings.cfg.warmth || 0) > 0 ? 0 : 0.5) };
        case "taskmgr": return { icon: "\uf0e4", label: Cfg.tr("Task Manager"), on: false, act: "$HOME/.local/bin/taskmgr" };
        case "barpos": return { icon: "\uf2d0", label: Cfg.tr("Bar position"), on: false, act: sc + "barpos.sh toggle" };
        case "lock": return { icon: "\uf023", label: Cfg.tr("Lock"), on: false, act: Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh" };
        // Sakura Cam: on / pause while the iPhone is connected, else the panel with the QR code
        case "cam": return { icon: "\uf10b", label: CamLink.streaming ? Cfg.tr("Streaming") : "Sakura Cam", on: CamLink.streaming,
                             keep: CamLink.connected, fn: () => { if (CamLink.connected) CamLink.stream(!CamLink.want); else Quickshell.execDetached(["sh", "-c", "sleep 0.25; qs ipc call cam open"]); } };
        }
        return null;
    }
    function powerDef(id) {
        const save = root.home + "/.config/hypr/scripts/session.py save; ";
        switch (id) {
        case "lock":     return { id: "lock", icon: "\uf023", tip: Cfg.tr("Lock"),      act: Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh" };
        case "logout":   return { id: "logout", icon: "\uf08b", tip: Cfg.tr("Log out"),   act: save + "uwsm stop || hyprctl dispatch 'hl.dsp.exit()'" };
        case "sleep":    return { id: "sleep", icon: "\uf186", tip: Cfg.tr("Sleep"),     act: "systemctl suspend" };
        case "restart":  return { id: "restart", icon: "\uf01e", tip: Cfg.tr("Restart"),   act: save + "systemctl reboot" };
        case "shutdown": return { id: "shutdown", icon: "\uf011", tip: Cfg.tr("Shut down"), act: save + "systemctl poweroff" };
        }
        return null;
    }

    property real openedAt: 0
    property bool grabOn: false
    function show()   { pickScreen(); search.text = ""; allApps = false; openedAt = Date.now(); open = true; grabOn = true; }
    function hide()   { open = false; mctxOpen = false; grabOn = false; if (ctxInMenu) { ctxOpen = false; ctxInMenu = false; } }
    function toggle() { open ? hide() : show(); }
    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); hide(); }

    IpcHandler {
        target: "menu"
        function toggle(): void { root.toggle(); }
        function open(): void   { root.show(); }
        function close(): void  { root.hide(); }
        function query(q: string): void { root.show(); search.text = q; }
        function menuctx(i: int): void { root.show(); root.openMctx(root.pinned[i], Qt.point(140, 260)); }
        function topctx(i: int): void { if (!root.open) root.show(); root.mctxOpen = false; root.ctxApp = root.dockApps[i]; root.ctxX = 350; root.ctxInMenu = true; root.ctxOpen = true; }
        function dockctx(i: int): void { root.ctxInMenu = false; root.ctxApp = root.dockApps[i]; root.ctxX = mainDock.width / 2; root.ctxOpen = true; }
    }

    // ── live state ──────────────────────────────────────────
    PwObjectTracker { objects: [ Pipewire.defaultAudioSink ] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var player: Players.player

    property bool vpnOn: false
    property string vpnText: "VPN"
    property bool dndOn: false
    property string uptime: ""

    Process {
        id: vpnProc
        command: ["sh", "-c", "mullvad status 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                root.vpnOn = t.startsWith("Connected");
                root.vpnText = t.startsWith("Connected") ? "VPN on" : (t.startsWith("Connecting") ? "VPN…" : "VPN off");
            }
        }
    }
    Process {
        id: dndProc
        command: ["true"]
        stdout: StdioCollector { onStreamFinished: root.dndOn = this.text.trim() === "true" }
    }
    Process {
        id: upProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector { onStreamFinished: {
            const t = Math.floor(parseFloat(this.text)), d = Math.floor(t / 86400), h = Math.floor(t % 86400 / 3600), m = Math.floor(t % 3600 / 60);
            root.uptime = (d > 0 ? d + " " + Cfg.tr("d") + " " : "") + (d > 0 || h > 0 ? h + " " + Cfg.tr("h") + " " : "") + m + " " + Cfg.tr("min");
        } }
    }
    Timer {
        interval: 2000; running: root.open; repeat: true; triggeredOnStart: true
        onTriggered: { vpnProc.running = true; dndProc.running = true; upProc.running = true; }
    }

    // ── apps ────────────────────────────────────────────────
    property var menuPinned: [
        "brave-browser", "firefox", "org.kde.dolphin", "kitty", "discord", "code-oss",
        "org.gnome.TextEditor", "org.gnome.Calculator", "org.gnome.Loupe", "mpv",
        "mullvad-vpn", "btop"
    ]
    FileView {
        id: menuFile
        path: root.home + "/.config/quickshell/menu.json"
        blockLoading: true
        onLoaded: { try { const j = JSON.parse(text()); if (Array.isArray(j.pinned)) root.menuPinned = j.pinned; } catch (e) {} }
    }
    function menuIsPinned(id) { return menuPinned.indexOf(id) >= 0; }
    function menuTogglePin(id) {
        const l = menuIsPinned(id) ? menuPinned.filter(x => x !== id) : menuPinned.concat([id]);
        menuPinned = l; menuFile.setText(JSON.stringify({ pinned: l }, null, 2));
    }
    // start-menu right-click
    property var mctxApp: null
    property point mctxPos: Qt.point(0, 0)
    property bool mctxOpen: false
    // windows of an app (by its dock key) - for "close" / "force quit" in the start menu's right-click menu
    function winsOf(key) { const d = dockApps.find(x => x.key === key); return d ? d.wins : []; }
    function mctxDo(a, it) {
        if (!a || !it || it.sep) return;
        const sh = root.home + "/.config/hypr/scripts/appctx.sh";
        root.mctxOpen = false;
        switch (it.act) {
        case "open": a.execute(); root.hide(); break;
        case "da": it.da.execute(); root.hide(); break;
        case "start": root.menuTogglePin(a.id); break;
        case "dock": root.togglePin({ key: a.id.toLowerCase(), entry: a }); break;
        case "close": root.winsOf(a.id.toLowerCase()).forEach(w => w.close()); break;
        case "locate": case "edit": case "uninstall": case "kill":
            Quickshell.execDetached([sh, it.act, a.id]); if (it.act !== "kill") root.hide(); break;
        }
    }
    function openMctx(app, pos) { mctxApp = app; mctxPos = pos; mctxOpen = true; }
    readonly property var everyApp: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .slice().sort((a, b) => a.name.localeCompare(b.name))
    readonly property var pinned: menuPinned.map(id => everyApp.find(e => e.id === id)).filter(e => e)
    readonly property var results: {
        const q = search.text.trim().toLowerCase();
        if (q === "") return everyApp;
        return everyApp.filter(e =>
            e.name.toLowerCase().includes(q) ||
            (e.genericName || "").toLowerCase().includes(q) ||
            (e.keywords || []).join(" ").toLowerCase().includes(q));
    }
    readonly property bool searching: search.text.trim() !== ""


    // ── smart search: calculator, currency, commands, apps, files, web ──
    property int selIndex: 0
    property var fx: null                       // currency rates (base USD)
    Process {
        id: fxProc
        command: ["curl", "-s", "--max-time", "6", "https://open.er-api.com/v6/latest/USD"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(this.text); if (d.rates) root.fx = d.rates; } catch (e) {} } }
    }
    property var fileHits: []
    property string fileQuery: ""
    Process {
        id: findProc
        stdout: StdioCollector { onStreamFinished: root.fileHits = this.text.split("\n").filter(x => x !== "").slice(0, 8) }
    }
    Timer {
        id: findTimer; interval: 280
        onTriggered: {
            let q = search.text.trim();
            // files: off in Settings, or another prefix; "/" = files only
            if (q.startsWith("/")) q = q.slice(1).trim();
            else if (Cfg.data.searchFiles === false || /^[>?=]/.test(q)) { root.fileHits = []; return; }
            if (q.length < 3 || root.calcValue(q) !== null) { root.fileHits = []; return; }
            root.fileQuery = q;
            findProc.running = false;
            findProc.command = ["sh", "-c",
                "timeout 2 find \"$HOME\" -maxdepth 6 \\( -path '*/.*' -o -path '*/node_modules' \\) -prune -o -iname \"*$1*\" -print 2>/dev/null | head -8; " +
                "timeout 2 find /mnt -maxdepth 4 -iname \"*$1*\" -print 2>/dev/null | head -6", "sh", q];
            findProc.running = true;
        }
    }
    Connections { target: search; function onTextChanged() { root.selIndex = 0; findTimer.restart(); if (!root.fx && /[a-z]{3}\s*(to|in|в)\s*[a-z]{3}/i.test(search.text)) fxProc.running = true; } }

    function calcValue(q) {
        let e = q.replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/").replace(/\^/g, "**").toLowerCase();
        e = e.replace(/(\d+(?:\.\d+)?)\s*%\s*(of|от)\s*(\d+(?:\.\d+)?)/g, "($1/100*$3)");
        if (!/[\d)]/.test(e) || !/[-+*/%()]|sqrt|sin|cos|tan|log|pi/.test(e)) return null;
        if (!/^[\d\s.+\-*/%()a-z]+$/.test(e)) return null;
        const names = ["sqrt","sin","cos","tan","log","pi","abs","round","floor","ceil","pow"];
        const words = e.match(/[a-z]+/g) || [];
        if (words.some(w => names.indexOf(w) < 0)) return null;
        e = e.replace(/\b(sqrt|sin|cos|tan|abs|round|floor|ceil|pow)\b/g, "Math.$1").replace(/\blog\b/g, "Math.log10").replace(/\bpi\b/g, "Math.PI");
        try { const v = Function("return (" + e + ")")(); return (typeof v === "number" && isFinite(v)) ? v : null; } catch (err) { return null; }
    }
    function fmtNum(v) { return Math.abs(v) >= 1e15 || (Math.abs(v) < 1e-6 && v !== 0) ? v.toExponential(6) : String(Math.round(v * 1e8) / 1e8); }
    function fxConvert(q) {
        const m = q.match(/^\s*(\d+(?:[.,]\d+)?)\s*([a-z]{3})\s*(?:to|in|в|->)\s*([a-z]{3})\s*$/i);
        if (!m || !fx) return null;
        const a = parseFloat(m[1].replace(",", ".")), f = m[2].toUpperCase(), t = m[3].toUpperCase();
        if (!fx[f] || !fx[t]) return null;
        return { text: (Math.round(a / fx[f] * fx[t] * 100) / 100).toLocaleString(Qt.locale("en_US"), "f", 2) + " " + t, sub: a + " " + f + " → " + t };
    }
    readonly property var commands: [
        { k: ["lock", "блок", "заблок"],            t: "Lock screen",      g: "\uf023", run: () => Quickshell.execDetached([root.home + "/.config/hypr/scripts/lock.sh"]) },
        { k: ["reboot", "restart", "перезагр"],      t: "Restart",          g: "\uf01e", run: () => Choreo.leave("restart") },
        { k: ["shutdown", "power off", "poweroff", "выключ"], t: "Shut down", g: "\uf011", run: () => Choreo.leave("shutdown") },
        { k: ["sleep", "suspend", "сон", "спать"],   t: "Sleep",            g: "\uf186", run: () => Quickshell.execDetached(["systemctl", "suspend"]) },
        { k: ["logout", "log out", "выход", "выйти"], t: "Log out",         g: "\uf08b", run: () => Quickshell.execDetached(["sh", "-c", "uwsm stop || hyprctl dispatch 'hl.dsp.exit()'"]) },
        { k: ["settings", "настройк", "параметр"],  t: "Settings",         g: "\uf013", run: () => settings.openPage("sound") },
        { k: ["sound", "звук", "audio", "громк"],    t: "Sound settings",   g: "\uf028", run: () => settings.openPage("sound") },
        { k: ["display", "monitor", "монитор", "экран"], t: "Displays",     g: "\uf108", run: () => settings.openPage("display") },
        { k: ["color", "vibrance", "цвет"],          t: "Color Control",    g: "\uf042", run: () => settings.openPage("color") },
        { k: ["rgb", "light", "подсвет"],            t: "Lighting",         g: "\uf0eb", run: () => settings.openPage("lighting") },
        { k: ["wifi", "network", "сеть", "vpn"],     t: "Network & VPN",    g: "\uf0e8", run: () => settings.openPage("network") },
        { k: ["screenshot", "скрин"],                t: "Screenshot",       g: "\uf030", run: () => Quickshell.execDetached(["sh", "-c", "sleep 0.4; " + root.home + "/.config/hypr/scripts/screenshot.sh region"]) },
        { k: ["record", "replay", "clip", "запис", "клип"], t: "Capture (Alt+Z)", g: "\uf03d", run: () => Quickshell.execDetached(["qs", "ipc", "call", "capture", "open"]) },
        { k: ["weather", "погод"],                   t: "Weather",          g: "\uf0c2", run: () => Quickshell.execDetached(["qs", "ipc", "call", "dashboard", "open", "weather"]) },
        { k: ["clipboard", "буфер"],                 t: "Clipboard history", g: "\uf0ea", run: () => Quickshell.execDetached([root.home + "/.config/hypr/scripts/clipboard.sh"]) },
        { k: ["keybind", "hotkey", "клавиш"],        t: "Keybinds",         g: "\uf11c", run: () => Quickshell.execDetached([root.home + "/.config/hypr/scripts/keybinds.sh"]) }
    ]
    // Settings > Start menu > Search: engine, what to look through, prefixes (> command · ? web · / files · = calculator)
    readonly property var engines: ({
        google: "https://www.google.com/search?q=", ddg: "https://duckduckgo.com/?q=", brave: "https://search.brave.com/search?q=",
        yandex: "https://yandex.ru/search/?text=", bing: "https://www.bing.com/search?q=", youtube: "https://www.youtube.com/results?search_query="
    })
    function webUrl(q) { return (engines[Cfg.data.searchEngine || "google"] || engines.google) + encodeURIComponent(q); }
    readonly property var items: {
        let raw = search.text.trim(), q = raw.toLowerCase();
        const out = [];
        if (q === "") return everyApp.map(e => ({ kind: "app", entry: e, title: e.name, sub: e.genericName || "" }));
        if (Cfg.data.searchPrefixes !== false) {
            if (raw.startsWith(">")) {
                const cmd = raw.slice(1).trim();
                return cmd === "" ? [{ kind: "info", title: Cfg.tr("Type a command to run"), sub: "", glyph: "\uf120" }]
                                  : [{ kind: "shell", title: cmd, sub: Cfg.tr(Cfg.data.searchShellTerm === true ? "Run in the terminal" : "Run"), glyph: "\uf120", cmd: cmd }];
            }
            if (raw.startsWith("?")) {
                const w = raw.slice(1).trim();
                return [{ kind: "web", title: Cfg.tr("Search the web for") + " “" + w + "”", sub: "", glyph: "\uf002", q: w }];
            }
            if (raw.startsWith("/")) return fileHits.map(f => ({ kind: "file", path: f, title: f.split("/").pop(), sub: f.replace(root.home, "~"), glyph: "\uf15b" }));
            if (raw.startsWith("=")) { raw = raw.slice(1).trim(); const v = calcValue(raw);
                return v !== null ? [{ kind: "calc", title: "= " + fmtNum(v), sub: Cfg.tr("Enter to copy"), glyph: "", copy: fmtNum(v) }] : []; }
        }
        const v = calcValue(raw);
        if (v !== null) out.push({ kind: "calc", title: "= " + fmtNum(v), sub: Cfg.tr("Enter to copy"), glyph: "", copy: fmtNum(v) });
        const c = fxConvert(raw);
        if (c) out.push({ kind: "calc", title: c.text, sub: c.sub + " · Enter to copy", glyph: "\uf155", copy: c.text });
        else if (/^\s*\d+(?:[.,]\d+)?\s*[a-z]{3}\s*(to|in|в|->)\s*[a-z]{3}\s*$/i.test(raw) && !fx)
            out.push({ kind: "info", title: "Getting exchange rates…", sub: "", glyph: "\uf021" });
        if (Cfg.data.searchCommands !== false) commands.forEach(cm => { if (cm.k.some(k => k.startsWith(q) || q.startsWith(k))) out.push({ kind: "cmd", title: cm.t, sub: Cfg.tr("command"), glyph: cm.g, run: cm.run }); });
        results.slice(0, Cfg.data.searchApps || 8).forEach(e => out.push({ kind: "app", entry: e, title: e.name, sub: e.genericName || "" }));
        fileHits.forEach(f => out.push({ kind: "file", path: f, title: f.split("/").pop(), sub: f.replace(root.home, "~"), glyph: "\uf15b" }));
        if (Cfg.data.searchWeb !== false) out.push({ kind: "web", title: Cfg.tr("Search the web for") + " “" + raw + "”", sub: "", glyph: "\uf002", q: raw });
        return out;
    }
    function runItem(it, alt) {
        if (!it) return;
        if (it.kind === "app") it.entry.execute();
        else if (it.kind === "calc") Quickshell.execDetached(["wl-copy", it.copy]);
        else if (it.kind === "cmd") it.run();
        else if (it.kind === "file") Quickshell.execDetached(["xdg-open", alt ? it.path.replace(/\/[^/]*$/, "") : it.path]);
        else if (it.kind === "web") Quickshell.execDetached(["xdg-open", webUrl(it.q)]);
        else if (it.kind === "shell") Quickshell.execDetached(Cfg.data.searchShellTerm === true ? ["kitty", "--hold", "sh", "-c", it.cmd] : ["sh", "-c", it.cmd]);
        else return;
        root.hide();
    }

    // ── window ──────────────────────────────────────────────
    PanelWindow {
        id: win
        // flows out of the dock on the main monitor: one glass shape with an S-curved neck down into the dock's hill.
        // Elsewhere (other monitor, a game underneath, dock tucked away) it is a plain card above the dock, as before.
        // (on the other monitor the menu brings its own copy of the dock, overlayDock, so it attaches there too)
        readonly property bool attached: !(root.menuOnMain && root.fsUnder) && Cfg.data.dockAutoHide !== true
        // attached: the window reaches down to the screen edge and the menu IS the dock's hill, grown taller and wider
        // (same ears into the edge); the dock hides its own row meanwhile (dockRow opacity), the copy below rides up instead
        readonly property int neck: attached ? 60 : 0
        readonly property int earW: 22
        readonly property int earH: 16
        readonly property real panelH: Math.max(560, banner.height + 16 + homeCol.implicitHeight + 20)
        property real grow: root.open ? 1 : 0
        Behavior on grow { NumberAnimation { duration: 360 * Cfg.anim; easing.type: Easing.OutCubic } }
        visible: root.open || grow > 0.001
        screen: root.menuScreen
        anchors.bottom: true
        margins.bottom: attached ? 0 : ((root.menuOnMain && root.fsUnder) ? 146 : 74)
        implicitWidth: 700 + 2 * earW
        // height follows what Settings > Start menu shows (but keeps room for search results)
        implicitHeight: panelH + neck
        mask: Region { item: panel; Region { item: dockCopy } }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "startmenu"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        HyprlandFocusGrab {
            windows: overlayDock.visible ? [ win, mainDock, overlayDock ] : [ win, mainDock ]   // clicks on the dock count as "inside" the menu
            active: root.grabOn
            onCleared: {
                // a fullscreen game grabs focus back right after the menu opens: ignore that, re-grab
                if (Date.now() - root.openedAt < 700) { root.grabOn = false; regrab.restart(); return; }
                root.hide();
            }
        }
        Timer { id: regrab; interval: 60; onTriggered: if (root.open) root.grabOn = true }

        // the glass: the dock's hill grows up and out into the menu (DEF → OPEN), one shape with ears into the screen edge
        Canvas {
            id: menuShape
            anchors.fill: parent
            readonly property real hill: root.menuOnMain ? (mainDock ? mainDock.hillW : 520) : (overlayDock ? overlayDock.hillW : 520)
            readonly property string key: [win.grow, width, height, hill, win.neck, root.glassNow].join(",")
            onKeyChanged: requestPaint()
            onPaint: {
                const c = getContext("2d"); c.reset();
                const W = width, H = height, g = win.grow, k = 0.5523, ex = win.earW, ey = win.earH;
                if (win.attached) {
                    // closed = exactly the dock's hill (hill wide, 60 tall); open = the whole menu + the dock row
                    const w = hill + (W - 2 * ex - hill) * g, hh = 60 + (H - 60) * g;
                    const x0 = (W - w) / 2, x1 = x0 + w, top = H - hh, r = 24 + 2 * g;
                    c.beginPath();
                    c.moveTo(x0 - ex, H);
                    c.bezierCurveTo(x0 - ex + ex * k, H, x0, H - ey + ey * k, x0, H - ey);       // left ear into the edge
                    c.lineTo(x0, top + r);
                    c.bezierCurveTo(x0, top + r - r * k, x0 + r - r * k, top, x0 + r, top);
                    c.lineTo(x1 - r, top);
                    c.bezierCurveTo(x1 - r + r * k, top, x1, top + r - r * k, x1, top + r);
                    c.lineTo(x1, H - ey);
                    c.bezierCurveTo(x1, H - ey + ey * k, x1 + ex - ex * k, H, x1 + ex, H);      // right ear
                    c.closePath();
                    c.fillStyle = root.glassNow;
                    c.fill();

                } else {
                    // plain card above the dock (other cases): grows up a little and fades
                    const r = 26, top = (1 - g) * 16, bot = H - (1 - g) * 0;
                    c.globalAlpha = Math.min(1, g * 1.4);
                    c.beginPath();
                    c.moveTo(ex + r, top); c.lineTo(W - ex - r, top);
                    c.bezierCurveTo(W - ex - r + r * k, top, W - ex, top + r - r * k, W - ex, top + r);
                    c.lineTo(W - ex, bot - r);
                    c.bezierCurveTo(W - ex, bot - r + r * k, W - ex - r + r * k, bot, W - ex - r, bot);
                    c.lineTo(ex + r, bot);
                    c.bezierCurveTo(ex + r - r * k, bot, ex, bot - r + r * k, ex, bot - r);
                    c.lineTo(ex, top + r);
                    c.bezierCurveTo(ex, top + r - r * k, ex + r - r * k, top, ex + r, top);
                    c.closePath();
                    c.fillStyle = root.glassNow;
                    c.fill();
                }
            }
        }

        // the dock's row, lifted: it rides on the top edge of the growing hill, the menu opens under it
        Row {
            id: dockCopy
            visible: win.attached
            readonly property real rideY: (win.height - 60) * (1 - win.grow)
            anchors.horizontalCenter: parent.horizontalCenter
            y: rideY
            height: 60
            spacing: 4
            Item {
                width: 48; height: 60
                Avatar {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 9
                    width: 42; height: 42; ringColor: root.cAccent
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.hide() }
            }
            Item { width: 9; height: 60
                Rectangle { anchors.centerIn: parent; width: 1; height: 30; color: root.cBorder } }
            Repeater {
                model: root.dockApps
                delegate: Item {
                    id: cslot
                    required property var modelData
                    readonly property bool running: modelData.wins.length > 0
                    readonly property bool active: modelData.wins.some(w => w.activated)
                    readonly property int sz: Cfg.data.dockIcon || 38
                    width: sz + 14; height: 60
                    IconImage {   // scale, not implicitSize (see the dock below: no twitching)
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: cslot.sz + 4
                        y: Math.round((60 - implicitSize) / 2) - 1
                        scale: cma.containsMouse ? 1 : cslot.sz / (cslot.sz + 4)
                        source: Quickshell.iconPath(cslot.modelData.entry ? cslot.modelData.entry.icon : cslot.modelData.key, "application-x-executable")
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 4 }
                        height: 4; radius: 2
                        width: cslot.active ? 18 : (cslot.running ? 6 : 0)
                        color: cslot.active ? root.cAccent : root.cMuted
                    }
                    property int cycle: 0
                    MouseArea {
                        id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        // same as a click on the real dock icon
                        onClicked: m => {
                            const a = cslot.modelData, wins = a.wins;
                            if (m.button === Qt.RightButton) {
                                root.mctxOpen = false;
                                root.ctxApp = a;
                                root.ctxX = cslot.mapToItem(panel, cslot.width / 2, 0).x;
                                root.ctxInMenu = true;
                                root.ctxOpen = true;
                                return;
                            }
                            root.ctxOpen = false; root.ctxInMenu = false;
                            root.hide();
                            if (m.button === Qt.MiddleButton || wins.length === 0) {
                                if (a.entry) a.entry.execute();
                                return;
                            }
                            if (wins.length === 1 && wins[0].activated) {
                                Quickshell.execDetached([root.home + "/.config/hypr/scripts/minimize.sh", "hide"]);
                                return;
                            }
                            cslot.cycle = (cslot.cycle + 1) % wins.length;
                            if (!genie.bringBack(wins[cslot.cycle])) wins[cslot.cycle].activate();
                            Quickshell.execDetached(["sh", "-c", "sleep 0.08; hyprctl eval 'hl.dispatch(hl.dsp.window.bring_to_top())'"]);
                        }
                    }
                }
            }
        }

        ClippingRectangle {
            id: panel
            anchors { top: parent.top; topMargin: win.attached ? 60 : 0; horizontalCenter: parent.horizontalCenter }
            width: 700
            height: win.panelH
            radius: 26
            color: "transparent"

            // the content fades in once the glass has nearly grown (and out first when closing)
            opacity: Math.max(0, (win.grow - 0.55) / 0.45)

            Keys.onEscapePressed: root.hide()

            // ── header: the wallpaper melting into the glass, who is here + power, search on top ──
            // one rhythm for the whole menu: 20 px sides, 16 px between sections, cards r18, tiles r14, buttons r12
            Item {
                id: banner
                readonly property bool art: Cfg.data.menu.banner !== false
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: art ? 168 : 128
                // the desktop's wallpaper (a video plays here too while the menu is open), faded out into the glass
                Item {
                    id: bannerArt
                    anchors.fill: parent
                    visible: false
                    layer.enabled: banner.art
                    WallThumb {
                        anchors.fill: parent
                        visible: banner.art
                        file: Cfg.data.wallpaper || ""
                        size: 900
                        live: root.open && banner.art
                    }
                }
                Rectangle {
                    id: bannerFade
                    anchors.fill: parent
                    visible: false
                    layer.enabled: banner.art
                    gradient: Gradient {
                        GradientStop { position: 0.0;  color: "#ffffffff" }
                        GradientStop { position: 0.25; color: "#ffffffff" }
                        GradientStop { position: 1.0;  color: "#00ffffff" }
                    }
                }
                MultiEffect {
                    anchors.fill: parent
                    visible: banner.art
                    source: bannerArt
                    maskEnabled: true
                    maskSource: bannerFade
                    maskThresholdMin: 0.5     // (0.5, 1.0) = a soft ramp; (0, x) shows no fade at all
                    maskSpreadAtMin: 1.0
                }
                // a soft shade at the top so the name and the buttons read on any wallpaper
                Rectangle {
                    visible: banner.art
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 76
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#800f1119" }
                        GradientStop { position: 1.0; color: "#000f1119" }
                    }
                }

                // who is here
                Row {
                    id: who
                    visible: Cfg.data.menu.user !== false
                    anchors { left: parent.left; leftMargin: 20; top: parent.top; topMargin: 18 }
                    spacing: 12
                    Avatar { width: 40; height: 40; ringColor: root.cAccent }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text { text: root.user; color: root.cFg; font.family: root.fUi; font.pixelSize: 15; font.weight: Font.Bold }
                        Text { text: Cfg.tr("up") + " " + root.uptime; color: Qt.rgba(1, 1, 1, 0.62); font.family: root.fUi; font.pixelSize: 11 }
                    }
                }

                // Settings, one tap away (same glass as the power pill)
                Rectangle {
                    id: gearBtn
                    anchors { right: powerPill.visible ? powerPill.left : parent.right; rightMargin: powerPill.visible ? 8 : 20
                              verticalCenter: powerPill.visible ? powerPill.verticalCenter : undefined
                              top: powerPill.visible ? undefined : parent.top; topMargin: 18 }
                    width: 44; height: 44; radius: 14
                    color: gearArea.containsMouse ? root.cAccent : "#4d0f1119"
                    border.width: 1; border.color: gearArea.containsMouse ? root.cAccent : root.cBorder
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Text { anchors.centerIn: parent; text: ""; font.family: root.fIcon; font.pixelSize: 16
                        color: gearArea.containsMouse ? root.cAccFg : root.cFg
                        rotation: gearArea.containsMouse ? 60 : 0
                        Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } } }
                    MouseArea { id: gearArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { settings.openPage("sound"); root.hide(); } }
                }

                // power, in one glass pill
                Rectangle {
                    id: powerPill
                    visible: pwRep.count > 0
                    anchors { right: parent.right; rightMargin: 20; verticalCenter: who.visible ? who.verticalCenter : undefined; top: who.visible ? undefined : parent.top; topMargin: 18 }
                    width: pwRow.width + 8; height: 44; radius: 14
                    color: "#4d0f1119"
                    border.width: 1; border.color: root.cBorder
                    Row {
                        id: pwRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            id: pwRep
                            model: Cfg.data.menu.powerList.map(id => root.powerDef(id)).filter(p => p)
                            delegate: Rectangle {
                                required property var modelData
                                width: 36; height: 36; radius: 11
                                color: pwArea.containsMouse ? root.cAccent : "transparent"
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Text { anchors.centerIn: parent; text: modelData.icon; font.family: root.fIcon; font.pixelSize: 14
                                    color: pwArea.containsMouse ? root.cAccFg : root.cFg }
                                MouseArea { id: pwArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.hide(); Choreo.leave(modelData.id); } }   // the leave choreography (Choreo.qml)
                            }
                        }
                    }
                }

                // search box
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 20; rightMargin: 20 }
                    height: 46; radius: 14
                    color: search.activeFocus ? "#b3141720" : "#99141720"
                    border.width: 1
                    border.color: search.activeFocus ? Cfg.acc(0.7) : root.cBorder
                    Behavior on border.color { ColorAnimation { duration: 160 } }
                    Text {
                        id: sIcon
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        text: ""; font.family: root.fIcon; font.pixelSize: 16; color: root.cAccent
                    }
                    TextInput {
                        id: search
                        anchors { left: sIcon.right; right: allPill.visible ? allPill.left : parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        color: root.cFg; font.family: root.fUi; font.pixelSize: 15
                        selectionColor: root.cAccent
                        focus: root.open
                        clip: true
                        Keys.onEscapePressed: root.hide()
                        Keys.onReturnPressed: root.runItem(root.items[root.selIndex])
                        Keys.onEnterPressed: root.runItem(root.items[root.selIndex])
                        Keys.onDownPressed: { root.selIndex = Math.min(root.items.length - 1, root.selIndex + 1); list.positionViewAtIndex(root.selIndex, ListView.Contain); }
                        Keys.onUpPressed: { root.selIndex = Math.max(0, root.selIndex - 1); list.positionViewAtIndex(root.selIndex, ListView.Contain); }
                        onTextChanged: if (text !== "") root.allApps = false
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Cfg.tr("Search apps, files, 2+2, 1000 jpy to usd…")
                            color: root.cMuted; font: search.font
                            visible: search.text === ""
                        }
                    }
                    Rectangle {
                        id: allPill
                        anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                        width: allTxt.implicitWidth + 40; height: 32; radius: 10
                        color: allArea.containsMouse ? Cfg.acc(0.22) : Cfg.acc(0.12)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        visible: !root.searching
                        MouseArea { id: allArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.allApps = !root.allApps }
                    Text {
                        id: allTxt
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: root.allApps ? 26 : 12 }
                        text: root.allApps ? Cfg.tr("Pinned") : Cfg.tr("All apps")
                        // the chevron is its own glyph in the icon font, so it sits centred instead of glued to the word
                        Text {
                            anchors { verticalCenter: parent.verticalCenter; verticalCenterOffset: 0.5 }
                            x: root.allApps ? -15 : parent.implicitWidth + 7
                            text: root.allApps ? "" : parent.chev
                            font.family: root.fIcon; font.pixelSize: 9
                            color: parent.color
                        }
                        readonly property string chev: ""
                        font.family: root.fUi; font.pixelSize: 12; font.weight: Font.DemiBold
                        color: allArea.containsMouse ? root.cFg : root.cAccent
                    }
                    }
                }
            }

            // ── main content ───────────────────────────────
            Item {
                id: body
                anchors { top: banner.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20; topMargin: 16 }

                // search results / all apps list
                ListView {
                    id: list
                    anchors.fill: parent
                    visible: root.searching || root.allApps
                    clip: true
                    spacing: 2
                    model: root.items
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool sel: root.searching && index === root.selIndex
                        width: list.width; height: modelData.kind === "calc" ? 56 : 46; radius: 12
                        color: sel ? Cfg.acc(0.15) : (rowArea.containsMouse ? root.cHover : "transparent")
                        border.width: sel ? 1 : 0; border.color: Cfg.acc(0.33)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Item {
                            id: rowIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: 28; height: 28
                            IconImage { anchors.fill: parent; visible: modelData.kind === "app"
                                source: modelData.kind === "app" ? Quickshell.iconPath(modelData.entry.icon, "application-x-executable") : "" }
                            Text { anchors.centerIn: parent; visible: modelData.kind !== "app"; text: modelData.glyph || ""
                                font.family: root.fIcon; font.pixelSize: 17; color: root.cAccent }
                        }
                        Column {
                            anchors { left: rowIcon.right; leftMargin: 14; right: openDir.visible ? openDir.left : parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text { width: parent.width; elide: Text.ElideMiddle; text: modelData.title
                                color: root.cFg; font.family: root.fUi; font.pixelSize: modelData.kind === "calc" ? 20 : 14
                                font.weight: modelData.kind === "calc" ? Font.Bold : Font.Normal }
                            Text { width: parent.width; elide: Text.ElideMiddle; visible: text !== ""; text: modelData.sub || ""
                                color: root.cMuted; font.family: root.fUi; font.pixelSize: 11 }
                        }
                        Rectangle {
                            id: openDir
                            visible: modelData.kind === "file"
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            width: 30; height: 30; radius: 10; color: odA.containsMouse ? root.cHover : "transparent"
                            Text { anchors.centerIn: parent; text: "\uf07c"; font.family: root.fIcon; font.pixelSize: 13; color: root.cMuted }
                            MouseArea { id: odA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.runItem(modelData, true) }
                        }
                        MouseArea { id: rowArea; anchors.fill: parent; anchors.rightMargin: openDir.visible ? 44 : 0
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: m => {
                                if (m.button === Qt.RightButton && modelData.kind === "app") { root.openMctx(modelData.entry, mapToItem(panel, m.x, m.y)); return; }
                                root.runItem(modelData);
                            } }
                    }
                }

                // home view
                Column {
                    id: homeCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    visible: !list.visible
                    spacing: 16

                    // a quiet section label (same for every section)
                    component Label: Text {
                        color: root.cMuted; font.family: root.fUi; font.pixelSize: 11; font.weight: Font.Bold
                        font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2
                        leftPadding: 4
                    }

                    // pinned
                    Label { visible: pinGrid.visible; text: Cfg.tr("Pinned") }
                    Grid {
                        id: pinGrid
                        visible: Cfg.data.menu.pinned !== false
                        columns: 6
                        columnSpacing: 4; rowSpacing: 4
                        width: parent.width
                        Repeater {
                            model: root.pinned.slice(0, 6 * (Cfg.data.menu.pinnedRows || 2))
                            delegate: Rectangle {
                                required property var modelData
                                width: (pinGrid.width - 5 * 4) / 6; height: 84; radius: 14
                                color: pinArea.containsMouse ? root.cHover : "transparent"
                                scale: pinArea.pressed ? 0.94 : 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 7
                                    IconImage {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        implicitSize: 38
                                        source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 92; horizontalAlignment: Text.AlignHCenter
                                        text: modelData.name; elide: Text.ElideRight
                                        color: root.cFg; font.family: root.fUi; font.pixelSize: 11
                                    }
                                }
                                MouseArea { id: pinArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: m => {
                                        if (m.button === Qt.RightButton) { root.openMctx(modelData, mapToItem(panel, m.x, m.y)); return; }
                                        modelData.execute(); root.hide();
                                    } }
                            }
                        }
                    }

                    // controls: volume + quick toggles share one card
                    Rectangle {
                        id: ctlCard
                        // from the settings, not volRow/qtRow.visible: a child's visible is false while this card is hidden,
                        // so after one search (home view hidden) the card stayed hidden for good
                        visible: Cfg.data.menu.volume !== false || (Cfg.data.menu.toggles !== false && qtRep.count > 0)
                        width: parent.width; height: ctlCol.implicitHeight + 20; radius: 18
                        color: root.cCard
                        border.width: 1; border.color: "#0affffff"
                    Column {
                        id: ctlCol
                        x: 10; y: 10; width: parent.width - 20
                        spacing: 10
                    // volume
                    Item {
                        id: volRow
                        visible: Cfg.data.menu.volume !== false
                        width: parent.width; height: 40
                        Text {
                            id: volIcon
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: (root.sink && root.sink.audio && root.sink.audio.muted) ? "" : ""
                            font.family: root.fIcon; font.pixelSize: 17; color: root.cAccent
                            MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted }
                        }
                        Item {
                            id: track
                            anchors { left: volIcon.right; right: volPct.left; leftMargin: 16; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            height: 22
                            readonly property real v: (root.sink && root.sink.audio) ? Math.min(1, root.sink.audio.volume) : 0
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: "#26ffffff" }
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * track.v; height: 6; radius: 3; color: root.cAccent }
                            Rectangle { x: parent.width * track.v - 8; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: "#ffffff" }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                function setAt(mx) { if (root.sink && root.sink.audio) root.sink.audio.volume = Math.round(Math.max(0, Math.min(1, mx / width)) * 20) / 20; }
                                onPressed: m => setAt(m.x)
                                onPositionChanged: m => { if (pressed) setAt(m.x); }
                                onWheel: w => { if (root.sink && root.sink.audio) root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05))); }
                            }
                        }
                        Text {
                            id: volPct
                            anchors { right: soundBtn.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: Math.round(track.v * 100) + "%"; width: 40; horizontalAlignment: Text.AlignRight
                            color: root.cFg; font.family: root.fUi; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Rectangle {
                            id: soundBtn
                            anchors { right: parent.right; rightMargin: 0; verticalCenter: parent.verticalCenter }
                            width: 36; height: 36; radius: 12
                            color: sbArea.containsMouse ? root.cHover : "transparent"
                            Text { anchors.centerIn: parent; text: ""; font.family: root.fIcon; font.pixelSize: 15; color: root.cFg }
                            MouseArea { id: sbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { settings.openPage("sound"); root.hide(); } }
                        }
                    }

                    // quick toggles (which ones + order: Settings > Start menu)
                    Row {
                        id: qtRow
                        visible: Cfg.data.menu.toggles !== false && qtRep.count > 0
                        width: parent.width
                        spacing: 8
                        Repeater {
                            id: qtRep
                            model: Cfg.data.menu.toggleList.map(id => root.toggleDef(id)).filter(t => t)
                            delegate: Rectangle {
                                required property var modelData
                                width: (qtRow.width - (qtRep.count - 1) * 8) / Math.max(1, qtRep.count); height: 64; radius: 14
                                color: modelData.on ? root.cAccent : (tArea.containsMouse ? root.cHover : "#0dffffff")
                                Behavior on color { ColorAnimation { duration: 160 } }
                                scale: tArea.pressed ? 0.94 : 1
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Column {
                                    anchors.centerIn: parent; spacing: 6
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon
                                        font.family: root.fIcon; font.pixelSize: 18; color: modelData.on ? root.cAccFg : root.cFg }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label
                                        font.family: root.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: modelData.on ? root.cAccFg : root.cFg }
                                }
                                MouseArea { id: tArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.fn) { modelData.fn(); if (!modelData.keep) root.hide(); refresh.restart(); return; }
                                        if (modelData.keep) { Quickshell.execDetached(["sh", "-c", modelData.act]); refresh.restart(); }
                                        else root.run(modelData.act);
                                    } }
                            }
                        }
                    }
                    }   // ctlCol
                    }   // ctlCard
                    Timer { id: refresh; interval: 600; onTriggered: { vpnProc.running = true; dndProc.running = true; } }

                    // settings shortcuts
                    Label { visible: setGrid.visible; text: Cfg.tr("Settings") }
                    Grid {
                        id: setGrid
                        visible: Cfg.data.menu.shortcuts !== false && Cfg.data.menu.shortcutList.length > 0
                        width: parent.width
                        columns: 3; columnSpacing: 8; rowSpacing: 8
                        Repeater {
                            model: Cfg.data.menu.shortcutList.map(id => Cfg.shortcutCatalog.find(c => c.id === id)).filter(c => c)
                                .map(c => ({ icon: c.icon, label: Cfg.tr(c.name), page: c.id }))
                            delegate: Rectangle {
                                required property var modelData
                                width: (setGrid.width - 2 * 8) / 3; height: 42; radius: 12
                                color: setArea.containsMouse ? root.cHover : "#0dffffff"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Row {
                                    anchors { left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    spacing: 10
                                    Rectangle {
                                        width: 30; height: 30; radius: 9; color: Cfg.acc(setArea.containsMouse ? 0.24 : 0.13)
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text { anchors.centerIn: parent; text: modelData.icon; font.family: root.fIcon; font.pixelSize: 13; color: root.cAccent }
                                    }
                                    Text { width: parent.width - 40; elide: Text.ElideRight; text: modelData.label; font.family: root.fUi; font.pixelSize: 13; color: root.cFg; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { id: setArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (modelData.page === "sakuracam") Quickshell.execDetached(["sh", "-c", "sleep 0.25; qs ipc call cam open"]); else settings.openPage(modelData.page); root.hide(); } }   // Sakura Cam: its panel, not the page
                            }
                        }
                    }

                    // media player
                    Rectangle {
                        visible: root.player !== null && Cfg.data.menu.media !== false
                        width: parent.width; height: 64; radius: 18; color: root.cCard
                        border.width: 1; border.color: "#0affffff"
                        ClippingRectangle {
                            id: art
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: 44; height: 44; radius: 11
                            color: "transparent"
                            visible: artImg.status === Image.Ready
                            Image {
                                id: artImg
                                anchors.fill: parent
                                source: root.player ? (root.player.trackArtUrl || "") : ""
                                fillMode: Image.PreserveAspectCrop
                            }
                        }
                        Column {
                            anchors { left: art.visible ? art.right : parent.left; leftMargin: 14; right: ctrls.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            Text { width: parent.width; elide: Text.ElideRight; text: root.player ? (root.player.trackTitle || Cfg.tr("Nothing playing")) : ""
                                color: root.cFg; font.family: root.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideRight; text: root.player ? (root.player.trackArtist || root.player.identity || "") : ""
                                color: root.cMuted; font.family: root.fUi; font.pixelSize: 12 }
                        }
                        Row {
                            id: ctrls
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            Repeater {
                                model: [ "prev", "play", "next" ]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: 36; height: 36; radius: modelData === "play" ? 18 : 12
                                    color: modelData === "play" ? root.cAccent : (mArea.containsMouse ? root.cHover : "transparent")
                                    Text { anchors.centerIn: parent; font.family: root.fIcon; font.pixelSize: 13
                                        color: modelData === "play" ? root.cAccFg : root.cFg
                                        text: modelData === "prev" ? "" : modelData === "next" ? ""
                                            : (root.player && root.player.isPlaying ? "" : "") }
                                    MouseArea { id: mArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.player) return;
                                            if (modelData === "prev") root.player.previous();
                                            else if (modelData === "next") root.player.next();
                                            else root.player.togglePlaying();
                                        } }
                                }
                            }
                        }
                    }
                }
            }

            // right-click menu for apps
            MouseArea {
                anchors.fill: parent
                visible: root.mctxOpen || (root.ctxOpen && root.ctxInMenu)
                z: 50
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: { root.mctxOpen = false; if (root.ctxInMenu) { root.ctxOpen = false; root.ctxInMenu = false; } }
            }
            // right-click menu of the dock row on top (same items as on the real dock)
            Rectangle {
                id: dctx
                visible: root.ctxOpen && root.ctxInMenu
                z: 51
                width: 240
                height: dctxCol.implicitHeight + 16
                x: Math.max(10, Math.min(panel.width - width - 10, root.ctxX - width / 2))
                y: 6
                radius: 16
                color: "#f20f1119"
                border.width: 1; border.color: root.cBorder
                Keys.onEscapePressed: { root.ctxOpen = false; root.ctxInMenu = false; }
                Column {
                    id: dctxCol
                    x: 8; y: 8; width: parent.width - 16; spacing: 2
                    Row {
                        spacing: 10; leftPadding: 8; topPadding: 4; bottomPadding: 6
                        IconImage { implicitSize: 22; anchors.verticalCenter: parent.verticalCenter
                            source: root.ctxApp ? Quickshell.iconPath(root.ctxApp.entry ? root.ctxApp.entry.icon : root.ctxApp.key, "application-x-executable") : "" }
                        Text { anchors.verticalCenter: parent.verticalCenter; color: root.cFg; font.family: root.fUi; font.pixelSize: 13; font.weight: Font.Bold
                            text: root.ctxApp ? (root.ctxApp.entry ? root.ctxApp.entry.name : root.ctxApp.key) : "" }
                    }
                    Rectangle { width: parent.width; height: 1; color: root.cBorder }
                    Repeater {
                        model: dctx.visible ? root.ctxItems(root.ctxApp) : []
                        delegate: Rectangle {
                            required property var modelData
                            width: dctxCol.width; height: 38; radius: 10
                            color: dca.containsMouse ? (modelData.danger ? "#33f28fad" : root.cHover) : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Text { id: dci; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } width: 18
                                text: modelData.icon; font.family: root.fIcon; font.pixelSize: 13
                                color: modelData.danger ? "#f28fad" : root.cAccent }
                            Text { anchors { left: dci.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                text: modelData.label; font.family: root.fUi; font.pixelSize: 13
                                color: modelData.danger ? "#f28fad" : root.cFg }
                            MouseArea { id: dca; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.ctxDo(root.ctxApp, modelData.act) }
                        }
                    }
                }
            }
            Rectangle {
                id: mctx
                visible: root.mctxOpen
                z: 51
                width: 250
                height: mctxCol.implicitHeight + 16
                x: Math.min(panel.width - width - 10, root.mctxPos.x)
                y: Math.min(panel.height - height - 10, root.mctxPos.y)
                radius: 14
                color: "#f20f1119"
                border.width: 1; border.color: root.cBorder
                Column {
                    id: mctxCol
                    x: 8; y: 8; width: parent.width - 16; spacing: 2
                    Repeater {
                        model: {
                            const a = root.mctxApp;
                            if (!a) return [];
                            const dockKey = a.id.toLowerCase();
                            const wins = root.winsOf(dockKey);
                            const out = [{ icon: "\uf04b", label: Cfg.tr(wins.length ? "New window" : "Open"), act: "open" }];
                            // the app's own jump list (.desktop Actions: new private window, compose, …)
                            for (const da of (a.actions || [])) out.push({ icon: "\uf105", label: da.name, act: "da", da: da });
                            out.push({ sep: true });
                            out.push({ icon: "\uf08d", label: Cfg.tr(root.menuIsPinned(a.id) ? "Unpin from Start" : "Pin to Start"), act: "start" });
                            out.push({ icon: "\uf0c9", label: Cfg.tr(root.isPinned(dockKey) ? "Unpin from dock" : "Pin to dock"), act: "dock" });
                            out.push({ icon: "\uf07c", label: Cfg.tr("Open file location"), act: "locate" });
                            out.push({ icon: "\uf044", label: Cfg.tr("Edit shortcut"), act: "edit" });
                            if (wins.length) {
                                out.push({ sep: true });
                                out.push({ icon: "\uf00d", label: wins.length > 1 ? Cfg.tr("Close all windows") + " (" + wins.length + ")" : Cfg.tr("Close window"), act: "close", danger: true });
                                out.push({ icon: "\uf0e7", label: Cfg.tr("Force quit"), act: "kill", danger: true });
                            }
                            out.push({ sep: true });
                            out.push({ icon: "\uf1f8", label: Cfg.tr("Uninstall"), act: "uninstall", danger: true });
                            return out;
                        }
                        delegate: Item {
                            required property var modelData
                            width: mctxCol.width; height: modelData.sep ? 9 : 36
                            Rectangle { visible: !!modelData.sep; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: root.cBorder }
                            Rectangle {
                                visible: !modelData.sep
                                anchors.fill: parent; radius: 10
                                color: ma.containsMouse ? (modelData.danger ? "#26ff6b81" : root.cHover) : "transparent"
                                Behavior on color { ColorAnimation { duration: 90 } }
                                Text { id: mi; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } width: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.icon || ""; font.family: root.fIcon; font.pixelSize: 12; color: modelData.danger ? "#ff8fa3" : root.cAccent }
                                Text { anchors { left: mi.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    elide: Text.ElideRight
                                    text: modelData.label || ""; font.family: root.fUi; font.pixelSize: 13; color: modelData.danger ? "#ffb3c1" : root.cFg }
                                MouseArea {
                                    id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.mctxDo(root.mctxApp, modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── dock ────────────────────────────────────────────────
    property var dockPinned: [ "brave-browser", "firefox", "org.kde.dolphin", "kitty", "discord", "code-oss" ]
    FileView {
        id: dockFile
        path: root.home + "/.config/quickshell/dock.json"
        blockLoading: true
        onLoaded: { try { const j = JSON.parse(text()); if (Array.isArray(j.pinned)) root.dockPinned = j.pinned; } catch (e) {} }
    }
    function savePinned(list) { dockPinned = list; dockFile.setText(JSON.stringify({ pinned: list }, null, 2)); }
    function isPinned(key) { return dockPinned.some(id => id.toLowerCase() === key); }
    function togglePin(app) {
        const id = app.entry ? app.entry.id : app.key;
        if (isPinned(app.key)) savePinned(dockPinned.filter(x => x.toLowerCase() !== app.key));
        else savePinned(dockPinned.concat([id]));
    }

    // our own quickshell windows all have the class org.quickshell: tell them apart by title
    // (sakura-settings / sakura-taskmgr .desktop entries carry their icons)
    function qsApp(cls, title) {
        if (String(cls).toLowerCase() !== "org.quickshell") return "";
        return title === "Settings" ? "sakura-settings" : title === "Task Manager" ? "sakura-taskmgr" : title === "Sakura Sound" ? "sakura-sound" : "";
    }
    function appOf(t) { return qsApp(t.appId, t.title) || String(t.appId || "").toLowerCase(); }
    readonly property var dockApps: {
        const tops = ToplevelManager.toplevels.values;
        const out = [];
        const seen = {};
        for (const id of dockPinned) {
            const key = id.toLowerCase();
            if (seen[key]) continue;
            const e = everyApp.find(x => x.id.toLowerCase() === key);
            seen[key] = true;
            out.push({ key: key, entry: e, wins: tops.filter(t => appOf(t) === key) });
        }
        for (const t of tops) {
            const key = appOf(t);
            if (!key || seen[key]) continue;
            seen[key] = true;
            // by .desktop id, then by its StartupWMClass (Electron apps often name the window differently from the .desktop file)
            const e = everyApp.find(x => x.id.toLowerCase() === key)
                   || everyApp.find(x => String(x.startupClass || "").toLowerCase() === key)
                   || DesktopEntries.heuristicLookup(t.appId) || DesktopEntries.heuristicLookup(key);
            out.push({ key: key, entry: e, wins: tops.filter(w => appOf(w) === key) });
        }
        return out;
    }

    // right-click menu state
    property var ctxApp: null
    property real ctxX: 0
    property bool ctxOpen: false
    property bool ctxInMenu: false      // the right-click menu was opened from the start menu's copy of the dock row
    function ctxItems(a) {
        if (!a) return [];
        const items = [];
        if (a.entry) items.push({ icon: "\uf067", label: "New window", act: "new" });
        items.push({ icon: "\uf08d", label: root.isPinned(a.key) ? "Unpin from dock" : "Pin to dock", act: "pin" });
        if (a.wins.length === 1) items.push({ icon: "\uf00d", label: "Close window", act: "close", danger: true });
        if (a.wins.length > 1) items.push({ icon: "\uf00d", label: "Close all " + a.wins.length + " windows", act: "close", danger: true });
        return items;
    }
    function ctxDo(a, act) {
        if (act === "new" && a.entry) a.entry.execute();
        else if (act === "pin") root.togglePin(a);
        else if (act === "close") a.wins.forEach(w => w.close());
        root.ctxOpen = false; root.ctxInMenu = false;
    }
    // drag-to-reorder state
    property int dragFrom: -1
    property int dragTo: -1
    function dockMove(from, to) {
        const apps = dockApps;
        if (from < 0 || from >= apps.length) return;
        const app = apps[from];
        const id = app.entry ? app.entry.id : app.key;
        let list = dockPinned.filter(x => x.toLowerCase() !== app.key);
        const pos = Math.max(0, Math.min(to, list.length));
        list.splice(pos, 0, id);
        savePinned(list);
    }

    component DockWindow: PanelWindow {
        id: dock
        property bool overlay: false
        readonly property real hillW: dockBg.width        // the start menu flows out of this
        readonly property bool flatTop: root.menuFlowsInto === dock
        // Settings > Taskbar > Dock
        readonly property int iconSz: Cfg.data.dockIcon || 38
        readonly property int magnify: typeof Cfg.data.dockMagnify === "number" ? Cfg.data.dockMagnify : 4
        readonly property int slotW: iconSz + 14
        readonly property bool autoHide: Cfg.data.dockAutoHide === true && !overlay
        // hidden = only a thin lip at the bottom edge; comes up under the mouse
        readonly property bool tucked: autoHide && !dockHover.hovered && !root.ctxOpen && root.dragFrom < 0 && prevKey === "" && !keepT.running
        Timer { id: keepT; interval: 700 }
        Connections { target: dockHover; function onHoveredChanged() { if (!dockHover.hovered) keepT.restart(); } }
        // window previews (hover an app that has 2+ windows)
        property string prevKey: ""
        property real prevX: 0
        readonly property var prevLive: prevKey !== "" ? root.dockApps.find(a => a.key === prevKey) || null : null
        Timer { id: prevHide; interval: 220; onTriggered: if (!prevHover.hovered) dock.prevKey = "" }
        // full screen width, always: the window must never resize when previews/menus appear,
        // otherwise it re-centres and the whole dock jitters (the surface is transparent and the mask limits clicks)
        anchors { bottom: true; left: true; right: true }
        margins.bottom: 0                                                  // flush with the edge: the hill rises out of it
        implicitHeight: 320                                                // room above for tooltips + right-click menu
        exclusiveZone: autoHide ? 0 : 64
        exclusionMode: overlay ? ExclusionMode.Ignore : ExclusionMode.Normal   // the overlay copy reserves nothing and sits at the very bottom
        color: "transparent"
        WlrLayershell.namespace: "dock"
        WlrLayershell.layer: overlay ? WlrLayer.Overlay : WlrLayer.Top
        mask: Region { item: Choreo.still ? dockBg : null; Region { item: ctxHit } Region { item: prevBox } }   // only the bar, menu and previews take clicks
        // login / restart / leaving (Choreo.qml): the dock rises out of the bottom edge and sinks back
        Binding { target: dock.contentItem; property: "y"; value: Math.round((1 - Choreo.dock) * 64) }
        HyprlandFocusGrab { windows: [ dock ]; active: root.ctxOpen && !root.ctxInMenu; onCleared: root.ctxOpen = false }

        // the dock grows out of the bottom edge like the top bar notches (waybar style.css): rounded top,
        // concave ears where it meets the edge, same color (@notch) - so it melts into the screen edge
        Item {
            id: dockBg
            HoverHandler { id: dockHover }
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            width: dockRow.implicitWidth + 20
            height: 60
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            // the start menu has lifted the dock row up (it shows a copy of it on its top edge)
            opacity: dock.flatTop ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 90 } }
            // tucked away: moved (not just drawn) down, so the click area and hover follow it
            anchors.bottomMargin: dock.tucked ? -54 : 0
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 260 * Cfg.anim; easing.type: Easing.OutCubic } }

            Canvas {
                id: bump
                readonly property int earW: 22         // concave quarter ellipse into the screen edge,
                readonly property int earH: 16         // same as the waybar notches (#custom-ear*)
                // rounded top corners (= notch corners); square while the start menu grows out of this dock, so the
                // dock's walls run straight on into the menu and the two read as one piece
                property real corner: dock.flatTop ? 0 : 24
                Behavior on corner { NumberAnimation { duration: 160 } }
                onCornerChanged: requestPaint()
                Connections { target: dock; function onFlatTopChanged() { bump.requestPaint(); } }
                x: -earW
                width: parent.width + 2 * earW
                height: parent.height
                onWidthChanged: requestPaint()
                Connections { target: Cfg; function onGlassChanged() { bump.requestPaint(); } }
                Connections { target: root; function onGlassNowChanged() { bump.requestPaint(); } }
                onPaint: {
                    const ctx = getContext("2d"), k = 0.5523, ex = earW, ey = earH, r = corner, w = width, h = height;
                    ctx.reset();
                    if (dock.flatTop) {          // the start menu's hill is around it: just fill the hole it leaves
                        ctx.fillStyle = root.glassNow;
                        ctx.fillRect(ex, 0, w - 2 * ex, h);
                        return;
                    }
                    ctx.beginPath();
                    ctx.moveTo(0, h);
                    ctx.bezierCurveTo(ex * k, h, ex, h - ey + ey * k, ex, h - ey);
                    ctx.lineTo(ex, r);
                    ctx.bezierCurveTo(ex, r - r * k, ex + r - r * k, 0, ex + r, 0);
                    ctx.lineTo(w - ex - r, 0);
                    ctx.bezierCurveTo(w - ex - r + r * k, 0, w - ex, r - r * k, w - ex, r);
                    ctx.lineTo(w - ex, h - ey);
                    ctx.bezierCurveTo(w - ex, h - ey + ey * k, w - ex * k, h, w, h);
                    ctx.closePath();
                    ctx.fillStyle = root.glassNow;      // = waybar @notch; hyprland blurs behind it (layer rule "blur-dock")
                    ctx.fill();
                }
            }
        }

        Row {
            id: dockRow
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            spacing: 4
            // the start menu carries its own copy of this row up to its top edge: the real one must not stay behind
            // under the menu's glass (it showed through behind the player strip). No fade: the copy starts on top of it.
            opacity: dock.flatTop ? 0 : 1
            enabled: !dock.flatTop

            // start button (avatar)
            Item {
                width: 48; height: 60
                ClippingRectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 9
                    width: 42; height: 42; radius: 21
                    color: root.open || startArea.containsMouse ? root.cAccent : "#33ffffff"
                    scale: startArea.pressed ? 0.93 : (startArea.containsMouse ? 1.05 : 1)
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Avatar { anchors.fill: parent; ring: 2; ringColor: "transparent" }
                }
                MouseArea { id: startArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggle() }
            }
            Item { width: 9; height: 60
                Rectangle { anchors.centerIn: parent; width: 1; height: 30; color: root.cBorder } }

            Repeater {
                model: root.dockApps
                delegate: Item {
                    id: slot
                    required property var modelData
                    required property int index
                    readonly property bool running: modelData.wins.length > 0
                    readonly property bool active: modelData.wins.some(w => w.activated)
                    property int cycle: 0
                    property bool dragging: false
                    property real dragDx: 0
                    width: dock.slotW; height: 60
                    z: dragging ? 10 : 0
                    // neighbours slide aside while you drag
                    readonly property real shift: {
                        const f = root.dragFrom, t = root.dragTo, i = slot.index;
                        if (f < 0 || i === f) return 0;
                        if (f < t && i > f && i <= t) return -(dock.slotW + 4);
                        if (f > t && i < f && i >= t) return dock.slotW + 4;
                        return 0;
                    }
                    transform: Translate {
                        x: slot.dragging ? slot.dragDx : slot.shift
                        Behavior on x { enabled: !slot.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }

                    // hover growth = GPU scale of an icon drawn once at the largest size: animating implicitSize
                    // re-rasterised the icon every frame and snapped it by half pixels (the icons twitched)
                    IconImage {
                        readonly property int big: dock.iconSz + Math.max(8, dock.magnify)
                        readonly property real want: slot.dragging ? dock.iconSz + 8 : (area.containsMouse ? dock.iconSz + dock.magnify : dock.iconSz)
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: big
                        y: Math.round((60 - big) / 2)
                        scale: want / big
                        transform: Translate {
                            y: area.containsMouse || slot.dragging ? -3 : -1
                            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                        source: Quickshell.iconPath(slot.modelData.entry ? slot.modelData.entry.icon : slot.modelData.key, "application-x-executable")
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 4 }
                        radius: 2
                        visible: (Cfg.data.dockDots || "line") !== "none"
                        width: Cfg.data.dockDots === "dots" ? (slot.running ? 5 : 0) : (slot.active ? 18 : (slot.running ? 6 : 0))
                        height: Cfg.data.dockDots === "dots" ? 5 : 4
                        color: slot.active ? root.cAccent : root.cMuted
                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    // unread notifications of this app
                    Rectangle {
                        readonly property int n: Cfg.data.dockBadges === false ? 0 : Notifs.list.filter(x => {
                            const a = String(x.appName || "").toLowerCase(), e = slot.modelData.entry;
                            return a !== "" && (a === String(slot.modelData.key).toLowerCase() || (e && a === String(e.name).toLowerCase())); }).length
                        visible: n > 0
                        anchors { right: parent.right; top: parent.top; rightMargin: 4; topMargin: 4 }
                        width: Math.max(16, bt.implicitWidth + 8); height: 16; radius: 8; color: root.cAccent
                        Text { id: bt; anchors.centerIn: parent; text: parent.n > 9 ? "9+" : parent.n; font.family: root.fUi; font.pixelSize: 9; font.weight: Font.Bold; color: root.cAccFg }
                    }
                    // name tooltip (inside the taller dock window, so it is never cut)
                    Rectangle {
                        opacity: area.containsMouse && !root.ctxOpen && root.dragFrom < 0 && dock.prevKey !== slot.modelData.key ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 8 }
                        width: tip.implicitWidth + 18; height: 28; radius: 9
                        color: root.glassNow; border.width: 1; border.color: root.cBorder
                        Text { id: tip; anchors.centerIn: parent; color: root.cFg; font.family: root.fUi; font.pixelSize: 12
                            text: slot.modelData.entry ? slot.modelData.entry.name : slot.modelData.key }
                    }
                    MouseArea {
                        id: area; anchors.fill: parent; hoverEnabled: true
                        onContainsMouseChanged: {
                            if (containsMouse && slot.modelData.wins.length >= 2 && !root.ctxOpen && root.dragFrom < 0) {
                                dock.prevKey = slot.modelData.key; dock.prevX = slot.mapToItem(null, slot.width / 2, 0).x; prevHide.stop();
                            } else if (containsMouse) {
                                prevHide.stop(); dock.prevKey = "";            // moved onto another app: old previews go away at once
                            } else prevHide.restart();                       // left the icon: short grace to reach the previews
                        }
                        cursorShape: slot.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        property real pressX: 0
                        property bool wasDrag: false
                        // measure in dock coordinates (the icon itself moves, so its own coords would feed back and jitter)
                        onPressed: m => { pressX = area.mapToItem(dockBg, m.x, 0).x; wasDrag = false; }
                        onPositionChanged: m => {
                            if (!(pressedButtons & Qt.LeftButton)) return;
                            const dx = area.mapToItem(dockBg, m.x, 0).x - pressX;
                            if (!slot.dragging && Math.abs(dx) > 8) { slot.dragging = true; root.dragFrom = slot.index; }
                            if (slot.dragging) {
                                slot.dragDx = dx;
                                root.dragTo = Math.max(0, Math.min(root.dockApps.length - 1, slot.index + Math.round(dx / (dock.slotW + 4))));
                            }
                        }
                        onReleased: m => {
                            if (!slot.dragging) return;
                            wasDrag = true;
                            const from = root.dragFrom, to = root.dragTo;
                            slot.dragging = false; slot.dragDx = 0;
                            root.dragFrom = -1; root.dragTo = -1;
                            if (to !== from) root.dockMove(from, to);
                        }
                        onClicked: m => {
                            if (wasDrag) { wasDrag = false; return; }
                            const wins = slot.modelData.wins;
                            if (m.button === Qt.RightButton) {
                                root.ctxInMenu = false;
                                root.ctxApp = slot.modelData;
                                root.ctxX = slot.mapToItem(null, slot.width / 2, 0).x;
                                root.ctxOpen = true;
                                return;
                            }
                            if (root.open) root.hide();       // launching from the dock while the menu is open
                            if (m.button === Qt.MiddleButton || wins.length === 0) {
                                if (slot.modelData.entry) slot.modelData.entry.execute();
                                return;
                            }
                            if (wins.length === 1 && wins[0].activated) {
                                Quickshell.execDetached([root.home + "/.config/hypr/scripts/minimize.sh", "hide"]);
                                return;
                            }
                            slot.cycle = (slot.cycle + 1) % wins.length;
                            if (!genie.bringBack(wins[slot.cycle])) wins[slot.cycle].activate();
                            Quickshell.execDetached(["sh", "-c", "sleep 0.08; hyprctl eval 'hl.dispatch(hl.dsp.window.bring_to_top())'"]);
                        }
                    }
                }
            }
        }

        // window previews (like the Windows taskbar): hover an app with several windows, click one to switch
        Rectangle {
            id: prevBox
            readonly property var wins: dock.prevLive ? dock.prevLive.wins : []
            readonly property bool want: wins.length >= 2 && !root.ctxOpen && root.dragFrom < 0
            visible: opacity > 0.01
            opacity: want ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            width: want ? wins.length * 226 + 14 : 0
            height: want ? 172 : 0
            x: Math.max(8, Math.min(dock.width - width - 8, dock.prevX - width / 2))
            y: dock.implicitHeight - 60 - height - 10
            transform: Translate { y: prevBox.want ? 0 : 8; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
            radius: 18
            color: root.glassNow
            border.width: 0
            HoverHandler { id: prevHover; onHoveredChanged: hovered ? prevHide.stop() : prevHide.restart() }
            Row {
                anchors.centerIn: parent
                spacing: 8
                Repeater {
                    model: prevBox.wins
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        readonly property bool game: /^(cs2|dota2|gamescope|steam_app_.*)$/i.test(String(modelData.appId || ""))
                        width: 218; height: 158; radius: 12
                        color: cardArea.containsMouse ? root.cHover : "transparent"
                        border.width: modelData.activated ? 1 : 0; border.color: root.cAccent
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Item {
                            id: cardHead
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            height: 22
                            IconImage { id: cardIcon; anchors.verticalCenter: parent.verticalCenter; implicitSize: 16
                                source: Quickshell.iconPath(dock.prevLive && dock.prevLive.entry ? dock.prevLive.entry.icon : String(card.modelData.appId || ""), "application-x-executable") }
                            Text { anchors { left: cardIcon.right; leftMargin: 7; right: closeBtn.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                text: card.modelData.title || ""; elide: Text.ElideRight
                                color: root.cFg; font.family: root.fUi; font.pixelSize: 11 }
                            Rectangle {
                                id: closeBtn
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: 20; height: 20; radius: 7
                                opacity: cardArea.containsMouse || cbA.containsMouse ? 1 : 0
                                color: cbA.containsMouse ? "#f28fad" : "transparent"
                                Text { anchors.centerIn: parent; text: "\uf00d"; font.family: root.fIcon; font.pixelSize: 10; color: cbA.containsMouse ? "#1a121a" : root.cFg }
                                MouseArea { id: cbA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.modelData.close() }
                            }
                        }
                        ClippingRectangle {
                            anchors { left: parent.left; right: parent.right; top: cardHead.bottom; bottom: parent.bottom; margins: 8; topMargin: 4 }
                            radius: 8; color: "#0f1119"
                            ScreencopyView {
                                id: shot
                                anchors.fill: parent
                                captureSource: prevBox.want && !card.game ? card.modelData : null
                                live: true
                                constraintSize: Qt.size(202, 118)
                            }
                            IconImage { anchors.centerIn: parent; visible: !shot.hasContent; implicitSize: 44
                                source: cardIcon.source }
                        }
                        MouseArea {
                            id: cardArea; anchors.fill: parent; anchors.rightMargin: 30; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!genie.bringBack(card.modelData)) card.modelData.activate();
                                Quickshell.execDetached(["sh", "-c", "sleep 0.08; hyprctl eval 'hl.dispatch(hl.dsp.window.bring_to_top())'"]);
                                dock.prevKey = "";
                                Quickshell.execDetached(["qs", "ipc", "call", "menu", "close"]);
                            }
                        }
                    }
                }
            }
        }

        // right-click menu (lives inside the dock window so outside clicks close it)
        Item {
            id: ctxHit
            x: Math.max(8, Math.min(dock.width - width - 8, root.ctxX - width / 2))
            y: dock.implicitHeight - 60 - height - 10
            readonly property bool on: root.ctxOpen && !root.ctxInMenu
            width: on ? 240 : 0
            height: on ? ctxCol.implicitHeight + 16 : 0
            visible: on
            focus: on
            Keys.onEscapePressed: root.ctxOpen = false
            HoverHandler { id: ctxHover }
            Timer {        // (no auto-close any more: it vanished while you were just reading it; closes on a click outside, Esc or a pick)
                interval: 1200
                running: false
                onTriggered: root.ctxOpen = false
            }
            Rectangle {
                id: ctxBox
                anchors.fill: parent
                radius: 16
                color: root.glassNow            // the same glass as the bar and the dock (blurred: layer rule "blur-dock")

                Column {
                    id: ctxCol
                    x: 8; y: 8
                    width: parent.width - 16
                    spacing: 2

                    Row {
                        spacing: 10; leftPadding: 8; topPadding: 4; bottomPadding: 6
                        IconImage { implicitSize: 22; anchors.verticalCenter: parent.verticalCenter
                            source: root.ctxApp ? Quickshell.iconPath(root.ctxApp.entry ? root.ctxApp.entry.icon : root.ctxApp.key, "application-x-executable") : "" }
                        Text { anchors.verticalCenter: parent.verticalCenter; color: root.cFg; font.family: root.fUi; font.pixelSize: 13; font.weight: Font.Bold
                            text: root.ctxApp ? (root.ctxApp.entry ? root.ctxApp.entry.name : root.ctxApp.key) : "" }
                    }
                    Rectangle { width: parent.width; height: 1; color: root.cBorder }

                    Repeater {
                        model: root.ctxItems(root.ctxApp)
                        delegate: Rectangle {
                            required property var modelData
                            width: ctxCol.width; height: 38; radius: 10
                            color: ca.containsMouse ? (modelData.danger ? "#33f28fad" : root.cHover) : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Text { id: ci; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } width: 18
                                text: modelData.icon; font.family: root.fIcon; font.pixelSize: 13
                                color: modelData.danger ? "#f28fad" : root.cAccent }
                            Text { anchors { left: ci.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                text: modelData.label; font.family: root.fUi; font.pixelSize: 13
                                color: modelData.danger ? "#f28fad" : root.cFg }
                            MouseArea {
                                id: ca; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.ctxDo(root.ctxApp, modelData.act)
                            }
                        }
                    }
                }
            }
        }
    }

    // the normal dock on the main monitor
    DockWindow {
        id: mainDock
        screen: Cfg.mainScreen
    }
    // a copy that shows above fullscreen apps (games) while the start menu is open
    DockWindow {
        id: overlayDock
        overlay: true
        visible: root.open && (!root.menuOnMain || root.fsUnder)
        screen: root.menuScreen
    }
}
