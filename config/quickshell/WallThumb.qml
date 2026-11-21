// sakura mono - preview of a wallpaper file: pictures load directly, videos get a cached frame
// from hypr/scripts/wallthumb.sh. Set `live: true` to play a video instead (muted, looping).
import Quickshell
import Quickshell.Io
import QtQuick
import QtMultimedia

Item {
    id: t
    property string file: ""
    property int size: 480                 // thumbnail width in px
    property bool live: false
    property int fillMode: Image.PreserveAspectCrop
    readonly property bool isVideo: /\.(mp4|webm|mkv|mov)$/i.test(file)
    property string still: ""
    readonly property bool ready: img.status === Image.Ready

    onFileChanged: load()
    Component.onCompleted: load()
    function load() {
        still = "";
        // test the file itself: on a file change the isVideo binding may not have updated yet (the still was skipped)
        if (file === "" || !/\.(mp4|webm|mkv|mov)$/i.test(file)) return;
        proc.running = false;
        proc.command = [Quickshell.env("HOME") + "/.config/hypr/scripts/wallthumb.sh", file, String(size)];
        proc.running = true;
    }
    Process { id: proc; stdout: StdioCollector { onStreamFinished: t.still = this.text.trim() } }

    Image {
        id: img
        anchors.fill: parent
        source: t.file === "" || (t.isVideo && t.still === "") ? "" : "file://" + (t.isVideo ? t.still : t.file)
        visible: t.still !== "" || !t.isVideo
        fillMode: t.fillMode
        asynchronous: true
        sourceSize.width: t.size
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    Loader {
        anchors.fill: parent
        active: false     // previews and banners never play the video (like iNiR): only the desktop does - `live` is kept for callers
        sourceComponent: Video {
            source: "file://" + t.file
            loops: MediaPlayer.Infinite; muted: true
            fillMode: t.fillMode === Image.PreserveAspectFit ? VideoOutput.PreserveAspectFit : VideoOutput.PreserveAspectCrop
            Component.onCompleted: play()
        }
    }
}
