// sakura mono - clipboard history (cliphist): search, pictures, pinned entries.
// Super+V (hypr/scripts/clipboard.sh) · qs ipc call clipboard toggle
// ↑/↓ choose · Enter copies and closes · Delete forgets · Ctrl+P pins · Esc closes.
// Pins live in ~/.config/sakura/clip-pins.json (pictures copied to ~/.local/share/sakura/clip-pins/).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

Scope {
    id: cb
    property bool shown: false
    property var screen0: Quickshell.screens[0]
    property var entries: []          // [{ id, text, img, size }]
    property var pins: []             // [{ text } | { file }]
    property string query: ""
    property string filter: "all"     // all | text | img | pins
    property int sel: 0

    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cCard:   "#14ffffff"
    readonly property color cHover:  "#29ffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string home:   Quickshell.env("HOME")
    readonly property string sh:     home + "/.config/hypr/scripts/clip.sh"

    // pinned first, then history; each row: { pin: index | -1, id, text, img, size, file }
    readonly property var rows: {
        const q = query.toLowerCase();
        const P = pins.map((p, i) => ({ pin: i, id: "", text: p.text || "", img: !!p.file, file: p.file || "", size: "" }));
        const H = filter === "pins" ? [] : entries.map(e => ({ pin: -1, id: e.id, text: e.text, img: e.img, file: "", size: e.size }))
                  .filter(e => !pins.some(p => p.text && p.text === e.text));
        let L = (filter === "all" || filter === "pins" ? P : P.filter(p => filter === "img" ? p.img : !p.img)).concat(H);
        if (filter === "text") L = L.filter(r => !r.img);
        if (filter === "img") L = L.filter(r => r.img);
        if (q !== "") L = L.filter(r => !r.img && r.text.toLowerCase().includes(q));
        return L;
    }
    readonly property var cur: rows.length ? rows[Math.max(0, Math.min(sel, rows.length - 1))] : null

    function open() {
        const fm = Hyprland.focusedMonitor;
        screen0 = (fm && Quickshell.screens.find(s => s.name === fm.name)) || Cfg.mainScreen || Quickshell.screens[0];
        query = ""; sel = 0; filter = "all";
        listProc.running = false; listProc.running = true;
        pinFile.reload();
        shown = true;
    }
    function close() { shown = false; }
    function toggle() { if (shown) close(); else open(); }
    IpcHandler { target: "clipboard"; function toggle(): void { cb.toggle(); } }

    Process {
        id: listProc
        command: [cb.sh, "list"]
        stdout: StdioCollector { onStreamFinished: {
            const L = [];
            this.text.split("\n").forEach(l => { try { if (l) L.push(JSON.parse(l)); } catch (e) {} });
            cb.entries = L;
        } }
    }
    FileView {
        id: pinFile
        path: cb.home + "/.config/sakura/clip-pins.json"
        onLoaded: { try { cb.pins = JSON.parse(text()); } catch (e) { cb.pins = []; } }
        onLoadFailed: cb.pins = []
    }
    function savePins(p) { pins = p; pinFile.setText(JSON.stringify(p, null, 1)); }

    function copy(r) {
        if (!r) return;
        if (r.pin >= 0) Quickshell.execDetached(r.img ? [sh, "copyfile", r.file] : [sh, "copytext", r.text]);
        else Quickshell.execDetached([sh, "copy", r.id]);
        close();
    }
    function remove(r) {
        if (!r) return;
        if (r.pin >= 0) { savePins(pins.filter((x, i) => i !== r.pin)); return; }
        Quickshell.execDetached([sh, "delete", r.id]);
        entries = entries.filter(e => e.id !== r.id);
    }
    function pin(r) {
        if (!r) return;
        if (r.pin >= 0) { remove(r); return; }
        if (!r.img) { fullProc.command = [sh, "full", r.id]; fullProc.running = true; return; }
        // pictures: keep a copy of the png
        Quickshell.execDetached(["sh", "-c", "d=\"$HOME/.local/share/sakura/clip-pins\"; mkdir -p \"$d\"; f=$(\"$1\" thumb \"$2\") && cp \"$f\" \"$d/$3.png\"", "sh", sh, r.id, String(Date.now())]);
        pinImgT.restart();
    }
    // the copy above names the file with its own Date.now(): list the folder instead of guessing
    Timer { id: pinImgT; property string file: ""; interval: 500; onTriggered: { pinDir.running = false; pinDir.running = true; } }
    Process {
        id: pinDir
        command: ["sh", "-c", "ls -t \"$HOME/.local/share/sakura/clip-pins\"/*.png 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: { const f = this.text.trim(); if (f && !cb.pins.some(p => p.file === f)) cb.savePins([{ file: f }].concat(cb.pins)); } }
    }
    Process {
        id: fullProc
        stdout: StdioCollector { onStreamFinished: { const t = this.text; if (t !== "" && !cb.pins.some(p => p.text === t)) cb.savePins([{ text: t }].concat(cb.pins)); } }
    }

    component Chip: Rectangle {
        id: ch
        property string label: ""
        property string icon: ""
        property bool on: false
        signal clicked()
        width: chRow.implicitWidth + 22; height: 30; radius: 10
        color: on ? Cfg.acc(0.18) : cma.containsMouse ? cb.cHover : cb.cCard
        border.width: on ? 1 : 0; border.color: Cfg.acc(0.45)
        Row { id: chRow; anchors.centerIn: parent; spacing: 6
            Text { text: ch.icon; font.family: cb.fIcon; font.pixelSize: 11; color: ch.on ? cb.cAccent : cb.cMuted; anchors.verticalCenter: parent.verticalCenter }
            Text { text: Cfg.tr(ch.label); font.family: cb.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: ch.on ? cb.cAccent : cb.cFg; anchors.verticalCenter: parent.verticalCenter } }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }

    PanelWindow {
        id: win
        screen: cb.screen0
        visible: cb.shown || panel.opacity > 0
        implicitWidth: 640; implicitHeight: 600
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "clipboard"
        WlrLayershell.keyboardFocus: cb.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        property bool grabOn: false
        onVisibleChanged: { grabOn = false; if (visible) regrab.restart(); }
        Timer { id: regrab; interval: 60; onTriggered: if (cb.shown) win.grabOn = true }
        HyprlandFocusGrab { windows: [ win ]; active: win.grabOn && cb.shown; onCleared: cb.close() }

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: 26; color: Cfg.glass
            opacity: cb.shown ? 1 : 0
            scale: cb.shown ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 240 * Cfg.anim; easing.type: Easing.OutCubic } }

            // search
            Rectangle {
                id: sbox
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                height: 40; radius: 13; color: cb.cCard
                border.width: search.activeFocus ? 1 : 0; border.color: Cfg.acc(0.5)
                Text { id: sIc; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                       text: ""; font.family: cb.fIcon; font.pixelSize: 13; color: cb.cAccent }
                TextInput {
                    id: search
                    anchors { left: sIc.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    focus: cb.shown
                    color: cb.cFg; font.family: cb.fUi; font.pixelSize: 14; clip: true; selectionColor: Cfg.acc(0.4)
                    onTextEdited: { cb.query = text; cb.sel = 0; }
                    Connections { target: cb; function onShownChanged() { if (cb.shown) { search.text = ""; search.forceActiveFocus(); } } }
                    Keys.onEscapePressed: { if (text !== "") { text = ""; cb.query = ""; } else cb.close(); }
                    Keys.onUpPressed: cb.sel = Math.max(0, cb.sel - 1)
                    Keys.onDownPressed: cb.sel = Math.min(cb.rows.length - 1, cb.sel + 1)
                    Keys.onReturnPressed: cb.copy(cb.cur)
                    Keys.onEnterPressed: cb.copy(cb.cur)
                    Keys.onDeletePressed: e => { if (text === "" || (e.modifiers & Qt.ShiftModifier)) cb.remove(cb.cur); else e.accepted = false; }
                    Keys.onPressed: e => {
                        if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_P) { cb.pin(cb.cur); e.accepted = true; }
                        else if (e.key === Qt.Key_Tab) { const f = ["all", "text", "img", "pins"]; cb.filter = f[(f.indexOf(cb.filter) + 1) % 4]; cb.sel = 0; e.accepted = true; }
                    }
                    Text { visible: search.text === ""; text: Cfg.tr("Search the clipboard"); color: cb.cMuted; font: search.font }
                }
            }
            // filters + wipe
            Row {
                id: chips
                anchors { left: parent.left; top: sbox.bottom; topMargin: 10; leftMargin: 16 }
                spacing: 6
                Chip { label: "All";      icon: ""; on: cb.filter === "all";  onClicked: { cb.filter = "all"; cb.sel = 0; } }
                Chip { label: "Text";     icon: ""; on: cb.filter === "text"; onClicked: { cb.filter = "text"; cb.sel = 0; } }
                Chip { label: "Pictures"; icon: ""; on: cb.filter === "img";  onClicked: { cb.filter = "img"; cb.sel = 0; } }
                Chip { label: "Pinned";   icon: ""; on: cb.filter === "pins"; onClicked: { cb.filter = "pins"; cb.sel = 0; } }
            }
            Chip {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: chips.verticalCenter }
                label: "Clear"; icon: ""
                onClicked: { Quickshell.execDetached([cb.sh, "wipe"]); cb.entries = []; }
            }

            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: chips.bottom; bottom: parent.bottom; margins: 16; topMargin: 12 }
                clip: true; spacing: 4
                cacheBuffer: 1600                 // rows just outside the view stay built
                model: cb.rows
                currentIndex: cb.sel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool cur: index === cb.sel
                    width: list.width
                    height: modelData.img ? 92 : Math.min(76, txt.implicitHeight + 24)
                    radius: 14
                    color: cur ? Cfg.acc(0.16) : rma.containsMouse ? cb.cCard : "transparent"
                    border.width: cur ? 1 : 0; border.color: Cfg.acc(0.4)

                    // picture
                    ClippingRectangle {
                        id: pic
                        visible: row.modelData.img
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        width: visible ? 120 : 0; height: 72; radius: 10; color: cb.cCard
                        property string path: row.modelData.file
                        Image { anchors.fill: parent; source: pic.path ? "file://" + pic.path : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 240 }
                        Process {
                            running: row.modelData.img && row.modelData.pin < 0
                            command: [cb.sh, "thumb", row.modelData.id]
                            stdout: StdioCollector { onStreamFinished: pic.path = this.text.trim() }
                        }
                    }
                    Text {
                        id: txt
                        anchors { left: pic.right; leftMargin: row.modelData.img ? 14 : 14; right: acts.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: row.modelData.img ? Cfg.tr("Picture") + (row.modelData.size ? "  ·  " + row.modelData.size : "") : row.modelData.text.replace(/\s+/g, " ")
                        color: row.modelData.img ? cb.cMuted : cb.cFg
                        font.family: cb.fUi; font.pixelSize: 13
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    }
                    MouseArea {
                        id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onEntered: cb.sel = row.index
                        onClicked: cb.copy(row.modelData)
                    }
                    Row {
                        id: acts
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Repeater {
                            model: [ { k: "pin", i: "" }, { k: "del", i: "" } ]
                            Rectangle {
                                required property var modelData
                                readonly property bool pinned: row.modelData.pin >= 0
                                visible: modelData.k === "pin" ? (pinned || row.cur || rma.containsMouse || am.containsMouse) : (row.cur || rma.containsMouse || am.containsMouse)
                                width: 28; height: 28; radius: 9
                                color: am.containsMouse ? cb.cHover : "transparent"
                                Text { anchors.centerIn: parent; text: parent.modelData.i; font.family: cb.fIcon; font.pixelSize: 12
                                       rotation: parent.modelData.k === "pin" && !parent.pinned ? 45 : 0
                                       color: parent.modelData.k === "pin" && parent.pinned ? cb.cAccent : am.containsMouse ? cb.cAccent : cb.cMuted }
                                MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (parent.modelData.k === "pin") cb.pin(row.modelData); else cb.remove(row.modelData); } }
                            }
                        }
                    }
                }
                // faster wheel: the default step is small
                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.NoButton; z: 10
                    onWheel: w => {
                        const max = Math.max(0, list.contentHeight - list.height) + list.originY;
                        wheelAnim.to = Math.max(list.originY, Math.min(max, (wheelAnim.running ? wheelAnim.to : list.contentY) - w.angleDelta.y * 2.2));
                        wheelAnim.restart();
                    }
                }
                NumberAnimation { id: wheelAnim; target: list; property: "contentY"; duration: 180; easing.type: Easing.OutCubic }
                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: listProc.running ? Cfg.tr("Loading…") : Cfg.tr("Nothing here yet")
                    color: cb.cMuted; font.family: cb.fUi; font.pixelSize: 14
                }
            }
        }
    }
}
