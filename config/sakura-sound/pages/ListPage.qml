// Generic collection page: {p: "list", kind, arg, title}
import QtQuick
import ".."

ItemList {
    id: lp
    property var page: ({})
    numbered: true
    kind: page.kind || ""
    Component.onCompleted: Qt.callLater(() => { loader = (next, cb) => Sound.list(lp.page.kind, lp.page.arg || null, cb, next); })
    header: PageHead {
        width: lp.width
        title: lp.page.title || ""
        sub: lp.items.length ? lp.items.length + (lp.nextTok ? "+" : "") + " " + Theme.tr("tracks") : ""
        tracks: lp.tracks
    }
}
