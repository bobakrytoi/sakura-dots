// sakura mono - lock screen (ext-session-lock, replaces hyprlock when Settings > Power & Sleep says so).
// Wallpaper (the video plays too), big clock, password pill, what is playing, latest notifications.
// Password check: PAM, the same config hyprlock uses (/etc/pam.d/hyprlock).
// qs ipc call lock lock   (hypr/scripts/lock.sh calls this; loginctl lock-session → hypridle → lock.sh)
// If the shell ever dies while locked, Hyprland keeps the screen locked (misc.allow_session_lock_restore lets
// a new locker take over: from a TTY run  hyprctl --instance 0 dispatch exec hyprlock).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pam
import QtQuick
import QtQuick.Effects

Scope {
    id: lk
    property bool locked: false
    property var topBar: null              // its keyboard layout (layout.py) for the indicator
    readonly property string layout: topBar ? topBar.layout.text : ""
    property string pending: ""
    property string error: ""
    property bool busy: false
    property int fails: 0

    function lock() {
        if (locked) return;
        unlockA.stop(); gone = 0;
        error = ""; pending = ""; busy = false;
        locked = true;
        Quickshell.execDetached(["hyprctl", "eval", "__setLockKeys(true)"]);
    }
    function tryUnlock(pw) {
        if (busy || unlockA.running || pw === "") return;
        pending = pw; busy = true; error = "";
        if (!pam.start()) { busy = false; error = Cfg.tr("Can't check the password"); }
    }
    IpcHandler { target: "lock"; function lock(): void { lk.lock(); } }
    property real gone: 0                  // 0 → 1 while unlocking
    SequentialAnimation {
        id: unlockA
        NumberAnimation { target: lk; property: "gone"; from: 0; to: 1; duration: 480 * Cfg.anim; easing.type: Easing.OutCubic }
        ScriptAction { script: {
            lk.locked = false;
            Quickshell.execDetached(["hyprctl", "eval", "__setLockKeys(false)"]);
            Choreo.enter("unlock");
        } }
        PauseAnimation { duration: 300 }
        ScriptAction { script: lk.gone = 0 }
    }

    PamContext {
        id: pam
        config: "hyprlock"
        onPamMessage: { if (responseRequired) respond(lk.pending); }
        onCompleted: result => {
            lk.busy = false; lk.pending = "";
            if (result === PamResult.Success) {
                lk.fails = 0;
                // the lock dissolves into the plain wallpaper, then the desktop grows back (Choreo.qml)
                Choreo.tuck(); unlockA.restart();
            } else { lk.fails += 1; lk.error = Cfg.tr("Wrong password"); }
        }
        onError: e => { lk.busy = false; lk.pending = ""; lk.error = Cfg.tr("Can't check the password"); }
    }

    WlSessionLock {
        id: sl
        locked: lk.locked

        WlSessionLockSurface {
            id: surf
            color: "#0e0e10"
            readonly property bool main: screen && screen.name === Cfg.mainName

            Item {
                id: root
                anchors.fill: parent
                // fade in
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 400 } }

                // wallpaper, softly blurred and dimmed; blurs more while you type
                WallThumb {
                    id: wall
                    anchors.fill: parent
                    file: Cfg.data.wallpaper || ""
                    size: 1920
                    live: lk.locked && Cfg.data.wallVideo !== false
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true; blurMax: 64
                        readonly property real base: typeof Cfg.data.lockBlur === "number" ? Cfg.data.lockBlur : 0.25
                        blur: (pw.text.length > 0 || lk.busy ? Math.min(1, base + 0.5) : base) * (1 - lk.gone)
                        Behavior on blur { NumberAnimation { duration: 400 } }
                        brightness: -(1 - lk.gone) * (typeof Cfg.data.lockDim === "number" ? Cfg.data.lockDim : 0.12)
                    }
                }
                Rectangle { anchors.fill: parent; opacity: 1 - lk.gone; gradient: Gradient {
                    GradientStop { position: 0.0; color: "#660e0e10" } GradientStop { position: 0.5; color: "#200e0e10" } GradientStop { position: 1.0; color: "#990e0e10" } } }

                // everything on top of the wallpaper; on unlock it fades and swells away (lk.gone)
                Item {
                anchors.fill: parent
                opacity: 1 - lk.gone
                scale: 1 + 0.05 * lk.gone
                // clock
                Column {
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.16 }
                    spacing: -6
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Cfg.timeStr(Desk.now, Cfg.data.lockSeconds === true).replace(/ [AP]M$/, "")
                           font.family: "Inter Display"; font.pixelSize: Cfg.data.lockClock === "small" ? 96 : 150
                           font.weight: Cfg.data.lockClock === "thin" ? Font.Light : Font.Black; color: "#ffffff"
                           layer.enabled: true; layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#a0000000"; shadowBlur: 1.0; blurMax: 40 } }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Cfg.dateLong(Desk.now)
                           font.family: Cfg.fontUi; font.pixelSize: 22; font.weight: Font.DemiBold; color: "#e6ffffff" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; topPadding: 14; visible: !!Desk.weather && Cfg.data.lockWeather !== false
                           text: Desk.weather ? Cfg.temp(Desk.weather.current.temperature_2m) + "  ·  " + Cfg.wText(Desk.weather.current.weather_code) + "  ·  " + Desk.weather.city : ""
                           font.family: Cfg.fontUi; font.pixelSize: 15; color: "#ccffffff" }
                }

                // avatar + password (main monitor)
                Column {
                    visible: surf.main
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.18 }
                    spacing: 14
                    ClippingRectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 84; height: 84; radius: 42; color: Cfg.accent
                        Avatar { anchors.fill: parent; ring: 3; ringColor: "transparent" }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Quickshell.env("USER")
                           font.family: Cfg.fontUi; font.pixelSize: 16; font.weight: Font.Bold; color: "#ffffff" }
                    Rectangle {
                        id: pill
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 300; height: 48; radius: 24
                        color: Cfg.glass
                        border.width: 1; border.color: lk.error !== "" ? "#f28fad" : pw.activeFocus ? Cfg.acc(0.6) : "#1fffffff"
                        // shake on a wrong password
                        transform: Translate { id: shake }
                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: shake; property: "x"; to: -12; duration: 50 }
                            NumberAnimation { target: shake; property: "x"; to: 10; duration: 70 }
                            NumberAnimation { target: shake; property: "x"; to: -6; duration: 60 }
                            NumberAnimation { target: shake; property: "x"; to: 0; duration: 60 }
                        }
                        Connections { target: lk; function onFailsChanged() { if (lk.fails > 0) { shakeAnim.restart(); pw.text = ""; } } }

                        // keyboard layout: shows the current one, click = next
                        Rectangle {
                            id: kb
                            visible: lk.layout !== ""
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            width: visible ? kbT.implicitWidth + 18 : 0; height: 32; radius: 16
                            color: kbM.containsMouse ? Cfg.acc(0.3) : Cfg.acc(0.16)
                            Text { id: kbT; anchors.centerIn: parent; text: lk.layout; font.family: Cfg.fontUi; font.pixelSize: 12; font.weight: Font.Bold; color: Cfg.accent }
                            MouseArea { id: kbM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"]); pw.forceActiveFocus(); } }
                        }
                        Text { id: lockIc; anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                               text: lk.busy ? "" : ""; font.family: "Symbols Nerd Font"; font.pixelSize: 14; color: Cfg.accent
                               RotationAnimation on rotation { running: lk.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                               Connections { target: lk; function onBusyChanged() { if (!lk.busy) lockIc.rotation = 0; } } }
                        TextInput {
                            id: pw
                            anchors { left: lockIc.right; leftMargin: 14; right: kb.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            focus: surf.main
                            echoMode: TextInput.Password; passwordCharacter: "●"
                            color: "#ffffff"; font.family: Cfg.fontUi; font.pixelSize: 16; font.letterSpacing: 2
                            clip: true; enabled: !lk.busy
                            onTextEdited: lk.error = ""
                            onAccepted: lk.tryUnlock(text)
                            Keys.onEscapePressed: text = ""
                            Text { visible: pw.text === ""; anchors.verticalCenter: parent.verticalCenter
                                   text: lk.busy ? Cfg.tr("Checking…") : Cfg.tr("Password"); color: "#99ffffff"; font.family: Cfg.fontUi; font.pixelSize: 14; font.letterSpacing: 0 }
                        }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; height: 16; text: lk.error; color: "#f28fad"; font.family: Cfg.fontUi; font.pixelSize: 13 }
                }

                // what is playing (main monitor, bottom left)
                Rectangle {
                    visible: surf.main && Desk.player !== null && Cfg.data.lockMedia !== false
                    anchors { left: parent.left; bottom: parent.bottom; margins: 36 }
                    width: 360; height: 92; radius: 22; color: Cfg.glass
                    ClippingRectangle {
                        id: art
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 68; height: 68; radius: 16; color: "#1fffffff"
                        Image { anchors.fill: parent; source: Desk.player ? (Desk.player.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                    }
                    Column {
                        anchors { left: art.right; leftMargin: 14; right: ctl.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 3
                        Text { width: parent.width; elide: Text.ElideRight; text: Desk.player ? (Desk.player.trackTitle || "") : ""
                               font.family: Cfg.fontUi; font.pixelSize: 14; font.weight: Font.Bold; color: "#ffffff" }
                        Text { width: parent.width; elide: Text.ElideRight; text: Desk.player ? (Desk.player.trackArtist || "") : ""
                               font.family: Cfg.fontUi; font.pixelSize: 12; color: Cfg.accent }
                    }
                    Row {
                        id: ctl
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Repeater {
                            model: ["prev", "play", "next"]
                            Rectangle {
                                required property string modelData
                                readonly property bool big: modelData === "play"
                                width: big ? 38 : 28; height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
                                color: big ? Cfg.accent : (pm.containsMouse ? "#22ffffff" : "transparent")
                                Text { anchors.centerIn: parent; font.family: "Symbols Nerd Font"; font.pixelSize: parent.big ? 14 : 11; color: parent.big ? Cfg.accFg : "#ffffff"
                                       text: parent.modelData === "prev" ? "" : parent.modelData === "next" ? "" : (Desk.player && Desk.player.isPlaying ? "" : "") }
                                MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { const p = Desk.player; if (!p) return; if (parent.modelData === "prev") p.previous(); else if (parent.modelData === "next") p.next(); else p.togglePlaying(); } }
                            }
                        }
                    }
                }

                // latest notifications (main monitor, top right) - only who wrote and the title
                Column {
                    visible: surf.main && Notifs.count > 0 && Cfg.data.lockNotifs !== false
                    anchors { right: parent.right; top: parent.top; margins: 36 }
                    width: 320; spacing: 8
                    Row { anchors.right: parent.right; spacing: 8
                        Text { text: ""; font.family: "Symbols Nerd Font"; font.pixelSize: 13; color: Cfg.accent; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: Notifs.count + " " + Cfg.tr("notifications"); font.family: Cfg.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: "#ffffff" } }
                    Repeater {
                        model: Notifs.list.slice(0, 3)
                        Rectangle {
                            required property var modelData
                            width: 320; height: 52; radius: 16; color: Cfg.glass
                            Column { anchors { left: parent.left; right: parent.right; leftMargin: 14; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.appName || ""; font.family: Cfg.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: Cfg.accent }
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.summary || ""; font.family: Cfg.fontUi; font.pixelSize: 13; color: "#ffffff" } }
                        }
                    }
                }

                // power (main monitor, bottom right)
                Row {
                    visible: surf.main && Cfg.data.lockPower !== false
                    anchors { right: parent.right; bottom: parent.bottom; margins: 36 }
                    spacing: 8
                    Repeater {
                        model: [ { i: "", c: "systemctl suspend" }, { i: "", c: "systemctl reboot" }, { i: "", c: "systemctl poweroff" } ]
                        Rectangle {
                            required property var modelData
                            width: 44; height: 44; radius: 22
                            color: bm.containsMouse ? Cfg.accent : Cfg.glass
                            Text { anchors.centerIn: parent; text: parent.modelData.i; font.family: "Symbols Nerd Font"; font.pixelSize: 15; color: bm.containsMouse ? Cfg.accFg : "#ffffff" }
                            MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["sh", "-c", parent.modelData.c]) }
                        }
                    }
                }
                }
            }
        }
    }
}
