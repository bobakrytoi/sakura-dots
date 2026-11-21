// sakura mono - network menu: flows out of the top bar under the network button (DropPanel.qml).
// What you are connected through (cable / Wi-Fi), the local IP, Mullvad VPN on/off, and the full settings.
import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: nm
    property var topBar: null
    property bool shown: false
    property var screen0: Quickshell.screens[0]
    property real anchorX: -1
    readonly property string covering: drop.covering

    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cCard:   "#14ffffff"
    readonly property color cCard2:  "#1fffffff"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"

    // cable wins over Wi-Fi; the VPN tunnel and loopback don't count
    property var net: ({ kind: "off", name: "", ip: "" })
    Process {
        id: netProc
        command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status; echo @@; ip -4 -o addr show scope global | awk '{print $2\" \"$4}'"]
        stdout: StdioCollector { onStreamFinished: {
            const parts = this.text.split("@@");
            const devs = parts[0].split("\n").filter(l => l).map(l => l.split(":"));
            const ips = {};
            (parts[1] || "").split("\n").filter(l => l.trim()).forEach(l => { const a = l.trim().split(" "); ips[a[0]] = (a[1] || "").split("/")[0]; });
            const up = t => devs.find(d => d[1] === t && d[2] === "connected");
            const d = up("ethernet") || up("wifi");
            nm.net = d ? { kind: d[1] === "ethernet" ? "eth" : "wifi", name: d[3], ip: ips[d[0]] || "" } : { kind: "off", name: "", ip: "" };
        } }
    }
    property bool vpnOn: false
    property string vpnText: ""
    Process {
        id: vpnProc
        command: ["sh", "-c", "mullvad status 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: {
            const t = this.text, first = t.split("\n")[0].trim();
            nm.vpnOn = first.startsWith("Connected");
            const loc = (t.match(/Visible location:\s*([^.\n]+)/) || [])[1] || "";
            nm.vpnText = first.startsWith("Connecting") ? Cfg.tr("Connecting…") : nm.vpnOn ? loc : Cfg.tr("Off");
        } }
    }
    function refresh() { netProc.running = true; vpnProc.running = true; }
    Timer { interval: 2000; running: nm.shown; repeat: true; onTriggered: nm.refresh() }

    // from the top bar: open under that button (x: its middle on that screen)
    function toggleAt(screenName, x) {
        if (shown) { shown = false; return; }
        if (drop.justClosed()) return;
        const sc = Quickshell.screens.find(s => s.name === screenName);
        if (sc) screen0 = sc;
        anchorX = x; refresh(); shown = true;
    }

    DropPanel {
        id: drop
        topBar: nm.topBar
        shown: nm.shown
        onCloseRequested: nm.shown = false
        screen0: nm.screen0
        anchorX: nm.anchorX
        boxW: 320
        boxH: col.implicitHeight + 32
        ns: "netmenu"

        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 10

            // what you are connected through
            Row {
                spacing: 12
                Rectangle {
                    width: 42; height: 42; radius: 14; color: nm.net.kind === "off" ? nm.cCard : nm.cAccent
                    Text { anchors.centerIn: parent; font.family: nm.fIcon; font.pixelSize: 18
                        text: nm.net.kind === "eth" ? "\u{F0200}" : nm.net.kind === "wifi" ? "" : "\u{F0C9B}"
                        color: nm.net.kind === "off" ? nm.cMuted : nm.cAccFg }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: nm.net.kind === "eth" ? Cfg.tr("Cable") : nm.net.kind === "wifi" ? "Wi-Fi" : Cfg.tr("Offline")
                        color: nm.cFg; font.family: nm.fUi; font.pixelSize: 14; font.weight: Font.Bold }
                    Text { visible: text !== ""; text: [nm.net.name, nm.net.ip].filter(x => x).join(" · ")
                        color: nm.cMuted; font.family: nm.fUi; font.pixelSize: 11 }
                }
            }

            // Mullvad
            Rectangle {
                width: parent.width; height: 52; radius: 14
                color: va.containsMouse ? nm.cCard2 : nm.cCard
                Behavior on color { ColorAnimation { duration: 120 } }
                Text { id: vIc; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: ""; font.family: nm.fIcon; font.pixelSize: 15; color: nm.vpnOn ? nm.cAccent : nm.cMuted }
                Column {
                    anchors { left: vIc.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Text { text: "Mullvad VPN"; color: nm.cFg; font.family: nm.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { text: nm.vpnText; color: nm.cMuted; font.family: nm.fUi; font.pixelSize: 11 }
                }
                Rectangle {     // switch
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    width: 38; height: 22; radius: 11
                    color: nm.vpnOn ? nm.cAccent : nm.cCard2
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Rectangle {
                        width: 16; height: 16; radius: 8; anchors.verticalCenter: parent.verticalCenter
                        x: nm.vpnOn ? parent.width - width - 3 : 3
                        color: nm.vpnOn ? nm.cAccFg : nm.cMuted
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }
                MouseArea {
                    id: va; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["mullvad", nm.vpnOn ? "disconnect" : "connect"]);
                        nm.vpnOn = !nm.vpnOn; nm.vpnText = nm.vpnOn ? Cfg.tr("Connecting…") : Cfg.tr("Off");
                        vpnAgain.restart();
                    }
                }
                Timer { id: vpnAgain; interval: 1500; onTriggered: vpnProc.running = true }
            }

            // the full settings
            Rectangle {
                width: parent.width; height: 38; radius: 12
                color: sa.containsMouse ? nm.cCard2 : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                Row {
                    anchors.centerIn: parent; spacing: 8
                    Text { text: ""; font.family: nm.fIcon; font.pixelSize: 12; color: sa.containsMouse ? nm.cAccent : nm.cMuted; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: Cfg.tr("Network settings"); font.family: nm.fUi; font.pixelSize: 12; color: sa.containsMouse ? nm.cFg : nm.cMuted; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: sa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { nm.shown = false; Quickshell.execDetached(["nm-connection-editor"]); } }
            }
        }
    }
}
