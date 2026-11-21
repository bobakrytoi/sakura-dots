// sakura mono - desktop widgets on the wallpaper (main monitor; a widget with "mon": "<output>" lives on that one).
// Which widgets are shown and where: Settings > Desktop widgets, or right on the desktop
// (right-click > Edit widgets: drag, grid, size, style, hide/add). Stored in ~/.config/sakura/settings.json.
// Each widget is its own small layer surface, so empty desktop space never eats clicks.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

Scope {
    id: dw
    readonly property int pad: 24          // room for the soft shadow around the text
    // widgets with buttons / text fields take clicks (and the keyboard, on click)
    readonly property var clicky: ["player", "note", "todo", "timer"]
    readonly property var typing: ["note", "todo"]

    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cBg:     Cfg.glass
    readonly property color cHover:  "#29ffffff"
    readonly property color cCard:   "#14ffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"

    Variants {
        // the model is just the ids of the widgets that are on: a list of strings stays "the same" when any other
        // setting changes, so the widget windows are kept (an array of objects was rebuilt on every settings.json
        // write - every widget flashed). Position/size/style are read live from Cfg below.
        model: Desk.editing ? [] : Cfg.data.widgets.filter(w => w.on).map(w => w.id)
        delegate: PanelWindow {
            id: ww
            required property string modelData
            readonly property var wd: Cfg.widget(modelData) || ({ x: 0, y: 0, scale: 1 })
            readonly property real sc: wd.scale || 1
            screen: Cfg.widgetScreen(wd)
            anchors { left: true; top: true }
            margins { left: Math.round(wd.x - dw.pad); top: Math.round(wd.y - dw.pad) }
            implicitWidth: Math.ceil(dwi.implicitWidth * sc) + dw.pad * 2
            implicitHeight: Math.ceil(dwi.implicitHeight * sc) + dw.pad * 2
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Bottom              // above the wallpaper, below every window
            WlrLayershell.namespace: "desktop-widgets"
            WlrLayershell.keyboardFocus: dw.typing.includes(modelData) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            mask: Region { item: dw.clicky.includes(ww.modelData) ? dwi : null }
            // login / restart (Choreo.qml): the widgets fade and rise in one after another
            readonly property int enterI: Math.max(0, Cfg.data.widgets.filter(w => w.on).map(w => w.id).indexOf(modelData))
            readonly property real enterP: Choreo.widgetIn(enterI)
            DeskWidget {
                id: dwi
                x: dw.pad; y: dw.pad + Math.round((1 - ww.enterP) * 18)
                opacity: ww.enterP
                kind: ww.modelData
                style: ww.wd.style || ""
                darkText: Desk.lumaAt(ww.wd.x, ww.wd.y, implicitWidth * ww.sc, implicitHeight * ww.sc) > 160
                scale: ww.sc
                transformOrigin: Item.TopLeft
            }
        }
    }

    // ── editor: one full-screen surface on EVERY monitor, each draws the widgets that live on it ──
    // shared between the monitors: the selection, which monitor shows the add list, and the drag "ghost"
    // (a widget being dragged from one monitor onto another is drawn on the target monitor as a ghost)
    property string sel: ""
    property string addOn: ""                 // screen name whose toolbar has the add list open, "" = closed
    property var ghost: null                  // { id, scr, x, y, w, h } while a drag is over another monitor
    function screenAt(gx, gy) {
        return Quickshell.screens.find(s => gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height) || null;
    }
    // put a widget on a monitor: "mon" is left empty for the main monitor, so it follows "mainMonitor"
    function placeOn(id, scr, x, y, extra) { Cfg.placeWidget(id, scr, x, y, extra); }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: ed
            required property var modelData
            visible: Desk.editing
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top                 // above windows while editing
            WlrLayershell.namespace: "widget-editor"
            // the monitor it was opened on takes the keyboard (Esc closes); the others only on click
            WlrLayershell.keyboardFocus: !Desk.editing ? WlrKeyboardFocus.None
                                       : Desk.editScreen === modelData.name ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

            readonly property int g: Desk.grid
            function snap(v) { return g > 0 ? Math.round(v / g) * g : Math.round(v); }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: { if (dw.addOn !== "") dw.addOn = ""; else Desk.editing = false; }

                Rectangle { anchors.fill: parent; color: "#30000000" }   // < ignore_alpha 0.2: hyprland blurs only the toolbars
                // grid dots
                Canvas {
                    anchors.fill: parent
                    visible: ed.g > 0
                    readonly property int g: ed.g
                    onGChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d"); c.reset();
                        if (g <= 0) return;
                        c.fillStyle = "rgba(255,255,255,0.22)";
                        for (let x = 0; x <= width; x += g) for (let y = 0; y <= height; y += g) c.fillRect(x - 1, y - 1, 2, 2);
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: { dw.sel = ""; dw.addOn = ""; } }

                // a widget dragged here from another monitor
                Rectangle {
                    readonly property var gh: dw.ghost && dw.ghost.scr === ed.modelData.name ? dw.ghost : null
                    visible: gh !== null
                    x: gh ? gh.x - 8 : 0; y: gh ? gh.y - 8 : 0
                    width: gh ? gh.w + 16 : 0; height: gh ? gh.h + 16 : 0
                    radius: 14; color: Cfg.acc(0.14); border.width: 2; border.color: dw.cAccent; z: 6
                }

                Repeater {
                    model: Desk.editing ? Cfg.data.widgets.filter(w => w.on && Cfg.widgetScreen(w) === ed.modelData) : []
                    delegate: Item {
                        id: wi
                        required property var modelData
                        readonly property real sc: modelData.scale || 1
                        readonly property bool selected: dw.sel === modelData.id
                        readonly property bool away: dw.ghost !== null && dw.ghost.id === modelData.id
                        x: modelData.x; y: modelData.y
                        width: dwp.implicitWidth * sc; height: dwp.implicitHeight * sc
                        z: selected || wma.drag ? 5 : 1
                        opacity: away ? 0.3 : 1

                        DeskWidget { id: dwp; kind: wi.modelData.id; style: wi.modelData.style || ""; preview: true; scale: wi.sc; transformOrigin: Item.TopLeft }
                        Rectangle {
                            anchors.fill: parent; anchors.margins: -8; radius: 14
                            color: wma.drag ? Cfg.acc(0.10) : "transparent"
                            border.width: wi.selected || wma.containsMouse ? 2 : 1
                            border.color: wi.selected || wma.containsMouse ? dw.cAccent : "#40ffffff"
                        }
                        MouseArea {
                            id: wma
                            anchors.fill: parent; anchors.margins: -8
                            hoverEnabled: true; preventStealing: true
                            property bool drag: false
                            property point off
                            cursorShape: drag ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            onPressed: m => { const p = mapToItem(null, m.x, m.y); off = Qt.point(p.x - wi.x, p.y - wi.y); drag = true; dw.sel = wi.modelData.id; dw.addOn = ""; }
                            onPositionChanged: m => {
                                if (!drag) return;
                                const p = mapToItem(null, m.x, m.y), free = (m.modifiers & Qt.ShiftModifier) !== 0;
                                const s = ed.modelData, t = dw.screenAt(s.x + p.x, s.y + p.y);
                                if (t && t !== s) {
                                    // the pointer is over another monitor: show where it would land there
                                    let nx = s.x + p.x - off.x - t.x, ny = s.y + p.y - off.y - t.y;
                                    if (!free) { nx = ed.snap(nx); ny = ed.snap(ny); }
                                    dw.ghost = { id: wi.modelData.id, scr: t.name, w: wi.width, h: wi.height,
                                                 x: Math.max(0, Math.min(t.width - wi.width, nx)), y: Math.max(0, Math.min(t.height - wi.height, ny)) };
                                    return;
                                }
                                dw.ghost = null;
                                let nx = p.x - off.x, ny = p.y - off.y;
                                if (!free) { nx = ed.snap(nx); ny = ed.snap(ny); }
                                wi.x = Math.max(0, Math.min(ed.width - wi.width, nx));
                                wi.y = Math.max(0, Math.min(ed.height - wi.height, ny));
                            }
                            onReleased: {
                                drag = false;
                                const gh = dw.ghost, t = gh ? Quickshell.screens.find(s => s.name === gh.scr) : null;
                                dw.ghost = null;
                                if (t) dw.placeOn(wi.modelData.id, t, gh.x, gh.y);
                                else Cfg.setWidget(wi.modelData.id, { x: Math.round(wi.x), y: Math.round(wi.y) });
                            }
                        }

                        // per-widget toolbar: style · size · monitor · hide
                        Rectangle {
                            visible: wi.selected && !wma.drag
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: wi.y > 60 ? -48 : wi.height + 14
                            width: tb.implicitWidth + 12; height: 36; radius: 12; color: dw.cBg
                            border.width: 1; border.color: dw.cBorder
                            Row {
                                id: tb; anchors.centerIn: parent; spacing: 2
                                readonly property var styles: Cfg.widgetStyles[wi.modelData.id] || []
                                TBtn {
                                    visible: tb.styles.length > 1; icon: "\uf1fc"; label: Cfg.tr("Style")
                                    onClicked: { const s = tb.styles, cur = s.indexOf(wi.modelData.style || s[0]); Cfg.setWidget(wi.modelData.id, { style: s[(cur + 1) % s.length] }); }
                                }
                                TBtn { icon: "\uf068"; onClicked: Cfg.setWidget(wi.modelData.id, { scale: Math.max(0.5, Math.round((wi.sc - 0.1) * 10) / 10) }) }
                                Text { width: 40; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter
                                       text: Math.round(wi.sc * 100) + "%"; font.family: dw.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: dw.cFg }
                                TBtn { icon: "\uf067"; onClicked: Cfg.setWidget(wi.modelData.id, { scale: Math.min(2, Math.round((wi.sc + 0.1) * 10) / 10) }) }
                                Rectangle { width: 1; height: 18; color: dw.cBorder; anchors.verticalCenter: parent.verticalCenter }
                                // send to the next monitor, same spot (kept inside the screen)
                                TBtn {
                                    visible: Quickshell.screens.length > 1; icon: "\uf108"; label: Cfg.tr("Monitor")
                                    onClicked: {
                                        const ss = Quickshell.screens, t = ss[(ss.indexOf(ed.modelData) + 1) % ss.length];
                                        dw.placeOn(wi.modelData.id, t, Math.min(wi.x, t.width - wi.width), Math.min(wi.y, t.height - wi.height));
                                    }
                                }
                                TBtn { icon: "\uf070"; label: Cfg.tr("Hide"); onClicked: { Cfg.setWidget(wi.modelData.id, { on: false }); dw.sel = ""; } }
                            }
                        }
                    }
                }

                // ── top toolbar: grid · add · reset · done ──
                Rectangle {
                    id: bar
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 96 }
                    width: br.implicitWidth + 16; height: 48; radius: 16; color: dw.cBg
                    border.width: 1; border.color: dw.cBorder
                    Row {
                        id: br; anchors.centerIn: parent; spacing: 6
                        Text { text: "\uf00a"; font.family: dw.fIcon; font.pixelSize: 13; color: dw.cAccent; anchors.verticalCenter: parent.verticalCenter; leftPadding: 6 }
                        Text { text: Cfg.tr("Grid"); font.family: dw.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: dw.cMuted; anchors.verticalCenter: parent.verticalCenter; rightPadding: 2 }
                        Repeater {
                            model: [0, 16, 32, 48, 64]
                            Rectangle {
                                required property int modelData
                                readonly property bool on: Desk.grid === modelData
                                width: gl.implicitWidth + 18; height: 32; radius: 10
                                color: on ? Cfg.acc(0.22) : gm.containsMouse ? dw.cHover : "transparent"
                                anchors.verticalCenter: parent.verticalCenter
                                Text { id: gl; anchors.centerIn: parent; text: parent.modelData === 0 ? Cfg.tr("Off") : parent.modelData
                                       font.family: dw.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: parent.on ? dw.cAccent : dw.cFg }
                                MouseArea { id: gm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Cfg.set("deskGrid", parent.modelData) }
                            }
                        }
                        Rectangle { width: 1; height: 22; color: dw.cBorder; anchors.verticalCenter: parent.verticalCenter }
                        BarBtn { icon: "\uf067"; label: Cfg.tr("Add widget"); onClicked: dw.addOn = dw.addOn === ed.modelData.name ? "" : ed.modelData.name }
                        BarBtn { icon: "\uf0e2"; label: Cfg.tr("Reset"); onClicked: Cfg.resetWidgets() }
                        BarBtn { icon: "\uf00c"; label: Cfg.tr("Done"); primary: true; onClicked: Desk.editing = false }
                    }
                }
                // ── add list: the widgets that are hidden; they appear on this monitor ──
                Rectangle {
                    visible: dw.addOn === ed.modelData.name
                    anchors { horizontalCenter: bar.horizontalCenter; top: bar.bottom; topMargin: 8 }
                    width: 300; height: addCol.implicitHeight + 12; radius: 16; color: dw.cBg
                    border.width: 1; border.color: dw.cBorder
                    Column {
                        id: addCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                        readonly property var off: Cfg.widgetCatalog.filter(c => { const w = Cfg.widget(c.id); return !w || !w.on; })
                        Text { visible: addCol.off.length === 0; width: parent.width; horizontalAlignment: Text.AlignHCenter; topPadding: 10; bottomPadding: 10
                               text: Cfg.tr("All widgets are on the desktop"); font.family: dw.fUi; font.pixelSize: 12; color: dw.cMuted }
                        Repeater {
                            model: addCol.off
                            Rectangle {
                                required property var modelData
                                width: addCol.width; height: 34; radius: 10
                                color: am.containsMouse ? dw.cHover : "transparent"
                                Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                       text: Cfg.tr(parent.modelData.name); font.family: dw.fUi; font.pixelSize: 13; color: dw.cFg }
                                Text { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                       text: "\uf067"; font.family: dw.fIcon; font.pixelSize: 11; color: am.containsMouse ? dw.cAccent : dw.cMuted }
                                MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const id = parent.modelData.id, w = Cfg.widget(id), s = ed.modelData;
                                        const x = w && typeof w.x === "number" ? Math.min(w.x, s.width - 200) : 96, y = w && typeof w.y === "number" ? Math.min(w.y, s.height - 200) : 96;
                                        dw.placeOn(id, s, x, y, { on: true }); dw.sel = id; dw.addOn = "";
                                    } }
                            }
                        }
                    }
                }
            }
        }
    }

    component TBtn: Rectangle {
        id: tbb
        property string icon: ""
        property string label: ""
        signal clicked()
        width: Math.max(28, tl.implicitWidth + 16); height: 28; radius: 8
        color: tbm.containsMouse ? dw.cHover : "transparent"
        Row { id: tl; anchors.centerIn: parent; spacing: 6
            Text { visible: tbb.icon !== ""; text: tbb.icon; font.family: dw.fIcon; font.pixelSize: 12; color: tbm.containsMouse ? dw.cAccent : dw.cFg; anchors.verticalCenter: parent.verticalCenter }
            Text { visible: tbb.label !== ""; text: tbb.label; font.family: dw.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: dw.cFg; anchors.verticalCenter: parent.verticalCenter } }
        MouseArea { id: tbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tbb.clicked() }
    }
    component BarBtn: Rectangle {
        id: bb
        property string icon: ""
        property string label: ""
        property bool primary: false
        signal clicked()
        width: bl.implicitWidth + 24; height: 32; radius: 10
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: primary ? (bbm.containsMouse ? Qt.lighter(dw.cAccent, 1.08) : dw.cAccent) : bbm.containsMouse ? dw.cHover : "transparent"
        Row { id: bl; anchors.centerIn: parent; spacing: 7
            Text { text: bb.icon; font.family: dw.fIcon; font.pixelSize: 12; color: bb.primary ? dw.cAccFg : bbm.containsMouse ? dw.cAccent : dw.cFg; anchors.verticalCenter: parent.verticalCenter }
            Text { text: bb.label; font.family: dw.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: bb.primary ? dw.cAccFg : dw.cFg; anchors.verticalCenter: parent.verticalCenter } }
        MouseArea { id: bbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bb.clicked() }
    }
}
