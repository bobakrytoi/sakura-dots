// sakura mono - one invisible 2 px drop catcher on a screen edge for the file converter (Convert.qml).
// A drag with files entering it opens the radial menu on that screen.
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: ec
    property var host: null             // the Convert scope
    property string side: "left"
    property var scr: null
    property bool want: false
    property int mTop: 90
    property int mBottom: 110
    screen: scr
    visible: want
    anchors { left: side === "left"; right: side === "right"; top: true; bottom: true }
    margins { top: ec.mTop; bottom: ec.mBottom }
    implicitWidth: 2
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "convert-edge"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    DropArea {
        anchors.fill: parent
        onEntered: drag => {
            const l = ec.host.fromUrls(drag.urls || []);
            if (!l.length) { drag.accepted = false; return; }
            drag.accept(Qt.CopyAction);
            ec.host.openOn(ec.scr, l, ec.side === "left" ? 0 : ec.scr.width, ec.mTop + drag.y, ec.side, true, false);
        }
        onDropped: drop => { drop.accepted = false; }
    }
}
