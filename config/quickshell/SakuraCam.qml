// sakura mono - Sakura Cam panel: the iPhone as a webcam. Flows out of the top bar's notch (DropPanel.qml).
//  · no phone yet: a QR code (scan with the iPhone camera → setup page → camera page) + Wi-Fi / USB choice
//  · phone connected: the live picture (click = focus there, wheel = zoom), lenses, on/off, torch, mic, mirror
// Backend: CamLink.qml (singleton) → hypr/scripts/sakura-cam/server.py. While the camera streams the notch shows a
// live activity "cam" (Notch.qml); a click on it opens this. IPC: qs ipc call cam toggle|open|close|state
import Quickshell
import Quickshell.Io
import QtQuick
import QtMultimedia

Scope {
    id: sc
    property var topBar: null
    property bool shown: false
    property var screen0: Quickshell.screens[0]
    property real anchorX: -1
    readonly property string covering: drop.covering

    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cCard:   "#14ffffff"
    readonly property color cHover:  "#29ffffff"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"
    function t(s) { return Cfg.tr(s); }

    function toggleAt(screenName, x) {
        if (shown) { shown = false; return; }
        if (drop.justClosed()) return;
        const s = Quickshell.screens.find(q => q.name === screenName);
        if (s) screen0 = s;
        anchorX = x; shown = true;
    }
    function open() {
        const n = Notch.focusedScreen(), s = Quickshell.screens.find(q => q.name === n);
        if (s) screen0 = s;
        anchorX = -1; shown = true;
    }
    IpcHandler {
        target: "cam"
        function toggle(): string { return CamLink.toggle(); }
        function open(): void { sc.open(); }
        function close(): void { sc.shown = false; }
        function panel(): void { if (sc.shown) sc.shown = false; else sc.open(); }
        function state(): string {
            return CamLink.up ? (CamLink.connected ? (CamLink.streaming ? "streaming " + CamLink.resText : "connected, paused") : "waiting for the phone")
                                + " · device " + (CamLink.device || "missing") : "service down";
        }
    }

    component Round: Rectangle {
        id: rb
        property string glyph: ""
        property string tip: ""
        property bool on: false
        property bool dim: false
        signal clicked()
        width: 44; height: 44; radius: 22
        opacity: dim ? 0.35 : 1
        color: on ? Cfg.acc(0.24) : (ra.containsMouse ? sc.cHover : sc.cCard)
        scale: ra.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: rb.glyph; font.family: sc.fIcon; font.pixelSize: 17; color: rb.on ? sc.cAccent : sc.cFg }
        MouseArea { id: ra; anchors.fill: parent; hoverEnabled: true; enabled: !rb.dim; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }

    readonly property bool live: CamLink.connected
    readonly property int boxW: live ? 640 : 560
    readonly property int boxH: live ? 472 : 262

    DropPanel {
        id: drop
        topBar: sc.topBar
        shown: sc.shown
        onCloseRequested: sc.shown = false
        screen0: sc.screen0
        anchorX: sc.anchorX
        boxW: sc.boxW
        boxH: sc.boxH
        ns: "sakuracam"

        // ── no phone: QR + how to connect ───────────────────────
        Item {
            id: pair
            anchors { fill: parent; margins: 18 }
            visible: !sc.live
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 * Cfg.anim } }

            Rectangle {
                id: qrCard
                width: 226; height: 226; radius: 20
                color: "#eceef4"          // dark modules on a light tile: every phone camera reads that
                Image {
                    id: qr
                    anchors { fill: parent; margins: 18 }
                    source: sc.shown && CamLink.up ? CamLink.qrUrl() : ""
                    sourceSize: Qt.size(372, 372)
                    smooth: false; cache: false; asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 260 } }
                }
                // service down / loading
                Text {
                    anchors.centerIn: parent; visible: qr.status !== Image.Ready
                    text: "\u{F0567}"; font.family: sc.fIcon; font.pixelSize: 40; color: sc.cMuted
                }
            }
            Column {
                anchors { left: qrCard.right; leftMargin: 22; right: parent.right; verticalCenter: qrCard.verticalCenter }
                spacing: 10
                Row {
                    spacing: 9
                    Rectangle { width: 9; height: 9; radius: 5; anchors.verticalCenter: parent.verticalCenter
                        color: CamLink.up ? sc.cAccent : "#ff8b9a"
                        SequentialAnimation on opacity { running: CamLink.up; loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine } } }
                    Text { text: "Sakura Cam"; color: sc.cFg; font.family: sc.fUi; font.pixelSize: 22; font.weight: Font.ExtraBold }
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; color: sc.cMuted; font.family: sc.fUi; font.pixelSize: 13
                    text: !CamLink.up ? sc.t("The camera service is not running.")
                          : sc.t("Scan with the iPhone camera. The first time it walks you through a one-time setup.")
                }
                // how the phone reaches the PC
                Row {
                    spacing: 6
                    visible: CamLink.up
                    Repeater {
                        model: [{ v: "auto", t: "Auto", ok: true }, { v: "wifi", t: "Wi-Fi", ok: CamLink.hasWifi }, { v: "usb", t: "USB", ok: CamLink.hasUsb }]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool sel: CamLink.o.net === modelData.v
                            width: nt.implicitWidth + 26; height: 30; radius: 10
                            opacity: modelData.ok ? 1 : 0.4
                            color: sel ? sc.cAccent : (na.containsMouse ? sc.cHover : sc.cCard)
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Text { id: nt; anchors.centerIn: parent; text: sc.t(modelData.t); color: parent.sel ? sc.cAccFg : sc.cFg
                                   font.family: sc.fUi; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea { id: na; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { CamLink.set("net", modelData.v); CamLink.qrSerial++; } }
                        }
                    }
                }
                Text {
                    width: parent.width; elide: Text.ElideMiddle; color: sc.cMuted; font.family: sc.fUi; font.pixelSize: 11
                    visible: CamLink.up
                    text: {
                        const u = (CamLink.st.urls || {}), n = CamLink.o.net;
                        const url = n === "auto" ? (u.usb || u.wifi || u.lan || "") : (u[n] || (n === "usb" ? sc.t("Turn on Personal Hotspot and plug the iPhone in") : ""));
                        return url;
                    }
                }
                Rectangle {
                    visible: !CamLink.up || CamLink.outError === "missing"
                    width: parent.width; height: warnT.implicitHeight + 16; radius: 12; color: "#1fff8b9a"
                    Text {
                        id: warnT; anchors { fill: parent; margins: 8; leftMargin: 12; rightMargin: 12 }
                        wrapMode: Text.WordWrap; color: "#ffc4cc"; font.family: sc.fUi; font.pixelSize: 11
                        text: !CamLink.up ? sc.t("Start it: systemctl --user start sakura-cam") : sc.t("The virtual camera is not set up yet (v4l2loopback). The picture will not reach apps until it is.")
                    }
                    MouseArea { anchors.fill: parent; enabled: !CamLink.up; cursorShape: Qt.PointingHandCursor; onClicked: CamLink.startService() }
                }
            }
        }

        // ── phone connected: picture + controls ─────────────────
        Item {
            id: liveBox
            anchors { fill: parent; margins: 16 }
            visible: sc.live
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 * Cfg.anim } }

            // the picture: two images take turns (the next frame loads in the hidden one), ~12 fps
            Rectangle {
                id: pic
                width: parent.width; height: Math.round(width * 9 / 16)
                radius: 16; color: "#0b0c12"; clip: true
                // the picture: an mjpeg stream from the server (25 fps) played by QtMultimedia. Not the v4l2 device
                // itself: v4l2loopback lets one reader stream at a time, the panel would lock Discord out.
                MediaPlayer {
                    id: pv
                    videoOutput: vout
                    readonly property bool want: sc.shown && CamLink.streaming
                    function restart() { if (want) { source = CamLink.api + "/preview.mjpeg?t=" + Date.now(); play(); } else { stop(); source = ""; } }
                    onWantChanged: restart()
                    Component.onCompleted: restart()
                    // the server restarted / the stream broke: try again in a moment (the jpeg poll fills in meanwhile)
                    onErrorOccurred: (e, msg) => { pic.fallback = true; pvRetry.restart(); }
                    onMediaStatusChanged: { if (mediaStatus === MediaPlayer.EndOfMedia) { pic.fallback = true; pvRetry.restart(); }
                                            else if (mediaStatus === MediaPlayer.BufferedMedia || mediaStatus === MediaPlayer.LoadedMedia) pic.fallback = false; }
                }
                Timer { id: pvRetry; interval: 1200; onTriggered: pv.restart() }
                property bool fallback: false
                readonly property bool direct: !fallback
                VideoOutput { id: vout; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop; visible: pic.direct && CamLink.streaming }
                property int n: 0
                property bool aFront: true
                Timer { interval: 80; repeat: true; running: !pic.direct && sc.shown && CamLink.streaming
                    onTriggered: { const back = pic.aFront ? imgB : imgA; if (back.status !== Image.Loading) back.source = CamLink.api + "/preview.jpg?n=" + (++pic.n); } }
                Image { id: imgA; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; cache: false; asynchronous: true
                        visible: !pic.direct && pic.aFront && CamLink.streaming; onStatusChanged: if (status === Image.Ready && !pic.aFront) pic.aFront = true }
                Image { id: imgB; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; cache: false; asynchronous: true
                        visible: !pic.direct && !pic.aFront && CamLink.streaming; onStatusChanged: if (status === Image.Ready && pic.aFront) pic.aFront = false }
                // paused / starting
                Column {
                    anchors.centerIn: parent; spacing: 8; visible: !CamLink.streaming
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "\u{F0567}"; font.family: sc.fIcon; font.pixelSize: 34; color: sc.cMuted }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; color: sc.cMuted; font.family: sc.fUi; font.pixelSize: 13
                           text: CamLink.want ? sc.t("Starting the camera…") : sc.t("Paused") }
                }
                // click = focus there (the ring shows where), wheel = zoom
                Rectangle {
                    id: ring
                    width: 54; height: 54; radius: 16; color: "transparent"; border.width: 1.5; border.color: sc.cAccent
                    opacity: 0; scale: 1.4
                    ParallelAnimation { id: ringA
                        NumberAnimation { target: ring; property: "scale"; from: 1.5; to: 1; duration: 260; easing.type: Easing.OutCubic }
                        SequentialAnimation {
                            NumberAnimation { target: ring; property: "opacity"; from: 0; to: 1; duration: 160 }
                            PauseAnimation { duration: 420 }
                            NumberAnimation { target: ring; property: "opacity"; to: 0; duration: 320 } } }
                }
                MouseArea {
                    anchors.fill: parent; enabled: CamLink.streaming; cursorShape: Qt.CrossCursor
                    onClicked: m => { ring.x = m.x - 27; ring.y = m.y - 27; ringA.restart(); CamLink.focus(m.x / width, m.y / height); }
                    onWheel: w => { CamLink.setZoom(CamLink.zoom * (w.angleDelta.y > 0 ? 1.08 : 1 / 1.08)); zoomTip.show(); }
                }
                // zoom readout
                Rectangle {
                    id: zoomTip
                    anchors.centerIn: parent; width: zt.implicitWidth + 26; height: 32; radius: 16; color: "#b30f1119"
                    opacity: 0
                    function show() { opacity = 1; zoomHide.restart(); }
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Timer { id: zoomHide; interval: 700; onTriggered: zoomTip.opacity = 0 }
                    Text { id: zt; anchors.centerIn: parent; text: CamLink.zoom.toFixed(1) + "×"; color: sc.cFg; font.family: sc.fUi; font.pixelSize: 14; font.weight: Font.DemiBold }
                }
                // live badge, top left
                Rectangle {
                    x: 10; y: 10; visible: CamLink.streaming
                    width: lb.implicitWidth + 30; height: 26; radius: 13; color: "#b30f1119"
                    Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 4; color: sc.cAccent }
                    Text { id: lb; x: 22; anchors.verticalCenter: parent.verticalCenter; text: CamLink.resText + (CamLink.st.rtt ? " · " + CamLink.st.rtt + " ms" : "")
                           color: sc.cFg; font.family: sc.fUi; font.pixelSize: 11; font.weight: Font.DemiBold }
                }
                // lenses, bottom middle on the picture
                Rectangle {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                    readonly property var lenses: ["wide", "back", "tele", "front"].filter(k => (CamLink.phone.lenses || ["back", "front"]).indexOf(k) >= 0)
                    visible: lenses.length > 1
                    width: lensRow.implicitWidth + 8; height: 34; radius: 17; color: "#b30f1119"
                    Row {
                        id: lensRow; anchors.centerIn: parent; spacing: 2
                        Repeater {
                            model: parent.parent.lenses
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool sel: (CamLink.phone.cam || CamLink.o.camera) === modelData
                                width: Math.max(30, lt.implicitWidth + 16); height: 26; radius: 13
                                color: sel ? "#ebffffff" : (la.containsMouse ? "#29ffffff" : "transparent")
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Text { id: lt; anchors.centerIn: parent; font.family: modelData === "front" ? sc.fIcon : sc.fUi; font.pixelSize: 11; font.weight: Font.Bold
                                       color: parent.sel ? "#10121a" : sc.cFg
                                       text: ({ wide: "0.5×", back: "1×", tele: "2×", front: "\u{F0004}" })[modelData] }
                                MouseArea { id: la; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: CamLink.camera(modelData) }
                            }
                        }
                    }
                }
            }

            // controls under the picture
            Row {
                id: ctl
                anchors { top: pic.bottom; topMargin: 14; horizontalCenter: parent.horizontalCenter }
                spacing: 10
                Round { glyph: "\u{F0A72}"; tip: "Mirror"; on: !!CamLink.cfg.mirror; onClicked: CamLink.set("mirror", !CamLink.cfg.mirror) }
                Round { glyph: "\u{F0241}"; tip: "Torch"; on: !!CamLink.phone.torchOn; dim: !CamLink.phone.torch; onClicked: CamLink.torch() }
                // on / off: the same look as the phone's big button
                Item {
                    width: 56; height: 56; anchors.verticalCenter: parent.verticalCenter
                    Rectangle { anchors.fill: parent; radius: 28; color: "transparent"; border.width: 2.5
                                border.color: CamLink.want ? Cfg.acc(0.9) : "#d9ffffff"; scale: liveA.pressed ? 0.92 : 1
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } } }
                    Rectangle {
                        anchors.centerIn: parent
                        width: CamLink.want ? 20 : 44; height: width; radius: CamLink.want ? 6 : 22; color: sc.cAccent
                        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                        Behavior on radius { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                    }
                    MouseArea { id: liveA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: CamLink.stream(!CamLink.want) }
                }
                Round { glyph: CamLink.cfg.mic ? "\u{F036C}" : "\u{F036D}"; tip: "Microphone"; on: !!CamLink.cfg.mic; onClicked: CamLink.set("mic", !CamLink.cfg.mic) }
                Round { glyph: "\u{F0493}"; tip: "Settings"; onClicked: { sc.shown = false; Quickshell.execDetached(["sh", "-c", "sleep 0.3; qs ipc call settings open sakuracam"]); } }
            }
            // where the picture goes
            Text {
                anchors { top: ctl.bottom; topMargin: 10; horizontalCenter: parent.horizontalCenter }
                color: CamLink.outError ? "#ffc4cc" : sc.cMuted; font.family: sc.fUi; font.pixelSize: 11
                text: CamLink.device ? "Sakura Cam → " + CamLink.device + (CamLink.cfg.mic ? " · Sakura Mic" : "") + (CamLink.sizePinned ? " · " + CamLink.pinnedNote : "")
                      : sc.t("The virtual camera is not set up yet (v4l2loopback). The picture will not reach apps until it is.")
            }
        }
    }
}
