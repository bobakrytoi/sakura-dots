// sakura - screen-share picker (run by ../share-picker.py for xdg-desktop-portal-hyprland).
// Separate quickshell instance: data comes in $SAKURA_SHARE_DATA (json), the answer
// ("screen:DP-3" | "window:<handle>" | "region" | "" = cancel) is written to $SAKURA_SHARE_OUT.
// Arrows / Tab move · Enter or click picks · Esc or a click outside cancels.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

ShellRoot {
    id: root
    settings.watchFiles: false
    readonly property var d: { try { return JSON.parse(Quickshell.env("SAKURA_SHARE_DATA") || "{}"); } catch (e) { return {}; } }
    readonly property string outPath: Quickshell.env("SAKURA_SHARE_OUT") || ""

    // ── look (same tokens as the main shell's Cfg) ──
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

    // ── items: row 0 = screens + region, then windows in a grid ──
    readonly property int cols: 4
    readonly property var screensRow: (d.monitors || []).map(m => ({ kind: "screen", sel: "screen:" + m.name, name: m.name, w: m.w, h: m.h, main: m.main }))
        .concat([{ kind: "region", sel: "region" }])
    readonly property var wins: (d.windows || []).map(w => ({ kind: "window", sel: "window:" + w.handle, cls: w.cls, title: w.title, addr: w.addr, ws: w.ws }))
    readonly property var items: screensRow.concat(wins)
    property int cur: Math.max(0, screensRow.findIndex(s => s.name === d.focused))
    property bool shown: false
    property bool leaving: false

    function rowOf(i) { return i < screensRow.length ? 0 : 1 + Math.floor((i - screensRow.length) / cols); }
    function colOf(i) { return i < screensRow.length ? i : (i - screensRow.length) % cols; }
    function move(dx, dy) {
        if (dx !== 0) { cur = Math.max(0, Math.min(items.length - 1, cur + dx)); return; }
        const r = rowOf(cur) + dy;
        if (r < 0 || wins.length === 0) return;
        if (r === 0) { cur = Math.min(screensRow.length - 1, Math.round(colOf(cur) * (screensRow.length - 1) / Math.max(1, cols - 1))); return; }
        const c = rowOf(cur) === 0 ? Math.round(colOf(cur) * (cols - 1) / Math.max(1, screensRow.length - 1)) : colOf(cur);
        const i = screensRow.length + (r - 1) * cols + c;
        if (i < items.length) cur = i;
        else if (screensRow.length + (r - 1) * cols < items.length) cur = items.length - 1;
    }

    function finish(sel) {
        if (leaving) return;
        leaving = true; shown = false;
        writer.command = ["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", sel, outPath];
        quitT.start();
    }
    Timer { id: quitT; interval: 170; onTriggered: writer.running = true }
    Process { id: writer; onExited: Qt.quit() }
    Timer { interval: 16; running: true; onTriggered: root.shown = true }
    // test hook: SAKURA_SHARE_AUTO=<n> picks item n after 2.5 s (-1 = cancel)
    Timer { interval: 2500; running: Quickshell.env("SAKURA_SHARE_AUTO") !== null && Quickshell.env("SAKURA_SHARE_AUTO") !== ""
            onTriggered: { const n = parseInt(Quickshell.env("SAKURA_SHARE_AUTO")); root.finish(n >= 0 && n < root.items.length ? root.items[n].sel : ""); } }

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
    function screenOf(name) { return Quickshell.screens.find(s => s.name === name) || null; }

    PanelWindow {
        id: win
        screen: root.screenOf(root.d.focused) || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "share-picker"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        MouseArea { id: catcher; anchors.fill: parent; onClicked: root.finish("") }

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
            MouseArea { anchors.fill: parent }   // clicks on the glass don't cancel

            focus: true
            Keys.onPressed: e => {
                const k = e.key;
                if (k === Qt.Key_Escape) root.finish("");
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.finish(root.items[root.cur].sel);
                else if (k === Qt.Key_Left || k === Qt.Key_H) root.move(-1, 0);
                else if (k === Qt.Key_Right || k === Qt.Key_L) root.move(1, 0);
                else if (k === Qt.Key_Up || k === Qt.Key_K) root.move(0, -1);
                else if (k === Qt.Key_Down || k === Qt.Key_J) root.move(0, 1);
                else if (k === Qt.Key_Tab) root.cur = (root.cur + 1) % root.items.length;
                else if (k === Qt.Key_Backtab) root.cur = (root.cur - 1 + root.items.length) % root.items.length;
                else return;
                e.accepted = true;
            }

            Column {
                id: inner
                anchors.centerIn: parent
                spacing: 14
                readonly property int cardW: 292
                readonly property int gap: 14
                readonly property int rowW: root.screensRow.length * cardW + (root.screensRow.length - 1) * gap
                readonly property int winW: Math.floor((Math.max(rowW, 4 * 210 + 3 * gap) - (root.cols - 1) * gap) / root.cols)
                width: Math.max(rowW, 4 * 210 + 3 * gap)

                // header
                Row {
                    spacing: 10
                    Rectangle {
                        width: 30; height: 30; radius: 10; color: root.acc(0.18)
                        anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: ""; font.family: root.fIcon; font.pixelSize: 14; color: root.accent }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.tr("Share your screen", "Показать экран")
                        color: root.cFg; font.family: root.fUi; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                }

                // screens + region
                Row {
                    spacing: inner.gap
                    anchors.horizontalCenter: parent.horizontalCenter
                    Repeater {
                        model: root.screensRow
                        Card {
                            required property var modelData
                            required property int index
                            idx: index
                            width: inner.cardW
                            thumbH: Math.round(inner.cardW * 9 / 16)
                            icon: modelData.kind === "region" ? "" : ""
                            label: modelData.kind === "region" ? root.tr("Region", "Область") : modelData.name
                            sub: modelData.kind === "region" ? ""
                                 : modelData.w + "×" + modelData.h + (modelData.main ? root.tr(" · main", " · главный") : "")
                            isRegion: modelData.kind === "region"
                            liveScreen: modelData.kind === "screen" && modelData.name !== root.d.focused ? root.screenOf(modelData.name) : null
                            still: modelData.kind === "screen" && modelData.name === root.d.focused && root.d.snap ? "file://" + root.d.snap : ""
                        }
                    }
                }

                // windows
                Flickable {
                    id: wf
                    visible: root.wins.length > 0
                    width: inner.width
                    readonly property int rowH: Math.round(inner.winW * 9 / 16) + 52 + inner.gap
                    height: Math.min(Math.ceil(root.wins.length / root.cols), 3) * rowH - inner.gap + 4
                    contentHeight: grid.height + 4
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Grid {
                        id: grid
                        y: 2
                        columns: root.cols
                        spacing: inner.gap
                        Repeater {
                            model: root.wins
                            Card {
                                required property var modelData
                                required property int index
                                idx: root.screensRow.length + index
                                width: inner.winW
                                thumbH: Math.round(inner.winW * 9 / 16)
                                appIcon: root.iconOf(modelData.cls)
                                label: modelData.title || root.appName(modelData.cls)
                                sub: root.appName(modelData.cls) + (modelData.ws ? "  ·  " + modelData.ws : "")
                                liveWin: root.toplevelOf(modelData.addr)
                                onIsCurChanged: if (isCur) {
                                    const top = y, bot = y + height;
                                    if (top < wf.contentY) wf.contentY = top;
                                    else if (bot > wf.contentY + wf.height) wf.contentY = bot - wf.height + 4;
                                }
                            }
                        }
                    }
                    Behavior on contentY { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    // one pickable tile: preview on top, icon + two lines of text under it
    component Card: Item {
        id: card
        property int idx: 0
        property int thumbH: 160
        property string icon: ""
        property string appIcon: ""
        property string label: ""
        property string sub: ""
        property bool isRegion: false
        property var liveScreen: null
        property var liveWin: null
        property string still: ""
        readonly property bool isCur: root.cur === idx
        height: thumbH + 52

        Rectangle {
            id: bg
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
                captureSource: card.liveWin || card.liveScreen
                live: true
                visible: hasContent
                constraintSize: Qt.size(thumb.width, thumb.height)
            }
            Image {
                anchors.fill: parent
                visible: card.still !== ""
                source: card.still
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; smooth: true
            }
            // nothing to show (region, or a window on a hidden workspace): a big soft icon
            Item {
                anchors.fill: parent
                visible: !sv.hasContent && card.still === ""
                Rectangle {
                    anchors.centerIn: parent
                    width: 64; height: 64; radius: 20
                    color: card.isRegion ? root.acc(card.isCur ? 0.22 : 0.12) : "#10ffffff"
                    Text { visible: card.appIcon === ""; anchors.centerIn: parent; text: card.icon; font.family: root.fIcon; font.pixelSize: 26; color: root.accent }
                    IconImage { visible: card.appIcon !== ""; anchors.centerIn: parent; implicitSize: 40; source: card.appIcon }
                }
            }
        }

        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 9 }
            spacing: 9
            Item {
                width: 20; height: 20
                anchors.verticalCenter: parent.verticalCenter
                IconImage { visible: card.appIcon !== ""; anchors.fill: parent; source: card.appIcon }
                Text { visible: card.appIcon === ""; anchors.centerIn: parent; text: card.icon; font.family: root.fIcon; font.pixelSize: 13
                       color: card.isCur ? root.accent : root.cMuted }
            }
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
            onClicked: root.finish(root.items[card.idx].sel)
        }
    }
}
