// sakura mono - notification popups: glass cards in the top-right corner of the main monitor, under the bar.
// They slide in from the screen edge and leave after a few seconds (not while the mouse is on them);
// the notification itself stays in the center until dismissed there. Nothing pops up in Do not disturb.
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick

Scope {
    id: np
    PanelWindow {
        id: win
        screen: Cfg.mainScreen
        visible: Notifs.popups.length > 0 || col.children.length > 1
        readonly property string pos: Cfg.data.notifPos || "top-right"     // top-right | top-left | top-center | bottom-right
        anchors { top: pos !== "bottom-right"; bottom: pos === "bottom-right"; right: pos === "top-right" || pos === "bottom-right"; left: pos === "top-left" }
        margins { top: 50; right: 12; left: 12; bottom: 84 }
        implicitWidth: 400
        implicitHeight: Math.max(1, col.implicitHeight + 10)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: col }

        Column {
            id: col
            x: 10; width: 380
            spacing: 8
            move: Transition { NumberAnimation { properties: "y"; duration: 220 * Cfg.anim; easing.type: Easing.OutCubic } }
            Repeater {
                model: Notifs.popups
                delegate: NotifCard {
                    id: card
                    required property var modelData
                    n: modelData
                    popup: true
                    onCloseClicked: Notifs.dismiss(modelData)
                    // slide in from the edge it sits at
                    readonly property real from: win.pos === "top-left" ? -420 : win.pos === "top-center" ? 0 : 420
                    transform: Translate { id: tr; x: card.from; y: win.pos === "top-center" ? -40 : 0 }
                    Component.onCompleted: slideIn.start()
                    ParallelAnimation { id: slideIn
                        NumberAnimation { target: tr; property: "x"; from: card.from; to: 0; duration: 320 * Cfg.anim; easing.type: Easing.OutCubic }
                        NumberAnimation { target: tr; property: "y"; to: 0; duration: 320 * Cfg.anim; easing.type: Easing.OutCubic } }
                    Timer {
                        readonly property int ms: Cfg.data.ignoreAppTimeout !== true && card.n && card.n.expireTimeout > 0 ? card.n.expireTimeout : Notifs.timeout
                        interval: ms
                        running: !card.hovered && !(card.n && card.n.urgency === NotificationUrgency.Critical && Cfg.data.criticalStay !== false)
                        onTriggered: Notifs.hidePopup(card.n)
                    }
                }
            }
        }
    }
}
