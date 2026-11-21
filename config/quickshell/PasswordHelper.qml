// sakura mono - Password helper: radial overlay (port of the Windows "Password helper", C#/WPF, by the same author).
// Hotkey (default Ctrl+Shift+P, Settings > Password helper > Shortcut) → qs ipc call pwhelper toggle → a glass flower
// opens around the pointer on the monitor it is on, over a blurred backdrop:
//   inner ring  Generate · Clipboard · Saved · Add          outer ring  saved passwords (pinned first) · More
//   centre      X / Esc (shows what is under the pointer)
// Everything only copies (wl-copy, passwords as --sensitive) and says so in the notch; nothing is typed for you.
// Panels open in place: saved list (copy / username / details / edit / delete), clipboard history, add/edit form,
// details, delete confirm, vault recovery. Keyboard: ←/→ walk a ring, Tab switches rings, Enter picks, Esc back/close,
// in lists ↑/↓ + Enter, typing searches. Backend: PwVault.qml + hypr/scripts/pwhelper.py.
//   qs ipc call pwhelper toggle | open | close | state | panel <saved|clip|add|radial> | pick <i> | lock | unlock
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Shapes

Scope {
    id: ph
    property var lock: null                 // Lock.qml (vault locks with the screen)

    // ── state ─────────────────────────────────────────────
    property bool shown: false
    property var scr: Cfg.mainScreen || Quickshell.screens[0]
    property real cx: 600
    property real cy: 400
    property string panel: ""               // "" (radial) | saved | clip | edit | details | confirm | recover
    property int sel: -1                    // petal under the pointer / the keyboard
    property bool kbd: false                // selection made by keys (the centre then names it too)
    property var editing: null              // entry being edited, null = new
    property var detail: null
    property string backTo: ""
    property int openSerial: 0
    // shared tooltip (IconBtn)
    property var tipOwner: null
    property string tipText: ""
    property real tipX: 0
    property real tipY: 0
    function showTip(item, text) {
        if (!text || !item) return;
        const p = item.mapToItem(tipLayer, item.width / 2, 0);
        tipOwner = item; tipText = text; tipX = p.x; tipY = p.y;
    }
    function hideTip(item) { if (tipOwner === item) { tipOwner = null; tipText = ""; } }
    readonly property var o: PwVault.o
    function tr(s) { return PwVault.tr(s); }

    readonly property string fUi: Cfg.fontUi
    readonly property string fIcon: "Symbols Nerd Font"
    readonly property color cFg: "#eceef4"
    readonly property color cMuted: "#8a8fa3"
    readonly property real k: o.buttonSize === "s" ? 0.86 : o.buttonSize === "l" ? 1.16 : 1
    readonly property bool motion: o.animations && !o.reducedMotion
    function dur(ms) { return motion ? ms / Math.max(0.5, o.animSpeed) : 0; }
    readonly property color glassFill: Qt.rgba(15 / 255, 17 / 255, 25 / 255, o.glass ? Math.max(0.45, Math.min(0.97, o.glassOpacity)) : 0.96)

    // geometry (RadialLayout.cs in spirit: hub, then rings outward; sized by the button size setting)
    readonly property real rc: 56 * k
    readonly property real ri0: rc + 10
    readonly property real ri1: ri0 + 92 * k
    readonly property real ro0: ri1 + 8
    readonly property real ro1: ro0 + 64 * k
    readonly property real gap: 5
    readonly property real outerR: outer.length ? ro1 : ri1
    readonly property real box: 2 * (ro1 + 16)

    // ── what is on the rings ─────────────────────────────
    readonly property var inner: {
        const l = [ { kind: "gen", icon: "", label: "Generate", desc: "Generate a secure password", primary: true } ];
        if (o.history) l.push({ kind: "clip", icon: "", label: "Clipboard", desc: "Recent clipboard items" });
        l.push({ kind: "saved", icon: "", label: "Saved", desc: "Pick, edit, delete" });
        l.push({ kind: "add", icon: "", label: "Add", desc: "Save a new one" });
        return l;
    }
    readonly property var outer: {
        if (!PwVault.ready) return [];
        const all = PwVault.sorted, max = Math.max(0, o.maxRadial);
        const l = all.slice(0, max).map(e => ({ kind: "entry", e: e, label: e.title, mono: mono(e.title), desc: e.username || e.url || "Copy its password" }));
        if (all.length > max && max > 0) { l.pop(); l.push({ kind: "more", icon: "", label: "More", desc: (all.length - max + 1) + " " + "more" }); }
        return l;
    }
    readonly property var items: inner.concat(outer)
    function mono(t) { for (const c of String(t)) if (c.toUpperCase() !== c.toLowerCase() || (c >= "0" && c <= "9")) return c.toUpperCase(); return "•"; }
    readonly property real stepI: 360 / Math.max(1, inner.length)
    readonly property real spanO: outer.length ? Math.min(360 / outer.length, 40) : 0
    readonly property real startO: outer.length * spanO >= 359.9 ? 0 : -outer.length * spanO / 2
    function a0(i) { return i < inner.length ? i * stepI : startO + (i - inner.length) * spanO; }
    function span(i) { return i < inner.length ? stepI : spanO; }
    function pol(r, deg) { const a = (deg - 90) * Math.PI / 180; return [r * Math.cos(a), r * Math.sin(a)]; }
    // an annular sector with straight gaps and rounded corners (same shape as the file converter's petals)
    function sector(b0, b1, ri, ro, g, cr, c) {
        const off = (r) => Math.asin(Math.min(0.99, g / 2 / r)) * 180 / Math.PI;
        const P = (r, d) => { const p = pol(r, d); return (c + p[0]).toFixed(2) + " " + (c + p[1]).toFixed(2); };
        const oo = off(ro), oi = off(ri);
        const A0o = b0 + oo, A1o = b1 - oo, A0i = b0 + oi, A1i = b1 - oi;
        const dco = cr / ro * 180 / Math.PI, dci = cr / ri * 180 / Math.PI;
        const large = (A1o - A0o - 2 * dco) > 180 ? 1 : 0, largeI = (A1i - A0i - 2 * dci) > 180 ? 1 : 0;
        const rad = (r, d, o2) => { const p = pol(r, d), q = pol(1, d + 90); return (c + p[0] + q[0] * o2).toFixed(2) + " " + (c + p[1] + q[1] * o2).toFixed(2); };
        return "M " + P(ro, A0o + dco) + " A " + ro + " " + ro + " 0 " + large + " 1 " + P(ro, A1o - dco)
            + " Q " + P(ro, A1o) + " " + rad(ro - cr, b1, -g / 2) + " L " + rad(ri + cr, b1, -g / 2)
            + " Q " + P(ri, A1i) + " " + P(ri, A1i - dci) + " A " + ri + " " + ri + " 0 " + largeI + " 0 " + P(ri, A0i + dci)
            + " Q " + P(ri, A0i) + " " + rad(ri + cr, b0, g / 2) + " L " + rad(ro - cr, b0, g / 2)
            + " Q " + P(ro, A0o) + " " + P(ro, A0o + dco) + " Z";
    }
    // what is at (x, y) from the centre: petal index, -2 = centre, -1 = nothing
    function hitAt(x, y) {
        const d = Math.hypot(x, y);
        let deg = Math.atan2(y, x) * 180 / Math.PI + 90; if (deg < 0) deg += 360;
        if (d < rc + 4) return -2;
        if (d >= ri0 - 4 && d <= ri1 + 3) return Math.floor(deg / stepI) % inner.length;
        if (outer.length && d > ri1 + 3 && d <= ro1 + 8) {
            const rel = (((deg - startO) % 360) + 360) % 360, i = Math.floor(rel / spanO);
            if (i >= 0 && i < outer.length) return inner.length + i;
        }
        return -1;
    }
    readonly property var cur: sel >= 0 && sel < items.length ? items[sel] : null

    // ── open / close ─────────────────────────────────────
    function toggle() { shown ? close() : open(); }
    function open() {
        if (shown) return;
        panel = ""; sel = -1; kbd = false; search.text = ""; openSerial++;
        cursorP.running = false; cursorP.running = true;
    }
    Process {
        id: cursorP
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector { onStreamFinished: ph.placeAt(this.text) }
    }
    function placeAt(txt) {
        let p = null;
        try { p = JSON.parse(txt); } catch (e) {}
        const fm = Hyprland.focusedMonitor;
        let s = p ? Quickshell.screens.find(q => p.x >= q.x && p.x < q.x + q.width && p.y >= q.y && p.y < q.y + q.height) : null;
        if (!s) s = (fm && Quickshell.screens.find(q => q.name === fm.name)) || Cfg.mainScreen || Quickshell.screens[0];
        scr = s;
        const W = s.width, H = s.height, R = ro1 + 24;
        let x = W / 2, y = H / 2;
        if (o.placement !== "center" && p) { x = p.x - s.x; y = p.y - s.y; }
        cx = Math.max(R, Math.min(W - R, x));
        cy = Math.max(R, Math.min(H - R - 30, y));
        shown = true;
    }
    function close() { shown = false; panel = ""; detail = null; editing = null; }
    function done() { if (o.closeOnSelect) close(); }

    // ── doing it ─────────────────────────────────────────
    function activate(i) {
        const it = items[i]; if (!it) return;
        PwVault.click();
        switch (it.kind) {
        case "gen":   PwVault.generateCopy(); done(); break;
        case "clip":  showPanel("clip"); break;
        case "saved": case "more": openSaved(); break;
        case "add":   if (PwVault.ready) openEditor(null, ""); else openSaved(); break;
        case "entry": PwVault.copyPassword(it.e); done(); break;
        }
    }
    function openSaved() {
        if (PwVault.state === "locked" || PwVault.state === "nokeyring" || PwVault.state === "down") PwVault.unlock();
        showPanel(PwVault.state === "corrupt" ? "recover" : "saved");
    }
    function showPanel(p) { panel = p; listSel = 0; search.text = ""; if (p === "saved" || p === "clip") focusT.restart(); }
    Timer { id: focusT; interval: 30; onTriggered: { if (ph.panel === "edit") fTitle.focusIt(); else search.forceActiveFocus(); } }
    function back() {
        if (panel === "confirm" || panel === "edit" && backTo === "details") { panel = backTo || "saved"; backTo = ""; if (panel === "saved") focusT.restart(); return; }
        if (panel === "details" || panel === "edit") { panel = "saved"; focusT.restart(); return; }
        if (panel !== "") { panel = ""; return; }
        close();
    }
    function openEditor(e, from) {
        editing = e; backTo = from || "";
        fTitle.text = e ? e.title : ""; fUser.text = e ? e.username : ""; fPass.text = ""; fUrl.text = e ? e.url : "";
        fNotes.text = e ? e.notes : ""; fPinned = e ? !!e.pinned : false; editErr = ""; passShown = false;
        panel = "edit"; focusT.restart();
    }
    property bool fPinned: false
    property string editErr: ""
    property bool passShown: false
    function saveEditor() {
        const entry = { title: fTitle.text.trim(), username: fUser.text.trim(), password: fPass.text, url: fUrl.text.trim(), notes: fNotes.text, pinned: fPinned };
        if (!entry.title) { editErr = tr("Enter a title."); return; }
        if (!editing && !entry.password) { editErr = tr("Enter a password."); return; }
        PwVault.click();
        const after = r => { if (r.ok) { fPass.text = ""; if (ph.backTo === "details" && ph.editing) { ph.detail = PwVault.entries.find(x => x.id === ph.editing.id) || null; ph.panel = ph.detail ? "details" : "saved"; } else ph.showPanel("saved"); ph.editing = null; } else ph.editErr = r.error; };
        if (editing) PwVault.update(editing.id, entry, entry.password !== "", after);
        else PwVault.add(entry, after);
    }
    function openDetails(e) { detail = e; revealed = ""; panel = "details"; }
    property string revealed: ""
    property var confirmFor: null
    function askDelete(e, from) { confirmFor = e; backTo = from; panel = "confirm"; }
    function doDelete() { const e = confirmFor; if (!e) return; PwVault.remove(e.id, r => { ph.confirmFor = null; ph.detail = null; ph.backTo = ""; ph.showPanel("saved"); }); }

    // lists
    property int listSel: 0
    readonly property string q: search.text.trim().toLowerCase()
    readonly property var savedRows: PwVault.sorted.filter(e => !q || (e.title + " " + e.username + " " + e.url).toLowerCase().includes(q))
    readonly property var clipRows: PwVault.history.filter(h => !q || h.text.toLowerCase().includes(q))
    readonly property var rows: panel === "saved" ? savedRows : panel === "clip" ? clipRows : []
    function preview(t) { const c = String(t).replace(/\s+/g, " ").trim(); return c.length <= 64 ? c : c.slice(0, 63) + "…"; }
    function when(iso) { const d = new Date(iso); return isNaN(d.getTime()) ? "" : Qt.formatDateTime(d, "yyyy-MM-dd HH:mm"); }   // UTC on disk → local here
    function rel(ts) {
        const s = Date.now() / 1000 - ts;
        if (s < 10) return tr("just now");
        if (s < 60) return Math.floor(s) + " s"; if (s < 3600) return Math.floor(s / 60) + " min";
        if (s < 86400) return Math.floor(s / 3600) + " h"; return Math.floor(s / 86400) + " d";
    }
    function pickRow(i) {
        const r = rows[i]; if (!r) return;
        PwVault.click();
        if (panel === "saved") { PwVault.copyPassword(r); done(); }
        else if (panel === "clip") { PwVault.copyHistory(r); done(); }
    }
    readonly property string statusLine: PwVault.state === "locked" ? tr("Vault locked - click Saved to unlock")
        : PwVault.state === "nokeyring" ? tr("Keyring unavailable") + " · " + PwVault.problem
        : PwVault.state === "corrupt" ? tr("The vault does not open")
        : PwVault.state === "down" ? "pwhelper.py stopped"
        : PwVault.state === "loading" ? "…" : ""

    // vault follows the screen lock
    Connections {
        target: ph.lock
        ignoreUnknownSignals: true
        function onLockedChanged() { if (ph.lock.locked && ph.o.lockOnScreenLock) { PwVault.lock(); ph.close(); } }
    }

    IpcHandler {
        target: "pwhelper"
        function toggle(): void { ph.toggle(); }
        function open(): void { ph.open(); }
        function close(): void { ph.close(); }
        function lock(): void { PwVault.lock(); }
        function unlock(): void { PwVault.unlock(); }
        function screenLocked(): void { if (ph.o.lockOnScreenLock) { PwVault.lock(); ph.close(); } }      // hypr/scripts/lock.sh
        function panel(p: string): void { if (!ph.shown) ph.open(); ph.pendingPanel = p; panelT.restart(); }
        function pick(i: int): void { if (ph.shown && !ph.panel) ph.activate(i); }
        function hover(i: int): void { ph.sel = i; ph.kbd = true; }
        // tests (like convert's test/pick): fill the open form, press Save, open a row's details / editor, search
        function fill(title: string, user: string, pass: string, url: string): void { if (ph.panel !== "edit") return; fTitle.text = title; fUser.text = user; fPass.text = pass; fUrl.text = url; }
        function save(): void { if (ph.panel === "edit") ph.saveEditor(); }
        function details(i: int): void { if (ph.panel === "saved" && ph.rows[i]) ph.openDetails(ph.rows[i]); }
        function edit(i: int): void { if (ph.panel === "saved" && ph.rows[i]) ph.openEditor(ph.rows[i], "saved"); }
        function find(q: string): void { search.text = q; }
        function row(i: int): void { ph.listSel = i; }
        function hotkey(combo: string): string { PwVault.setHotkey(combo, err => PwVault.hotkeyMsg = err); return "checking"; }
        function hotkeyResult(): string { return PwVault.hotkeyMsg + " | now: " + PwVault.o.hotkey; }
        function state(): string {
            return JSON.stringify({ shown: ph.shown, panel: ph.panel, screen: ph.scr ? ph.scr.name : "", x: ph.cx, y: ph.cy,
                                    vault: PwVault.state, problem: PwVault.problem, entries: PwVault.entries.length,
                                    history: PwVault.history.length, items: ph.items.map(i => i.label), hotkey: PwVault.o.hotkey });
        }
    }
    property string pendingPanel: ""
    Timer { id: panelT; interval: 260; onTriggered: { const p = ph.pendingPanel; ph.pendingPanel = "";
            if (p === "add") ph.openEditor(null, ""); else if (p === "saved") ph.openSaved(); else if (p === "radial") ph.panel = ""; else ph.showPanel(p); } }

    // ── small pieces for the panels ──────────────
    component IconBtn: Rectangle {
        id: ib
        property string icon: ""
        property string tip: ""
        property bool danger: false
        signal clicked()
        width: 30; height: 30; radius: 10
        color: iba.containsMouse ? (danger ? "#40ff6b6b" : Cfg.acc(0.25)) : "#14ffffff"
        Text { anchors.centerIn: parent; text: ib.icon; font.family: ph.fIcon; font.pixelSize: 12; color: ib.danger && iba.containsMouse ? "#ff8a8a" : ph.cFg }
        MouseArea { id: iba; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { PwVault.click(); ib.clicked(); }
                    // the tooltip lives on a layer over the whole window (a clipped list would cut it)
                    onContainsMouseChanged: containsMouse ? ph.showTip(ib, ib.tip) : ph.hideTip(ib) }
        onVisibleChanged: if (!visible) ph.hideTip(ib)
        Component.onDestruction: ph.hideTip(ib)
    }
    component PBtn: Rectangle {
        id: pb
        property string text: ""
        property bool primary: false
        property bool danger: false
        signal clicked()
        width: pbT.implicitWidth + 30; height: 36; radius: 12
        color: primary ? (pba.containsMouse ? Qt.lighter(Cfg.accent, 1.08) : Cfg.accent)
             : danger ? (pba.containsMouse ? "#55ff6b6b" : "#33ff6b6b") : (pba.containsMouse ? "#24ffffff" : "#14ffffff")
        Text { id: pbT; anchors.centerIn: parent; text: pb.text; font.family: ph.fUi; font.pixelSize: 13; font.weight: Font.DemiBold
               color: pb.primary ? Cfg.accFg : pb.danger ? "#ffb3b3" : ph.cFg }
        MouseArea { id: pba; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { PwVault.click(); pb.clicked(); } }
    }
    component Fld: Column {
        id: fl
        property string label: ""
        property alias text: fti.text
        property alias input: fti
        property bool secret: false
        property string hint: ""
        property int maxLen: 200
        property real rightPad: 0
        property var next: null
        function focusIt() { fti.forceActiveFocus(); }
        spacing: 6
        width: parent ? parent.width : 0
        Text { text: fl.label.toUpperCase(); font.family: ph.fUi; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.8; color: ph.cMuted }
        Rectangle {
            width: parent.width; height: 38; radius: 11; color: "#14ffffff"
            border.width: 1; border.color: fti.activeFocus ? Cfg.accent : "#1fffffff"
            TextInput {
                id: fti
                anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12 + fl.rightPad; verticalCenter: parent.verticalCenter }
                color: ph.cFg; font.family: fl.secret ? "monospace" : ph.fUi; font.pixelSize: 13; clip: true
                selectionColor: Cfg.accent; selectedTextColor: Cfg.accFg
                echoMode: fl.secret && !ph.passShown ? TextInput.Password : TextInput.Normal
                maximumLength: fl.maxLen
                KeyNavigation.tab: fl.next
                onAccepted: ph.saveEditor()
                Keys.onEscapePressed: ph.back()
                Text { anchors.verticalCenter: parent.verticalCenter; text: fl.hint; color: ph.cMuted; font.family: ph.fUi; font.pixelSize: 13; visible: fti.text === "" }
            }
        }
    }

    component DRow: Rectangle {
        id: dr
        property string label: ""
        property string value: ""
        property bool mono: false
        default property alias extra: drX.data
        width: parent ? parent.width : 0; height: Math.max(52, drC.implicitHeight + 18); radius: 14; color: "#10ffffff"
        Column {
            id: drC
            anchors { left: parent.left; leftMargin: 14; right: drX.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 3
            Text { text: dr.label.toUpperCase(); font.family: ph.fUi; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 0.8; color: ph.cMuted }
            Text { width: parent.width; text: dr.value || "-"; wrapMode: Text.WrapAnywhere; maximumLineCount: 6; elide: Text.ElideRight
                   font.family: dr.mono ? "monospace" : ph.fUi; font.pixelSize: 13; color: ph.cFg }
        }
        Row { id: drX; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } spacing: 4 }
    }

    // ── the overlay ──────────────────────────────────────
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: ph.shown ? ph.dur(170) : ph.dur(130); easing.type: ph.shown ? Easing.OutCubic : Easing.InCubic } }

    PanelWindow {
            id: win
            visible: ph.shown || ph.t > 0.001
            screen: ph.scr
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "pwhelper"      // hyprland.lua: blur behind it
            WlrLayershell.keyboardFocus: ph.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            HyprlandFocusGrab { windows: [ win ]; active: ph.shown; onCleared: if (ph.o.closeOnOutside) ph.close() }

            // frosted backdrop: Hyprland blurs everything under this layer (layer rule "pwhelper"); off = a plain dim
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.03, 0.035, 0.06, ph.o.glass ? 0.10 + 0.34 * ph.o.blur : 0.86)
                opacity: ph.t
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: ph.shown
                onPositionChanged: mouse => { if (ph.panel) return; const h = ph.hitAt(mouse.x - ph.cx, mouse.y - ph.cy); if (h !== ph.sel || ph.kbd) { ph.sel = h; ph.kbd = false; } }
                onClicked: mouse => {
                    if (ph.panel) { if (ph.o.closeOnOutside) ph.close(); else ph.back(); return; }
                    const h = ph.hitAt(mouse.x - ph.cx, mouse.y - ph.cy);
                    if (h >= 0) ph.activate(h);
                    else if (h === -2) { PwVault.click(); ph.close(); }
                    else if (ph.o.closeOnOutside) ph.close();
                }
            }

            // keyboard
            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onPressed: ev => {
                    if (ev.key === Qt.Key_Escape) { ph.back(); ev.accepted = true; return; }
                    if (ph.panel !== "") return;
                    const n = ph.items.length, ni = ph.inner.length;
                    const inOuter = ph.sel >= ni;
                    const lo = inOuter ? ni : 0, cnt = inOuter ? n - ni : ni;
                    if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Down || ev.key === Qt.Key_Left || ev.key === Qt.Key_Up) {
                        const d = ev.key === Qt.Key_Right || ev.key === Qt.Key_Down ? 1 : -1;
                        ph.sel = ph.sel < 0 ? 0 : lo + ((ph.sel - lo + d + cnt) % cnt); ph.kbd = true; ev.accepted = true;
                    } else if (ev.key === Qt.Key_Tab || ev.key === Qt.Key_Backtab) {
                        ph.sel = n > ni && !inOuter ? ni : 0;
                        ph.kbd = true; ev.accepted = true;
                    } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) {
                        if (ph.sel >= 0) ph.activate(ph.sel); ev.accepted = true;
                    } else if (ev.key >= Qt.Key_1 && ev.key <= Qt.Key_9) {
                        const i = ni + ev.key - Qt.Key_1; if (i < n) ph.activate(i); ev.accepted = true;
                    }
                }
            }

            // ── the flower ───────────────────────────────
            Item {
                id: flower
                x: ph.cx - ph.box / 2; y: ph.cy - ph.box / 2
                width: ph.box; height: ph.box
                readonly property real c: width / 2
                visible: opacity > 0.01
                opacity: ph.panel === "" ? ph.t : 0
                scale: ph.panel === "" ? (ph.motion ? 0.86 + 0.14 * ph.t : 1) : 0.9
                Behavior on opacity { enabled: ph.shown; NumberAnimation { duration: ph.dur(150) } }
                Behavior on scale { enabled: ph.shown && ph.panel !== ""; NumberAnimation { duration: ph.dur(180); easing.type: Easing.OutCubic } }

                Repeater {
                    model: ph.items
                    Item {
                        id: pt
                        required property var modelData
                        required property int index
                        readonly property bool outerRing: index >= ph.inner.length
                        readonly property bool on: ph.sel === index
                        readonly property real b0: ph.a0(index)
                        readonly property real mid: b0 + ph.span(index) / 2
                        readonly property var push: ph.pol(on ? 6 : 0, mid)
                        width: flower.width; height: flower.height
                        x: push[0]; y: push[1]
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        // staggered entrance (OverlayWindow.xaml.cs: 0.72 → 1 with a slight back-ease)
                        property real appear: ph.motion ? 0 : 1
                        opacity: appear
                        scale: 0.72 + 0.28 * appear
                        transformOrigin: Item.Center
                        Connections { target: ph; function onOpenSerialChanged() { pt.appear = ph.motion ? 0 : 1; if (ph.motion) enter.restart(); } }
                        SequentialAnimation {
                            id: enter
                            running: ph.motion
                            PauseAnimation { duration: ph.dur(30 + pt.index * 22) }
                            NumberAnimation { target: pt; property: "appear"; to: 1; duration: ph.dur(230); easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                        }
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                fillColor: pt.on ? Cfg.acc(0.34) : pt.modelData.primary ? Qt.tint(ph.glassFill, Cfg.acc(0.16)) : ph.glassFill
                                strokeColor: pt.on ? Cfg.acc(0.9) : pt.modelData.primary ? Cfg.acc(0.45) : "#2effffff"
                                strokeWidth: 1.2
                                Behavior on fillColor { ColorAnimation { duration: 120 } }
                                PathSvg { path: pt.outerRing ? ph.sector(pt.b0, pt.b0 + ph.spanO, ph.ro0, ph.ro1, 4, 10, flower.c)
                                                             : ph.sector(pt.b0, pt.b0 + ph.stepI, ph.ri0, ph.ri1, ph.gap, 14, flower.c) }
                            }
                        }
                        // label
                        Column {
                            readonly property var p: ph.pol(pt.outerRing ? (ph.ro0 + ph.ro1) / 2 : (ph.ri0 + ph.ri1) / 2 + 3, pt.mid)
                            x: flower.c + p[0] - width / 2; y: flower.c + p[1] - height / 2
                            spacing: 3
                            // monogram for saved entries, an icon for the rest
                            Rectangle {
                                visible: pt.modelData.kind === "entry"
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 26 * ph.k; height: width; radius: width / 2
                                color: pt.on ? Cfg.accent : Cfg.acc(0.22)
                                border.width: pt.modelData.e && pt.modelData.e.pinned ? 1.5 : 0; border.color: Cfg.accent
                                Text { anchors.centerIn: parent; text: pt.modelData.mono || ""; font.family: ph.fUi; font.pixelSize: 13 * ph.k; font.weight: Font.Bold
                                       color: pt.on ? Cfg.accFg : ph.cFg }
                            }
                            Text {
                                visible: pt.modelData.kind !== "entry"
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: pt.modelData.icon || ""
                                font.family: ph.fIcon; font.pixelSize: (pt.outerRing ? 15 : 19) * ph.k
                                color: pt.on || pt.modelData.primary ? Cfg.accent : "#c9ccd8"
                            }
                            Text {
                                visible: !pt.outerRing || ph.spanO >= 34
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(implicitWidth, pt.outerRing ? 64 * ph.k : 110 * ph.k)
                                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                text: pt.modelData.kind === "entry" ? pt.modelData.label : ph.tr(pt.modelData.label)
                                font.family: ph.fUi; font.pixelSize: (pt.outerRing ? 10 : 13) * ph.k; font.weight: pt.outerRing ? Font.DemiBold : Font.Bold
                                color: pt.on ? "#ffffff" : ph.cFg
                            }
                        }
                    }
                }

                // centre: X / Esc, or what is under the pointer
                Rectangle {
                    id: hub
                    anchors.centerIn: parent
                    width: ph.rc * 2; height: width; radius: width / 2
                    color: ph.sel === -2 ? Qt.tint(ph.glassFill, Cfg.acc(0.25)) : Qt.rgba(15 / 255, 17 / 255, 25 / 255, Math.min(0.94, ph.glassFill.a + 0.12))
                    border.width: 1.2; border.color: ph.sel === -2 ? Cfg.acc(0.8) : "#30ffffff"
                    scale: (ph.sel === -2 ? 1.05 : 1) * (ph.motion ? 0.86 + 0.14 * ph.t : 1)
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        spacing: 2
                        Text {
                            visible: !ph.cur
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: ""; font.family: ph.fIcon; font.pixelSize: 22 * ph.k
                            color: ph.sel === -2 ? Cfg.accent : ph.cFg
                        }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            text: ph.cur ? (ph.cur.kind === "entry" ? ph.cur.label : ph.tr(ph.cur.label)) : "Esc"
                            font.family: ph.fUi; font.pixelSize: ph.cur ? 14 * ph.k : 10 * ph.k; font.weight: Font.Bold
                            color: ph.cur ? Cfg.accent : ph.cMuted
                        }
                        Text {
                            visible: !!ph.cur
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: ph.cur ? (ph.cur.kind === "entry" ? (ph.cur.e.username || ph.tr("Copy its password")) : ph.tr(ph.cur.desc)) : ""
                            font.family: ph.fUi; font.pixelSize: 10 * ph.k; color: ph.cMuted
                            wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                        }
                    }
                }
                // vault status under the flower
                Rectangle {
                    visible: ph.statusLine !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: flower.c + ph.outerR + 14
                    width: Math.min(560, stT.implicitWidth + 28); height: 28; radius: 14
                    color: ph.glassFill; border.width: 1; border.color: "#26ffffff"
                    Text { id: stT; anchors.centerIn: parent; width: parent.width - 24; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                           text: ph.statusLine; font.family: ph.fUi; font.pixelSize: 11; color: ph.cMuted }
                }
            }

            Rectangle {
                id: card
                readonly property bool on: ph.panel !== ""
                visible: opacity > 0.01
                opacity: on ? ph.t : 0
                scale: on ? 1 : (ph.motion ? 0.94 : 1)
                Behavior on opacity { NumberAnimation { duration: ph.dur(150) } }
                Behavior on scale { NumberAnimation { duration: ph.dur(220); easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                width: 470
                height: Math.min(win.height - 40, body.implicitHeight + 36)
                x: Math.max(16, Math.min(win.width - width - 16, ph.cx - width / 2))
                y: Math.max(16, Math.min(win.height - height - 16, ph.cy - height / 2))
                radius: 24; color: ph.glassFill; border.width: 1; border.color: "#24ffffff"
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: w => w.accepted = false }    // keep clicks inside

                Column {
                    id: body
                    x: 18; y: 18; width: parent.width - 36
                    spacing: 14

                    // header: back · title · close
                    Item {
                        width: parent.width; height: 32
                        IconBtn { icon: ""; tip: ph.tr("Back"); anchors.verticalCenter: parent.verticalCenter; onClicked: ph.back() }
                        Text {
                            anchors.centerIn: parent
                            text: ph.panel === "saved" ? ph.tr("Saved passwords") : ph.panel === "clip" ? ph.tr("Clipboard history")
                                : ph.panel === "edit" ? ph.tr(ph.editing ? "Edit password" : "Add password")
                                : ph.panel === "details" ? (ph.detail ? ph.detail.title : "") : ph.panel === "confirm" ? ph.tr("Delete password?")
                                : ph.panel === "recover" ? ph.tr("The vault does not open") : ""
                            font.family: ph.fUi; font.pixelSize: 15; font.weight: Font.Bold; color: ph.cFg
                            width: Math.min(implicitWidth, parent.width - 90); elide: Text.ElideRight
                        }
                        IconBtn { icon: ""; tip: ph.tr("Close"); anchors { right: parent.right; verticalCenter: parent.verticalCenter } onClicked: ph.close() }
                    }

                    // ── lists: saved / clipboard ──
                    Rectangle {
                        visible: ph.panel === "saved" || ph.panel === "clip"
                        width: parent.width; height: 38; radius: 12; color: "#14ffffff"
                        border.width: 1; border.color: search.activeFocus ? Cfg.accent : "#1fffffff"
                        Text { id: sIc; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: ""; font.family: ph.fIcon; font.pixelSize: 12; color: Cfg.accent }
                        TextInput {
                            id: search
                            anchors { left: sIc.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            color: ph.cFg; font.family: ph.fUi; font.pixelSize: 13; clip: true; selectionColor: Cfg.accent
                            onTextChanged: ph.listSel = 0
                            Keys.onPressed: ev => {
                                if (ev.key === Qt.Key_Down) { ph.listSel = Math.min(ph.rows.length - 1, ph.listSel + 1); ev.accepted = true; }
                                else if (ev.key === Qt.Key_Up) { ph.listSel = Math.max(0, ph.listSel - 1); ev.accepted = true; }
                                else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { ph.pickRow(ph.listSel); ev.accepted = true; }
                                else if (ev.key === Qt.Key_Escape) { ph.back(); ev.accepted = true; }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: search.text === ""; color: ph.cMuted; font: search.font
                                   text: ph.tr(ph.panel === "clip" ? "Search clipboard…" : "Search passwords…") }
                        }
                    }
                    Item {
                        visible: ph.panel === "saved" || ph.panel === "clip"
                        width: parent.width
                        height: Math.min(380, Math.max(70, list.contentHeight))
                        Text {
                            anchors.centerIn: parent; width: parent.width - 20
                            visible: ph.rows.length === 0
                            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                            text: ph.panel === "clip" ? ph.tr(ph.o.history ? "No clipboard history yet." : "Clipboard history is turned off.")
                                : PwVault.state === "locked" ? ph.tr("The vault is locked.")
                                : PwVault.state === "nokeyring" ? ph.tr("Keyring unavailable") + "\n" + PwVault.problem + (PwVault.problem.indexOf("No keyring") === 0 ? "\nsudo pacman -S gnome-keyring - then log out and back in" : "")
                                : PwVault.state !== "ready" ? (PwVault.problem || "…") : ph.tr("No saved passwords yet.")
                            font.family: ph.fUi; font.pixelSize: 12; color: ph.cMuted
                        }
                        ListView {
                            id: list
                            anchors.fill: parent
                            clip: true; spacing: 4
                            boundsBehavior: Flickable.StopAtBounds
                            model: ph.rows
                            currentIndex: ph.listSel
                            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property bool hot: ra.containsMouse || ph.listSel === index
                                width: list.width; height: 54; radius: 14
                                color: hot ? Cfg.acc(0.16) : "transparent"
                                MouseArea { id: ra; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onEntered: ph.listSel = row.index; onClicked: ph.pickRow(row.index) }
                                Rectangle {
                                    id: badge
                                    x: 10; anchors.verticalCenter: parent.verticalCenter
                                    width: 34; height: 34; radius: ph.panel === "saved" ? 17 : 11
                                    color: row.hot ? Cfg.accent : Cfg.acc(0.18)
                                    Text { anchors.centerIn: parent
                                           text: ph.panel === "saved" ? ph.mono(row.modelData.title) : ""
                                           font.family: ph.panel === "saved" ? ph.fUi : ph.fIcon; font.pixelSize: ph.panel === "saved" ? 14 : 12; font.weight: Font.Bold
                                           color: row.hot ? Cfg.accFg : ph.cFg }
                                }
                                Column {
                                    anchors { left: badge.right; leftMargin: 12; right: acts.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    spacing: 2
                                    Row {
                                        width: parent.width; spacing: 6
                                        Text { width: Math.min(implicitWidth, parent.width - 16); elide: Text.ElideRight
                                               text: ph.panel === "saved" ? row.modelData.title : ph.preview(row.modelData.text)
                                               font.family: ph.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: ph.cFg }
                                        Text { visible: ph.panel === "saved" && row.modelData.pinned; text: ""; font.family: ph.fIcon; font.pixelSize: 10; color: Cfg.accent; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    Text { width: parent.width; elide: Text.ElideRight; font.family: ph.fUi; font.pixelSize: 11; color: ph.cMuted
                                           text: ph.panel === "saved" ? (row.modelData.username || row.modelData.url || "-")
                                                 : row.modelData.text.length + " " + ph.tr("characters") + " · " + ph.rel(row.modelData.ts) }
                                }
                                Row {
                                    id: acts
                                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    spacing: 4
                                    opacity: row.hot ? 1 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 100 } }
                                    IconBtn { visible: ph.panel === "saved" && !!row.modelData.username; icon: ""; tip: ph.tr("Username"); onClicked: PwVault.copyUsername(row.modelData) }
                                    IconBtn { visible: ph.panel === "saved"; icon: ""; tip: ph.tr("Details"); onClicked: ph.openDetails(row.modelData) }
                                    IconBtn { visible: ph.panel === "saved"; icon: ""; tip: ph.tr("Edit"); onClicked: ph.openEditor(row.modelData, "saved") }
                                    IconBtn { icon: ""; tip: ph.tr("Delete"); danger: true
                                              onClicked: ph.panel === "saved" ? ph.askDelete(row.modelData, "saved") : PwVault.histRemove(row.modelData) }
                                }
                            }
                        }
                    }
                    Row {
                        visible: ph.panel === "saved" || ph.panel === "clip"
                        anchors.right: parent.right; spacing: 8
                        PBtn { visible: ph.panel === "saved" && PwVault.state === "locked"; text: ph.tr("Unlock"); onClicked: PwVault.unlock() }
                        PBtn { visible: ph.panel === "saved" && PwVault.ready; text: ph.tr("Lock"); onClicked: { PwVault.lock(); ph.back(); } }
                        PBtn { visible: ph.panel === "saved" && PwVault.ready; primary: true; text: "+  " + ph.tr("Add password"); onClicked: ph.openEditor(null, "saved") }
                        PBtn { visible: ph.panel === "clip" && PwVault.history.length > 0; danger: true; text: ph.tr("Clear history"); onClicked: PwVault.histClear() }
                    }

                    // ── add / edit ──
                    Column {
                        visible: ph.panel === "edit"
                        width: parent.width; spacing: 12
                        Fld { id: fTitle; label: ph.tr("Title"); maxLen: 80; next: fUser.input }
                        Fld { id: fUser; label: ph.tr("Username"); next: fPass.input }
                        Item {
                            width: parent.width; height: fPass.height
                            Fld { id: fPass; label: ph.tr("Password"); secret: true; maxLen: 256; rightPad: 70; next: fUrl.input
                                  hint: ph.editing ? ph.tr("Leave empty to keep the current one") : "" }
                            Row {
                                anchors { right: parent.right; rightMargin: 5; bottom: parent.bottom; bottomMargin: 4 }
                                spacing: 2
                                IconBtn { icon: ph.passShown ? "" : ""; tip: ph.tr(ph.passShown ? "Hide" : "Show"); color: "transparent"; onClicked: ph.passShown = !ph.passShown }
                                IconBtn { icon: ""; tip: ph.tr("Generate"); color: "transparent"
                                          onClicked: PwVault.generate(r => { if (r.ok) { fPass.text = r.password; } }) }
                            }
                        }
                        // strength
                        Row {
                            visible: fPass.text.length > 0
                            width: parent.width; spacing: 10
                            readonly property var s: PwVault.strength(fPass.text)
                            Rectangle {
                                width: parent.width - 80; height: 6; radius: 3; color: "#22ffffff"; anchors.verticalCenter: parent.verticalCenter
                                Rectangle { width: parent.width * parent.parent.s.frac; height: parent.height; radius: 3; color: parent.parent.s.color
                                            Behavior on width { NumberAnimation { duration: 160 } } }
                            }
                            Text { width: 70; horizontalAlignment: Text.AlignRight; text: parent.s.label + " · " + Math.round(parent.s.bits)
                                   font.family: ph.fUi; font.pixelSize: 11; color: parent.s.color }
                        }
                        Fld { id: fUrl; label: ph.tr("Website (optional)"); maxLen: 500; next: fNotes }
                        Column {
                            width: parent.width; spacing: 6
                            Text { text: ph.tr("Notes (optional)").toUpperCase(); font.family: ph.fUi; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.8; color: ph.cMuted }
                            Rectangle {
                                width: parent.width; height: 64; radius: 11; color: "#14ffffff"
                                border.width: 1; border.color: fNotes.activeFocus ? Cfg.accent : "#1fffffff"
                                TextEdit {
                                    id: fNotes
                                    anchors.fill: parent; anchors.margins: 10
                                    color: ph.cFg; font.family: ph.fUi; font.pixelSize: 12; wrapMode: TextEdit.Wrap; clip: true
                                    selectionColor: Cfg.accent
                                    KeyNavigation.tab: fTitle.input
                                    Keys.onEscapePressed: ph.back()
                                    onTextChanged: if (text.length > 2000) text = text.slice(0, 2000)
                                }
                            }
                        }
                        Item {
                            width: parent.width; height: 28
                            Rectangle {
                                id: pinBox
                                width: 20; height: 20; radius: 6; anchors.verticalCenter: parent.verticalCenter
                                color: ph.fPinned ? Cfg.accent : "transparent"; border.width: 1.5; border.color: ph.fPinned ? Cfg.accent : ph.cMuted
                                Text { anchors.centerIn: parent; visible: ph.fPinned; text: ""; font.family: ph.fIcon; font.pixelSize: 10; color: Cfg.accFg }
                            }
                            Text { anchors { left: pinBox.right; leftMargin: 10; verticalCenter: parent.verticalCenter } text: ph.tr("Pin to the ring")
                                   font.family: ph.fUi; font.pixelSize: 13; color: ph.cFg }
                            MouseArea { width: 200; height: parent.height; cursorShape: Qt.PointingHandCursor; onClicked: ph.fPinned = !ph.fPinned }
                        }
                        Text { visible: ph.editErr !== ""; width: parent.width; wrapMode: Text.WordWrap; text: ph.editErr; font.family: ph.fUi; font.pixelSize: 12; color: "#ff8a8a" }
                        Row {
                            anchors.right: parent.right; spacing: 8
                            PBtn { text: ph.tr("Cancel"); onClicked: ph.back() }
                            PBtn { primary: true; text: ph.tr("Save"); onClicked: ph.saveEditor() }
                        }
                    }

                    // ── details ──
                    Column {
                        visible: ph.panel === "details" && !!ph.detail
                        width: parent.width; spacing: 10
                        DRow { label: ph.tr("Username"); value: ph.detail ? ph.detail.username : ""
                               IconBtn { visible: ph.detail && !!ph.detail.username; icon: ""; tip: ph.tr("Copy"); onClicked: PwVault.copyUsername(ph.detail) } }
                        DRow { label: ph.tr("Password"); mono: true; value: ph.revealed !== "" ? ph.revealed : "••••••••••••"
                               IconBtn { icon: ph.revealed !== "" ? "" : ""; tip: ph.tr(ph.revealed !== "" ? "Hide" : "Show")
                                         onClicked: { if (ph.revealed !== "") ph.revealed = ""; else PwVault.reveal(ph.detail.id, r => { if (r.ok) ph.revealed = r.password; }); } }
                               IconBtn { icon: ""; tip: ph.tr("Copy"); onClicked: PwVault.copyPassword(ph.detail) } }
                        DRow { visible: ph.detail && !!ph.detail.url; label: ph.tr("Website (optional)").replace(/ \(.*\)/, ""); value: ph.detail ? ph.detail.url : "" }
                        DRow { visible: ph.detail && !!ph.detail.notes; label: ph.tr("Notes (optional)").replace(/ \(.*\)/, ""); value: ph.detail ? ph.detail.notes : "" }
                        Text { width: parent.width; font.family: ph.fUi; font.pixelSize: 11; color: ph.cMuted
                               text: ph.detail ? ph.tr("Created") + " " + ph.when(ph.detail.created) + "   ·   " + ph.tr("Modified") + " " + ph.when(ph.detail.modified) : "" }
                        Row {
                            anchors.right: parent.right; spacing: 8
                            PBtn { danger: true; text: ph.tr("Delete"); onClicked: ph.askDelete(ph.detail, "details") }
                            PBtn { primary: true; text: ph.tr("Edit"); onClicked: ph.openEditor(ph.detail, "details") }
                        }
                    }

                    // ── confirm delete ──
                    Column {
                        visible: ph.panel === "confirm"
                        width: parent.width; spacing: 16
                        Text { width: parent.width; wrapMode: Text.WordWrap; font.family: ph.fUi; font.pixelSize: 13; color: ph.cFg
                               text: (ph.confirmFor ? "“" + ph.confirmFor.title + "” - " : "") + ph.tr("This cannot be undone.") }
                        Row {
                            anchors.right: parent.right; spacing: 8
                            PBtn { text: ph.tr("Cancel"); onClicked: ph.back() }
                            PBtn { danger: true; text: ph.tr("Delete"); onClicked: ph.doDelete() }
                        }
                    }

                    // ── recovery (VaultRecoveryDialog) ──
                    Column {
                        visible: ph.panel === "recover"
                        width: parent.width; spacing: 14
                        Text { width: parent.width; wrapMode: Text.WordWrap; font.family: ph.fUi; font.pixelSize: 13; color: ph.cFg
                               text: (PwVault.problem || "") + "\n\nNothing has been deleted. Restore the last good backup, start an empty vault (the damaged files are kept next to it as vault.dat.broken-…), or leave it as it is for now." }
                        Row {
                            anchors.right: parent.right; spacing: 8
                            PBtn { text: ph.tr("Leave it"); onClicked: { PwVault.recover("leave"); ph.panel = ""; } }
                            PBtn { text: ph.tr("Start new"); danger: true; onClicked: PwVault.recover("new", r => { if (r.ok && PwVault.ready) ph.showPanel("saved"); }) }
                            PBtn { visible: PwVault.hasBak && PwVault.code !== "nokey"; primary: true; text: ph.tr("Restore backup")
                                   onClicked: PwVault.recover("restore", r => { if (r.ok && PwVault.ready) ph.showPanel("saved"); }) }
                        }
                    }
                }
            }
            Item {
                id: tipLayer
                anchors.fill: parent
                z: 100
                Rectangle {
                    visible: ph.tipText !== "" && ph.shown
                    width: tipT.implicitWidth + 16; height: 24; radius: 8
                    x: Math.max(4, Math.min(tipLayer.width - width - 4, ph.tipX - width / 2))
                    y: ph.tipY - height - 6 < 4 ? ph.tipY + 30 + 6 : ph.tipY - height - 6
                    color: "#ee101219"; border.width: 1; border.color: "#26ffffff"
                    Text { id: tipT; anchors.centerIn: parent; text: ph.tipText; font.family: ph.fUi; font.pixelSize: 11; color: ph.cFg }
                }
            }
        }
}
