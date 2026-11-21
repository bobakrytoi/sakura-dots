pragma Singleton
// sakura mono - timer, stopwatch and alarms (shown in the dashboard, "Timers" tab).
// Everything runs in the background and survives a shell restart (~/.config/sakura/timers.json):
// running timers are stored as an end time, alarms as hh:mm. When one goes off: a chime + a notification.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: tm
    readonly property string home: Quickshell.env("HOME")
    property real now: Date.now()

    // ── timer ──
    property real tEnd: 0          // epoch ms when it rings (0 = not running)
    property real tTotal: 5 * 60000
    property real tLeft: 5 * 60000 // shown while paused / stopped
    readonly property bool tRunning: tEnd > 0
    // (now is refreshed on every start/pause, otherwise the first frame after Start showed one second too much)
    readonly property real tRemain: tRunning ? Math.min(tTotal, Math.max(0, tEnd - now)) : tLeft
    function tStart() { now = Date.now(); if (tLeft <= 0) tLeft = tTotal; tEnd = now + tLeft; save(); }
    function tPause() { if (!tRunning) return; now = Date.now(); tLeft = Math.max(0, tEnd - now); tEnd = 0; save(); }
    function tReset() { tEnd = 0; tLeft = tTotal; save(); }
    function tSet(ms) { now = Date.now(); tTotal = Math.max(1000, ms); tLeft = tTotal; if (tRunning) tEnd = now + tTotal; save(); }
    function tAdd(ms) {
        now = Date.now();
        if (tRunning) { const r = Math.max(1000, tEnd - now + ms); tEnd = now + r; tTotal = Math.max(tTotal + ms, r); }
        else { tLeft = Math.max(1000, tLeft + ms); tTotal = tLeft; }
        save();
    }

    // ── stopwatch ──
    property real swStart: 0        // epoch ms of the current run (0 = stopped)
    property real swAcc: 0          // time from earlier runs
    property var laps: []           // [ms total at each lap], newest last
    readonly property bool swRunning: swStart > 0
    function swElapsed(t) { return swAcc + (swRunning ? Math.max(0, t - swStart) : 0); }
    function swToggle() { const t = Date.now(); if (swRunning) { swAcc += t - swStart; swStart = 0; } else swStart = t; save(); }
    function swLap() { if (swRunning) { laps = laps.concat([swElapsed(Date.now())]).slice(-50); save(); } }
    function swReset() { swStart = 0; swAcc = 0; laps = []; save(); }
    function fmtSw(ms) {
        const cs = Math.floor(ms / 10) % 100, s2 = Math.floor(ms / 1000), h = Math.floor(s2 / 3600), m = Math.floor(s2 % 3600 / 60), ss = s2 % 60;
        const p = n => String(n).padStart(2, "0");
        return (h > 0 ? h + ":" + p(m) : p(m)) + ":" + p(ss) + "." + p(cs);
    }

    // ── pomodoro (durations: Settings > Time & Language > Pomodoro) - drives the timer above ──
    property bool pomo: false
    property string pomoPhase: "focus"      // focus | break | long
    property int pomoDone: 0                // focus rounds finished
    function pomoMin(p) { return p === "focus" ? (Cfg.data.pomoFocus || 25) : p === "long" ? (Cfg.data.pomoLong || 15) : (Cfg.data.pomoBreak || 5); }
    function pomoStart() { pomo = true; pomoPhase = "focus"; pomoDone = 0; tSet(pomoMin("focus") * 60000); tStart(); }
    function pomoStop() { pomo = false; tReset(); }
    function pomoNext() {
        if (pomoPhase === "focus") { pomoDone += 1; pomoPhase = pomoDone % (Cfg.data.pomoCycles || 4) === 0 ? "long" : "break"; }
        else pomoPhase = "focus";
        tSet(pomoMin(pomoPhase) * 60000); tStart();
        ring(Cfg.tr(pomoPhase === "focus" ? "Back to focus" : pomoPhase === "long" ? "Long break" : "Short break"), pomoMin(pomoPhase) + " " + Cfg.tr("min"), true);
    }

    // ── alarms ──
    property var alarms: []          // [{ h, m, on, label, last }]  last = "yyyy-MM-dd" it last rang
    function addAlarm() { const d = new Date(Date.now() + 3600000); alarms = alarms.concat([{ h: d.getHours(), m: 0, on: true, label: "", last: "" }]); save(); }
    function setAlarm(i, patch) { alarms = alarms.map((a, j) => j === i ? Object.assign({}, a, patch) : a); save(); }
    function removeAlarm(i) { alarms = alarms.filter((a, j) => j !== i); save(); }
    readonly property var nextAlarm: {
        let best = null;
        const n = new Date(now);
        for (const a of alarms) {
            if (!a.on) continue;
            const d = new Date(n); d.setHours(a.h, a.m, 0, 0);
            if (d.getTime() <= n.getTime()) d.setDate(d.getDate() + 1);
            if (!best || d < best) best = d;
        }
        return best;
    }

    // ── ringing ──
    property string ringing: ""          // what just went off (shown in the dashboard until dismissed)
    signal rang(string title)          // Mascot.qml cheers
    // sounds: ~/.local/share/sounds/sakura/alarm-{a,b,c}.wav (Cfg "alarmSound", Settings > Time & Language > Pomodoro),
    // pomo-cue.wav for pomodoro phase changes. Made by ~/.config/hypr/scripts/bubble-synth.py (soft bubble pops).
    readonly property string sndDir: home + "/.local/share/sounds/sakura/"
    function alarmFile(k) { return sndDir + "alarm-" + (k || Cfg.data.alarmSound || "a") + ".wav"; }
    function preview(k) { Quickshell.execDetached(["pw-play", "--volume", "0.4", k === "pomo" ? sndDir + "pomo-cue.wav" : alarmFile(k)]); }
    // cue = true: a short soft chime (pomodoro phase change) instead of the full alarm
    function ring(title, body, cue) {
        ringing = title; rang(title);
        Notch.notice("timer", title);     // the notch says it too (TopBar.qml)
        stopRing();
        if (cue) {
            Quickshell.execDetached(["notify-send", "-a", "Timer", "-i", "alarm-symbolic", title, body]);
            Quickshell.execDetached(["pw-play", "--volume", "0.45", sndDir + "pomo-cue.wav"]);
            return;
        }
        // 3 rings ~2.5 s apart, getting a little louder; closing the notification (or `qs ipc call timers dismiss`) stops them
        ringProc.command = ["sh", "-c",
            "trap 'kill $p 2>/dev/null; exit 0' TERM INT; " +
            "for v in 0.35 0.45 0.55; do pw-play --volume $v \"$1\" 2>/dev/null & p=$!; wait $p; sleep 0.3 & p=$!; wait $p; done", "sh", alarmFile()];
        ringProc.running = true;
        noteProc.running = false;
        noteProc.command = ["notify-send", "-a", "Timer", "-u", "critical", "-i", "alarm-symbolic", "-w", "-A", "stop=" + Cfg.tr("Stop"), title, body];
        noteProc.running = true;
    }
    function stopRing() { ringProc.running = false; }
    function dismiss() { stopRing(); noteProc.running = false; ringing = ""; }
    Process { id: ringProc }
    Process { id: noteProc; onExited: tm.stopRing() }   // notification closed / "Stop" pressed
    function fmt(ms) {
        const s = Math.ceil(ms / 1000), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), ss = s % 60;
        const p = n => String(n).padStart(2, "0");
        return (h > 0 ? h + ":" + p(m) : p(m)) + ":" + p(ss);
    }

    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            tm.now = Date.now();
            if (tm.tRunning && tm.now >= tm.tEnd) {
                tm.tEnd = 0; tm.tLeft = 0; tm.save();
                if (tm.pomo) tm.pomoNext(); else tm.ring(Cfg.tr("Timer is up"), tm.fmt(tm.tTotal));
            }
            const d = new Date(tm.now), today = Qt.formatDate(d, "yyyy-MM-dd");
            tm.alarms.forEach((a, i) => {
                if (a.on && a.last !== today && d.getHours() === a.h && d.getMinutes() === a.m) {
                    tm.setAlarm(i, { last: today });
                    tm.ring(Cfg.tr("Alarm") + " " + String(a.h).padStart(2, "0") + ":" + String(a.m).padStart(2, "0"), a.label || "");
                }
            });
        }
    }

    // ── persistence ──
    FileView {
        id: file
        path: tm.home + "/.config/sakura/timers.json"
        blockLoading: true
        onLoaded: {
            try {
                const j = JSON.parse(text());
                for (const k of ["tEnd", "tTotal", "tLeft", "swStart", "swAcc", "laps"]) if (j[k] !== undefined) tm[k] = j[k];
                tm.alarms = j.alarms || [];
            } catch (e) {}
        }
    }
    Timer { id: saveT; interval: 300; onTriggered: file.setText(JSON.stringify({
        tEnd: tm.tEnd, tTotal: tm.tTotal, tLeft: tm.tLeft, swStart: tm.swStart, swAcc: tm.swAcc, laps: tm.laps, alarms: tm.alarms }, null, 1)) }
    function save() { saveT.restart(); }

    IpcHandler {
        target: "timers"
        function start(minutes: int): void { tm.tSet(minutes * 60000); tm.tStart(); }
        function pause(): void { tm.tPause(); }
        function stopwatch(): void { tm.swToggle(); }
        function pomodoro(): void { if (tm.pomo) tm.pomoStop(); else tm.pomoStart(); }
        function lap(): void { tm.swLap(); }
        function dismiss(): void { tm.dismiss(); }
        function status(): string { return (tm.tRunning ? "timer " + tm.fmt(tm.tRemain) : "timer " + tm.fmt(tm.tLeft) + " (stopped)") + " | stopwatch " + tm.fmtSw(tm.swElapsed(Date.now())) + (tm.swRunning ? "" : " (stopped)") + " laps " + tm.laps.length + " | alarms " + tm.alarms.length; }
    }
}
