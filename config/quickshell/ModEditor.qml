// sakura mono - Settings > Taskbar: the module editor for the bar's wings ("bar") or the corner island ("island").
// A live preview over the current wallpaper (same glass and shape as the real thing) whose modules are dragged
// into place (ModHub / DropSlot), the modules not in use below (ModPalette). A click on a module opens its
// little options (Cfg.modOptCatalog → Cfg.setMo). Order goes to settings.json through Cfg.set.
import Quickshell
import QtQuick

Item {
    id: me
    property string kind: "bar"
    property string wallpaper: ""
    implicitHeight: col.implicitHeight
    height: implicitHeight

    readonly property color cFg: "#eceef4"
    readonly property color cMuted: "#8a8fa3"
    readonly property string fIcon: "Symbols Nerd Font"
    function t(s) { return Cfg.tr(s); }

    readonly property var islandVal: Cfg.islandItems
    readonly property string corner: Cfg.data.islandCorner || "tr"
    readonly property bool bottomCorner: kind === "island" && corner[0] === "b"
    readonly property bool rightCorner: kind === "island" && corner[1] === "r"

    // what a module looks like (the bar's glyphs, made-up numbers, its options applied)
    function look(id) {
        const c = Cfg.islandCatalog.concat(Cfg.barLeftCatalog, Cfg.barRightCatalog).find(x => x.id === id), g = c ? c.icon : "";
        switch (id) {
        case "clock": return { glyph: "", label: (Cfg.mo("clock", "date") ? Cfg.locale.toString(new Date(), "ddd d") + "  " : "") + Cfg.timeStr(new Date(), false) };
        case "layout": return { glyph: "", label: Cfg.mo("layout", "long") ? "English (US)" : "EN" };
        case "volume": return { glyph: "", label: Cfg.mo("volume", "pct") ? "62%" : "" };
        case "network": return { glyph: g, label: Cfg.mo("network", "name") ? "Wired" : "" };
        case "cpu": return { glyph: g, label: Cfg.mo("cpu", "pct") ? "12%" : "" };
        case "ram": return { glyph: "\u{F035B}", label: Cfg.mo("ram", "pct") ? "41%" : "" };
        case "notify": return { glyph: g, label: Cfg.mo("notify", "count") ? "3" : "" };
        case "updates": return { glyph: g, label: "4" };
        case "minimized": return { glyph: g, label: "2" };
        case "track": return { glyph: Cfg.mo("track", "art") || !Cfg.mo("track", "text") ? "" : "", label: Cfg.mo("track", "text") ? "Artist" : "" };
        }
        return { glyph: g, label: "" };
    }

    ModHub { id: edHub }

    // a module in the preview, like the bar's buttons
    Component {
        id: chipC
        Rectangle {
            id: ch
            property string mid: ""
            property var slot: null
            readonly property var lk: me.look(mid)
            readonly property bool hot: da.containsMouse
            readonly property bool picked: edHub.isSel(slot, mid)
            implicitHeight: 24
            implicitWidth: cr.implicitWidth + 14
            radius: 9
            color: hot || picked ? Cfg.acc(0.22) : "transparent"
            border.width: picked ? 1 : 0
            border.color: Cfg.acc(0.7)
            opacity: edHub.dragId === mid && edHub.dragSlot === slot ? 0.25 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Row {
                id: cr
                anchors.centerIn: parent
                spacing: 6
                Text { visible: ch.lk.glyph !== ""; text: ch.lk.glyph; font.family: me.fIcon; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter
                       color: ch.hot || ch.picked ? Cfg.accent : me.cFg }
                Text { visible: ch.lk.label !== ""; text: ch.lk.label; anchors.verticalCenter: parent.verticalCenter
                       color: me.cFg; font.family: Cfg.fontUi; font.pixelSize: 12; font.weight: Font.Medium }
            }
            DragArea { id: da; anchors.fill: parent; hub: edHub; slot: ch.slot; mid: ch.mid }
            ChipX { hub: edHub; slot: ch.slot; mid: ch.mid; show: ch.hot }
        }
    }

    Column {
        id: col
        width: me.width
        spacing: 10

        // ── the preview ──
        Rectangle {
            id: pv
            width: me.width; height: me.kind === "bar" ? 104 : 120
            radius: 16; clip: true
            color: "#0b0c12"
            border.width: 1; border.color: "#1fffffff"
            WallThumb { anchors.fill: parent; file: me.wallpaper; size: 900; opacity: 0.85 }
            Rectangle { anchors.fill: parent; color: "#33000000" }

            // everything is drawn at real size on a stage that shrinks to fit the preview
            Item {
                id: stage
                readonly property real need: me.kind === "bar"
                    ? 2 * (notch.width / 2 + 24 + 4 + Math.max(leftSlot.width, rightSlot.width) + 9 + 22 + 14)
                    : islSlot.width + 20 + 24 + 40
                readonly property real k: Math.min(1, pv.width / Math.max(1, need))
                width: pv.width / k; height: pv.height / k
                scale: k; transformOrigin: Item.TopLeft

                Canvas {
                    id: shape
                    anchors.fill: parent
                    readonly property string key: [width, me.kind, me.corner, Cfg.glass, leftSlot.x, leftSlot.width, rightSlot.x, rightSlot.width,
                                                   islSlot.x, islSlot.width, notch.x, notch.width].join(",")
                    onKeyChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const k = 0.5523, ew = 22, eh = 16;
                        if (me.kind === "bar") {
                            const x0 = notch.x, x1 = notch.x + notch.width, d = 40, wh = 30, s = 24, r = 15;
                            const xl = Math.min(x0 - s, leftSlot.x - 9), xr = Math.max(x1 + s, rightSlot.x + rightSlot.width + 9);
                            ctx.beginPath();
                            ctx.moveTo(xl - ew, 0);
                            ctx.bezierCurveTo(xl - ew + ew * k, 0, xl, eh - eh * k, xl, eh);
                            ctx.lineTo(xl, wh - r);
                            ctx.bezierCurveTo(xl, wh - r + r * k, xl + r - r * k, wh, xl + r, wh);
                            ctx.lineTo(x0 - s, wh);
                            ctx.bezierCurveTo(x0 - s / 2, wh, x0 - s / 2, d, x0, d);
                            ctx.lineTo(x1, d);
                            ctx.bezierCurveTo(x1 + s / 2, d, x1 + s / 2, wh, x1 + s, wh);
                            ctx.lineTo(xr - r, wh);
                            ctx.bezierCurveTo(xr - r + r * k, wh, xr, wh - r + r * k, xr, wh - r);
                            ctx.lineTo(xr, eh);
                            ctx.bezierCurveTo(xr, eh - eh * k, xr + ew - ew * k, 0, xr + ew, 0);
                            ctx.closePath();
                            ctx.fillStyle = Cfg.glass;
                            ctx.fill();
                        } else {
                            const W = width, H = height, X = x => me.rightCorner ? W - x : x, Y = y => me.bottomCorner ? H - y : y;
                            const w = Math.max(40, islSlot.width + 20), h = 36, s = 24, b = 8, R = 22, Lb = 30;
                            ctx.beginPath();
                            ctx.moveTo(X(0), Y(0));
                            ctx.lineTo(X(w + s), Y(0));
                            ctx.bezierCurveTo(X(w + s / 2), Y(0), X(w + s / 2), Y(h), X(w), Y(h));
                            ctx.lineTo(X(b + R), Y(h));
                            ctx.bezierCurveTo(X(b + R - R * k), Y(h), X(b), Y(h + R - R * k), X(b), Y(h + R));
                            ctx.lineTo(X(b), Y(h + R + Lb));
                            ctx.bezierCurveTo(X(b), Y(h + R + Lb + ew * k), X(0), Y(h + R + Lb + ew - ew * k), X(0), Y(h + R + Lb + ew));
                            ctx.closePath();
                            ctx.fillStyle = Qt.rgba(0.05, 0.055, 0.08, 0.92);
                            ctx.fill();
                        }
                    }
                }

                // the bar's clock notch (fixed)
                Item {
                    id: notch
                    visible: me.kind === "bar"
                    width: nRow.implicitWidth + 36; height: 40
                    x: Math.round(stage.width / 2 - width / 2)
                    Row {
                        id: nRow; anchors.centerIn: parent; spacing: 8
                        Text { text: Cfg.timeStr(new Date(), false); color: me.cFg; font.family: Cfg.fontUi; font.pixelSize: 13; font.weight: Font.Bold }
                        Text { text: Cfg.cap(Cfg.locale.toString(new Date(), "ddd, d MMM")); color: "#a9adbd"; font.family: Cfg.fontUi; font.pixelSize: 12 }
                    }
                }

                DropSlot {
                    id: leftSlot
                    visible: me.kind === "bar"
                    hub: me.kind === "bar" ? edHub : null
                    catalog: Cfg.barLeftCatalog; value: Cfg.barLeft; look: me.look; chip: chipC
                    onChanged: v => Cfg.set("barLeft", v)
                    width: Math.max(rowWidth, 30); height: 24; spacing: 2
                    x: notch.x - 24 - 4 - width; y: 3
                }
                DropSlot {
                    id: rightSlot
                    visible: me.kind === "bar"
                    hub: me.kind === "bar" ? edHub : null
                    catalog: Cfg.barRightCatalog; value: Cfg.barRight; look: me.look; chip: chipC
                    onChanged: v => Cfg.set("barRight", v)
                    width: Math.max(rowWidth, 30); height: 24; spacing: 2
                    x: notch.x + notch.width + 24 + 4; y: 3
                }
                DropSlot {
                    id: islSlot
                    visible: me.kind === "island"
                    hub: me.kind === "island" ? edHub : null
                    catalog: Cfg.islandCatalog; value: me.islandVal; look: me.look; chip: chipC; rtl: me.rightCorner
                    onChanged: v => Cfg.set("islandItems", v)
                    width: Math.max(rowWidth, 30); height: 24; spacing: 2
                    x: me.rightCorner ? stage.width - 10 - width : 10
                    y: me.bottomCorner ? stage.height - 36 + 6 : 6
                }
            }
        }

        // ── options of the clicked module ──
        Rectangle {
            id: optBox
            readonly property var opts: edHub.sel !== "" ? (Cfg.modOptCatalog[edHub.sel] || []) : []
            visible: opts.length > 0
            width: me.width; height: 50; radius: 14
            color: "#14ffffff"; border.width: 1; border.color: Cfg.acc(0.35)
            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text { text: edHub.sel !== "" ? (me.look(edHub.sel).glyph || "") : ""; font.family: me.fIcon; font.pixelSize: 14; color: Cfg.accent; anchors.verticalCenter: parent.verticalCenter }
                Text { text: edHub.selSlot ? edHub.selSlot.nameOf(edHub.sel) : ""; color: me.cFg; font.family: Cfg.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold
                       anchors.verticalCenter: parent.verticalCenter; rightPadding: 8 }
                Repeater {
                    model: optBox.opts
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: Cfg.mo(edHub.sel, modelData.k)
                        width: ot.implicitWidth + 40; height: 32; radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: on ? Cfg.accent : (oa.containsMouse ? "#29ffffff" : "#14ffffff")
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            anchors.centerIn: parent; spacing: 7
                            Text { text: on ? "" : ""; font.family: me.fIcon; font.pixelSize: 10; color: on ? Cfg.accFg : me.cMuted; anchors.verticalCenter: parent.verticalCenter }
                            Text { id: ot; text: me.t(modelData.t); color: on ? Cfg.accFg : me.cFg; font.family: Cfg.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: oa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Cfg.setMo(edHub.sel, modelData.k, !on) }
                    }
                }
            }
            Text {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                text: ""; font.family: me.fIcon; font.pixelSize: 12; color: cl.containsMouse ? Cfg.accent : me.cMuted
                MouseArea { id: cl; anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: edHub.click(edHub.selSlot, edHub.sel) }
            }
        }

        ModPalette {
            width: me.width
            hub: edHub
            slots: me.kind === "bar" ? [leftSlot, rightSlot] : [islSlot]
        }
    }
}
