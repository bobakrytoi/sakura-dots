// sakura mono - SDDM login theme, the same look as the lock screen (quickshell/Lock.qml):
// softly blurred wallpaper (blurs more while you type), big clock + date, avatar, glass password pill with the
// keyboard layout, session pill bottom-left, round power buttons bottom-right. Accent comes from theme.conf
// (written by hypr/scripts/sddm-theme.sh from Settings). SDDM opens this once per monitor: the form lives only on the
// main one (primary, set by sddm-xsetup.sh); the others show the wallpaper and the clock.
// Wallpaper and avatar come from /var/lib/sakura-sddm/ (kept current by hypr/scripts/sddm-sync.sh on every change, no sudo),
// falling back to the theme's own copies; the accent comes the same way through theme.conf.user (a symlink there).
// Key sounds: Sounds.qml (QtMultimedia), loaded separately so it can never break the login.
import QtQuick 2.15
import QtQuick.Effects

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#0e0e10"

    readonly property color accent: config.accent || "#f2b8d0"
    readonly property color accFg: (0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b) > 0.55 ? "#1a121a" : "#ffffff"
    readonly property color glass: "#8c0f1119"
    readonly property string fUi: "Inter"
    readonly property string fIcon: "Symbols Nerd Font"

    property string userName: userModel.lastUser !== "" ? userModel.lastUser : config.defaultUser
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool busy: false
    property string error: ""
    readonly property bool isMain: typeof primaryScreen === "undefined" ? true : primaryScreen

    readonly property string shared: "file:///var/lib/sakura-sddm/"
    Loader { id: sounds; source: root.isMain ? "Sounds.qml" : "" }
    function sound(f) { if (sounds.item) sounds.item[f](); }

    function doLogin() {
        if (busy || pw.text === "") return;
        error = ""; busy = true;
        sddm.login(root.userName, pw.text, root.sessionIndex);
    }
    Connections {
        target: sddm
        function onLoginFailed() { root.busy = false; root.error = "Wrong password"; pw.text = ""; shakeAnim.restart(); pw.forceActiveFocus(); }
        function onLoginSucceeded() { root.busy = false; }
    }

    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    // wallpaper, softly blurred and dimmed; blurs more while you type
    Image {
        id: wall
        anchors.fill: parent
        source: root.shared + "background.jpg"
        onStatusChanged: if (status === Image.Error && String(source).indexOf("sakura-sddm") >= 0) source = "background.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true; blurMax: 64
            blur: pw.text.length > 0 || root.busy || !root.isMain ? 0.75 : 0.25
            Behavior on blur { NumberAnimation { duration: 400 } }
            brightness: -0.12
        }
    }
    Rectangle { anchors.fill: parent; gradient: Gradient {
        GradientStop { position: 0.0; color: "#660e0e10" } GradientStop { position: 0.5; color: "#200e0e10" } GradientStop { position: 1.0; color: "#990e0e10" } } }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0
        Component.onCompleted: { opacity = 1; if (root.isMain) pw.forceActiveFocus(); }
        Behavior on opacity { NumberAnimation { duration: 400 } }

        // clock
        Column {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.16 }
            spacing: -6
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatTime(root.now, "HH:mm")
                   font.family: "Inter Display"; font.pixelSize: 150; font.weight: Font.Black; color: "#ffffff"
                   layer.enabled: true; layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#a0000000"; shadowBlur: 1.0; blurMax: 40 } }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDate(root.now, "dddd, d MMMM")
                   font.family: root.fUi; font.pixelSize: 22; font.weight: Font.DemiBold; color: "#e6ffffff" }
        }

        // avatar + password (main monitor)
        Column {
            visible: root.isMain
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.18 }
            spacing: 14
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 84; height: 84; radius: 42; color: root.accent
                Image {
                    id: av
                    anchors.fill: parent; anchors.margins: 3
                    source: root.shared + "avatar.png"; onStatusChanged: if (status === Image.Error && String(source).indexOf("sakura-sddm") >= 0) source = "avatar.png"
                    mipmap: true; smooth: true; visible: false
                }
                Rectangle { id: avMask; anchors.fill: av; radius: width / 2; visible: false; layer.enabled: true }
                MultiEffect { anchors.fill: av; source: av; maskEnabled: true; maskSource: avMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.userName
                   font.family: root.fUi; font.pixelSize: 16; font.weight: Font.Bold; color: "#ffffff" }
            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300; height: 48; radius: 24
                color: root.glass
                border.width: 1; border.color: root.error !== "" ? "#f28fad" : pw.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6) : "#1fffffff"
                transform: Translate { id: shake }
                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: shake; property: "x"; to: -12; duration: 50 }
                    NumberAnimation { target: shake; property: "x"; to: 10; duration: 70 }
                    NumberAnimation { target: shake; property: "x"; to: -6; duration: 60 }
                    NumberAnimation { target: shake; property: "x"; to: 0; duration: 60 }
                }
                Text { id: lockIc; anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                       text: root.busy ? "" : ""; font.family: root.fIcon; font.pixelSize: 14; color: root.accent
                       RotationAnimation on rotation { running: root.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite } }
                // keyboard layout: shows the current one, click = next
                Rectangle {
                    id: kb
                    readonly property string name: keyboard && keyboard.layouts && keyboard.layouts.length > 0
                                                    ? String(keyboard.layouts[keyboard.currentLayout].shortName).toUpperCase() : ""
                    visible: name !== ""
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    width: visible ? kbT.implicitWidth + 18 : 0; height: 32; radius: 16
                    color: kbM.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3) : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                    Text { id: kbT; anchors.centerIn: parent; text: kb.name; font.family: root.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: root.accent }
                    MouseArea { id: kbM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length; pw.forceActiveFocus(); } }
                }
                TextInput {
                    id: pw
                    anchors { left: lockIc.right; leftMargin: 14; right: kb.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    focus: root.isMain
                    echoMode: TextInput.Password; passwordCharacter: "●"
                    color: "#ffffff"; font.family: root.fUi; font.pixelSize: 16; font.letterSpacing: 2
                    clip: true; enabled: !root.busy
                    onTextEdited: root.error = ""
                    Keys.onReturnPressed: { root.sound("enter"); root.doLogin(); }
                    Keys.onEnterPressed: { root.sound("enter"); root.doLogin(); }
                    Keys.onEscapePressed: text = ""
                    // everything else: a key sound, then the key goes on to the field as usual
                    Keys.onPressed: event => {
                        event.accepted = false;
                        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) { if (pw.text !== "") root.sound("back"); }
                        else if (event.text !== "" && event.text.charCodeAt(0) >= 32 && !(event.modifiers & Qt.ControlModifier)) root.sound("key");
                    }
                    Text { visible: pw.text === ""; anchors.verticalCenter: parent.verticalCenter
                           text: root.busy ? "Checking…" : "Password"; color: "#99ffffff"; font.family: root.fUi; font.pixelSize: 14; font.letterSpacing: 0 }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; height: 16; text: root.error; color: "#f28fad"; font.family: root.fUi; font.pixelSize: 13 }
        }

        // session (main monitor, bottom left) - same glass pill as the lock screen's player
        Rectangle {
            visible: root.isMain
            anchors { left: parent.left; bottom: parent.bottom; margins: 36 }
            width: 300; height: 48; radius: 24; color: root.glass
            Text { anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                   text: ""; font.family: root.fIcon; font.pixelSize: 13; color: root.accent }
            Text {
                anchors { left: parent.left; leftMargin: 44; right: nextS.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: sessions.currentItem ? sessions.currentItem.label : ""
                font.family: root.fUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: "#ffffff"
            }
            ListView { id: sessions; width: 10; height: 10; opacity: 0; interactive: false; model: sessionModel; currentIndex: root.sessionIndex
                       delegate: Item { required property string name; readonly property string label: name } }
            Rectangle {
                id: nextS
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                width: 32; height: 32; radius: 16
                color: nsM.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3) : "transparent"
                Text { anchors.centerIn: parent; text: ""; font.family: root.fIcon; font.pixelSize: 12; color: "#ffffff" }
                MouseArea { id: nsM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.sessionIndex = (root.sessionIndex + 1) % Math.max(1, sessions.count) }
            }
        }

        // power (main monitor, bottom right)
        Row {
            visible: root.isMain
            anchors { right: parent.right; bottom: parent.bottom; margins: 36 }
            spacing: 8
            Repeater {
                model: [ { i: "", a: "suspend" }, { i: "", a: "reboot" }, { i: "", a: "off" } ]
                Rectangle {
                    required property var modelData
                    visible: modelData.a === "suspend" ? sddm.canSuspend : modelData.a === "reboot" ? sddm.canReboot : sddm.canPowerOff
                    width: 44; height: 44; radius: 22
                    color: bm.containsMouse ? root.accent : root.glass
                    Text { anchors.centerIn: parent; text: parent.modelData.i; font.family: root.fIcon; font.pixelSize: 15; color: bm.containsMouse ? root.accFg : "#ffffff" }
                    MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (parent.modelData.a === "suspend") sddm.suspend(); else if (parent.modelData.a === "reboot") sddm.reboot(); else sddm.powerOff(); } }
                }
            }
        }
    }
}
