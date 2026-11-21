// sakura mono - autoscroll anchor (middle button, like Windows). Driven by hypr/scripts/autoscroll.py via IPC.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: as
    property bool shown: false
    property int gx: 0          // anchor, global coordinates
    property int gy: 0
    property int dv: 0          // -1 up, 1 down, 0 none
    property int dh: 0          // -1 left, 1 right
    readonly property var scr: {
        const l = Quickshell.screens;
        for (let i = 0; i < l.length; i++) {
            const s = l[i];
            if (gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height) return s;
        }
        return l[0];
    }
    IpcHandler {
        target: "autoscroll"
        function state(shown: int, x: int, y: int, v: int, h: int): void {
            if (shown) { as.gx = x; as.gy = y; }
            as.dv = v; as.dh = h; as.shown = shown !== 0;
        }
    }
    PanelWindow {
        visible: as.shown || dial.opacity > 0.01
        screen: as.scr
        anchors { top: true; left: true }
        margins { left: as.gx - as.scr.x - 24; top: as.gy - as.scr.y - 24 }
        implicitWidth: 48; implicitHeight: 48
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "autoscroll"
        mask: Region {}                       // never takes the mouse
        Rectangle {
            id: dial
            anchors.centerIn: parent
            width: 40; height: 40; radius: 20
            color: Cfg.glass
            border.width: 1.5; border.color: Cfg.acc(0.55)
            opacity: as.shown ? 1 : 0
            scale: as.shown ? 1 : 0.6
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            Rectangle {      // center dot
                anchors.centerIn: parent
                width: 6; height: 6; radius: 3
                color: Cfg.acc(as.dv === 0 && as.dh === 0 ? 1 : 0.6)
            }
            // arrows: up / down strong, left / right faint
            Repeater {
                model: [ { a: 0, on: as.dv < 0, main: true }, { a: 180, on: as.dv > 0, main: true },
                         { a: 270, on: as.dh < 0, main: false }, { a: 90, on: as.dh > 0, main: false } ]
                delegate: Item {
                    required property var modelData
                    anchors.fill: parent
                    rotation: modelData.a
                    Canvas {
                        id: tri
                        property color c: modelData.on ? Cfg.accent : Qt.rgba(1, 1, 1, modelData.main ? 0.8 : 0.35)
                        onCChanged: requestPaint()
                        x: parent.width / 2 - 5; y: 4
                        width: 10; height: 7
                        scale: modelData.on ? 1.25 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        onPaint: {
                            const g = getContext("2d");
                            g.reset(); g.fillStyle = c;
                            g.beginPath(); g.moveTo(5, 0); g.lineTo(10, 7); g.lineTo(0, 7); g.closePath(); g.fill();
                        }
                    }
                }
            }
        }
    }
}
