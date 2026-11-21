// Plain slider: from/to/step, value; moved(v) while dragging.
import QtQuick

Item {
    id: sl
    property real from: 0
    property real to: 1
    property real step: 0
    property real value: 0
    property string suffix: ""
    property int decimals: 0
    signal moved(real v)
    width: 220; height: 28
    readonly property real frac: to > from ? (value - from) / (to - from) : 0
    function pick(x) {
        let v = from + Math.max(0, Math.min(1, x / track.width)) * (to - from);
        if (step > 0) v = Math.round(v / step) * step;
        moved(Number(v.toFixed(4)));
    }
    Rectangle { id: track; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52; height: 4; radius: 2; color: Theme.cardHi
        Rectangle { width: parent.width * sl.frac; height: parent.height; radius: 2; color: Theme.accent }
        Rectangle { x: parent.width * sl.frac - 7; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7; color: Theme.fg } }
    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 44; horizontalAlignment: Text.AlignRight
           text: sl.value.toFixed(sl.decimals) + sl.suffix; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11; font.features: { "tnum": 1 } }
    MouseArea { anchors.fill: track; anchors.margins: -10; cursorShape: Qt.PointingHandCursor
        onPressed: m => sl.pick(m.x - 10); onPositionChanged: m => { if (pressed) sl.pick(m.x - 10); } }
}
