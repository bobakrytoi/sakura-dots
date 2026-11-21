// SoundCloud waveform seek bar. Styles: bars / line / mirror / off (plain bar).
// Repaints only when the played part crosses a bar or the hover moves.
import QtQuick

Item {
    id: w
    property var samples: Sound.wave
    property real pos: ma.dragFrac >= 0 ? ma.dragFrac * dur : Sound.livePos
    property real dur: Sound.dur
    property string style: Theme.waveStyle
    property var comments: []               // [{t, user}] markers
    property color played: Theme.accent
    property color rest: Theme.a(Theme.fg, 0.22)
    readonly property bool plain: style === "off" || !samples || samples.length === 0
    readonly property int n: samples ? samples.length : 0
    readonly property real frac: dur > 0 ? Math.max(0, Math.min(1, pos / dur)) : 0
    readonly property real hoverFrac: ma.containsMouse ? Math.max(0, Math.min(1, ma.mouseX / width)) : -1
    readonly property int playedBars: Math.floor(frac * (plain ? width : n))
    implicitHeight: 40

    onPlayedBarsChanged: if (!plain) cv.requestPaint()
    onSamplesChanged: cv.requestPaint()
    onStyleChanged: cv.requestPaint()
    onHoverFracChanged: if (!plain) cv.requestPaint()
    onWidthChanged: cv.requestPaint()
    onPlayedChanged: cv.requestPaint()

    // plain bar
    Item {
        visible: w.plain
        anchors.fill: parent
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: ma.containsMouse ? 6 : 4; radius: 3; color: w.rest }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * w.frac; height: ma.containsMouse ? 6 : 4; radius: 3; color: w.played }
    }

    Canvas {
        id: cv
        visible: !w.plain
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const n = w.n; if (!n) return;
            const W = width, H = height;
            const gap = W / n > 3 ? 1 : 0.5;
            const bw = W / n;
            const hv = w.hoverFrac;
            if (w.style === "line") {
                // simple envelope stroke
                for (let pass = 0; pass < 2; pass++) {
                    ctx.save();
                    ctx.beginPath();
                    if (pass === 0) ctx.rect(w.frac * W, 0, W, H); else ctx.rect(0, 0, w.frac * W, H);
                    ctx.clip();
                    ctx.beginPath();
                    for (let i = 0; i < n; i++) {
                        const x = i * bw + bw / 2, y = H / 2 - w.samples[i] * H * 0.45;
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    for (let i = n - 1; i >= 0; i--) ctx.lineTo(i * bw + bw / 2, H / 2 + w.samples[i] * H * 0.45);
                    ctx.closePath();
                    ctx.fillStyle = pass === 0 ? Qt.rgba(w.rest.r, w.rest.g, w.rest.b, 0.5) : w.played;
                    ctx.fill();
                    ctx.restore();
                }
                return;
            }
            const mirror = w.style === "mirror";
            for (let i = 0; i < n; i++) {
                const v = Math.max(0.06, w.samples[i]);
                const x = i * bw;
                const isPlayed = (i + 0.5) / n <= w.frac;
                const isHover = hv >= 0 && (i + 0.5) / n <= hv && !isPlayed;
                ctx.fillStyle = isPlayed ? w.played : isHover ? Qt.rgba(w.played.r, w.played.g, w.played.b, 0.45) : w.rest;
                if (mirror) {
                    const h = v * H * 0.62;
                    ctx.fillRect(x, H * 0.62 - h, Math.max(0.5, bw - gap), h);
                    ctx.globalAlpha = 0.35;
                    ctx.fillRect(x, H * 0.62 + 1, Math.max(0.5, bw - gap), v * H * 0.36);
                    ctx.globalAlpha = 1;
                } else {
                    const h = Math.max(2, v * H);
                    ctx.fillRect(x, (H - h) / 2, Math.max(0.5, bw - gap), h);
                }
            }
        }
    }

    // comment markers
    Repeater {
        model: w.dur > 0 ? w.comments.length : 0
        Rectangle {
            readonly property var cm: w.comments[index]
            x: w.width * Math.min(1, cm.t / w.dur) - 1
            y: w.height - 3; width: 2; height: 3; radius: 1
            color: Theme.a(Theme.fg, 0.5)
        }
    }

    // hover time
    Rectangle {
        visible: ma.containsMouse && w.dur > 0
        x: Math.max(0, Math.min(w.width - width, ma.mouseX - width / 2))
        y: -height - 6
        width: hvT.implicitWidth + 12; height: 20; radius: 10
        color: Theme.pop
        Text { id: hvT; anchors.centerIn: parent; text: Theme.time(w.hoverFrac * w.dur); color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 11; font.features: { "tnum": 1 } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        property real dragFrac: -1
        onPressed: m => { if (w.dur > 0) dragFrac = Math.max(0, Math.min(1, m.x / width)); }
        onPositionChanged: m => { if (pressed && w.dur > 0) dragFrac = Math.max(0, Math.min(1, m.x / width)); }
        onReleased: { if (dragFrac >= 0) Sound.seek(dragFrac * w.dur); dragFrac = -1; }
        onCanceled: dragFrac = -1
    }
}
