import QtQuick

Item {
    id: sb
    property var app: null
    width: Theme.sideW

    Rectangle { anchors.fill: parent; color: Theme.side }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }

    Column {
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: 18
        spacing: 2

        Row {
            leftPadding: 10; bottomPadding: 20; spacing: 9
            SakuraMark { width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter; spin: Sound.playing && Theme.cover === "spin" }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: "sakura<font color='" + Theme.muted + "'>sound</font>"
                color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 16; font.weight: Font.Bold; font.letterSpacing: -0.3
            }
        }

        Repeater {
            model: sb.app ? sb.app.navItems : []
            Rectangle {
                required property var modelData
                readonly property bool on: sb.app && sb.app.page.p === modelData.p
                width: parent.width; height: 40; radius: 12
                color: on ? Theme.cardHi : nMa.containsMouse ? Theme.hover : "transparent"
                Row {
                    anchors.verticalCenter: parent.verticalCenter; leftPadding: 12; spacing: 12
                    Ico { name: modelData.icon; size: 17; color: on ? Theme.accent : Theme.muted; width: 20 }
                    Text { text: modelData.label; color: on ? Theme.fg : Theme.muted; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: nMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sb.app.go({ p: modelData.p }, true) }
            }
        }
    }

    // account
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: 12
        height: 52; radius: 14
        color: acMa.containsMouse ? Theme.hover : "transparent"
        Row {
            anchors.verticalCenter: parent.verticalCenter; leftPadding: 8; spacing: 10
            Cover { width: 34; height: 34; style: "circle"; src: Sound.me ? Theme.small(Sound.me.avatar, 80) : ""; anchors.verticalCenter: parent.verticalCenter }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: Sound.me ? Sound.me.name : Theme.tr("Guest"); color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold
                       width: sb.width - 90; elide: Text.ElideRight }
                Text { text: Sound.signedIn ? (Sound.auth.go ? "Go+" : "SoundCloud") : Theme.tr("Not signed in"); color: Sound.signedIn ? Theme.muted : Theme.accent
                       font.family: Theme.fontUi; font.pixelSize: 11 }
            }
        }
        Ico { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; name: "cog"; size: 15; color: Theme.muted }
        MouseArea { id: acMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sb.app.go({ p: "settings" }, true) }
    }
}
