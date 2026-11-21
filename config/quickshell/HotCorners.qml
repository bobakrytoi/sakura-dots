// sakura mono - hot corners: push the mouse into a screen corner and hold it there a moment → an action.
// Settings > Taskbar > Hot corners (settings.json "corners" = { tl, tr, bl, br }, "cornerDelay" ms).
// Off on a screen while a window there is fullscreen (games).
// "convert" = the file converter (Convert.qml): that corner reacts to dragged files (drag enter), not to the mouse.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

Scope {
    id: hc
    property var converter: null           // Convert.qml, for the "convert" action
    readonly property var corners: Cfg.data.corners || ({})
    readonly property int delay: Cfg.data.cornerDelay || 250
    readonly property string sc: Quickshell.env("HOME") + "/.config/hypr/scripts/"
    readonly property var actions: ({
        menu:      ["sh", "-c", sc + "menu.sh"],
        dashboard: ["qs", "ipc", "call", "dashboard", "toggle"],
        notifs:    ["qs", "ipc", "call", "notifs-center", "toggle"],
        clipboard: ["qs", "ipc", "call", "clipboard", "toggle"],
        wallpaper: ["qs", "ipc", "call", "wallpicker", "toggle"],
        screenshot:["sh", "-c", sc + "screenshot.sh region"],
        mixer:     ["qs", "ipc", "call", "mixer", "toggle"],
        notes:     ["qs", "ipc", "call", "notes", "toggle"],
        lock:      ["sh", "-c", sc + "lock.sh"],
        settings:  ["qs", "ipc", "call", "settings", "toggle"]
    })
    function run(a) { const c = actions[a]; if (c) Quickshell.execDetached(c); }

    Variants {
        model: Quickshell.screens
        Scope {
            id: scr
            required property var modelData
            readonly property var hmon: Hyprland.monitorFor(modelData)
            readonly property bool fs: hmon && hmon.activeWorkspace ? hmon.activeWorkspace.hasFullscreen === true : false
            Variants {                 // (a Repeater makes nothing here: a Scope is not an Item)
                model: ["tl", "tr", "bl", "br"]
                delegate: Scope {
                    id: c
                    required property string modelData
                    readonly property string act: hc.corners[modelData] || "none"
                    PanelWindow {
                        visible: c.act !== "none" && !scr.fs
                        screen: scr.modelData
                        anchors { top: c.modelData[0] === "t"; bottom: c.modelData[0] === "b"; left: c.modelData[1] === "l"; right: c.modelData[1] === "r" }
                        implicitWidth: c.act === "convert" ? 6 : 3; implicitHeight: c.act === "convert" ? 6 : 3   // a drag gets a bit more room
                        color: "transparent"
                        exclusionMode: ExclusionMode.Ignore
                        WlrLayershell.layer: WlrLayer.Overlay
                        WlrLayershell.namespace: "hotcorner"
                        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onEntered: if (c.act !== "convert") dwell.restart()
                            onExited: dwell.stop()
                        }
                        Timer { id: dwell; interval: hc.delay; onTriggered: hc.run(c.act) }
                        // file converter: files dragged into the corner open its radial menu on this screen
                        DropArea {
                            anchors.fill: parent
                            enabled: c.act === "convert" && !!hc.converter
                            onEntered: drag => {
                                const l = hc.converter.fromUrls(drag.urls || []);
                                if (!l.length) { drag.accepted = false; return; }
                                drag.accept(Qt.CopyAction);
                                const s = scr.modelData, right = c.modelData[1] === "r";
                                hc.converter.openOn(s, l, right ? s.width : 0, c.modelData[0] === "b" ? s.height : 0, right ? "right" : "left", true, false);
                            }
                            onDropped: drop => { drop.accepted = false; }
                        }
                    }
                }
            }
        }
    }
}
