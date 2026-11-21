// sakura mono - the grip of a chip (see ModHub): drag = move it, click = select (in a list) or add (in the palette)
import QtQuick

MouseArea {
    id: da
    property var hub: null
    property var slot: null
    property string mid: ""
    property bool pal: false
    hoverEnabled: true
    preventStealing: true
    cursorShape: hub && hub.dragId !== "" ? Qt.ClosedHandCursor : (pal ? Qt.PointingHandCursor : Qt.OpenHandCursor)
    property real px: 0
    property real py: 0
    property bool moved: false
    onPressed: m => { px = m.x; py = m.y; moved = false; }
    onPositionChanged: m => {
        if (!pressed || !hub || !slot) return;
        if (!moved && Math.abs(m.x - px) + Math.abs(m.y - py) > 5) { moved = true; hub.begin(mid, slot, pal); }
        if (moved) hub.move(da, m.x, m.y);
    }
    onReleased: {
        if (!hub || !slot) return;
        if (moved) hub.end();
        else if (pal) slot.add(mid);
        else hub.click(slot, mid);
    }
    onCanceled: if (moved && hub) hub.end()
}
