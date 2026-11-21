// sakura mono - quick notes: slides out from the left edge (EdgeTab.qml), like the sketch pad.
// A list of notes on the left, the editor on the right. Everything saves itself as you type
// (~/.local/share/sakura/notes/notes.json). Click outside / Esc hides the panel.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

Scope {
    id: nt

    readonly property color cBg:     Cfg.glass
    readonly property color cCard:   "#14ffffff"
    readonly property color cCard2:  "#1fffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string dir:    Quickshell.env("HOME") + "/.local/share/sakura/notes"
    function t(s) { return Cfg.tr(s); }

    property bool shown: false
    property real closedAt: 0
    onShownChanged: { if (!shown) { closedAt = Date.now(); flush(); } else Qt.callLater(() => editor.forceActiveFocus()); }

    property var notes: []          // [{ id, text, pinned, updated }]
    property string curId: ""
    property string query: ""
    property var trash: null        // last deleted note (for "undo")

    IpcHandler {
        target: "notes"
        function toggle(): void { nt.shown = !nt.shown; }
        function open(): void { nt.shown = true; }
        function close(): void { nt.shown = false; }
    }

    FileView {
        id: store
        path: nt.dir + "/notes.json"
        blockLoading: true
        onLoaded: { try { const j = JSON.parse(text()); nt.notes = j.notes || []; nt.curId = j.cur || ""; } catch (e) {} nt.ensureOne(); }
        onLoadFailed: nt.ensureOne()
    }
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", dir])
    Timer { id: saveT; interval: 500; onTriggered: nt.flush() }
    function flush() { saveT.stop(); store.setText(JSON.stringify({ notes: notes, cur: curId }, null, 1)); }

    function ensureOne() {
        if (notes.length === 0) notes = [{ id: String(Date.now()), text: "", pinned: false, updated: Date.now() }];
        if (!notes.some(n => n.id === curId)) curId = notes[0].id;
        editor.text = current() ? current().text : "";
    }
    function current() { return notes.find(n => n.id === curId) || null; }
    function titleOf(n) { const l = n.text.split("\n").find(s => s.trim() !== ""); return l ? l.trim() : t("Empty note"); }
    function previewOf(n) { const ls = n.text.split("\n").filter(s => s.trim() !== ""); return ls.length > 1 ? ls.slice(1).join(" ").trim() : ""; }
    function when(ms) {
        const d = new Date(ms), now = new Date();
        return d.toDateString() === now.toDateString() ? Cfg.timeStr(d, false) : Cfg.locale.toString(d, "d MMM");
    }
    readonly property var shownNotes: {
        const q = query.trim().toLowerCase();
        return notes.filter(n => q === "" || n.text.toLowerCase().includes(q))
                    .slice().sort((a, b) => (b.pinned - a.pinned) || (b.updated - a.updated));
    }
    function select(id) { if (id === curId) return; curId = id; editor.text = current() ? current().text : ""; saveT.restart(); }
    function newNote() {
        const n = { id: String(Date.now()), text: "", pinned: false, updated: Date.now() };
        notes = [n].concat(notes); query = ""; search.text = ""; select(n.id); editor.forceActiveFocus();
    }
    function edited(txt) {
        const c = current(); if (!c || c.text === txt) return;
        notes = notes.map(n => n.id === curId ? Object.assign({}, n, { text: txt, updated: Date.now() }) : n);
        saveT.restart();
    }
    function remove(id) {
        trash = notes.find(n => n.id === id) || null;
        notes = notes.filter(n => n.id !== id);
        if (id === curId) { curId = ""; }
        ensureOne(); saveT.restart(); toast(t("Note deleted"), true);
    }
    function restore() { if (!trash) return; notes = [trash].concat(notes); select(trash.id); trash = null; toastText = ""; saveT.restart(); }
    function togglePin(id) { notes = notes.map(n => n.id === id ? Object.assign({}, n, { pinned: !n.pinned }) : n); saveT.restart(); }

    property string toastText: ""
    property bool toastUndo: false
    Timer { id: toastT; interval: 3500; onTriggered: { nt.toastText = ""; nt.trash = null; } }
    function toast(s, undo) { toastText = s; toastUndo = !!undo; toastT.restart(); }

    PanelWindow {
        id: win
        screen: Cfg.mainScreen
        visible: nt.shown || panel.x > -panel.width + 2
        anchors.left: true
        implicitWidth: 860; implicitHeight: 600
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "notes"
        WlrLayershell.keyboardFocus: nt.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        HyprlandFocusGrab { windows: [ win ]; active: nt.shown; onCleared: nt.shown = false }

        Rectangle {
            id: panel
            x: nt.shown ? 8 : -width - 10
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            width: parent.width - 16; height: parent.height
            radius: 22; color: nt.cBg; border.width: 1; border.color: nt.cBorder
            Keys.onPressed: e => {
                const ctrl = e.modifiers & Qt.ControlModifier;
                if (e.key === Qt.Key_Escape) { nt.shown = false; e.accepted = true; }
                else if (ctrl && e.key === Qt.Key_N) { nt.newNote(); e.accepted = true; }
                else if (ctrl && e.key === Qt.Key_F) { search.forceActiveFocus(); e.accepted = true; }
            }

            // ── list ──
            Item {
                id: side
                x: 14; y: 14; width: 250; height: parent.height - 28
                Row {
                    id: head; width: parent.width; height: 34; spacing: 8
                    Rectangle {
                        width: parent.width - 42; height: 34; radius: 11; color: "#14ffffff"
                        border.width: 1; border.color: search.activeFocus ? nt.cAccent : nt.cBorder
                        Text { id: si; x: 11; anchors.verticalCenter: parent.verticalCenter; text: ""; font.family: nt.fIcon; font.pixelSize: 11; color: nt.cAccent }
                        TextInput {
                            id: search
                            anchors { left: si.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            color: nt.cFg; font.family: nt.fUi; font.pixelSize: 12; clip: true; selectionColor: nt.cAccent
                            onTextChanged: nt.query = text
                            Keys.onPressed: e => { if (e.key === Qt.Key_Escape) { if (text) text = ""; else nt.shown = false; e.accepted = true; }
                                                   else if (e.key === Qt.Key_Return || e.key === Qt.Key_Down) { editor.forceActiveFocus(); e.accepted = true; } }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: nt.t("Search notes"); visible: !search.text; color: nt.cMuted; font: search.font }
                        }
                    }
                    Rectangle {
                        width: 34; height: 34; radius: 11; color: nma.containsMouse ? "#ffffff" : nt.cAccent
                        Text { anchors.centerIn: parent; text: ""; font.family: nt.fIcon; font.pixelSize: 13; color: nt.cAccFg }
                        MouseArea { id: nma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nt.newNote() }
                    }
                }
                ListView {
                    id: list
                    anchors { top: head.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true; spacing: 4; boundsBehavior: Flickable.StopAtBounds
                    model: nt.shownNotes
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool sel: modelData.id === nt.curId
                        width: list.width; height: 62; radius: 13
                        color: sel ? Cfg.acc(0.15) : (rma.containsMouse ? nt.cCard2 : "transparent")
                        border.width: sel ? 1 : 0; border.color: Cfg.acc(0.33)
                        MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { nt.select(row.modelData.id); editor.forceActiveFocus(); } }
                        Column {
                            anchors { left: parent.left; leftMargin: 12; right: acts.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            spacing: 3
                            Row { spacing: 6; width: parent.width
                                Text { visible: row.modelData.pinned; text: ""; font.family: nt.fIcon; font.pixelSize: 9; color: nt.cAccent; anchors.verticalCenter: parent.verticalCenter }
                                Text { width: parent.width - (row.modelData.pinned ? 16 : 0); elide: Text.ElideRight; text: nt.titleOf(row.modelData)
                                       color: nt.cFg; font.family: nt.fUi; font.pixelSize: 13; font.weight: Font.DemiBold } }
                            Text { width: parent.width; elide: Text.ElideRight; color: nt.cMuted; font.family: nt.fUi; font.pixelSize: 11
                                   text: nt.when(row.modelData.updated) + (nt.previewOf(row.modelData) ? "  ·  " + nt.previewOf(row.modelData) : "") }
                        }
                        Row {
                            id: acts
                            visible: rma.containsMouse || pinA.containsMouse || delA.containsMouse
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Rectangle { width: 26; height: 26; radius: 8; color: pinA.containsMouse ? nt.cCard : "transparent"
                                Text { anchors.centerIn: parent; text: ""; rotation: row.modelData.pinned ? 0 : 45; font.family: nt.fIcon; font.pixelSize: 11; color: nt.cAccent }
                                MouseArea { id: pinA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nt.togglePin(row.modelData.id) } }
                            Rectangle { width: 26; height: 26; radius: 8; color: delA.containsMouse ? nt.cCard : "transparent"
                                Text { anchors.centerIn: parent; text: ""; font.family: nt.fIcon; font.pixelSize: 11; color: delA.containsMouse ? "#ff8a9a" : nt.cMuted }
                                MouseArea { id: delA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nt.remove(row.modelData.id) } }
                        }
                    }
                }
                Text { anchors.centerIn: list; visible: nt.shownNotes.length === 0; text: nt.t("Nothing found"); color: nt.cMuted; font.family: nt.fUi; font.pixelSize: 12 }
            }

            // ── editor ──
            Rectangle {
                id: pageBox
                anchors { left: side.right; leftMargin: 14; right: parent.right; rightMargin: 14; top: parent.top; topMargin: 14; bottom: parent.bottom; bottomMargin: 14 }
                radius: 16; color: nt.cCard; border.width: 1; border.color: nt.cBorder
                Row {
                    id: tools
                    anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 10 }
                    spacing: 6; z: 2
                    Repeater {
                        model: [ { i: "", tip: "Copy", act: "copy" }, { i: "", tip: "Pin", act: "pin" }, { i: "", tip: "Delete", act: "del" } ]
                        Rectangle {
                            id: tbtn
                            required property var modelData
                            width: 30; height: 30; radius: 9; color: tba.containsMouse ? nt.cCard2 : "transparent"
                            Text { anchors.centerIn: parent; text: tbtn.modelData.i; font.family: nt.fIcon; font.pixelSize: 12
                                   rotation: tbtn.modelData.act === "pin" && !(nt.current() && nt.current().pinned) ? 45 : 0
                                   color: tbtn.modelData.act === "del" && tba.containsMouse ? "#ff8a9a" : nt.cAccent }
                            MouseArea { id: tba; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const c = nt.current(); if (!c) return;
                                    if (tbtn.modelData.act === "copy") { Quickshell.execDetached(["wl-copy", c.text]); nt.toast(nt.t("Copied"), false); }
                                    else if (tbtn.modelData.act === "pin") nt.togglePin(c.id);
                                    else nt.remove(c.id);
                                } }
                        }
                    }
                }
                Flickable {
                    id: fl
                    anchors { fill: parent; margins: 18; topMargin: 16; rightMargin: 14 }
                    contentWidth: width; contentHeight: editor.contentHeight + 40
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    function ensureVisible(r) {
                        if (contentY >= r.y) contentY = r.y;
                        else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height;
                    }
                    TextEdit {
                        id: editor
                        width: fl.width - 90 > 200 ? fl.width : fl.width
                        rightPadding: 90           // keep clear of the buttons in the corner
                        wrapMode: TextEdit.Wrap
                        color: nt.cFg; selectionColor: nt.cAccent; selectedTextColor: nt.cAccFg
                        font.family: nt.fUi; font.pixelSize: 15
                        selectByMouse: true; persistentSelection: true
                        onTextChanged: nt.edited(text)
                        onCursorRectangleChanged: fl.ensureVisible(cursorRectangle)
                        Keys.onPressed: e => {
                            const ctrl = e.modifiers & Qt.ControlModifier;
                            if (e.key === Qt.Key_Escape) { nt.shown = false; e.accepted = true; }
                            else if (ctrl && e.key === Qt.Key_N) { nt.newNote(); e.accepted = true; }
                            else if (ctrl && e.key === Qt.Key_F) { search.forceActiveFocus(); e.accepted = true; }
                        }
                        Text { visible: !editor.text; text: nt.t("Write something… the first line becomes the title"); color: nt.cMuted; font: editor.font }
                    }
                }
                // toast
                Rectangle {
                    visible: nt.toastText !== ""
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                    width: toastRow.implicitWidth + 24; height: 34; radius: 12; color: "#f20f1119"; border.width: 1; border.color: nt.cBorder
                    Row { id: toastRow; anchors.centerIn: parent; spacing: 12
                        Text { text: nt.toastText; color: nt.cFg; font.family: nt.fUi; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        Text { visible: nt.toastUndo && nt.trash !== null; text: nt.t("Undo"); color: nt.cAccent; font.family: nt.fUi; font.pixelSize: 12; font.weight: Font.Bold
                               anchors.verticalCenter: parent.verticalCenter
                               MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: nt.restore() } } }
                }
            }
        }
    }
}
