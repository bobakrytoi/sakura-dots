// sakura mono - the pocket: a tray for a day on the edge drum (EdgeTab). Type text into it (Enter = keep),
// Ctrl+V a picture from the clipboard into it; click a row to copy it back. Nothing else - on purpose.
// Pictures are saved into ~/.cache/sakura/pocket/<id>/, the list is ~/.cache/sakura/pocket/index.json.
// Everything older than 24 h is cleaned up by itself.
import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: pk

    readonly property string dir: Quickshell.env("HOME") + "/.cache/sakura/pocket"
    readonly property int maxItems: 40
    readonly property real ttl: 24 * 3600 * 1000
    property var items: []              // newest first: { id, kind: text|image, text, path, t }
    property int rev: 0

    function fileUrl(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/"); }

    Process {
        running: true
        command: ["mkdir", "-p", pk.dir]
        onExited: { index.path = pk.dir + "/index.json"; }
    }
    FileView {
        id: index
        printErrors: false
        onLoaded: {
            let a = [];
            try { a = JSON.parse(text()); } catch (e) { a = []; }
            pk.items = Array.isArray(a) ? a.filter(i => i.kind === "text" || i.kind === "image") : [];
            pk.prune();
        }
        onLoadFailed: { pk.items = []; pk.prune(); }
    }
    function save() { if (index.path !== "") index.setText(JSON.stringify(items)); }

    function push(e) {
        let a = items.filter(i => !(e.kind === "text" && i.kind === "text" && i.text === e.text));   // same text → to the top
        a.unshift(e);
        for (const x of a.slice(maxItems)) drop_(x);
        items = a.slice(0, maxItems);
        save();
    }
    function drop_(x) { if (x.kind === "image") Quickshell.execDetached(["rm", "-rf", "--", dir + "/" + x.id]); }

    function addText(t) {
        if (!t || t.trim() === "") return;
        push({ id: String(Date.now()), kind: "text", text: t, t: Date.now() });
    }

    // Ctrl+V: a picture in the clipboard → saved into the pocket; anything else → onText() (the field pastes it)
    property var onText: null
    function paste(textFallback) {
        if (pasteProc.running) return;
        onText = textFallback;
        const id = String(Date.now());
        pasteProc.pid_ = id;
        pasteProc.command = ["sh", "-c",
            "t=$(wl-paste --list-types 2>/dev/null | grep -m1 '^image/') || { echo TXT; exit 0; }; " +
            "e=${t#image/}; e=${e%%[;+]*}; d=\"$1/$2\"; mkdir -p \"$d\" && wl-paste -t \"$t\" > \"$d/paste.$e\" && echo \"IMG $d/paste.$e\"",
            "sh", dir, id];
        pasteProc.running = true;
    }
    Process {
        id: pasteProc
        property string pid_: ""
        stdout: StdioCollector { onStreamFinished: {
            const s = this.text.trim();
            if (s.startsWith("IMG ")) { pk.push({ id: pasteProc.pid_, kind: "image", path: s.slice(4), t: Date.now() }); pk.rev++; }
            else if (pk.onText) pk.onText();
        } }
    }

    function remove(id) {
        const x = items.find(i => i.id === id);
        if (x) drop_(x);
        items = items.filter(i => i.id !== id);
        save();
    }
    function clear() {
        for (const x of items) drop_(x);
        items = [];
        save();
    }
    function copy(x) {
        if (x.kind === "image") Quickshell.execDetached(["sh", "-c", "wl-copy < \"$1\"", "sh", x.path]);
        else Quickshell.execDetached(["wl-copy", "--", x.text]);
    }
    function ago(t) {
        const m = Math.floor((Date.now() - t) / 60000);
        return m < 1 ? Cfg.tr("just now") : m < 60 ? m + " " + Cfg.tr("min") : Math.floor(m / 60) + " " + Cfg.tr("h");
    }

    // older than a day → gone (and picture folders the list lost track of)
    function prune() {
        const cut = Date.now() - ttl;
        const old = items.filter(i => !(i.t >= cut));
        if (old.length > 0) { for (const x of old) drop_(x); items = items.filter(i => i.t >= cut); save(); }
        Quickshell.execDetached(["find", dir, "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-mmin", "+1440", "-exec", "rm", "-rf", "{}", "+"]);
    }
    Timer { interval: 10 * 60 * 1000; repeat: true; running: true; onTriggered: pk.prune() }
}
