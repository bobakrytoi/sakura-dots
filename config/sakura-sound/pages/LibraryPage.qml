// Library: Liked tracks · Playlists · Albums · Stations · Following · History
import QtQuick
import ".."

Item {
    id: lib
    property var app: null
    property var page: ({})
    property string tab: "likes"
    readonly property var tabs: [
        { v: "likes", t: "Liked tracks" }, { v: "playlists", t: "Playlists" }, { v: "albums", t: "Albums" },
        { v: "stations", t: "Recently played" }, { v: "following", t: "Following" }, { v: "history", t: "History" }
    ]
    Component.onCompleted: Qt.callLater(() => { if (page.tab) tab = page.tab; load(); })
    onTabChanged: load()
    Connections { target: Sound
        function onLikesRevChanged() { if (lib.tab === "likes") list.reload(); }
        function onFollowRevChanged() { if (lib.tab === "following") list.reload(); } }

    // playlists/albums merge several sources (library/all + likes + own)
    function merged(kinds, filter, cb) {
        let left = kinds.length, acc = [], seen = {};
        for (const k of kinds) Sound.list(k, null, r => {
            if (!r.err) for (const x of r.items) if (x.type === "playlist" && filter(x) && !seen[x.id]) { seen[x.id] = true; acc.push(x); }
            if (--left === 0) cb({ items: acc, next: null });
        });
    }
    function load() {
        if (!list) return;
        const t = tab;
        list.numbered = t === "likes" || t === "history";
        list.kind = t;
        if (t === "playlists") list.loader = (n, cb) => merged(["library", "playlist_likes", "my_playlists"], x => !x.album, cb);
        else if (t === "albums") list.loader = (n, cb) => merged(["library", "playlist_likes"], x => x.album, cb);
        else if (t === "stations") list.loader = (n, cb) => Sound.list("contexts", null, cb, n);
        else list.loader = (n, cb) => Sound.list(t, null, cb, n);
    }

    ItemList {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 16; anchors.rightMargin: 16
        app: lib.app
        emptyText: Theme.tr("Nothing found")
        header: Column {
            width: list.width
            spacing: 14
            topPadding: 24; bottomPadding: 12
            Text { x: 12; text: Theme.tr("Library"); color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 30; font.weight: Font.ExtraBold }
            Flow {
                x: 12; width: parent.width - 24; spacing: 8
                Repeater {
                    model: lib.tabs
                    Rectangle {
                        required property var modelData
                        readonly property bool on: lib.tab === modelData.v
                        width: tt.implicitWidth + 28; height: 32; radius: 16
                        color: on ? Theme.accent : tMa.containsMouse ? Theme.cardHi : Theme.card
                        Text { id: tt; anchors.centerIn: parent; text: Theme.tr(modelData.t); color: parent.on ? Theme.accFg : Theme.fg
                               font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                        MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lib.tab = modelData.v }
                    }
                }
            }
            Row {
                x: 12; spacing: 10
                visible: list.tracks.length > 0
                Rectangle {
                    width: 104; height: 38; radius: 19; color: Theme.accent
                    Row { anchors.centerIn: parent; spacing: 6
                        Ico { name: "play"; size: 18; color: Theme.accFg }
                        Text { text: Theme.tr("Play"); color: Theme.accFg; font.family: Theme.fontUi; font.pixelSize: 14; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Sound.playList(list.tracks, 0) }
                }
                Btn { icon: "shuffle"; size: 38; onClicked: { if (!Sound.shuffle) Sound.setShuffle(); Sound.playList(list.tracks, Math.floor(Math.random() * list.tracks.length)); } }
            }
        }
    }
}
