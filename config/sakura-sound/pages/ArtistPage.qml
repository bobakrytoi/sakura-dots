// Artist: banner/avatar header, tabs Popular · Tracks · Albums · Playlists · Reposts · Likes
import QtQuick
import QtQuick.Effects
import ".."

Item {
    id: ap
    property var app: null
    property var page: ({})
    property var user: null
    property string tab: "user_top"
    readonly property var tabs: [
        { v: "user_top", t: "Popular" }, { v: "user_tracks", t: "Tracks" }, { v: "user_albums", t: "Albums" },
        { v: "user_playlists", t: "Playlists" }, { v: "user_reposts", t: "Reposts" }, { v: "user_likes", t: "Likes" }
    ]
    Component.onCompleted: Qt.callLater(() => {
        Sound.send("user", { uid: page.uid }, r => { if (!r.err) ap.user = r.user; });
        load();
    })
    onTabChanged: load()
    function load() { const t = tab, uid = page.uid; list.numbered = t === "user_top"; list.kind = t; list.loader = (n, cb) => Sound.list(t, uid, cb, n); }

    ItemList {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 16; anchors.rightMargin: 16
        app: ap.app
        header: Column {
            width: list.width
            spacing: 16
            bottomPadding: 10
            Item {
                width: parent.width; height: 230
                Image {
                    id: ban
                    anchors.fill: parent
                    source: ap.user ? (ap.user.banner || Theme.small(ap.user.avatar, 300)) : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 1000
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent; source: ban
                    visible: ban.status === Image.Ready
                    blurEnabled: !(ap.user && ap.user.banner); blur: 0.9; blurMax: 48
                    opacity: 0.55
                    maskEnabled: true
                    maskSource: ShaderEffectSource { sourceItem: Rectangle { width: ban.width; height: ban.height; radius: 18 } hideSource: true }
                }
                Rectangle { anchors.fill: parent; radius: 18
                    gradient: Gradient { GradientStop { position: 0.3; color: "transparent" } GradientStop { position: 1; color: "#cc0b0c12" } } }
                Row {
                    anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 22
                    spacing: 20
                    Cover { width: 128; height: 128; style: "circle"; src: ap.user ? Theme.small(ap.user.avatar, 300) : "" }
                    Column {
                        anchors.bottom: parent.bottom
                        spacing: 6
                        Text { visible: ap.user && ap.user.verified; text: "✓ Verified"; color: Theme.accent; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.Bold }
                        Text { text: ap.user ? ap.user.name : ""; color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 36; font.weight: Font.ExtraBold }
                        Text { text: ap.user ? Theme.num(ap.user.followers) + " " + Theme.tr("followers") + " · " + ap.user.tracks + " " + Theme.tr("tracks") + (ap.user.city ? " · " + ap.user.city : "") : ""
                               color: Theme.a(Theme.fg, 0.75); font.family: Theme.fontUi; font.pixelSize: 13 }
                    }
                }
            }
            Row {
                x: 12; spacing: 10
                Rectangle {
                    visible: list.tracks.length > 0
                    width: 104; height: 38; radius: 19; color: Theme.accent
                    Row { anchors.centerIn: parent; spacing: 6
                        Ico { name: "play"; size: 18; color: Theme.accFg }
                        Text { text: Theme.tr("Play"); color: Theme.accFg; font.family: Theme.fontUi; font.pixelSize: 14; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Sound.playList(list.tracks, 0) }
                }
                Btn { visible: list.tracks.length > 1; icon: "shuffle"; size: 38; onClicked: { if (!Sound.shuffle) Sound.setShuffle(); Sound.playList(list.tracks, Math.floor(Math.random() * list.tracks.length)); } }
                Rectangle {
                    readonly property bool fol: ap.user && Sound.isFollowing(ap.user.id)
                    visible: !!ap.user && (!Sound.me || Sound.me.id !== ap.user.id)
                    width: fT.implicitWidth + 30; height: 38; radius: 19
                    color: fol ? (fMa.containsMouse ? Theme.cardHi : Theme.card) : "transparent"
                    border.width: fol ? 0 : 1; border.color: fMa.containsMouse ? Theme.fg : Theme.a(Theme.fg, 0.4)
                    Text { id: fT; anchors.centerIn: parent; text: Theme.tr(parent.fol ? "Subscribed" : "Follow"); color: Theme.fg
                           font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Bold }
                    MouseArea { id: fMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Sound.follow(ap.user.id, undefined, ap.user) }
                }
                Btn { icon: "open"; size: 38; tint: Theme.muted; onClicked: if (ap.user) Sound.openUrl(ap.user.url) }
            }
            Flow {
                x: 12; width: parent.width - 24; spacing: 8
                Repeater {
                    model: ap.tabs
                    Rectangle {
                        required property var modelData
                        readonly property bool on: ap.tab === modelData.v
                        width: tt.implicitWidth + 28; height: 32; radius: 16
                        color: on ? Theme.accent : tMa.containsMouse ? Theme.cardHi : Theme.card
                        Text { id: tt; anchors.centerIn: parent; text: Theme.tr(modelData.t); color: parent.on ? Theme.accFg : Theme.fg
                               font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                        MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ap.tab = modelData.v }
                    }
                }
            }
        }
    }
}
