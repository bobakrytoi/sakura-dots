pragma Singleton
// sakura mono - Sakura Cam backend glue: the iPhone as a webcam (hypr/scripts/sakura-cam/server.py, user service
// sakura-cam.service). State comes as Server-Sent Events from the local API (127.0.0.1:8782/events), commands go
// to POST /cmd. Settings: settings.json → "cam" (Settings > Sakura Cam); they are pushed to the server on change.
// The hotkey: ~/.config/hypr/sakuracam.lua (written here, loaded by hyprland.lua) + live hl.bind via hyprctl eval.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: cl
    readonly property string api: "http://127.0.0.1:8782"
    readonly property string bindFile: Quickshell.env("HOME") + "/.config/hypr/sakuracam.lua"

    // ── settings ──
    readonly property var defaults: ({ res: "1080p", fps: 30, camera: "back", mirror: false, rotate: 0, fit: "fill",
                                       mic: false, bitrate: 8, net: "auto", zoom: 1.0, autostream: true, hotkey: "SUPER + ALT + C" })
    readonly property var o: Object.assign({}, defaults, Cfg.data.cam || {})
    function set(k, v) {
        const p = Object.assign({}, Cfg.data.cam || {}); p[k] = v; Cfg.set("cam", p);
        if (k !== "hotkey") cmd({ cmd: "set", key: k, value: v });
    }
    function pushConfig() { const c = Object.assign({}, o); delete c.hotkey; cmd({ cmd: "config", cfg: c }); }

    // ── state from the server ──
    property bool up: false                 // the service answers
    property var st: ({})
    readonly property bool connected: up && !!st.connected
    readonly property bool streaming: up && !!st.streaming
    readonly property bool want: up && st.want !== false
    readonly property var phone: st.phone || ({})
    readonly property var cfg: st.cfg || o
    readonly property string device: st.out ? st.out.device || "" : ""
    readonly property string outError: st.out ? st.out.error || "" : ""
    readonly property real since: st.since || 0
    readonly property var ifaces: st.ifaces || []
    readonly property bool hasUsb: ifaces.some(i => i.kind === "usb")
    readonly property bool hasWifi: ifaces.some(i => i.kind === "wifi" || i.kind === "lan")
    readonly property string resText: streaming && st.out ? st.out.h + "p" + (st.in && st.in.fps ? " · " + Math.round(st.in.fps) + " fps" : "") : ""
    // the size is pinned by an app that has the camera open (v4l2loopback): say so, it switches when that app lets go
    readonly property bool sizePinned: !!(st.out && st.out.want && st.out.h && st.out.want !== st.out.h)
    readonly property string pinnedNote: sizePinned ? st.out.want + "p " + Cfg.tr("after") + " " + ((st.out.held || [])[0] || Cfg.tr("the app")) + " " + Cfg.tr("closes the camera") : ""
    readonly property bool zoomNative: !!(phone.zoomNative)
    readonly property real zoomMin: zoomNative ? phone.zoomNative.min : 1
    readonly property real zoomMax: zoomNative ? Math.min(10, phone.zoomNative.max) : 4
    readonly property real zoom: zoomNative ? (phone.zoom || 1) : (cfg.zoom || 1)
    property int qrSerial: 0                // bumps when the address may have changed (reload the QR picture)

    property bool wasConnected: false
    property bool wasStreaming: false
    property bool armed: false
    property int lineN: 0
    property int evN: 0                     // events received (for checks: qs ipc call camlink raw)
    IpcHandler { target: "camlink"; function raw(): string { return "lines " + cl.lineN + " events " + cl.evN + " up " + cl.up + " " + JSON.stringify(cl.st).slice(0, 160); } }
    function onState(s) {
        evN++;
        const first = !up;
        st = s; up = true;
        if (first) { pushConfig(); qrSerial++; armT.restart(); }
        if (connected !== wasConnected) {
            if (armed) Notch.notice("share", connected ? "iPhone connected" : "iPhone disconnected");
            wasConnected = connected;
        }
        if (streaming !== wasStreaming) { wasStreaming = streaming; }
    }
    Timer { id: armT; interval: 1500; onTriggered: cl.armed = true }
    onIfacesChanged: qrSerial++

    Process {
        id: events
        command: ["curl", "-sN", "--max-time", "0", cl.api + "/events"]
        running: true
        // SSE: "data: {json}" blocks split by blank lines (a chunk may start with the blank line's "\n")
        stdout: SplitParser { onRead: l => { cl.lineN++; for (const x of l.split("\n")) if (x.startsWith("data: ")) { try { cl.onState(JSON.parse(x.slice(6))); } catch (e) {} } } }
        onRunningChanged: if (!running) { cl.up = false; cl.st = ({}); cl.wasConnected = false; cl.wasStreaming = false; retryT.restart(); }
    }
    Timer { id: retryT; interval: 3000; onTriggered: events.running = true }

    function cmd(m) { if (up) Quickshell.execDetached(["curl", "-s", "-m", "3", "-XPOST", "-H", "Content-Type: application/json", api + "/cmd", "-d", JSON.stringify(m)]); }
    function stream(on) { cmd({ cmd: "stream", on: on === undefined ? "toggle" : on }); }
    function focus(x, y) { cmd({ cmd: "focus", x: x, y: y }); }
    function torch() { cmd({ cmd: "torch", on: "toggle" }); }
    function setZoom(z) { const v = Math.max(zoomMin, Math.min(zoomMax, z)); cmd({ cmd: "set", key: "zoom", value: v }); }
    function camera(k) { set("camera", k); }
    function startService() { Quickshell.execDetached(["systemctl", "--user", "start", "sakura-cam.service"]); }
    function qrUrl(net) { return api + "/qr.svg?net=" + (net || o.net) + "&dark=%230f1119&s=" + qrSerial; }

    // the hotkey: on / off from anywhere
    function toggle() {
        if (!up) { Notch.notice("info", "Sakura Cam is not running"); startService(); return "down"; }
        if (!connected) { Notch.notice("info", "Open Sakura Cam on your iPhone"); return "nophone"; }
        const on = !want;
        stream(on);
        Notch.notice("share", on ? "Camera on" : "Camera paused");
        return on ? "on" : "off";
    }

    // ── hotkey (same scheme as the password helper) ──
    readonly property var modBits: ({ SHIFT: 1, CTRL: 4, ALT: 8, SUPER: 64 })
    function parseCombo(s) {
        const parts = String(s).toUpperCase().split("+").map(x => x.trim()).filter(x => x);
        let mask = 0, key = "";
        for (const p of parts) { if (modBits[p] !== undefined) mask |= modBits[p]; else key = p; }
        return { mask: mask, key: key };
    }
    function pretty(s) {
        if (!s) return Cfg.tr("Off");
        const c = parseCombo(s), l = [];
        if (c.mask & 4) l.push("Ctrl"); if (c.mask & 8) l.push("Alt"); if (c.mask & 64) l.push("Super"); if (c.mask & 1) l.push("Shift");
        l.push(c.key);
        return l.join(" + ");
    }
    function luaBind(s) { return "pcall(hl.bind, \"" + s + "\", hl.dsp.exec_cmd(\"qs ipc call cam toggle\"), { desc = \"Sakura Cam\" })"; }
    property string hkError: ""
    property var hkJob: null
    function setHotkey(s) {
        hkError = "";
        if (!s) { applyBind(o.hotkey, ""); set("hotkey", ""); return; }
        const c = parseCombo(s);
        hkJob = { combo: s, mask: c.mask, key: c.key, old: o.hotkey };
        bindsP.running = false; bindsP.running = true;
    }
    Process {
        id: bindsP
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { onStreamFinished: {
            const j = cl.hkJob; cl.hkJob = null; if (!j) return;
            let binds = []; try { binds = JSON.parse(this.text); } catch (e) {}
            const clash = binds.find(b => b.modmask === j.mask && String(b.key).toUpperCase() === j.key && b.description !== "Sakura Cam" && !b.release && !b.mouse);
            if (clash) { cl.hkError = Cfg.tr("Already used by") + " “" + (clash.description || clash.dispatcher) + "”"; return; }
            cl.applyBind(j.old, j.combo); cl.set("hotkey", j.combo);
        } }
    }
    function applyBind(oldCombo, combo) {
        Quickshell.execDetached(["hyprctl", "eval", (oldCombo ? "pcall(hl.unbind, \"" + oldCombo + "\"); " : "") + (combo ? luaBind(combo) : "")]);
        bindView.setText("-- generated by quickshell (Settings > Sakura Cam > Shortcut); edit there\n" + (combo ? luaBind(combo) + "\n" : ""));
    }
    FileView { id: bindView; path: cl.bindFile; blockLoading: true; printErrors: false }
    Component.onCompleted: {
        const t = bindView.text();
        if (o.hotkey && (!t || t.indexOf(o.hotkey) < 0)) applyBind("", o.hotkey);
    }
}
