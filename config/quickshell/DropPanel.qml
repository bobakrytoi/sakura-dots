// sakura mono - a menu that flows out of the top bar (sound, network, power, …).
// With the bar at the top it IS the bar morphed: it takes the bar's shape over (TopBar.drawShape) and turns it into
// its own box hanging from the top edge, under the button it was opened from - and back into the collapsed bar when
// it closes; TopBar hides itself on that screen meanwhile (covering). With the bar at the bottom (barpos.sh) it is
// a rounded card above the dock instead. The content goes inside (default property), in a boxW × boxH box.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

Scope {
    id: dp
    default property alias content: box.data
    property var topBar: null
    property bool shown: false
    signal closeRequested()
    property var screen0: Quickshell.screens[0]
    property real anchorX: -1                 // middle of the button it opened from, in screen coords (-1: centred)
    property int boxW: 320
    property int boxH: 200
    property int radius: 22
    property string ns: "drop"                // layer namespace (hyprland blurs behind the listed ones)
    property color fill: Cfg.glass          // = TopBar.fill (that one draws the shape at the top)

    property bool barDown: false
    FileView { path: Quickshell.env("HOME") + "/.config/sakura/barpos"; watchChanges: true; onFileChanged: reload()
        onLoaded: dp.barDown = text().trim() === "bottom"; onLoadFailed: dp.barDown = false }
    readonly property bool atBottom: barDown && !!screen0 && screen0.name === Cfg.mainName

    readonly property real screenW: screen0 ? screen0.width : 1920
    readonly property real dropX: Math.round(anchorX < 0 ? (screenW - boxW) / 2
                                             : Math.max(30, Math.min(screenW - boxW - 30, anchorX - boxW / 2)))   // 30: room for the ears
    property var fromGeo: null                // the bar's shape it starts from / ends in
    readonly property string covering: win.visible && !atBottom && screen0 ? screen0.name : ""
    property real closedAt: 0
    onShownChanged: {
        if (!shown) closedAt = Date.now();
        if (topBar && !atBottom && screen0) fromGeo = shown ? topBar.geoFor(screen0.name) : topBar.restGeoFor(screen0.name);
    }
    // a click on the button that opened it first closes it (click outside), then would open it again: don't
    function justClosed() { return Date.now() - closedAt < 350; }

    PanelWindow {
        id: win
        visible: dp.shown || grow > 0.001     // stays up while it morphs back into the bar
        screen: dp.screen0
        anchors { top: !dp.atBottom; bottom: dp.atBottom; left: true; right: true }    // the bar's shape is wider than the box
        margins.bottom: 76
        implicitHeight: dp.boxH
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: dp.ns
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        mask: Region { item: box }
        HyprlandFocusGrab { windows: [ win ]; active: dp.shown; onCleared: dp.closeRequested() }

        // 0 = the bar's shape, 1 = the whole box; the content fades in at the end (and out first on close)
        property real grow: dp.shown ? 1 : 0
        Behavior on grow { NumberAnimation { duration: 340 * Cfg.anim; easing.type: Easing.OutCubic } }

        Canvas {
            anchors.fill: parent
            readonly property string key: [win.grow, width, height, box.x, dp.boxW, dp.fromGeo ? dp.fromGeo.xl : 0, Cfg.glass].join(",")
            onKeyChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                if (!dp.atBottom && dp.topBar && dp.fromGeo) {
                    const mid = box.x + box.width / 2;
                    const to = { xl: box.x, xr: box.x + box.width, x0: mid - 10, x1: mid + 10, wh: height, d: height, r: dp.radius };
                    dp.topBar.drawShape(ctx, dp.topBar.lerpGeo(dp.fromGeo, to, win.grow));
                } else {      // above the dock (bar at the bottom): a rounded card growing up from the bottom
                    const h = 30 + (height - 30) * win.grow;
                    ctx.beginPath();
                    ctx.roundedRect(box.x, height - h, box.width, h, dp.radius, dp.radius);
                    ctx.fillStyle = dp.fill;
                    ctx.fill();
                }
            }
        }

        Item {
            id: box
            x: dp.dropX; width: dp.boxW; height: dp.boxH
            opacity: Math.max(0, (win.grow - 0.55) / 0.45)
            focus: dp.shown
            Keys.onEscapePressed: dp.closeRequested()
        }
    }
}
