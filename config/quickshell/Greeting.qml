// sakura mono - hello after login: "Good morning, <user>", the time and the weather in the middle of the main
// monitor. The lines cascade in one after another, then the bar, dock and widgets follow (Choreo.qml), and the
// lines fold away upwards. Once per session (Choreo checks $XDG_RUNTIME_DIR/sakura-greeted). Any click skips.
// On/off: Settings > Appearance > Shell (settings.json "greet").  Again: qs ipc call greeting play
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

Scope {
    id: gr
    property bool shown: false
    property real t: 0                     // ms of the cascade (line i comes in at i * step)
    property bool out: false               // folding away
    readonly property int step: 110
    readonly property int dur: 420

    // at login the lines follow the choreography's own clock (Choreo.clk), so a busy start never makes them jump
    property bool follow: false
    readonly property real tt: follow ? Choreo.clk : t
    onTtChanged: if (follow && !out && tt >= 1900 * Choreo.k) close()
    function show(hold) {
        out = false; t = 0; shown = true;
        follow = !hold && Choreo.moment === "login";
        if (follow) return;
        cascade.restart(); hideT.interval = hold || 1900; hideT.restart();
    }
    function close() { hideT.stop(); out = true; offT.restart(); }
    function skip() { cascade.stop(); follow = false; t = 9999; close(); Choreo.skip(); }
    Timer { id: hideT; onTriggered: gr.close() }
    Timer { id: offT; interval: 560; onTriggered: { gr.shown = false; gr.out = false; gr.follow = false; } }
    NumberAnimation { id: cascade; target: gr; property: "t"; from: 0; to: 1200; duration: 1200 }
    IpcHandler { target: "greeting"; function play(): void { gr.show(3600); } }
    Connections { target: Choreo; function onGreet() { gr.show(0); } }

    function lineP(i) {
        const x = Math.max(0, Math.min(1, (tt - i * step) / dur));
        return 1 - Math.pow(1 - x, 3);
    }

    PanelWindow {
        visible: gr.shown
        screen: Cfg.mainScreen
        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "greeting"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // while the login choreography runs a click anywhere skips it; afterwards only the card takes clicks
        mask: Region { item: Choreo.moment === "login" ? catcher : card }
        Item { id: catcher; anchors.fill: parent }
        MouseArea { anchors.fill: parent; onPressed: gr.skip() }

        Item {
            id: card
            anchors.centerIn: parent
            width: col.implicitWidth + 80; height: col.implicitHeight + 60

            Column {
                id: col
                anchors.centerIn: parent
                spacing: 6
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#c0000000"; shadowBlur: 1.0; blurMax: 48 }

                component Line: Text {
                    id: ln
                    property int i: 0
                    // in: rise from below one after another · out: they lift away, the last line first
                    readonly property real p: gr.lineP(i)
                    property real q: gr.out ? 0 : 1
                    Behavior on q { NumberAnimation { duration: 280 + (3 - ln.i) * 70; easing.type: Easing.InCubic } }
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: p * q
                    transform: Translate { y: (1 - ln.p) * 22 - (1 - ln.q) * 26 }
                }
                Line { i: 0; text: Desk.greeting() + ","
                       font.family: Cfg.fontUi; font.pixelSize: 30; font.weight: Font.DemiBold; color: "#e6ffffff" }
                Line { i: 1; text: Quickshell.env("USER")
                       font.family: "Inter Display"; font.pixelSize: 76; font.weight: Font.Black; color: Cfg.accent }
                Line { i: 2; topPadding: 6
                       text: Cfg.timeStr(Desk.now, false) + "  ·  " + Cfg.dateLong(Desk.now)
                       font.family: Cfg.fontUi; font.pixelSize: 18; color: "#ffffff" }
                Line { i: 3; visible: !!Desk.weather
                       text: Desk.weather ? Cfg.temp(Desk.weather.current.temperature_2m) + "  " + Cfg.wText(Desk.weather.current.weather_code) + "  ·  " + Desk.weather.city : ""
                       font.family: Cfg.fontUi; font.pixelSize: 16; color: "#ccffffff" }
            }
        }
    }
}
