import QtQuick
import ".."

Flickable {
    id: hp
    property var app: null
    property var page: ({})
    contentHeight: col.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    property var recent: []
    property var likes: []
    property var feed: []
    property var shelves: []
    property var mine: []
    Connections { target: Sound; function onLikesRevChanged() { Sound.list("likes", null, r => { if (!r.err) hp.likes = r.items.slice(0, 20); }); }
                                 function onFollowRevChanged() { Sound.send("local_feed", {}, r => { if (!r.err) hp.mine = r.items; }); } }
    property bool loadedOnce: false
    function load() {
        Sound.list("history", null, r => { if (!r.err) hp.recent = hp.dedupe(r.items).slice(0, 20); });
        Sound.list("likes", null, r => { if (!r.err) hp.likes = r.items.slice(0, 20); });
        Sound.list("feed", null, r => { if (!r.err) hp.feed = (hp.app ? hp.app.filterItems(r.items, "feed") : r.items).filter(x => x.type === "track").slice(0, 20); });
        Sound.send("local_feed", {}, r => { if (!r.err) hp.mine = r.items; });
        Sound.send("home", {}, r => { if (!r.err) hp.shelves = r.shelves.filter(x => !/recently played/i.test(x.title)); });
        loadedOnce = true;
    }
    function dedupe(a) { const s = {}; return a.filter(x => x && !s[x.id] && (s[x.id] = true)); }
    Component.onCompleted: Qt.callLater(() => { if (Sound.ready) load(); })
    Connections { target: Sound; function onAuthChanged() { hp.load(); } }

    readonly property string greet: {
        const h = new Date().getHours();
        return Theme.tr(h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening");
    }

    Column {
        id: col
        x: 28; y: 26
        width: hp.width - 56
        spacing: 30

        Text { text: hp.greet + (Sound.me ? ", " + Sound.me.name : ""); color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 30; font.weight: Font.ExtraBold }

        // continue: the current queue around the playing track
        Shelf {
            width: col.width; app: hp.app; title: Theme.tr("Continue")
            items: (Sound.queueRev, Sound.queue.slice(Math.max(0, Sound.idx), Math.max(0, Sound.idx) + 20))
        }
        Shelf { width: col.width; app: hp.app; title: Theme.tr("Recently played"); items: hp.recent
                action: Theme.tr("Show all"); onShowAll: hp.app.go({ p: "list", kind: "history", title: Theme.tr("History") }) }
        Shelf { width: col.width; app: hp.app; title: Theme.tr("Liked tracks"); items: hp.likes
                action: Theme.tr("Show all"); onShowAll: hp.app.go({ p: "list", kind: "likes", title: Theme.tr("Liked tracks") }) }
        Shelf { width: col.width; app: hp.app; title: Theme.tr("From people you follow"); items: hp.feed
                action: Theme.tr("Show all"); onShowAll: hp.app.go({ p: "list", kind: "feed", title: Theme.tr("Feed") }) }
        Shelf { width: col.width; app: hp.app; title: Theme.tr("From your artists"); items: hp.mine }
        Repeater {
            model: hp.shelves.length
            Shelf { required property int index; width: col.width; app: hp.app; title: hp.shelves[index].title; items: hp.shelves[index].items }
        }

        Column {
            visible: !Sound.signedIn && Sound.ready
            spacing: 10
            Text { text: Theme.tr("Sign in to SoundCloud in Brave"); color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 15; font.weight: Font.DemiBold }
            Rectangle { width: 150; height: 34; radius: 17; color: Theme.accent
                Text { anchors.centerIn: parent; text: "soundcloud.com"; color: Theme.accFg; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Sound.openUrl("https://soundcloud.com/signin") } }
        }
    }
}
