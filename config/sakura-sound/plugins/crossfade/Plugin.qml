// Gapless playback (mpv gapless-audio). The two-mpv crossfade that lived here was removed: too fragile.
import QtQuick
import "../.."

Item {
    id: pl
    property var api: null
    readonly property string gapless: api ? api.get("gapless", "weak") : "weak"
    function push() { if (api) api.send("gapless", { mode: gapless }); }
    onApiChanged: push()
    onGaplessChanged: push()
    Connections { target: Sound; function onReadyChanged() { if (Sound.ready) pl.push(); } }
}
