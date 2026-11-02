// sakura mono — volume mixer (click the volume on the top bar): output device, master volume, per-app volume
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import QtQuick

Scope {
    id: mx

    readonly property color cBg:     "#f20f1119"
    readonly property color cCard:   "#1a1d28"
    readonly property color cCard2:  "#22263a"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: "#f2b8d0"
    readonly property color cAccFg:  "#1a121a"
    readonly property string fUi:    "Inter"
    readonly property string fIcon:  "Symbols Nerd Font"

    property bool shown: false
    property bool pickOut: false
    property var screen0: Quickshell.screens[0]
    function toggle() {
        if (!shown) {
            const m = Hyprland.focusedMonitor;
            const sc = m ? Quickshell.screens.find(s => s.name === m.name) : null;
            if (sc) screen0 = sc;
            pickOut = false;
        }
        shown = !shown;
    }
    IpcHandler { target: "mixer"; function toggle(): void { mx.toggle(); } }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    // apps that are playing sound right now
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream)
    readonly property var apps: streams.filter(n => ((n.properties || {})["media.class"] || "") === "Stream/Output/Audio")
    PwObjectTracker { objects: [ mx.sink ].concat(mx.streams).concat(mx.sinks) }

    function nodeName(n) { return n.description || n.nickname || n.name; }
    function appEntry(n) {
        const p = n.properties || {};
        const bin = (p["application.process.binary"] || "").toLowerCase().replace(/\.(bin|exe)$/, "");
        return bin ? DesktopEntries.heuristicLookup(bin) : null;
    }
    function appName(n) {
        const e = appEntry(n); if (e) return e.name;
        const p = n.properties || {};
        return p["application.name"] || p["media.name"] || n.name || "App";
    }
    function appSub(n) {
        const p = n.properties || {}; const m = p["media.name"] || "";
        // hide technical stream names ("Playback", "playStream", "audio stream #1"...)
        if (!m || m === appName(n) || /^(playback|playstream|audio[ _-]?stream.*|output|sink.*|alsa.*)$/i.test(m)) return "";
        return m;
    }
    function appIcon(n) {
        const e = appEntry(n); if (e && e.icon) return Quickshell.iconPath(e.icon, true) || "";
        const p = n.properties || {};
        const cand = [p["application.icon-name"], (p["application.process.binary"] || "").toLowerCase(), (p["application.name"] || "").toLowerCase()];
        for (const c of cand) if (c) return Quickshell.iconPath(c, true) || "";
        return "";
    }

    component VolRow: Item {
        id: vr
        property var node: null
        property string title: ""
        property string sub: ""
        property string icon: ""        // image path
        property string glyph: ""       // fallback glyph
        property bool big: false
        width: parent ? parent.width : 0; height: big ? 64 : 56
        readonly property real vol: node && node.audio ? node.audio.volume : 0
        readonly property bool muted: node && node.audio ? node.audio.muted : false
        Rectangle { anchors.fill: parent; radius: 16; color: vr.big ? mx.cCard2 : mx.cCard }
        Item {
            id: ic
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            width: 32; height: 32
            IconImage { anchors.fill: parent; source: vr.icon; visible: vr.icon !== "" }
            Text { anchors.centerIn: parent; visible: vr.icon === ""; text: vr.glyph; font.family: mx.fIcon; font.pixelSize: 18; color: mx.cAccent }
            opacity: vr.muted ? 0.4 : 1
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (vr.node && vr.node.audio) vr.node.audio.muted = !vr.node.audio.muted }
        }
        Column {
            anchors { left: ic.right; leftMargin: 12; right: pct.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 6
            Row {
                width: parent.width; spacing: 6
                Text { text: vr.title; color: mx.cFg; font.family: mx.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight; width: Math.min(implicitWidth, parent.width * 0.6) }
                Text { text: vr.sub; color: mx.cMuted; font.family: mx.fUi; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width * 0.4 - 6; anchors.verticalCenter: parent.verticalCenter }
            }
            Item {
                width: parent.width; height: 14
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: "#2a2e40" }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * Math.min(1, vr.vol); height: 6; radius: 3
                    color: vr.muted ? "#55f2b8d0" : mx.cAccent; Behavior on width { NumberAnimation { duration: 90 } } }
                Rectangle { x: parent.width * Math.min(1, vr.vol) - 7; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7; color: "#ffffff" }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                    function set(x) { if (vr.node && vr.node.audio) { vr.node.audio.volume = Math.round(Math.max(0, Math.min(1, x / width)) * 100) / 100; if (vr.node.audio.muted) vr.node.audio.muted = false; } }
                    onPressed: m => set(m.x)
                    onPositionChanged: m => { if (pressed) set(m.x); }
                    onWheel: w => set(width * (vr.vol + (w.angleDelta.y > 0 ? 0.05 : -0.05)))
                }
            }
        }
        Text { id: pct; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: 40; horizontalAlignment: Text.AlignRight
            text: vr.muted ? "mute" : Math.round(vr.vol * 100) + "%"; color: vr.muted ? mx.cMuted : mx.cFg
            font.family: mx.fUi; font.pixelSize: 12; font.weight: Font.DemiBold }
    }

    PanelWindow {
        id: win
        visible: mx.shown
        screen: mx.screen0
        anchors { top: true; right: true }
        margins { top: 54; right: 14 }
        implicitWidth: 400
        implicitHeight: Math.min(640, col.implicitHeight + 32)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "mixer"
        HyprlandFocusGrab { windows: [ win ]; active: mx.shown; onCleared: mx.shown = false }

        Rectangle {
            anchors.fill: parent
            radius: 24; color: mx.cBg; border.width: 1; border.color: mx.cBorder
            opacity: mx.shown ? 1 : 0
            transform: Translate { y: mx.shown ? 0 : -10; Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Flickable {
                anchors { fill: parent; margins: 16 }
                contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: col
                    width: parent.width; spacing: 8

                    Row { spacing: 8
                        Text { text: ""; font.family: mx.fIcon; font.pixelSize: 14; color: mx.cAccent; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Sound"; font.family: mx.fUi; font.pixelSize: 16; font.weight: Font.Bold; color: mx.cFg } }

                    // output device (click to change)
                    Rectangle {
                        width: parent.width; height: 40; radius: 12; color: oma.containsMouse ? mx.cCard2 : mx.cCard
                        Text { anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } text: ""; font.family: mx.fIcon; font.pixelSize: 13; color: mx.cAccent }
                        Text { anchors { left: parent.left; leftMargin: 40; right: parent.right; rightMargin: 34; verticalCenter: parent.verticalCenter }
                            text: mx.sink ? mx.nodeName(mx.sink) : "No output"; elide: Text.ElideRight; color: mx.cFg; font.family: mx.fUi; font.pixelSize: 13 }
                        Text { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } text: mx.pickOut ? "" : ""; font.family: mx.fIcon; font.pixelSize: 11; color: mx.cMuted }
                        MouseArea { id: oma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mx.pickOut = !mx.pickOut }
                    }
                    Column {
                        width: parent.width; spacing: 4; visible: mx.pickOut
                        Repeater { model: mx.sinks
                            delegate: Rectangle { required property var modelData
                                readonly property bool sel: mx.sink && modelData.id === mx.sink.id
                                width: parent.width; height: 36; radius: 10; color: sel ? "#26f2b8d0" : (sa.containsMouse ? mx.cCard2 : "transparent")
                                Text { anchors { left: parent.left; leftMargin: 40; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: mx.nodeName(modelData); elide: Text.ElideRight; font.family: mx.fUi; font.pixelSize: 12; color: sel ? mx.cAccent : mx.cFg }
                                MouseArea { id: sa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { Pipewire.preferredDefaultAudioSink = modelData; mx.pickOut = false; } } } }
                    }

                    VolRow { node: mx.sink; title: "Master"; sub: ""; glyph: ""; big: true }

                    Text { text: mx.apps.length ? "Apps" : "No apps are playing sound"; topPadding: 6
                        font.family: mx.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: mx.apps.length ? mx.cAccent : mx.cMuted }
                    Repeater {
                        model: mx.apps
                        delegate: VolRow { required property var modelData
                            node: modelData; title: mx.appName(modelData); sub: mx.appSub(modelData); icon: mx.appIcon(modelData); glyph: "" }
                    }

                    Rectangle {
                        width: parent.width; height: 36; radius: 12; color: ama.containsMouse ? mx.cCard2 : "transparent"
                        Text { anchors.centerIn: parent; text: "Sound settings"; font.family: mx.fUi; font.pixelSize: 12; color: mx.cMuted }
                        MouseArea { id: ama; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { mx.shown = false; Quickshell.execDetached(["qs", "ipc", "call", "settings", "open", "sound"]); } }
                    }
                }
            }
        }
    }
}
