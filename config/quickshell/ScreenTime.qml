pragma Singleton
// sakura mono - screen time: how long each app was the active window, per day.
// Counted every 10 s while you are not idle (5 min without input; a playing video keeps it counting).
// ~/.local/share/sakura/screentime.json = { "2026-11-10": { "firefox": 3600, … }, … }, the last 30 days.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Singleton {
    id: stt
    readonly property string path: Quickshell.env("HOME") + "/.local/share/sakura/screentime.json"
    property var days: ({})
    property bool loaded: false

    function key(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }

    FileView {
        id: file
        path: stt.path
        onLoaded: { try { stt.days = JSON.parse(text()); } catch (e) { stt.days = {}; } stt.loaded = true; }
        onLoadFailed: { stt.days = {}; stt.loaded = true; }
    }
    IdleMonitor { id: idle; timeout: 300; respectInhibitors: true }

    readonly property var active: ToplevelManager.activeToplevel
    Timer {
        interval: 10000; running: stt.loaded; repeat: true
        onTriggered: {
            const t = stt.active;
            if (idle.isIdle || !t || !t.activated) return;
            const app = String(t.appId || "").toLowerCase();
            if (app === "") return;
            const k = stt.key(new Date()), d = Object.assign({}, stt.days);
            const day = Object.assign({}, d[k] || {});
            day[app] = (day[app] || 0) + 10;
            d[k] = day;
            stt.days = d;
            stt.dirty = true;
        }
    }
    property bool dirty: false
    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: {
            if (!stt.dirty) return;
            // keep 30 days
            const keep = {}, ks = Object.keys(stt.days).sort().slice(-30);
            for (const k of ks) keep[k] = stt.days[k];
            Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/share/sakura"]);
            file.setText(JSON.stringify(keep));
            stt.dirty = false;
        }
    }

    // [{ app, secs }] sorted, for today or the last 7 days
    function top(range) {
        const tot = {}, now = new Date();
        const n = range === "week" ? 7 : 1;
        for (let i = 0; i < n; i++) {
            const d = days[key(new Date(now.getFullYear(), now.getMonth(), now.getDate() - i))] || {};
            for (const a in d) tot[a] = (tot[a] || 0) + d[a];
        }
        return Object.keys(tot).map(a => ({ app: a, secs: tot[a] })).sort((x, y) => y.secs - x.secs);
    }
    function total(range) { return top(range).reduce((s, x) => s + x.secs, 0); }
    // seconds for each of the last 7 days, oldest first
    function week() {
        const r = [], now = new Date();
        for (let i = 6; i >= 0; i--) {
            const dt = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i), d = days[key(dt)] || {};
            r.push({ date: dt, secs: Object.values(d).reduce((s, x) => s + x, 0) });
        }
        return r;
    }
    function fmt(s) {
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60);
        return h > 0 ? h + " " + Cfg.tr("h") + " " + m + " " + Cfg.tr("min") : m + " " + Cfg.tr("min");
    }
    function appName(a) { const e = DesktopEntries.heuristicLookup(a); return e ? e.name : a; }
    function appIcon(a) { const e = DesktopEntries.heuristicLookup(a); return Quickshell.iconPath(e ? e.icon : a, "application-x-executable"); }
}
