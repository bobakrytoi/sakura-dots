// Paged list of tracks / playlists / users. Model = fixed ListModel that only
// grows (never rebuilt while scrolling - no flicker); rows read `items[index]`.
//   loader(next, cb): fetch a page; cb(reply) with {items, next, err}
import QtQuick

ListView {
    id: lv
    property var items: []
    property var loader: null
    property string nextTok: ""
    property bool loading: false
    property string err: ""
    property bool numbered: false
    property bool showArt: true
    property string emptyText: Theme.tr("Nothing found")
    property var app: null
    signal loaded()
    readonly property var tracks: items.filter(x => x && x.type === "track")

    model: ListModel { id: m }
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 600
    reuseItems: false
    spacing: 0

    property string kind: ""
    function filt(a) { return app && app.filterItems ? app.filterItems(a || [], kind) : (a || []); }
    function reset(arr, next) {
        items = filt(arr);
        nextTok = next || "";
        m.clear();
        for (let i = 0; i < items.length; i++) m.append({ k: i });
        Qt.callLater(() => { lv.contentY = lv.originY; });
        loaded();
    }
    function add(arr, next) {
        const base = items.length;
        const more = filt(arr);
        items = items.concat(more);
        nextTok = next || "";
        for (let i = 0; i < more.length; i++) m.append({ k: base + i });
    }
    function reload() {
        if (!loader) return;
        loading = true; err = "";
        loader("", r => { loading = false; if (r.err) { err = r.err; reset([], ""); } else reset(r.items, r.next); });
    }
    function more() {
        if (!loader || loading || !nextTok) return;
        loading = true;
        loader(nextTok, r => { loading = false; if (!r.err) add(r.items, r.next); else nextTok = ""; });
    }
    property bool _atTop: true
    onContentYChanged: { _atTop = contentY - originY < 4; if (contentHeight - contentY - height < 600) more(); }
    onOriginYChanged: if (_atTop && !moving) contentY = originY   // header grew: stay at the very top
    onLoaderChanged: reload()

    function playAt(i) {
        const t = items[i];
        if (!t) return;
        if (t.type === "track") {
            const tr = tracks;
            Sound.playList(tr, tr.indexOf(t));
        } else if (app) app.openItem(t);
    }

    delegate: Row2 {
        required property int index
        width: lv.width
        item: lv.items[index]
        num: lv.numbered ? index + 1 : 0
        showArt: lv.showArt
        onActivated: lv.playAt(index)
        onMenu: (x, y) => { if (lv.app) lv.app.menuFor(item, mapToItem(lv.app, x, y)); }
    }

    footer: Item {
        width: lv.width
        height: lv.loading || lv.err || lv.items.length === 0 ? 120 : 24
        Text {
            anchors.centerIn: parent
            visible: !lv.loading && lv.items.length === 0
            text: lv.err ? Theme.tr("Couldn't load") : lv.emptyText
            color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 13
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.verticalCenter; anchors.topMargin: 14
            visible: !!lv.err && !lv.loading
            text: Theme.tr("Retry"); color: Theme.accent; font.family: Theme.fontUi; font.pixelSize: 12
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: lv.reload() }
        }
        Spinner { anchors.centerIn: parent; visible: lv.loading }
    }
}
