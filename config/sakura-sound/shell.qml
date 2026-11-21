// Sakura Sound - SoundCloud player for the sakura rice.
//   qs -n -d -p ~/.config/sakura-sound      (or `sakura-sound`)
//   qs -p ~/.config/sakura-sound ipc call sound toggle|show|hide|play-pause|next|prev
// Closing the window only hides it; music keeps playing.
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root
    property bool shown: Quickshell.env("SAKURA_SOUND_HIDDEN") !== "1"
    property bool warned: false

    // cookies stale / not signed in → one notice in the shell's notch, click opens the sign-in page
    Connections {
        target: Sound
        function onAuthChanged() {
            if (Sound.auth.ok || !Sound.auth.browser || root.warned || Sound.auth.err) return;
            root.warned = true;
            Quickshell.execDetached(["qs", "ipc", "call", "notice", "file", "info", "Sign in to SoundCloud in Brave", "https://soundcloud.com/signin"]);
        }
    }

    FloatingWindow {
        id: win
        title: "Sakura Sound"
        visible: root.shown
        implicitWidth: 1240
        implicitHeight: 800
        minimumSize: Qt.size(860, 560)
        color: Theme.glass
        onVisibleChanged: if (!visible) root.shown = false
        App { id: appItem; anchors.fill: parent; focus: true }
        Component.onCompleted: Sound.smooth = true
    }

    // app icon follows the system accent (same mark as in the sidebar)
    Process { id: iconGen; command: [Theme.dir + "/make-icon.sh", String(Theme.sysAccent)] }
    Connections { target: Theme; function onSysAccentChanged() { iconT.restart(); } }
    Timer { id: iconT; interval: 1500; running: true; onTriggered: iconGen.running = true }

    IpcHandler {
        target: "sound"
        function toggle(): void { root.shown = !root.shown; }
        function open(): void { root.shown = true; }   // not "show": that is a qs ipc subcommand
        function hide(): void { root.shown = false; }
        function playPause(): void { Sound.toggle(); }
        function next(): void { Sound.next(); }
        function prev(): void { Sound.prev(); }
        function page(p: string): void { root.shown = true; appItem.go({ p: p }, true); }
        function browser(b: string): void { Sound.send("auth", { browser: b }); }
        function state(): string { return (Sound.playing ? "playing" : "paused") + (Sound.track ? " · " + Sound.track.title + " - " + Sound.track.artist : ""); }
    }
}
