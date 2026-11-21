import QtQuick
import QtQuick.Effects
import "../.."

Item {
    id: pl
    property var api: null
    property var data: ({ synced: [], plain: "" })
    property bool loading: false
    readonly property var lines: data.synced || []
    readonly property real t: api ? api.position + api.get("offset", 0) + 0.15 : 0
    // frame-accurate clock for the letter fill (runs only while a lyrics view is shown and music plays)
    property int views: 0
    property real ft: 0
    FrameAnimation {
        running: pl.views > 0 && Sound.playing && !Sound.buffering
        onTriggered: pl.ft = Sound.pos + (Date.now() - Sound._posAt) / 1000 + (pl.api ? pl.api.get("offset", 0) : 0) + 0.15
    }
    readonly property int cur: {
        const L = lines; if (!L.length) return -1;
        let lo = 0, hi = L.length - 1, ans = -1;
        while (lo <= hi) { const mid = (lo + hi) >> 1; if (L[mid].t <= t) { ans = mid; lo = mid + 1; } else hi = mid - 1; }
        return ans;
    }
    function load() {
        if (!api || !api.track) { data = { synced: [], plain: "" }; return; }
        const id = api.track.id;
        loading = true;
        api.send("lyrics", { track: api.track }, r => { if (api.track && api.track.id === id) { pl.data = r.err ? { synced: [], plain: "" } : r; pl.loading = false; } });
    }
    onApiChanged: if (api) {
        api.addSideTab({ id: "lyrics", icon: "lyrics", label: "Lyrics", component: panel });
        api.addNowBlock({ component: nowLine });
        load();
    }
    Connections { target: pl.api; function onStarted() { pl.data = { synced: [], plain: "" }; loadT.restart(); } }
    Timer { id: loadT; interval: 300; onTriggered: pl.load() }

    Component {
        id: panel
        Item {
            Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Theme.line }
            Text { x: 20; y: 18; text: Theme.tr("Lyrics"); color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 17; font.weight: Font.Bold }
            Text { anchors.centerIn: parent; width: parent.width - 48; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                   visible: !pl.loading && !pl.lines.length && !pl.data.plain
                   text: Theme.tr("No lyrics found"); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 13 }
            Spinner { anchors.centerIn: parent; visible: pl.loading }
            Flickable {
                visible: !pl.lines.length && !!pl.data.plain
                anchors.fill: parent; anchors.topMargin: 56; anchors.margins: 20
                contentHeight: plainT.implicitHeight + 40; clip: true
                Text { id: plainT; width: parent.width; text: pl.data.plain || ""; wrapMode: Text.WordWrap; color: Theme.fg
                       font.family: Theme.fontUi; font.pixelSize: pl.api ? pl.api.get("size", 17) - 2 : 15; lineHeight: 1.25 }
            }
            // Apple-Music-like view: smooth follow, current line grows and lights up word by word,
            // other lines shrink/dim/blur a little, lines catch up in a staggered wave.
            Flickable {
                id: fl
                visible: pl.lines.length > 0
                Component.onCompleted: pl.views += 1
                Component.onDestruction: pl.views -= 1
                anchors.fill: parent; anchors.topMargin: 56; anchors.bottomMargin: 12
                clip: true
                contentHeight: lcol.height + height * 0.6
                boundsBehavior: Flickable.StopAtBounds
                property bool userScroll: false
                onMovementStarted: { userScroll = true; resumeT.stop(); }
                onMovementEnded: resumeT.restart()
                Timer { id: resumeT; interval: 3000; onTriggered: { fl.userScroll = false; fl.follow(); } }
                property real target: 0
                function follow() {
                    if (userScroll || pl.cur < 0 || !rep.itemAt(pl.cur)) return;
                    const it = rep.itemAt(pl.cur);
                    target = Math.max(0, Math.min(contentHeight - height, it.y - height * 0.32));
                    followAnim.restart();
                }
                NumberAnimation { id: followAnim; target: fl; property: "contentY"; to: fl.target; duration: Theme.dur(650); easing.type: Easing.OutCubic }
                Connections { target: pl; function onCurChanged() { fl.follow(); } }
                onHeightChanged: follow()

                Column {
                    id: lcol
                    width: fl.width
                    spacing: 14
                    topPadding: 8
                    Repeater {
                        id: rep
                        model: pl.lines.length
                        Item {
                            id: ld
                            required property int index
                            readonly property var ln: pl.lines[index]
                            readonly property int dist: pl.cur < 0 ? 3 : Math.abs(index - pl.cur)
                            readonly property bool on: index === pl.cur
                            readonly property real t0: ln.t
                            readonly property real t1: index + 1 < pl.lines.length ? pl.lines[index + 1].t : ln.t + 4
                            readonly property var words: (ln.text || "♪").split(/\s+/).filter(w => w.length)
                            readonly property var cum: { let c = 0, out = []; const tot = words.join("").length || 1; for (const w of words) { out.push(c / tot); c += w.length; } return out; }
                            width: lcol.width; height: flow.implicitHeight
                            scale: on ? 1.0 : 0.97
                            transformOrigin: Item.Left
                            Behavior on scale { NumberAnimation { duration: Theme.dur(420); easing.type: Easing.OutCubic } }
                            opacity: on ? 1 : index < pl.cur ? Math.max(0.28, 0.5 - dist * 0.04) : Math.max(0.35, 0.62 - dist * 0.05)
                            Behavior on opacity { NumberAnimation { duration: Theme.dur(350) } }
                            // staggered catch-up wave when the current line changes
                            transform: Translate { id: shift; y: 0 }
                            Connections {
                                target: pl
                                function onCurChanged() {
                                    if (ld.dist > 7 || fl.userScroll) return;
                                    wave.stop(); shift.y = 8; pause.duration = Math.min(7, ld.dist) * 25; wave.start();
                                }
                            }
                            SequentialAnimation {
                                id: wave
                                PauseAnimation { id: pause; duration: 0 }
                                NumberAnimation { target: shift; property: "y"; to: 0; duration: Theme.dur(520); easing.type: Easing.OutCubic }
                            }
                            // neighbours slightly blurred, the current line softly glowing
                            layer.enabled: ld.dist <= 6
                            layer.effect: MultiEffect {
                                blurEnabled: !ld.on; blurMax: 10; blur: Math.min(0.35, ld.dist * 0.09)
                                shadowEnabled: ld.on; shadowColor: Theme.fg; shadowBlur: 0.6; shadowOpacity: 0.28
                                shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                            }

                            Flow {
                                id: flow
                                x: 20; width: parent.width - 40
                                spacing: Math.round((pl.api ? pl.api.get("size", 17) : 17) * 0.28)
                                Repeater {
                                    model: ld.words.length
                                    // a word. The current line is drawn letter by letter: each letter eases from dim to full colour
                                    // over ~2-3 letters (a soft gradient, no hard edge) and the letter being sung swells and lifts a bit.
                                    Item {
                                        id: wd
                                        required property int index
                                        readonly property string w: ld.words[index]
                                        readonly property real span: (ld.t1 - ld.t0) * 0.9
                                        readonly property real ws: ld.t0 + ld.cum[index] * span
                                        readonly property real we: ld.t0 + (index + 1 < ld.cum.length ? ld.cum[index + 1] : 1) * span
                                        readonly property real fs: pl.api ? pl.api.get("size", 17) : 17
                                        width: ld.on ? chars.implicitWidth : base.implicitWidth
                                        height: base.implicitHeight
                                        Text {
                                            id: base
                                            visible: !ld.on
                                            text: wd.w; color: Theme.fg
                                            font.family: Theme.fontUi; font.pixelSize: wd.fs; font.weight: Font.Bold
                                        }
                                        Row {
                                            id: chars
                                            visible: ld.on
                                            Repeater {
                                                model: ld.on ? wd.w.length : 0
                                                Text {
                                                    required property int index
                                                    readonly property real step: Math.max(0.03, (wd.we - wd.ws) / Math.max(1, wd.w.length))
                                                    // soft wipe over ~3.5 letters; eased so the edge has no visible step. Nothing moves:
                                                    // letters never scale or shift, the line stays perfectly readable.
                                                    readonly property real p: Math.max(0, Math.min(1, (pl.ft - (wd.ws + index * step)) / (step * 3.5)))
                                                    readonly property real e: p * p * (3 - 2 * p)
                                                    text: wd.w.charAt(index)
                                                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.4 + 0.6 * e)
                                                    font.family: Theme.fontUi; font.pixelSize: wd.fs; font.weight: Font.Bold
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { fl.userScroll = false; pl.api.seek(Math.max(0, ld.t0 - pl.api.get("offset", 0))); } }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: nowLine
        Text {
            id: nlText
            visible: pl.api && pl.api.get("now", true) && pl.cur >= 0
            width: parent ? parent.width : 400
            text: pl.cur >= 0 ? pl.lines[pl.cur].text : ""
            wrapMode: Text.WordWrap; maximumLineCount: 2
            color: Theme.a(Theme.fg, 0.85); font.family: Theme.fontUi; font.pixelSize: 18; font.weight: Font.DemiBold
            topPadding: 10
            transform: Translate { id: nlT }
            onTextChanged: nlAnim.restart()
            ParallelAnimation {
                id: nlAnim
                NumberAnimation { target: nlT; property: "y"; from: 12; to: 0; duration: Theme.dur(420); easing.type: Easing.OutCubic }
                NumberAnimation { target: nlText; property: "opacity"; from: 0; to: 1; duration: Theme.dur(320) }
            }
        }
    }
}
