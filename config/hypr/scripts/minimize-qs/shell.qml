// sakura - minimized windows picker (run by ../minimize-pick.py from `minimize.sh restore`).
// Same look as ../share-picker-qs. Data in $SAKURA_MIN_DATA (json), the chosen address
// (or "" = cancel) is written to $SAKURA_MIN_OUT; minimize.sh then does restore-addr as before.
// Typing filters · arrows / Tab move · Enter or click restores · Esc or a click outside cancels.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

ShellRoot {
    id: root
    settings.watchFiles: false
    readonly property var d: { try { return JSON.parse(Quickshell.env("SAKURA_MIN_DATA") || "{}"); } catch (e) { return {}; } }
    readonly property string outPath: Quickshell.env("SAKURA_MIN_OUT") || ""

    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(d.accent || "") ? d.accent : "#f2b8d0"
    function acc(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }
    readonly property real glassA: typeof d.glass === "number" ? Math.max(0.15, Math.min(0.95, d.glass)) : 0.55
    readonly property color glass: Qt.rgba(15 / 255, 17 / 255, 25 / 255, Math.max(glassA, 0.62))
    readonly property color cFg: "#eceef4"
    readonly property color cMuted: "#8a8fa3"
    readonly property color cCard: "#12ffffff"
    readonly property color cHover: "#22ffffff"
    readonly property string fUi: d.font || "Inter"
    readonly property string fIcon: "Symbols Nerd Font"
    readonly property bool ru: d.lang === "ru"
    function tr(en, r) { return ru ? r : en; }

    readonly property var all: d.windows || []
    property string query: ""
    readonly property var items: {
        const q = query.toLowerCase();
        return q === "" ? all : all.filter(w => (w.title + " " + w.cls + " " + appName(w.cls)).toLowerCase().includes(q));
    }
    readonly property int cols: Math.max(1, Math.min(4, all.length))
    property int cur: 0
    onItemsChanged: cur = Math.min(cur, Math.max(0, items.length - 1))
    property bool shown: false
    property bool leaving: false

    function move(dx, dy) {
        if (items.length === 0) return;
        let i = cur + dx + dy * cols;
        if (dy !== 0 && (i < 0 || i >= items.length)) return;
        cur = Math.max(0, Math.min(items.length - 1, i));
    }
    function finish(addr) {
        if (leaving) return;
        leaving = true; shown = false;
        writer.command = ["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", addr, outPath];
        quitT.start();
    }
    Timer { id: quitT; interval: 170; onTriggered: writer.running = true }
    Process { id: writer; onExited: Qt.quit() }
    Timer { interval: 16; running: true; onTriggered: root.shown = true }
    Timer { interval: 2500; running: (Quickshell.env("SAKURA_MIN_AUTO") || "") !== ""
            onTriggered: { const n = parseInt(Quickshell.env("SAKURA_MIN_AUTO")); root.finish(n >= 0 && n < root.items.length ? root.items[n].addr : ""); } }

    function norm(a) { return String(a || "").replace(/^0x/, "").toLowerCase(); }
    function toplevelOf(addr) {
        const n = norm(addr); if (!n) return null;
        const t = Hyprland.toplevels.values.find(x => norm(x.address) === n);
        return t ? t.wayland : null;
    }
    function iconOf(cls) {
        const e = DesktopEntries.heuristicLookup(cls);
        return Quickshell.iconPath(e && e.icon ? e.icon : String(cls || "").toLowerCase(), "application-x-executable");
    }
    function appName(cls) { const e = DesktopEntries.heuristicLookup(cls); return e ? e.name : cls; }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === root.d.focused) || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "minimize-picker"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        MouseArea { anchors.fill: parent; onClicked: root.finish("") }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: inner.width + 48
            height: inner.height + 48
            radius: 30
            color: root.glass
            border.width: 1; border.color: "#16ffffff"
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: 170 } }
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }

            Column {
                id: inner
                anchors { top: parent.top; topMargin: 24; horizontalCenter: parent.horizontalCenter }
                spacing: 14
                readonly property int cardW: root.cols <= 2 ? 300 : 236
                readonly property int gap: 14
                width: Math.max(root.cols * cardW + (root.cols - 1) * gap, 520)

                // header: icon, title, search
                Item {
                    width: parent.width; height: 36
                    Row {
                        spacing: 10
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: 30; height: 30; radius: 10; color: root.acc(0.18)
                            anchors.verticalCenter: parent.verticalCenter
                            Text { anchors.centerIn: parent; text: ""; font.family: root.fIcon; font.pixelSize: 13; color: root.accent }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.tr("Minimized", "Свёрнутые")
                            color: root.cFg; font.family: root.fUi; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.all.length
                            color: root.cMuted; font.family: root.fUi; font.pixelSize: 14
                        }
                    }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 220; height: 36; radius: 13
                        color: root.cCard
                        border.width: search.text !== "" ? 1 : 0; border.color: root.acc(0.5)
                        Text { id: sIc; anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
                               text: ""; font.family: root.fIcon; font.pixelSize: 12; color: search.text !== "" ? root.accent : root.cMuted }
                        TextInput {
                            id: search
                            anchors { left: sIc.right; leftMargin: 10; right: parent.right; rightMargin: 13; verticalCenter: parent.verticalCenter }
                            focus: true
                            color: root.cFg; font.family: root.fUi; font.pixelSize: 13; clip: true; selectionColor: root.acc(0.4)
                            onTextEdited: { root.query = text; root.cur = 0; }
                            Keys.onPressed: e => {
                                const k = e.key;
                                if (k === Qt.Key_Escape) { if (text !== "") { text = ""; root.query = ""; } else root.finish(""); }
                                else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (root.items.length) root.finish(root.items[root.cur].addr); }
                                else if (k === Qt.Key_Left) root.move(-1, 0);
                                else if (k === Qt.Key_Right) root.move(1, 0);
                                else if (k === Qt.Key_Up) root.move(0, -1);
                                else if (k === Qt.Key_Down) root.move(0, 1);
                                else if (k === Qt.Key_Tab) { if (root.items.length) root.cur = (root.cur + 1) % root.items.length; }
                                else if (k === Qt.Key_Backtab) { if (root.items.length) root.cur = (root.cur - 1 + root.items.length) % root.items.length; }
                                else return;
                                e.accepted = true;
                            }
                        }
                    }
                }

                Flickable {
                    id: wf
                    width: inner.width
                    readonly property int rowH: Math.round(inner.cardW * 9 / 16) + 52 + inner.gap
                    readonly property int rows: Math.max(1, Math.ceil(root.all.length / root.cols))
                    height: Math.min(rows, 3) * rowH - inner.gap + 4
                    contentHeight: grid.height + 4
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Behavior on contentY { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Grid {
                        id: grid
                        y: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: root.cols
                        spacing: inner.gap
                        Repeater {
                            model: root.items
                            Card {
                                required property var modelData
                                required property int index
                                idx: index
                                width: inner.cardW
                                thumbH: Math.round(inner.cardW * 9 / 16)
                                appIcon: root.iconOf(modelData.cls)
                                label: modelData.title || root.appName(modelData.cls)
                                sub: root.appName(modelData.cls)
                                liveWin: root.toplevelOf(modelData.addr)
                                addr: modelData.addr
                                onIsCurChanged: if (isCur) {
                                    const top = y, bot = y + height;
                                    if (top < wf.contentY) wf.contentY = top;
                                    else if (bot > wf.contentY + wf.height) wf.contentY = bot - wf.height + 4;
                                }
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: root.items.length === 0
                        text: ""
                        font.family: root.fIcon; font.pixelSize: 28; color: root.acc(0.35)
                    }
                }
            }
        }
    }

    component Card: Item {
        id: card
        property int idx: 0
        property int thumbH: 160
        property string appIcon: ""
        property string label: ""
        property string sub: ""
        property string addr: ""
        property var liveWin: null
        readonly property bool isCur: root.cur === idx
        height: thumbH + 52

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: card.isCur ? root.acc(0.16) : ma.containsMouse ? root.cHover : root.cCard
            border.width: card.isCur ? 2 : 1
            border.color: card.isCur ? root.acc(0.85) : "#10ffffff"
            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on border.color { ColorAnimation { duration: 140 } }
        }
        scale: card.isCur ? 1.0 : ma.pressed ? 0.97 : 0.985
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ClippingRectangle {
            id: thumb
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7 }
            height: card.thumbH - 7
            radius: 14
            color: "#0cffffff"
            ScreencopyView {
                id: sv
                anchors.fill: parent
                captureSource: card.liveWin
                live: true
                visible: hasContent
                constraintSize: Qt.size(thumb.width, thumb.height)
            }
            Rectangle {
                visible: !sv.hasContent
                anchors.centerIn: parent
                width: 64; height: 64; radius: 20; color: "#10ffffff"
                IconImage { anchors.centerIn: parent; implicitSize: 40; source: card.appIcon }
            }
        }

        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 9 }
            spacing: 9
            IconImage { width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter; source: card.appIcon }
            Column {
                width: parent.width - 29
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text { width: parent.width; text: card.label; elide: Text.ElideRight; color: root.cFg
                       font.family: root.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { width: parent.width; text: card.sub; elide: Text.ElideRight; color: card.isCur ? root.acc(0.9) : root.cMuted
                       font.family: root.fUi; font.pixelSize: 11 }
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.cur = card.idx
            onClicked: root.finish(card.addr)
        }
    }
}
