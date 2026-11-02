// sakura mono — snap preview: shows where a dragged window will land (driven by Hyprland via IPC)
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: sn
    property bool shown: false
    property string mon: "DP-3"
    property real rx: 0
    property real ry: 0
    property real rw: 0
    property real rh: 0
    IpcHandler {
        target: "snap"
        function show(mon: string, x: int, y: int, w: int, h: int): void {
            const first = !sn.shown || sn.mon !== mon;
            sn.mon = mon; sn.rx = x; sn.ry = y; sn.rw = w; sn.rh = h; sn.shown = true;
        }
        function hide(): void { sn.shown = false; }
    }
    PanelWindow {
        visible: sn.shown || box.opacity > 0.01
        screen: Quickshell.screens.find(s => s.name === sn.mon) || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "snap-preview"
        mask: Region {}                       // never takes the mouse
        Rectangle {
            id: box
            x: sn.rx; y: sn.ry; width: sn.rw; height: sn.rh
            radius: 16
            color: "#33f2b8d0"
            border.width: 3; border.color: "#cff2b8d0"
            opacity: sn.shown ? 1 : 0
            scale: sn.shown ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
    }
}
