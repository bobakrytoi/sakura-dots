// sakura mono - Alt+Tab window switcher with live previews
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

Scope {
    id: sw

    readonly property color cBg:     Cfg.glass
    readonly property color cCard:   "#14ffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: Cfg.accent

    property bool shown: false
    property bool loading: false
    property bool pendingCommit: false
    property int pendingStep: 1
    property int idx: 0
    property var wins: []
    // Settings > Taskbar > Window switcher
    readonly property bool compact: Cfg.data.swStyle === "icons"
    readonly property int cardW: compact ? 120 : 220
    readonly property int cardH: compact ? 128 : 210

    function norm(a) { return String(a || "").toLowerCase().replace(/^0x/, ""); }
    function toplevelFor(addr) {
        const n = norm(addr);
        const t = Hyprland.toplevels.values.find(x => norm(x.address) === n);
        return t ? t.wayland : null;
    }

    // safety: never stay open - if no key for 3 s, switch to the selected window and close
    Timer { id: idleCommit; interval: 3000; onTriggered: sw.commit() }
    function dbg(msg) {
        Quickshell.execDetached(["sh", "-c", "echo \"$(date +%T.%3N) " + msg + "\" >> $HOME/.cache/switcher.log"]);
    }
    // Alt+Tab and the Alt release reach us as two separate `qs ipc` processes, so on a quick tap the
    // release can arrive *before* the press. Remember a release that came in while nothing was going on:
    // a press right after it is that same quick tap -> just switch, never leave the overlay up.
    property real lastIdleRelease: 0
    // the monitor is picked once when the overlay opens (following the focused monitor live made the
    // layer surface move/recreate while focus jumped to another screen, and a ghost copy could stay up)
    property var openScreen: null
    function start(step) {
        dbg("start step=" + step + " shown=" + shown + " loading=" + loading);
        if (shown) { idx = (idx + step + wins.length) % wins.length; idleCommit.restart(); return; }
        if (loading) { pendingStep += step; return; }
        loading = true; pendingStep = step;
        pendingCommit = Date.now() - lastIdleRelease < 250;
        loadGuard.restart();
        clients.running = true;
    }
    // if hyprctl ever hangs, don't stay "loading" forever (every later Alt+Tab would be swallowed)
    Timer { id: loadGuard; interval: 2000; onTriggered: if (sw.loading) { sw.dbg("load timeout"); sw.loading = false; sw.pendingCommit = false; } }
    function focusAddr(addr) {
        const w = wins.find(x => x.address === addr);
        // small delay so the switcher overlay has released the keyboard first
        if (w && w.minimized)   // bring it back from the hidden "minimized" workspace
            Quickshell.execDetached(["sh", "-c", "sleep 0.12; \"$HOME/.config/hypr/scripts/minimize.sh\" restore-addr " + addr]);
        else
            // focus and raise; the mouse stays where it is (it used to jump to the window's centre - unwanted)
            Quickshell.execDetached(["sh", "-c", "sleep 0.12; hyprctl eval \"hl.dispatch(hl.dsp.focus({ window = 'address:" + addr + "' })); hl.dispatch(hl.dsp.window.bring_to_top())\""]);
    }
    function commit() {
        dbg("commit shown=" + shown + " loading=" + loading);
        if (loading) { pendingCommit = true; return; }
        if (!shown) { lastIdleRelease = Date.now(); return; }
        shown = false;
        idleCommit.stop();
        if (wins.length > 0) focusAddr(wins[idx].address);
    }
    function cancel() { dbg("cancel"); shown = false; loading = false; pendingCommit = false; idleCommit.stop(); }

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
                const fmon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.id : -1;
                list = list.filter(c => c.mapped && c.workspace && c.workspace.id !== -1 &&
                                        (!c.workspace.name.startsWith("special:") || (c.workspace.name === "special:minimized" && Cfg.data.swMinimized !== false)) &&
                                        (Cfg.data.swThisMonitor !== true || c.monitor === fmon || c.workspace.name === "special:minimized"))
                           .sort((a, b) => a.focusHistoryID - b.focusHistoryID);
                sw.wins = list.map(c => ({
                    address: c.address,
                    title: c.title,
                    cls: c["class"],
                    minimized: c.workspace.name === "special:minimized",
                    // our quickshell windows (Settings, Task Manager) share one class: pick their own entry by title
                    entry: (c["class"] === "org.quickshell" && c.title === "Settings" ? DesktopEntries.byId("sakura-settings")
                          : c["class"] === "org.quickshell" && c.title === "Task Manager" ? DesktopEntries.byId("sakura-taskmgr")
                          : c["class"] === "org.quickshell" && c.title === "Sakura Sound" ? DesktopEntries.byId("sakura-sound") : null)
                           || DesktopEntries.heuristicLookup(c["class"])
                }));
                sw.loading = false;
                loadGuard.stop();
                if (sw.wins.length === 0) return;
                const start = ((sw.pendingStep % sw.wins.length) + sw.wins.length) % sw.wins.length;
                sw.idx = sw.wins.length > 1 ? start : 0;
                if (sw.pendingCommit) {                 // quick Alt+Tab tap: just switch
                    sw.pendingCommit = false;
                    sw.focusAddr(sw.wins[sw.idx].address);
                    return;
                }
                const fm = Hyprland.focusedMonitor;
                sw.openScreen = (fm && Quickshell.screens.find(s => s.name === fm.name)) || Quickshell.screens[0];
                sw.shown = true;
                idleCommit.restart();
            }
        }
    }

    // the overlay only exists while it is shown: hiding destroys the surface, so nothing can linger
    LazyLoader {
    active: sw.shown
    PanelWindow {
        id: win
        visible: true
        screen: sw.openScreen || Quickshell.screens[0]
        implicitWidth: Math.min(row.implicitWidth + 40, (screen ? screen.width : 1920) - 80)
        implicitHeight: sw.cardH + 40
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
                contentX: Math.max(0, Math.min(contentWidth - width, sw.idx * (sw.cardW + 12) - width / 2 + sw.cardW / 2))
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
                            width: sw.cardW; height: sw.cardH; radius: 18
                            color: sel ? Cfg.acc(0.15) : (ca.containsMouse ? "#1affffff" : sw.cCard)
                            border.width: sel ? 2 : 1
                            border.color: sel ? sw.cAccent : sw.cBorder
                            scale: sel ? 1.0 : 0.96
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 140 } }

                            ClippingRectangle {
                                id: prev
                                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 10 }
                                height: sw.compact ? 64 : 130; radius: 12
                                color: sw.compact ? "transparent" : "#0f1119"
                                ScreencopyView {
                                    id: shot
                                    anchors.fill: parent
                                    // never capture games / gamescope (it breaks them)
                                    visible: !sw.compact
                                    captureSource: (sw.shown && !sw.compact && !/^(gamescope|cs2|steam_app_.*)$/i.test(card.modelData.cls)) ? sw.toplevelFor(card.modelData.address) : null
                                    live: false
                                    constraintSize: Qt.size(200, 130)
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: sw.compact || !shot.hasContent
                                    implicitSize: sw.compact ? 52 : 56
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
                                    visible: !sw.compact
                                    implicitSize: 24
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: Quickshell.iconPath(card.modelData.entry ? card.modelData.entry.icon : card.modelData.cls, "application-x-executable")
                                }
                                Column {
                                    width: sw.compact ? parent.width : parent.width - 32
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text { width: parent.width; elide: Text.ElideRight
                                        text: card.modelData.entry ? card.modelData.entry.name : card.modelData.cls
                                        color: card.sel ? sw.cAccent : sw.cFg; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.title; visible: Cfg.data.swTitles !== false
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
}
