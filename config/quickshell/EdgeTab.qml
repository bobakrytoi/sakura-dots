// sakura mono - the edge drum: a hidden tab on the left edge of the main monitor.
// Normally only a hair-thin line shows. Hover that spot of the edge and a half circle
// of glass flows out of the edge, its rims melting back into the edge with concave ears (like the corner island),
// tinted with the wallpaper's color there. It is a revolver drum: the active item sits big in the middle with its
// name, the neighbours ride the arc above and below, smaller and faded. The wheel turns it (spring, a soft click,
// endless loop), left click opens the active item. Every time it opens it starts at the first item.
// Items with a panel (ambient sounds, pocket) open a glass card beside the drum. While you type into the pocket
// the drum takes the keyboard (OnDemand) and stays open; Esc or a click elsewhere closes it.
//
// Add an item: one more entry in `items` -
//   { id, icon (Nerd Font glyph), label (English, Cfg.tr'd), action: () => …    ← does something and closes
//     panel: Component                                                          ← or opens a card beside the drum
//     badge: () => bool                                                         ← optional small dot (something runs)
//     keys: true                                                                ← its panel needs the keyboard }
// qs ipc call edgetab open | close | select <id> - for key binds / testing
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: et
    required property var sketch
    required property var notes

    Ambient { id: ambient }
    Pocket { id: pocketStore }
    Component { id: ambientPanel; AmbientPanel { amb: ambient } }
    Component { id: pocketPanel; PocketPanel { pocket: pocketStore; tab: et } }

    readonly property var items: [
        { id: "sketch",  icon: "", label: "Sketch pad",     action: () => { et.sketch.shown = true; } },
        { id: "notes",   icon: "", label: "Notes",          action: () => { et.notes.shown = true; } },
        { id: "ambient", icon: "", label: "Ambient sounds", panel: ambientPanel, badge: () => ambient.playing },
        { id: "pocket",  icon: "", label: "Pocket",         panel: pocketPanel,  badge: () => pocketStore.items.length > 0, keys: true }
    ]
    readonly property int n: items.length

    readonly property color cFg: "#eceef4"
    readonly property color cMuted: "#8a8fa3"
    readonly property string fIcon: "Symbols Nerd Font"

    // ── geometry ──
    readonly property int rad: 128          // the half circle
    readonly property int ear: 30           // concave ears into the edge
    readonly property real earA: 0.46       // where an ear meets the circle (rad from straight up/down)
    readonly property int gap: 14           // drum → card
    readonly property int cardW: 330

    // ── state ──
    property bool open: false
    property bool cardOpen: false
    property string cardId: ""
    property bool typing: false             // the pocket's field has the keyboard
    property int idx: 0                     // target slot (unbounded, so the spring always turns the short way)
    property real pos: 0                    // where the drum is right now
    property bool snap: false
    Behavior on pos { enabled: !et.snap; SpringAnimation { spring: 3.4; damping: 0.26; epsilon: 0.002 } }
    readonly property int active: ((idx % n) + n) % n
    onIdxChanged: { pos = idx; if (!snap) tick(); }
    onActiveChanged: if (cardOpen) { if (items[active].panel) cardId = items[active].id; else cardOpen = false; }

    readonly property bool anyShown: sketch.shown || notes.shown
    onAnyShownChanged: if (anyShown) close()

    readonly property var cardItem: cardOpen ? items.find(i => i.id === cardId) || null : null

    function openDrum() {
        hideT.stop();
        if (open) return;
        snap = true; idx = 0; pos = 0; snap = false;     // always from the first item
        cardOpen = false;
        open = true;
    }
    function close() { open = false; cardOpen = false; typing = false; }
    function goTo(i) { let d = ((i - active) % n + n) % n; if (d > n / 2) d -= n; idx += d; }
    // wheel (mouse: 120 a notch; touchpads send small steps, they add up)
    property real wheelAcc: 0
    function wheel(w) {
        wheelAcc += w.angleDelta.y;
        while (Math.abs(wheelAcc) >= 120) { const s = wheelAcc > 0 ? -1 : 1; idx += s; wheelAcc += 120 * s; }
    }
    function activate(i) {
        const m = items[i];
        if (i !== active) { goTo(i); return; }
        if (m.panel) {
            if (cardOpen && cardId === m.id) cardOpen = false;
            else { cardId = m.id; cardOpen = true; }
        } else if (m.action) { close(); m.action(); }
    }
    function select(id) {
        const i = items.findIndex(x => x.id === id);
        if (i < 0) return;
        openDrum(); goTo(i);
        if (items[i].panel) { cardId = id; cardOpen = true; }
    }

    // the soft click of the drum (the shell's own click sound; off with the system sounds)
    property real lastTick: 0
    function tick() {
        const now = Date.now();
        if (now - lastTick < 45) return;
        lastTick = now;
        Quickshell.execDetached(["sh", "-c", "[ -e \"$HOME/.config/sakura/sounds-off\" ] || exec pw-play --volume 0.32 \"$HOME/.local/share/sounds/sakura/pw-click.wav\""]);
    }

    readonly property bool hot: rootHover.containsMouse || typing
    onHotChanged: if (hot) hideT.stop(); else if (open) hideT.restart();
    Timer { id: hideT; interval: 550; onTriggered: if (!et.hot) et.close() }

    IpcHandler {
        target: "edgetab"
        function open(): void { et.openDrum(); }
        function close(): void { et.close(); }
        function select(id: string): void { et.select(id); }
        function sound(id: string): void { ambient.toggle(id); }                   // toggle one ambient sound
        function soundsOff(): void { ambient.stopAll(); }
        function soundVol(id: string, d: int): void { ambient.nudge(id, d); }     // ± volume of one sound
        function pocketAdd(s: string): void { pocketStore.addText(s); }           // a text into the pocket
    }

    PanelWindow {
        id: win
        screen: Cfg.mainScreen
        anchors.left: true                          // only the left edge: vertically centred
        implicitWidth: et.rad + 30 + et.gap + et.cardW + 20
        implicitHeight: 470
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "edge-tab"
        WlrLayershell.keyboardFocus: et.cardItem && et.cardItem.keys ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        visible: !et.anyShown
        // closed: only the strip at the very edge takes the mouse; open: the drum (+ the card)
        mask: Region {
            item: et.open || win.p > 0.05 ? drumBox : strip
            Region { item: card.shown ? card : null }
        }

        readonly property real cy: height / 2
        // how far out the drum is: springs out (a little wobble past 1 = the liquid feel), slides back in
        property real p: et.open ? 1 : 0
        Behavior on p { SpringAnimation { spring: et.open ? 3.0 : 5.0; damping: et.open ? 0.3 : 0.6; epsilon: 0.004 } }
        readonly property real pp: Math.max(0, p)
        readonly property real r: et.rad * pp

        // ── the wallpaper's color at this spot of the edge (16 x 9 copy, left middle pixel) ──
        property color tone: Cfg.accent
        property bool toneOk: false
        readonly property string wall: Cfg.data.wallpaper || ""
        onWallChanged: toneProc.running = true
        Process {
            id: toneProc
            running: true
            command: ["sh", "-c", "f=$(\"$0\" \"$1\" 320) && magick \"$f\" -resize '16x9!' -format '%[hex:p{1,4}]' info:",
                      Quickshell.env("HOME") + "/.config/hypr/scripts/wallthumb.sh", win.wall]
            stdout: StdioCollector { onStreamFinished: {
                const h = this.text.trim();
                if (/^[0-9a-fA-F]{6}/.test(h)) { win.tone = "#" + h.slice(0, 6); win.toneOk = true; } else win.toneOk = false;
            } }
        }
        function tinted(t, a) {
            const c = toneOk ? tone : Cfg.accent, k = toneOk ? t : t * 0.5;
            return Qt.rgba((15 / 255) * (1 - k) + c.r * k, (17 / 255) * (1 - k) + c.g * k, (25 / 255) * (1 - k) + c.b * k, a);
        }

        // one hover area over everything (an ancestor of all buttons, so it stays "hovered" over them too;
        // HoverHandlers never saw the pointer on this layer surface). Closed, only the strip is in the mask.
        MouseArea {
            id: rootHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onContainsMouseChanged: if (containsMouse) et.openDrum()

            // ── closed: the thin line (+ a breathing dot while ambient sounds play) ──
            Item {
                id: strip
                x: 0; y: win.cy - 70; width: 5; height: 140
            }
            Rectangle {
                x: 0; y: win.cy - height / 2
                width: 3; height: 56; radius: 2
                color: Cfg.accent; opacity: 0.55 * Math.max(0, 1 - win.pp * 4)
            }
            Rectangle {
                x: 0; y: win.cy + 28 + 7
                width: 5; height: 5; radius: 2.5
                color: Cfg.accent
                visible: ambient.playing && win.pp < 0.25
                SequentialAnimation on opacity {
                    running: ambient.playing; loops: Animation.Infinite
                    NumberAnimation { from: 0.95; to: 0.3; duration: 1300; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.3; to: 0.95; duration: 1300; easing.type: Easing.InOutSine }
                }
            }

            // ── the drum's glass: half circle + concave ears into the edge ──
            Canvas {
                id: shape
                anchors.fill: parent
                readonly property string key: [width, height, win.r, Cfg.glassAlpha, win.tone, win.toneOk, Cfg.accent].join(",")
                onKeyChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const r = win.r;
                    if (r < 12) return;
                    const cy = win.cy, a = et.earA, e = et.ear * Math.min(1, win.pp * 1.3), L = e * 0.72;
                    const sa = Math.sin(a), ca = Math.cos(a);
                    const p1x = r * sa, p1y = cy - r * ca, p2y = cy + r * ca;
                    const outline = () => {
                        ctx.moveTo(0, p1y - e);
                        ctx.bezierCurveTo(0, p1y - e + e * 0.62, p1x - ca * L, p1y - sa * L, p1x, p1y);       // top ear
                        ctx.arc(0, cy, r, -(Math.PI / 2 - a), Math.PI / 2 - a, false);                         // the drum
                        ctx.bezierCurveTo(p1x - ca * L, p2y + sa * L, 0, p2y + e - e * 0.62, 0, p2y + e);     // bottom ear
                    };
                    // glass, a touch lighter toward the middle
                    ctx.beginPath(); outline(); ctx.closePath();
                    const g = ctx.createRadialGradient(r * 0.35, cy, r * 0.1, 0, cy, r + e);
                    g.addColorStop(0, win.tinted(0.16, Math.min(0.97, Cfg.glassAlpha + 0.12)));
                    g.addColorStop(1, win.tinted(0.08, Math.max(0.8, Cfg.glassAlpha)));
                    ctx.fillStyle = g;
                    ctx.fill();
                    // a thin rim on the round side only
                    ctx.beginPath(); outline();
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = "rgba(255,255,255,0.10)";
                    ctx.stroke();
                    // the slot the active item sits in: a soft accent arc on the inside
                    ctx.beginPath();
                    ctx.arc(0, cy, r - 7, -0.32, 0.32, false);
                    ctx.lineWidth = 2.5; ctx.lineCap = "round";
                    ctx.strokeStyle = Qt.rgba(Cfg.accent.r, Cfg.accent.g, Cfg.accent.b, 0.55 * win.pp);
                    ctx.stroke();
                }
            }

            // the drum's area (hover, wheel, click)
            Item {
                id: drumBox
                x: 0; y: win.cy - et.rad - et.ear
                width: Math.max(5, win.r + 2); height: 2 * (et.rad + et.ear)
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onWheel: w => et.wheel(w)
                    onClicked: et.activate(et.active)
                }
            }

            // ── the items on the drum ──
            Repeater {
                model: et.items
                Item {
                    id: slot
                    required property var modelData
                    required property int index
                    // offset from the middle in slots, wrapped into [-n/2, n/2)
                    readonly property real d: { let x = ((index - et.pos) % et.n + et.n) % et.n; if (x >= et.n / 2) x -= et.n; return x; }
                    readonly property real ad: Math.abs(d)
                    readonly property real th: d * 0.84
                    readonly property real ra: et.rad * 0.54 * win.pp
                    readonly property bool mid: ad < 0.5
                    readonly property bool busy: modelData.badge ? modelData.badge() : false
                    width: 52; height: 52
                    x: ra * Math.cos(th) - width / 2 + 4
                    y: win.cy + ra * 1.12 * Math.sin(th) - height / 2 - 8 * Math.max(0, 1 - ad)
                    z: 10 - ad
                    scale: Math.max(0.3, 1 - 0.44 * ad) * (0.55 + 0.45 * win.pp)
                    opacity: win.pp * Math.max(0, 1 - ad * 0.56)
                    visible: opacity > 0.01

                    Text {
                        anchors.centerIn: parent
                        text: slot.modelData.icon; font.family: et.fIcon; font.pixelSize: 30
                        color: slot.mid || sa.containsMouse ? Cfg.accent : et.cFg
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                    // something runs (ambient plays / pocket has things)
                    Rectangle {
                        visible: slot.busy
                        x: parent.width - 12; y: 6; width: 8; height: 8; radius: 4
                        color: Cfg.accent; border.width: 1.5; border.color: win.tinted(0.1, 1)
                        SequentialAnimation on scale {
                            running: slot.busy && slot.modelData.id === "ambient"; loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.7; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.7; to: 1; duration: 900; easing.type: Easing.InOutSine }
                        }
                    }
                    MouseArea {
                        id: sa
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: et.activate(slot.index)
                        onWheel: w => et.wheel(w)
                    }
                }
            }
            // the active item's name, under its icon (fades while the drum turns)
            Text {
                readonly property int near: ((Math.round(et.pos) % et.n) + et.n) % et.n
                readonly property real off: Math.abs(et.pos - Math.round(et.pos))
                text: Cfg.tr(et.items[near].label)
                // stays inside the drum: at most ~0.7 of the radius wide, two lines if it must
                width: et.rad * 0.72
                x: et.rad * 0.54 * win.pp + 4 - width / 2; y: win.cy + 15
                wrapMode: Text.WordWrap; maximumLineCount: 2; lineHeight: 0.9
                elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                color: et.cFg; font.family: Cfg.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold
                opacity: win.pp * Math.max(0, 1 - off * 4)
                visible: opacity > 0.01
            }

            // ── the card beside the drum ──
            Item {
                id: card
                property real cp: et.cardItem ? 1 : 0
                Behavior on cp { NumberAnimation { duration: 260 * Cfg.anim; easing.type: Easing.OutCubic } }
                readonly property bool shown: cp > 0.01 && et.open
                visible: shown
                x: win.r + et.gap - 18 * (1 - cp)
                y: Math.round(win.cy - height / 2)
                width: loader.item ? loader.item.implicitWidth : 0
                height: loader.item ? loader.item.implicitHeight : 0
                opacity: cp
                scale: 0.94 + 0.06 * cp
                transformOrigin: Item.Left

                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    color: win.tinted(0.10, Math.max(0.82, Cfg.glassAlpha))
                    border.width: 1; border.color: "#1fffffff"
                }
                Loader {
                    id: loader
                    // keep the last panel while the card fades out
                    property var last: null
                    sourceComponent: et.cardItem ? et.cardItem.panel : last
                    onLoaded: last = sourceComponent
                }
            }
        }
    }
}
