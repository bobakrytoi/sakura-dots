// sakura mono - one notification: app icon or picture, title, text, action buttons, close.
// Used by the popups (NotifPopups.qml) and the list in the center (NotifCenter.qml).
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick

Rectangle {
    id: c
    required property var n                 // Notification
    property bool popup: false
    property bool hovered: ma.containsMouse || closeMa.containsMouse
    signal closeClicked()
    width: 380
    height: col.implicitHeight + 24
    radius: 18
    color: popup ? Cfg.glass : (ma.containsMouse ? "#1fffffff" : "#14ffffff")
    border.width: n && n.urgency === NotificationUrgency.Critical ? 1 : 0
    border.color: Cfg.acc(0.6)

    readonly property string fUi: Cfg.fontUi
    readonly property string fIcon: "Symbols Nerd Font"
    readonly property string pic: n ? (n.image || "") : ""
    readonly property string icon: n && n.appIcon ? (n.appIcon.startsWith("/") || n.appIcon.startsWith("file:") ? n.appIcon : Quickshell.iconPath(n.appIcon, true)) : ""

    MouseArea {
        id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: if (c.n) Notifs.activate(c.n)
    }

    Row {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 12
        // picture / app icon
        ClippingRectangle {
            width: 44; height: 44; radius: c.pic !== "" ? 12 : 22
            color: c.pic !== "" ? "transparent" : Cfg.acc(0.18)
            Image { anchors.fill: parent; visible: c.pic !== ""; source: c.pic; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            IconImage { anchors.centerIn: parent; visible: c.pic === "" && c.icon !== ""; implicitSize: 26; source: c.icon }
            Text { anchors.centerIn: parent; visible: c.pic === "" && c.icon === ""; text: ""; font.family: c.fIcon; font.pixelSize: 17; color: Cfg.accent }
        }
        Column {
            width: col.width - 44 - 12
            spacing: 3
            Item {
                width: parent.width; height: appT.implicitHeight
                Text { id: appT; anchors.left: parent.left; text: c.n ? (c.n.appName || "") : ""; font.family: c.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: Cfg.accent
                       width: parent.width - timeT.implicitWidth - 30; elide: Text.ElideRight }
                Text { id: timeT; anchors.right: parent.right; anchors.rightMargin: 24; text: c.n && Notifs.times[c.n.id] ? (Notifs.now, Notifs.ago(Notifs.times[c.n.id])) : ""
                       font.family: c.fUi; font.pixelSize: 11; color: "#8a8fa3" }
            }
            Text { width: parent.width; text: c.n ? (c.n.summary || "") : ""; font.family: c.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: "#eceef4"
                   wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
            Text { width: parent.width; visible: text !== ""; text: c.n ? (c.n.body || "") : ""; textFormat: Text.StyledText
                   font.family: c.fUi; font.pixelSize: 12; color: "#cfd2de"; wrapMode: Text.Wrap; maximumLineCount: c.popup ? 3 : 4; elide: Text.ElideRight
                   onLinkActivated: l => Qt.openUrlExternally(l) }
            // actions
            Flow {
                width: parent.width; spacing: 6; topPadding: 4
                visible: c.n && c.n.actions.filter(a => a.identifier !== "default").length > 0
                Repeater {
                    model: c.n ? c.n.actions.filter(a => a.identifier !== "default") : []
                    Rectangle {
                        required property var modelData
                        width: at.implicitWidth + 22; height: 28; radius: 9
                        color: am.containsMouse ? Cfg.accent : "#1fffffff"
                        Text { id: at; anchors.centerIn: parent; text: parent.modelData.text; font.family: c.fUi; font.pixelSize: 12; font.weight: Font.DemiBold
                               color: am.containsMouse ? Cfg.accFg : "#eceef4" }
                        MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.modelData.invoke() }
                    }
                }
            }
        }
    }
    // close
    Rectangle {
        anchors { right: parent.right; top: parent.top; margins: 8 }
        width: 22; height: 22; radius: 11
        visible: c.hovered
        color: closeMa.containsMouse ? Cfg.acc(0.3) : "#1fffffff"
        Text { anchors.centerIn: parent; text: ""; font.family: c.fIcon; font.pixelSize: 10; color: "#eceef4" }
        MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.closeClicked() }
    }
}
