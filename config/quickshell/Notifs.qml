pragma Singleton
// sakura mono - the notification daemon (replaces swaync). Every notification is kept (tracked) until it is
// dismissed in the center (NotifCenter.qml); new ones also pop up for a few seconds (NotifPopups.qml).
// Do not disturb: no popups and no sound (critical ones still pop up). Stored in settings.json ("dnd").
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

Singleton {
    id: ns
    readonly property bool dnd: Cfg.data.dnd === true
    // quiet hours (Settings > Notifications): like Do not disturb between two times, e.g. 22:00-08:00
    property bool quiet: false
    function checkQuiet() {
        if (Cfg.data.quietHours !== true) { quiet = false; return; }
        const m = s => { const p = String(s || "0:0").split(":"); return parseInt(p[0]) * 60 + parseInt(p[1] || 0); };
        const d = new Date(), now = d.getHours() * 60 + d.getMinutes(), a = m(Cfg.data.quietFrom || "22:00"), b = m(Cfg.data.quietTo || "08:00");
        quiet = a <= b ? (now >= a && now < b) : (now >= a || now < b);
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: ns.checkQuiet() }
    Connections { target: Cfg; function onDataChanged() { ns.checkQuiet(); } }
    readonly property bool silent: dnd || quiet
    readonly property var muted: Cfg.data.mutedApps || []           // no popup, no sound (still in the center)
    readonly property int timeout: (Cfg.data.notifTimeout || 6) * 1000
    // app names seen this session (for the mute list in Settings)
    property var seenApps: []
    function setDnd(on) { Cfg.set("dnd", on); }
    function toggleDnd() { setDnd(!dnd); }

    readonly property var list: server.trackedNotifications.values.slice().reverse()   // newest first
    readonly property int count: list.length
    property int unread: 0
    property var popups: []          // notifications showing as popups right now (newest first)

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        persistenceSupported: true
        onNotification: n => {
            n.tracked = true;
            ns.unread += 1;
            const critical = n.urgency === NotificationUrgency.Critical;
            const app = n.appName || "";
            if (app && !ns.seenApps.includes(app)) ns.seenApps = ns.seenApps.concat([app]);
            if (ns.muted.includes(app) && !critical) return;
            if (!ns.silent || critical) {
                ns.popups = [n].concat(ns.popups.filter(p => p !== n)).slice(0, 5);
                if (n.urgency !== NotificationUrgency.Low)
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sfx.sh", "notify"]);
            }
            n.closed.connect(() => { ns.popups = ns.popups.filter(p => p !== n); });
        }
    }
    function hidePopup(n) { popups = popups.filter(p => p !== n); }
    function dismiss(n) { hidePopup(n); n.dismiss(); }
    function clearAll() { popups = []; for (const n of server.trackedNotifications.values.slice()) n.dismiss(); unread = 0; }
    function activate(n) {
        const a = n.actions.find(x => x.identifier === "default") || null;
        if (a) a.invoke(); else dismiss(n);
    }
    function seen() { unread = 0; }

    // seconds/minutes ago
    function ago(t) {
        const s = Math.max(0, Math.floor((Date.now() - t) / 1000));
        if (s < 60) return Cfg.tr("now");
        if (s < 3600) return Math.floor(s / 60) + " " + Cfg.tr("min");
        if (s < 86400) return Math.floor(s / 3600) + " " + Cfg.tr("h");
        return Math.floor(s / 86400) + " " + Cfg.tr("d");
    }
    // arrival time of each notification (Notification has none)
    property var times: ({})
    Connections {
        target: server.trackedNotifications
        function onValuesChanged() {
            const t = Object.assign({}, ns.times), now = Date.now();
            for (const n of server.trackedNotifications.values) if (t[n.id] === undefined) t[n.id] = now;
            ns.times = t;
        }
    }
    property real now: Date.now()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: ns.now = Date.now() }

    IpcHandler {
        target: "notifs"
        function dnd(): void { ns.toggleDnd(); }
        function clear(): void { ns.clearAll(); }
    }
}
