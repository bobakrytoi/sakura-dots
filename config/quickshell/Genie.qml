// sakura mono - minimize / restore: the window flies into the top bar's notch, which swallows it (a little gulp),
// and is spat back out of it when it comes back.
// minimize.sh calls "qs ipc call genie eat|spit ADDR X Y W H" (the window's rectangle, screen coordinates); this
// plays the flight and does the real move at the right moment ("minimize.sh hide-now" / "restore-now").
// The picture taken on the way in is kept and flies back out on restore; without one (minimized before a shell
// restart) a glass card flies instead. With the bar at the bottom (barpos.sh) the mouth is the bottom middle.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

Scope {
    id: gn
    property var topBar: null
    readonly property string sc: Quickshell.env("HOME") + "/.config/hypr/scripts/minimize.sh"
    readonly property int dur: Math.round(430 * Cfg.anim)
    property var shots: ({})           // address → grabbed picture of the window, kept while it is minimized

    function norm(a) { return String(a).replace(/^0x/, "").toLowerCase(); }
    function toplevelOf(addr) {
        const n = norm(addr), t = Hyprland.toplevels.values.find(x => norm(x.address) === n);
        return t ? t.wayland : null;
    }
    function screenAt(x, y) {
        return Quickshell.screens.find(s => x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) || Quickshell.screens[0];
    }
    function overlayOn(s) { return overlays.instances.find(o => o.modelData.name === s.name) || null; }
    // where the bar swallows, in that screen's coordinates
    function mouth(s) {
        const bottom = !!topBar && topBar.barBottom && s.name === Cfg.mainName;
        const g = topBar && !bottom ? topBar.geoFor(s.name) : null;
        if (!g) return Qt.rect(s.width / 2 - 22, bottom ? s.height - 26 : 8, 44, 14);
        return Qt.rect((g.x0 + g.x1) / 2 - 22, g.d - 18, 44, 14);
    }
    function gulp(s) { if (topBar && topBar.gulp) topBar.gulp(s.name); }
    // a click on a minimized window (dock, bar, previews): spit it out instead of activating it - activating it
    // makes Hyprland flash the hidden workspace first. false for a normal window (then the caller activates it).
    function bringBack(toplevel) {
        const h = Hyprland.toplevels.values.find(x => x.wayland === toplevel);
        if (!h) return false;
        const ipc = h.lastIpcObject || {};
        const ws = (h.workspace && h.workspace.name) || (ipc.workspace && ipc.workspace.name) || "";
        if (ws !== "special:minimized") return false;
        Quickshell.execDetached([sc, "restore-addr", "0x" + norm(h.address)]);
        return true;
    }
    function run(cmd, addr) { Quickshell.execDetached([gn.sc, cmd, addr]); }

    IpcHandler {
        target: "genie"
        function eat(addr: string, x: int, y: int, w: int, h: int): void { gn.eat(addr, x, y, w, h); }
        function spit(addr: string, x: int, y: int, w: int, h: int): void { gn.spit(addr, x, y, w, h); }    }

    function eat(addr, x, y, w, h) {
        const s = screenAt(x + w / 2, y + h / 2), ov = overlayOn(s), cap = toplevelOf(addr);
        if (!ov || !cap) { run("hide-now", addr); gulp(s); return; }
        flyer.createObject(ov.stage, { eat: true, addr: norm(addr), screen: s, cap: cap,
            from: Qt.rect(x - s.x, y - s.y, w, h), to: mouth(s) });
    }
    function spit(addr, x, y, w, h) {
        const s = screenAt(x + w / 2, y + h / 2), ov = overlayOn(s), n = norm(addr);
        if (!ov) { run("restore-now", addr); return; }
        const shot = shots[n];
        flyer.createObject(ov.stage, { eat: false, addr: n, screen: s, pic: shot ? shot.url : "",
            from: mouth(s), to: Qt.rect(x - s.x, y - s.y, w, h) });
    }

    // one flight: a picture of the window moving between its place and the bar's mouth
    Component {
        id: flyer
        Item {
            id: fl
            property bool eat: true
            property string addr: ""
            property var screen
            property var cap: null            // eat: the window, captured once
            property string pic: ""           // spit: the picture taken on the way in
            property rect from
            property rect to
            property real t: 0
            property bool started: false
            property bool handed: false       // the real window has been moved (hidden / brought back)

            // eat: speeds up into the mouth and thins out sideways faster than it shrinks down (a bit like a genie);
            // spit: shoots out and overshoots a little
            readonly property real tx: t
            readonly property real ty: eat ? Math.pow(t, 1.4) : t
            x: from.x + (to.x - from.x) * tx
            y: from.y + (to.y - from.y) * ty
            width: from.width + (to.width - from.width) * tx
            height: from.height + (to.height - from.height) * ty
            opacity: eat ? (t < 0.75 ? 1 : 1 - (t - 0.75) / 0.25) : Math.min(1, t * 5)

            Component.onCompleted: { gn.overlayOn(screen).busy++; if (!eat) { gn.gulp(screen); startT.start(); } else waitT.start(); }
            Component.onDestruction: { const o = gn.overlayOn(screen); if (o) o.busy--; }

            ClippingRectangle {
                anchors.fill: parent
                radius: 14
                color: fl.eat || fl.pic !== "" ? "transparent" : Cfg.glass
                border.width: fl.eat || fl.pic !== "" ? 0 : 1; border.color: "#1fffffff"
                ScreencopyView {
                    id: shot
                    anchors.fill: parent
                    visible: fl.eat
                    captureSource: fl.eat ? fl.cap : null
                    live: false
                }
                Image { anchors.fill: parent; visible: !fl.eat && fl.pic !== ""; source: fl.pic; smooth: true }
            }

            // eat: wait for the picture (a few frames at most), keep a copy for the way back, then go
            Timer {
                id: waitT; interval: 16; repeat: true
                property int tries: 0
                onTriggered: {
                    tries++;
                    if (!shot.hasContent && tries < 12) return;
                    stop();
                    if (shot.hasContent) shot.grabToImage(r => { const m = Object.assign({}, gn.shots); m[fl.addr] = r; gn.shots = m; });
                    gn.run("hide-now", fl.addr);
                    fl.handed = true;
                    anim.start();
                }
            }
            // spit: let the mouth open first
            Timer { id: startT; interval: 110; onTriggered: anim.start() }

            NumberAnimation {
                id: anim
                target: fl; property: "t"; from: 0; to: 1
                duration: gn.dur
                easing.type: fl.eat ? Easing.InQuad : Easing.OutBack
                easing.overshoot: 1.1
                onFinished: {
                    if (fl.eat) { gn.gulp(fl.screen); fl.destroy(); return; }
                    const m = Object.assign({}, gn.shots); delete m[fl.addr]; gn.shots = m;
                    endT.start();
                }
            }
            // spit: the real window comes back as the picture lands, then the picture goes
            onTChanged: if (!eat && !handed && t > 0.82) { handed = true; gn.run("restore-now", addr); }
            Timer { id: endT; interval: 140; onTriggered: fl.destroy() }
        }
    }

    // a see-through layer over each screen, up only while something flies on it
    Variants {
        id: overlays
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            property int busy: 0
            property alias stage: stageItem
            screen: modelData
            visible: busy > 0
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "genie"
            mask: Region {}
            Item { id: stageItem; anchors.fill: parent }
        }
    }
}
