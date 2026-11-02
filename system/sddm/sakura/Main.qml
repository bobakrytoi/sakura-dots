import QtQuick 2.15

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#0f1119"

    property string userName: userModel.lastUser !== "" ? userModel.lastUser : config.defaultUser
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool typing: pw.text.length > 0

    function doLogin() {
        msg.text = ""
        sddm.login(root.userName, pw.text, root.sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            pw.text = ""
            msg.text = "wrong password"
            shake.restart()
            pw.forceActiveFocus()
        }
    }

    // background + blur that fades in while typing
    Image {
        anchors.fill: parent
        source: "background.jpg"
        fillMode: Image.PreserveAspectCrop
    }
    Image {
        anchors.fill: parent
        source: "background-blur.jpg"
        fillMode: Image.PreserveAspectCrop
        opacity: root.typing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#660f1119" }
            GradientStop { position: 0.5; color: "#000f1119" }
            GradientStop { position: 1.0; color: "#990f1119" }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0
        transform: Translate { id: lift; y: 40 }
        Component.onCompleted: { intro.start(); pw.forceActiveFocus() }

        ParallelAnimation {
            id: intro
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: lift; property: "y"; to: 0; duration: 1100; easing.type: Easing.OutBack }
        }

        // clock
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.12
            spacing: 2
            Text {
                id: clock
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#eceef4"
                font.family: "Inter Display"
                font.weight: Font.ExtraBold
                font.pixelSize: 128
                text: Qt.formatTime(new Date(), "HH:mm")
            }
            Text {
                id: date
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#c9ccd8"
                font.family: "Inter"
                font.pixelSize: 22
                text: Qt.formatDate(new Date(), "dddd, MMMM d")
            }
            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: {
                    clock.text = Qt.formatTime(new Date(), "HH:mm")
                    date.text = Qt.formatDate(new Date(), "dddd, MMMM d")
                }
            }
        }

        // login card
        Column {
            id: card
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 120
            spacing: 16

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 136; height: 136; radius: 68
                color: "#f2b8d0"
                Image {
                    anchors.centerIn: parent
                    width: 128; height: 128
                    source: "avatar.png"
                    smooth: true
                    mipmap: true
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.userName
                color: "#eceef4"
                font.family: "Inter"
                font.weight: Font.DemiBold
                font.pixelSize: 20
            }

            Rectangle {
                id: field
                anchors.horizontalCenter: parent.horizontalCenter
                width: 340; height: 54; radius: 18
                color: "#b30f1119"
                border.width: 2
                border.color: pw.activeFocus ? "#f2b8d0" : "#33ffffff"
                Behavior on border.color { ColorAnimation { duration: 250 } }
                transform: Translate { id: shakeX; x: 0 }

                SequentialAnimation {
                    id: shake
                    loops: 1
                    NumberAnimation { target: shakeX; property: "x"; to: -14; duration: 50 }
                    NumberAnimation { target: shakeX; property: "x"; to: 14;  duration: 70 }
                    NumberAnimation { target: shakeX; property: "x"; to: -10; duration: 70 }
                    NumberAnimation { target: shakeX; property: "x"; to: 8;   duration: 70 }
                    NumberAnimation { target: shakeX; property: "x"; to: 0;   duration: 60 }
                }

                TextInput {
                    id: pw
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 60
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#eceef4"
                    font.family: "Inter"
                    font.pixelSize: 18
                    font.letterSpacing: 3
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    selectionColor: "#f2b8d0"
                    clip: true
                    focus: true
                    Keys.onReturnPressed: root.doLogin()
                    Keys.onEnterPressed: root.doLogin()
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    text: "password..."
                    color: "#8a8fa3"
                    font.family: "Inter"
                    font.pixelSize: 17
                    visible: pw.text.length === 0
                }
                Rectangle {
                    id: go
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40; radius: 14
                    color: goArea.containsMouse ? "#ffffff" : "#f2b8d0"
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Text {
                        anchors.centerIn: parent
                        text: "→"
                        color: "#1a121a"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }
                    MouseArea { id: goArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.doLogin() }
                }
            }

            Text {
                id: msg
                anchors.horizontalCenter: parent.horizontalCenter
                text: ""
                color: "#f28fad"
                font.family: "Inter"
                font.pixelSize: 14
                height: 18
            }
        }

        // session switcher (bottom-left)
        Row {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 36
            spacing: 10

            Rectangle {
                width: 300; height: 44; radius: 16
                color: "#990f1119"
                border.width: 1; border.color: "#22ffffff"
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "‹"; color: "#f2b8d0"; font.pixelSize: 24
                    MouseArea { anchors.fill: parent; anchors.margins: -8
                        onClicked: root.sessionIndex = (root.sessionIndex - 1 + sessions.count) % sessions.count }
                }
                ListView {
                    id: sessions
                    anchors.centerIn: parent
                    width: 220; height: 30
                    model: sessionModel
                    currentIndex: root.sessionIndex
                    orientation: ListView.Horizontal
                    interactive: false
                    clip: true
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: 0
                    preferredHighlightEnd: 220
                    highlightMoveDuration: 300
                    delegate: Text {
                        width: 220; height: 30
                        text: model.name
                        color: "#eceef4"
                        font.family: "Inter"
                        font.pixelSize: 15
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "›"; color: "#f2b8d0"; font.pixelSize: 24
                    MouseArea { anchors.fill: parent; anchors.margins: -8
                        onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessions.count }
                }
            }
        }

        // power buttons (bottom-right)
        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 36
            spacing: 12

            Repeater {
                model: [
                    { icon: "", act: "suspend", ok: sddm.canSuspend },
                    { icon: "", act: "reboot",  ok: sddm.canReboot },
                    { icon: "", act: "off",     ok: sddm.canPowerOff }
                ]
                delegate: Rectangle {
                    visible: modelData.ok
                    width: 48; height: 48; radius: 16
                    color: pa.containsMouse ? "#f2b8d0" : "#990f1119"
                    border.width: 1; border.color: "#22ffffff"
                    Behavior on color { ColorAnimation { duration: 200 } }
                    scale: pa.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.icon
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 18
                        color: pa.containsMouse ? "#1a121a" : "#eceef4"
                    }
                    MouseArea {
                        id: pa; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            if (modelData.act === "suspend") sddm.suspend()
                            else if (modelData.act === "reboot") sddm.reboot()
                            else sddm.powerOff()
                        }
                    }
                }
            }
        }
    }
}
