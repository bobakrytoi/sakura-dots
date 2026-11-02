// sakura mono — desktop widgets on the wallpaper (main monitor): big clock, date, weather, now playing
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects

Scope {
    id: dw
    readonly property color cFg:     "#eceef4"
    readonly property color cSoft:   "#cfd2de"
    readonly property color cAccent: "#f2b8d0"
    readonly property color cAccFg:  "#1a121a"
    readonly property string fUi:    "Inter"
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string home:   Quickshell.env("HOME")

    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: dw.now = new Date() }

    // weather from the dashboard cache
    property var weather: null
    Process {
        id: wRead
        command: ["cat", dw.home + "/.cache/sakura-weather.json"]
        stdout: StdioCollector { onStreamFinished: { try { dw.weather = JSON.parse(this.text); } catch (e) {} } }
    }
    Timer { interval: 10 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: wRead.running = true }
    function wText(code) {
        if (code === 0) return "Clear"; if (code <= 2) return "Partly cloudy"; if (code === 3) return "Cloudy";
        if (code <= 48) return "Fog"; if (code <= 57) return "Drizzle"; if (code <= 67) return "Rain";
        if (code <= 77) return "Snow"; if (code <= 82) return "Showers"; if (code <= 86) return "Snow showers"; return "Thunderstorm";
    }

    readonly property var player: Mpris.players.values.find(p => !String(p.dbusName || "").includes("playerctld") && p.isPlaying)
                                   || Mpris.players.values.find(p => !String(p.dbusName || "").includes("playerctld")) || null

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === "DP-3") || Quickshell.screens[0]
        anchors { left: true; top: true }
        margins { left: 70; top: 130 }
        implicitWidth: 560
        implicitHeight: 420
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom              // above the wallpaper, below every window
        WlrLayershell.namespace: "desktop-widgets"
        mask: Region { item: mediaCard }                    // only the player card takes clicks

        Column {
            id: content
            spacing: 2
            layer.enabled: true
            layer.effect: MultiEffect {          // soft blurred shadow so text stays readable on bright petals
                shadowEnabled: true
                shadowColor: "#d0000000"
                shadowBlur: 1.0
                shadowVerticalOffset: 3
                shadowHorizontalOffset: 0
                blurMax: 40
            }
            // clock with a soft shadow
            Item {
                width: clock.implicitWidth; height: clock.implicitHeight
                Text { id: clock; text: String(dw.now.getHours()).padStart(2, "0") + ":" + String(dw.now.getMinutes()).padStart(2, "0")
                    font.family: "Inter Display"; font.pixelSize: 128; font.weight: Font.Black; color: dw.cFg }
            }
            Item {
                width: date.implicitWidth; height: date.implicitHeight
                Text { id: date; text: Qt.formatDate(dw.now, "dddd, d MMMM"); font.family: dw.fUi; font.pixelSize: 26; font.weight: Font.DemiBold; color: dw.cSoft }
            }
            Item { width: 1; height: 8 }
            Row {
                spacing: 10; visible: dw.weather !== null
                Text { text: dw.weather ? Math.round(dw.weather.current.temperature_2m) + "°" : ""; font.family: dw.fUi; font.pixelSize: 22; font.weight: Font.Bold; color: dw.cAccent }
                Text { text: dw.weather ? dw.wText(dw.weather.current.weather_code) + " · " + dw.weather.city : ""
                    font.family: dw.fUi; font.pixelSize: 17; color: dw.cSoft; anchors.verticalCenter: parent.verticalCenter }
            }
            Item { width: 1; height: 22 }

            // now playing
            Rectangle {
                id: mediaCard
                visible: dw.player !== null
                width: 380; height: 96; radius: 22
                color: "#a60f1119"; border.width: 1; border.color: "#1fffffff"
                ClippingRectangle {
                    id: art
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 72; height: 72; radius: 16; color: "#22263a"
                    Image { anchors.fill: parent; source: dw.player ? (dw.player.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                }
                Column {
                    anchors { left: art.right; leftMargin: 14; right: ctl.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    Text { width: parent.width; elide: Text.ElideRight; text: dw.player ? (dw.player.trackTitle || "") : ""
                        font.family: dw.fUi; font.pixelSize: 15; font.weight: Font.Bold; color: dw.cFg }
                    Text { width: parent.width; elide: Text.ElideRight; text: dw.player ? (dw.player.trackArtist || "") : ""
                        font.family: dw.fUi; font.pixelSize: 12; color: dw.cAccent }
                }
                Row {
                    id: ctl
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Repeater {
                        model: [ "prev", "play", "next" ]
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool big: modelData === "play"
                            width: big ? 40 : 30; height: big ? 40 : 30; radius: big ? 20 : 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: big ? dw.cAccent : (ba.containsMouse ? "#22ffffff" : "transparent")
                            Text { anchors.centerIn: parent; font.family: dw.fIcon; font.pixelSize: big ? 15 : 12
                                color: big ? dw.cAccFg : dw.cFg
                                text: modelData === "prev" ? "" : modelData === "next" ? ""
                                    : (dw.player && dw.player.isPlaying ? "" : "") }
                            MouseArea { id: ba; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (!dw.player) return;
                                    if (modelData === "prev") dw.player.previous(); else if (modelData === "next") dw.player.next(); else dw.player.togglePlaying(); } }
                        }
                    }
                }
            }
        }
    }
}
