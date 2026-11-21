// sakura mono - right-click menu on the empty desktop (the click comes from Wallpaper.qml).
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

Scope {
    id: dm
    property var settings: null
    property var picker: null
    property bool shown: false
    property var screen0: Quickshell.screens[0]
    property real px: 0
    property real py: 0

    readonly property color cBg:     Cfg.glass   // same glass as the top bar (blur: hyprland.lua)
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cHover:  "#1fffffff"
    readonly property color cCard:   "#14ffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"

    readonly property var items: [
        { id: "widgets", icon: "\uf009", name: "Edit widgets" },
        { id: "look",    cp: 0xf03d8, name: "Appearance" },
        { id: "accent",  icon: "\uf1fc", name: "Color from wallpaper", check: true },
        { id: "sep" },
        { id: "settings",icon: "\uf013", name: "Settings" },
        { id: "reload",  icon: "\uf021", name: "Reload shell" }
    ]

    function openAt(sc, x, y) {
        screen0 = sc; px = x; py = y; shown = true; grabOn = false; regrab.restart();
    }
    function run(id) {
        shown = false;
        if (id === "pick") { if (picker) picker.open(dm.screen0); }
        else if (id === "random") { if (picker) picker.randomNow(); }
        else if (id === "accent") {
            const on = !(Cfg.data.accentAuto === true);
            Cfg.set("accentAuto", on);
            if (on && settings) settings.accentProc("auto");
        }
        else if (id === "widgets") Desk.edit(dm.screen0);
        else if (id === "look") { if (settings) settings.openPage("appearance"); }
        else if (id === "settings") { if (settings) settings.openPage(settings.page); }
        else if (id === "reload") Quickshell.reload(true);
    }

    property bool grabOn: false
    Timer { id: regrab; interval: 40; onTriggered: if (dm.shown) dm.grabOn = true }

    PanelWindow {
        id: win
        screen: dm.screen0
        visible: dm.shown || card.opacity > 0
        anchors { left: true; top: true }
        margins {
            left: Math.round(Math.max(8, Math.min(dm.px, (dm.screen0 ? dm.screen0.width : 1920) - implicitWidth - 8)))
            top: Math.round(Math.max(8, Math.min(dm.py, (dm.screen0 ? dm.screen0.height : 1080) - implicitHeight - 8)))
        }
        implicitWidth: 260
        implicitHeight: col.implicitHeight + 12
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "desktopmenu"
        WlrLayershell.keyboardFocus: dm.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        HyprlandFocusGrab { windows: [ win ]; active: dm.grabOn && dm.shown; onCleared: dm.shown = false }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 20
            color: dm.cBg
            border.width: 0
            opacity: dm.shown ? 1 : 0
            scale: dm.shown ? 1 : 0.94
            transformOrigin: Item.TopLeft
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            focus: true
            Keys.onEscapePressed: dm.shown = false

            Column {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 0

                // current wallpaper: click = picker, shuffle = random
                ClippingRectangle {
                    width: col.width; height: Math.round(width * 9 / 16 * 0.78); radius: 15; color: dm.cCard
                    WallThumb { anchors.fill: parent; file: Cfg.data.wallpaper || ""; size: 520; live: dm.shown }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.45; color: "#000f1119" }
                            GradientStop { position: 1.0;  color: "#d90f1119" }
                        }
                    }
                    Rectangle { anchors.fill: parent; color: "#ffffff"; opacity: wma.containsMouse && !sma.containsMouse ? 0.06 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } } }
                    MouseArea { id: wma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dm.run("pick") }
                    Column {
                        anchors { left: parent.left; bottom: parent.bottom; margins: 12 }
                        Text { text: Cfg.tr("Wallpaper"); color: "#ffffff"; font.family: dm.fUi; font.pixelSize: 14; font.weight: Font.Bold }
                        Text { text: Cfg.tr("Change"); color: wma.containsMouse && !sma.containsMouse ? dm.cAccent : "#d9ffffff"; font.family: dm.fUi; font.pixelSize: 11
                               Behavior on color { ColorAnimation { duration: 140 } } }
                    }
                    Rectangle {
                        anchors { right: parent.right; bottom: parent.bottom; margins: 10 }
                        width: 30; height: 30; radius: 15
                        color: sma.containsMouse ? dm.cAccent : Cfg.glass
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text { anchors.centerIn: parent; text: "\uf074"; font.family: dm.fIcon; font.pixelSize: 12
                               color: sma.containsMouse ? dm.cAccFg : "#ffffff" }
                        MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dm.run("random") }
                    }
                }
                Item { width: 1; height: 6 }
                Repeater {
                    model: dm.items
                    delegate: Item {
                        id: it
                        required property var modelData
                        width: col.width
                        height: modelData.id === "sep" ? 9 : 36
                        Rectangle {
                            visible: it.modelData.id === "sep"
                            anchors.centerIn: parent; width: parent.width - 20; height: 1; color: dm.cBorder
                        }
                        Rectangle {
                            visible: it.modelData.id !== "sep"
                            anchors.fill: parent; radius: 10
                            color: ma.containsMouse ? dm.cHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: ic
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                width: 18; horizontalAlignment: Text.AlignHCenter
                                text: it.modelData.cp ? String.fromCodePoint(it.modelData.cp) : (it.modelData.icon || "")
                                color: ma.containsMouse ? dm.cAccent : dm.cMuted
                                font.family: dm.fIcon; font.pixelSize: 14
                            }
                            Text {
                                anchors { left: ic.right; leftMargin: 12; right: chk.left; verticalCenter: parent.verticalCenter }
                                text: Cfg.tr(it.modelData.name || "")
                                color: dm.cFg; elide: Text.ElideRight
                                font.family: dm.fUi; font.pixelSize: 13
                            }
                            Rectangle {
                                id: chk
                                visible: it.modelData.check === true
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                width: visible ? 30 : 0; height: 18; radius: 9
                                color: Cfg.data.accentAuto === true ? dm.cAccent : "#29ffffff"
                                Behavior on color { ColorAnimation { duration: 160 } }
                                Rectangle {
                                    width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter
                                    x: Cfg.data.accentAuto === true ? parent.width - width - 3 : 3
                                    color: Cfg.data.accentAuto === true ? dm.cAccFg : dm.cFg
                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dm.run(it.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
