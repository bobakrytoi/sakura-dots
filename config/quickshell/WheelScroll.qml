import QtQuick

// Browser-like wheel scrolling for a Flickable. Put it over the Flickable (anchors.fill: flick, z above it);
// clicks and hover pass through (acceptedButtons: NoButton), only the wheel is taken.
//  · mouse wheel: `step` px per notch (hi-res wheels send fractions of a notch), eased over `duration` ms;
//    the target accumulates, so a fast spin keeps going from where the last notch was headed - no lag, no reset
//  · touchpad (pixelDelta, or a scroll with phases): 1:1, no easing
MouseArea {
    id: ws
    property Flickable flick
    property real step: 110
    property int duration: 180
    property real goal: 0
    readonly property real maxY: flick ? Math.max(0, flick.contentHeight - flick.height) : 0
    acceptedButtons: Qt.NoButton

    function clamp(v) { return Math.max(0, Math.min(maxY, v)); }
    // jump straight there (and drop any running ease)
    function jump(y) { anim.stop(); if (flick) flick.contentY = clamp(y); goal = flick ? flick.contentY : 0; }

    NumberAnimation { id: anim; target: ws.flick; property: "contentY"; duration: ws.duration; easing.type: Easing.OutCubic }

    onWheel: w => {
        if (!flick) return;
        if (w.pixelDelta.y !== 0 && w.phase !== Qt.NoScrollPhase) {       // touchpad: 1:1
            jump(flick.contentY - w.pixelDelta.y);
            return;
        }
        if (w.angleDelta.y === 0) { if (w.pixelDelta.y !== 0) jump(flick.contentY - w.pixelDelta.y); return; }
        // mouse wheel: continue from where a running ease is heading
        const from = anim.running ? ws.goal : flick.contentY;
        ws.goal = clamp(from - w.angleDelta.y / 120 * step);
        anim.stop();
        anim.from = flick.contentY;
        anim.to = ws.goal;
        anim.start();
    }
}
