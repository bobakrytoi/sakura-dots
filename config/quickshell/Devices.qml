pragma Singleton
// sakura mono - battery of wireless peripherals (the "devices" module of the bar wings and the corner island).
//  · hypr/scripts/devbat.py reads them straight from hidraw (read-only): Logitech G733 (HID++ voltage) and
//    Glorious Model O/D Wireless (Sinowealth feature report). Every 60 s, every 20 s while one charges or is low.
//  · Plus anything UPower knows (mouse / keyboard / headset / gamepad that the kernel exposes), as a fallback.
//  · ids: list of strings (the Repeater model; rebuilt only when the set changes), info(id) for the values.
//  · Notch notices: "<device> 12 %" once when it drops under `low` while not charging, connect / disconnect.
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

Singleton {
    id: dv
    readonly property int low: 15
    property var map: ({})              // id -> { id, name, kind, percent, charging, asleep }
    property var ids: []
    property bool polled: false
    property var warned: ({})           // id -> true once the low notice was said
    readonly property var glyphs: ({ headset: "\u{F02CE}", mouse: "\u{F037D}", keyboard: "\u{F030C}", gamepad: "\u{F0297}" })
    readonly property var kindNames: ({ headset: "Headset", mouse: "Mouse", keyboard: "Keyboard", gamepad: "Gamepad" })
    function info(id) { return map[id] || null; }
    function glyph(k) { return glyphs[k] || "\u{F0079}"; }
    // per-kind filter of the module: Cfg.mo("devices", "headset" | "mouse" | "keyboard"); delegates use visible: wanted(d)
    function wanted(d) { return !!d && Cfg.mo("devices", d.kind === "gamepad" ? "mouse" : d.kind); }
    function line(d) {
        if (!d) return "";
        const st = d.percent === undefined ? Cfg.tr("asleep") : d.percent + "%";
        return d.name + " · " + st + (d.charging ? " · " + Cfg.tr("charging") : "");
    }
    readonly property string tip: ids.map(i => line(map[i])).join("<br>")
    readonly property bool busy: ids.some(i => map[i] && (map[i].charging || (map[i].percent !== undefined && map[i].percent < low)))

    // UPower fallback: devices the kernel itself reports (none on this PC today, 2026-11-10)
    function upowerList() {
        const out = [];
        const kinds = { 5: "mouse", 6: "keyboard", 12: "gamepad", 17: "headset", 19: "headset" };
        const vs = UPower.devices.values || [];
        for (let i = 0; i < vs.length; i++) {
            const u = vs[i];
            const k = kinds[u.type];
            if (!k || !u.isPresent || u.isLaptopBattery) continue;
            const p = u.percentage <= 1 ? Math.round(u.percentage * 100) : Math.round(u.percentage);
            out.push({ id: "up:" + (u.nativePath || u.model), name: u.model || Cfg.tr(kindNames[k]), kind: k, percent: p, charging: u.state === 1 || u.state === 4 });
        }
        return out;
    }

    function apply(list) {
        const old = map, m = {};
        const all = list.concat(upowerList().filter(u => !list.some(d => d.kind === u.kind)));
        for (const d of all) {
            // asleep: keep the last reading, mark it
            if (d.asleep && old[d.id] && old[d.id].percent !== undefined) d.percent = old[d.id].percent;
            m[d.id] = d;
        }
        const w = Object.assign({}, warned);
        if (polled) {
            for (const id in m) {
                const d = m[id];
                if (!old[id]) Notch.notice("battery", d.name + " · " + Cfg.tr("connected") + (d.percent !== undefined ? " · " + d.percent + "%" : ""));
                else if (d.percent !== undefined && d.percent < low && !d.charging && !w[id]) { Notch.notice("batterylow", d.name + " · " + d.percent + "%"); w[id] = true; }
            }
            for (const id in old) if (!m[id]) Notch.notice("battery", old[id].name + " · " + Cfg.tr("disconnected"));
        }
        for (const id in m) if (m[id].charging || (m[id].percent !== undefined && m[id].percent >= low + 5)) delete w[id];
        warned = w;
        map = m;
        const n = Object.keys(m).sort();
        if (n.join("|") !== ids.join("|")) ids = n;
        polled = true;
    }

    Process {
        id: proc
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/devbat.py"]
        stdout: StdioCollector { onStreamFinished: { try { dv.apply(JSON.parse(this.text)); } catch (e) {} } }
    }
    function poll() { if (!proc.running) proc.running = true; }
    Timer { interval: dv.busy ? 20000 : 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: dv.poll() }
    Connections { target: UPower.devices; function onValuesChanged() { if (dv.polled) dv.poll(); } }

    IpcHandler {
        target: "devices"
        function poll(): void { dv.poll(); }
        function state(): string { return JSON.stringify(dv.map); }
    }
}
