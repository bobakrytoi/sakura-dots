// sakura mono — Alt+Tab window switcher with live previews
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

Scope {
    id: sw

    readonly property color cBg:     "#e60f1119"
    readonly property color cCard:   "#14ffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: "#f2b8d0"

    property bool shown: false
    property bool loading: false
    property bool pendingCommit: false
    property int pendingStep: 1
    property int idx: 0
    property var wins: []

    function norm(a) { return String(a || "").toLowerCase().replace(/^0x/, ""); }
    function toplevelFor(addr) {
        const n = norm(addr);
        const t = Hyprland.toplevels.values.find(x => norm(x.address) === n);
        return t ? t.wayland : null;
    }

    // safety: never stay open — if no key for 3 s, switch to the selected window and close
    Timer { id: idleCommit; interval: 3000; onTriggered: sw.commit() }
    Process { id: dbgProc }
    function dbg(msg) {
        dbgProc.command = ["sh", "-c", "echo \"$(date +%T.%3N) " + msg + "\" >> $HOME/.cache/switcher.log"];
        dbgProc.running = true;
    }
    function start(step) {
        dbg("start step=" + step + " shown=" + shown + " loading=" + loading);
        if (shown) { idx = (idx + step + wins.length) % wins.length; idleCommit.restart(); return; }
        if (loading) { pendingStep += step; return; }
        loading = true; pendingCommit = false; pendingStep = step;
        clients.running = true;
    }
    function focusAddr(addr) {
        const w = wins.find(x => x.address === addr);
        // small delay so the switcher overlay has released the keyboard first
        if (w && w.minimized)   // bring it back from the hidden "minimized" workspace
            Quickshell.execDetached(["sh", "-c", "sleep 0.12; \"$HOME/.config/hypr/scripts/minimize.sh\" restore-addr " + addr]);
        else
            // focus, raise, and move the mouse into it (focus follows the mouse, so a game under the cursor would steal it back)
            Quickshell.execDetached(["sh", "-c", "sleep 0.12; hyprctl eval \"local w = hl.get_window('address:" + addr + "'); hl.dispatch(hl.dsp.focus({ window = 'address:" + addr + "' })); hl.dispatch(hl.dsp.window.bring_to_top()); if w then local a, z = w.at, w.size; hl.dispatch(hl.dsp.cursor.move({ x = (a.x or a[1]) + (z.x or z[1]) / 2, y = (a.y or a[2]) + (z.y or z[2]) / 2 })) end\""]);
    }
    function commit() {
        dbg("commit shown=" + shown + " loading=" + loading);
        if (loading) { pendingCommit = true; return; }
        if (!shown) return;
        shown = false;
        idleCommit.stop();
        if (wins.length > 0) focusAddr(wins[idx].address);
    }
    function cancel() { shown = false; loading = false; pendingCommit = false; idleCommit.stop(); }

    IpcHandler {
        target: "switcher"
        function next(): void { sw.start(1); }
        function prev(): void { sw.start(-1); }
        function commit(): void { sw.commit(); }
        function cancel(): void { sw.cancel(); }
    }

    Process {
        id: clients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(this.text); } catch (e) {}
                list = list.filter(c => c.mapped && c.workspace && c.workspace.id !== -1 &&
                                        (!c.workspace.name.startsWith("special:") || c.workspace.name === "special:minimized"))
                           .sort((a, b) => a.focusHistoryID - b.focusHistoryID);
                sw.wins = list.map(c => ({
                    address: c.address,
                    title: c.title,
                    cls: c["class"],
                    minimized: c.workspace.name === "special:minimized",
                    entry: DesktopEntries.heuristicLookup(c["class"])
                }));
                sw.loading = false;
                if (sw.wins.length === 0) return;
                const start = ((sw.pendingStep % sw.wins.length) + sw.wins.length) % sw.wins.length;
                sw.idx = sw.wins.length > 1 ? start : 0;
                if (sw.pendingCommit) {                 // quick Alt+Tab tap: just switch
                    sw.pendingCommit = false;
                    sw.focusAddr(sw.wins[sw.idx].address);
                    return;
                }
                sw.shown = true;
                idleCommit.restart();
            }
        }
    }

    PanelWindow {
        id: win
        visible: sw.shown
        screen: {
            const m = Hyprland.focusedMonitor;
            return (m && Quickshell.screens.find(s => s.name === m.name)) || Quickshell.screens[0];
        }
        implicitWidth: Math.min(row.implicitWidth + 40, (screen ? screen.width : 1920) - 80)
        implicitHeight: 250
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "switcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            radius: 24
            color: sw.cBg
            border.width: 1; border.color: sw.cBorder

            focus: sw.shown
            Keys.onPressed: e => {
                idleCommit.restart();
                if (e.key === Qt.Key_Tab)          { sw.idx = (sw.idx + 1) % sw.wins.length; e.accepted = true; }
                else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Left) { sw.idx = (sw.idx - 1 + sw.wins.length) % sw.wins.length; e.accepted = true; }
                else if (e.key === Qt.Key_Right)   { sw.idx = (sw.idx + 1) % sw.wins.length; e.accepted = true; }
                else if (e.key === Qt.Key_Escape)  { sw.cancel(); e.accepted = true; }
                else if (e.key === Qt.Key_Return)  { sw.commit(); e.accepted = true; }
            }
            Keys.onReleased: e => { if (e.key === Qt.Key_Alt || e.key === Qt.Key_Meta) sw.commit(); }

            Flickable {
                anchors { fill: parent; margins: 20 }
                contentWidth: row.implicitWidth
                contentX: Math.max(0, Math.min(contentWidth - width, sw.idx * 232 - width / 2 + 110))
                Behavior on contentX { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                interactive: false
                clip: true

                Row {
                    id: row
                    spacing: 12
                    Repeater {
                        model: sw.wins
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            required property int index
                            readonly property bool sel: index === sw.idx
                            width: 220; height: 210; radius: 18
                            color: sel ? "#26f2b8d0" : (ca.containsMouse ? "#1affffff" : sw.cCard)
                            border.width: sel ? 2 : 1
                            border.color: sel ? sw.cAccent : sw.cBorder
                            scale: sel ? 1.0 : 0.96
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 140 } }

                            ClippingRectangle {
                                id: prev
                                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 10 }
                                height: 130; radius: 12
                                color: "#0f1119"
                                ScreencopyView {
                                    id: shot
                                    anchors.fill: parent
                                    // never capture games / gamescope (it breaks them)
                                    captureSource: (sw.shown && !/^(gamescope|cs2|steam_app_.*)$/i.test(card.modelData.cls)) ? sw.toplevelFor(card.modelData.address) : null
                                    live: false
                                    constraintSize: Qt.size(200, 130)
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: !shot.hasContent
                                    implicitSize: 56
                                    source: Quickshell.iconPath(card.modelData.entry ? card.modelData.entry.icon : card.modelData.cls, "application-x-executable")
                                }
                                Rectangle {
                                    visible: card.modelData.minimized
                                    anchors { right: parent.right; top: parent.top; margins: 6 }
                                    width: mt.implicitWidth + 12; height: 20; radius: 7; color: "#cc0f1119"
                                    Text { id: mt; anchors.centerIn: parent; text: "minimized"; color: sw.cMuted; font.family: "Inter"; font.pixelSize: 10 }
                                }
                            }
                            Row {
                                anchors { top: prev.bottom; topMargin: 10; left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12 }
                                spacing: 8
                                IconImage {
                                    implicitSize: 24
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: Quickshell.iconPath(card.modelData.entry ? card.modelData.entry.icon : card.modelData.cls, "application-x-executable")
                                }
                                Column {
                                    width: parent.width - 32
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text { width: parent.width; elide: Text.ElideRight
                                        text: card.modelData.entry ? card.modelData.entry.name : card.modelData.cls
                                        color: card.sel ? sw.cAccent : sw.cFg; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.title
                                        color: sw.cMuted; font.family: "Inter"; font.pixelSize: 11 }
                                }
                            }
                            MouseArea {
                                id: ca; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { sw.idx = card.index; sw.commit(); }
                            }
                        }
                    }
                }
            }
        }
    }
}
