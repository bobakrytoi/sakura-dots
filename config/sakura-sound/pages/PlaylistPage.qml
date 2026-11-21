import QtQuick
import ".."

ItemList {
    id: pp
    property var page: ({})
    property var pl: null
    numbered: true
    Component.onCompleted: Qt.callLater(() => {
        loader = (n, cb) => Sound.send("playlist", { pid: pp.page.pid }, r => { if (!r.err) pp.pl = r.playlist; cb(r); });
    })
    header: PageHead {
        width: pp.width
        art: pp.pl ? pp.pl.art : ""
        kicker: pp.pl ? (pp.pl.album ? Theme.tr("Album") : pp.pl.system ? Theme.tr("Station") : Theme.tr("Playlist")) : ""
        title: pp.pl ? pp.pl.title : (pp.page.title || "")
        sub: pp.pl ? [pp.pl.artist, pp.tracks.length + " " + Theme.tr("tracks"), pp.pl.dur ? Theme.time(pp.pl.dur) : ""].filter(x => x).join(" · ") : ""
        tracks: pp.tracks
        Btn { icon: "user"; size: 40; tint: Theme.muted; visible: pp.pl && pp.pl.artistId; onClicked: pp.app.openArtist(pp.pl.artistId) }
        Btn { icon: "open"; size: 40; tint: Theme.muted; visible: pp.pl && pp.pl.url; onClicked: Sound.openUrl(pp.pl.url) }
    }
}
