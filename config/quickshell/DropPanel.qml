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
    property bool grabFocus: true             // false: shows without taking the keyboard (look checks)
    // smoothness knobs (default = the old behaviour):
    property int winH: boxH                   // window height; a panel whose box grows/shrinks keeps it at its largest, so the
                                              // surface is not resized on every frame (only the shape is redrawn)
    property real contentFrom: 0.55           // grow value where the content starts to fade in
    property bool clipToShape: false          // clip the content to the shape while it morphs (content shows early, never outside)
    property bool fastShape: false            // Canvas FBO instead of a CPU image - DON'T: on this setup it leaves ghosts of old frames on screen

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
        implicitHeight: dp.winH
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: dp.ns
        WlrLayershell.keyboardFocus: dp.grabFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        mask: Region { item: box }
        HyprlandFocusGrab { windows: [ win ]; active: dp.shown && dp.grabFocus; onCleared: dp.closeRequested() }

        // 0 = the bar's shape, 1 = the whole box; the content fades in at the end (and out first on close)
        property real grow: dp.shown ? 1 : 0
        Behavior on grow { NumberAnimation { duration: 340 * Cfg.anim; easing.type: Easing.OutCubic } }

        // the shape right now (top: the bar morphing into the box), null above the dock
        readonly property var geo: {
            if (dp.atBottom || !dp.topBar || !dp.fromGeo) return null;
            const mid = dp.dropX + dp.boxW / 2;
            const to = { xl: dp.dropX, xr: dp.dropX + dp.boxW, x0: mid - 10, x1: mid + 10, wh: dp.boxH, d: dp.boxH, r: dp.radius };
            return dp.topBar.lerpGeo(dp.fromGeo, to, win.grow);
        }
        Canvas {
            anchors.fill: parent
            renderTarget: dp.fastShape ? Canvas.FramebufferObject : Canvas.Image
            readonly property string key: [win.grow, width, height, dp.dropX, dp.boxW, dp.boxH, dp.fromGeo ? dp.fromGeo.xl : 0, Cfg.glass].join(",")
            onKeyChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                if (win.geo) dp.topBar.drawShape(ctx, win.geo);
                else {        // above the dock (bar at the bottom): a rounded card growing up from the bottom
                    const h = 30 + (dp.boxH - 30) * win.grow;
                    ctx.beginPath();
                    ctx.roundedRect(dp.dropX, height - h, dp.boxW, h, dp.radius, dp.radius);
                    ctx.fillStyle = dp.fill;
                    ctx.fill();
                }
            }
        }

        Item {
            id: clipper
            readonly property bool on: dp.clipToShape && !!win.geo
            x: on ? win.geo.xl : 0
            width: on ? win.geo.xr - win.geo.xl : win.width
            height: on ? Math.min(win.geo.wh, win.height) : win.height
            clip: on
            Item {
                id: box
                x: dp.dropX - clipper.x
                y: dp.atBottom ? win.height - dp.boxH : 0
                width: dp.boxW; height: dp.boxH
                opacity: Math.max(0, (win.grow - dp.contentFrom) / (1 - dp.contentFrom))
                focus: dp.shown
                Keys.onEscapePressed: dp.closeRequested()
            }
        }
    }
}
