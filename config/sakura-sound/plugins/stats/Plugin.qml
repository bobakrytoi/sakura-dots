import QtQuick
import "../.."

Item {
    id: pl
    property var api: null
    onApiChanged: if (api) api.addPage({ p: "stats", icon: "chart", label: Theme.tr("Statistics"), component: page })
    Component {
        id: page
        Flickable {
            id: fp
            property int days: 7
            property var data: ({ tracks: [], artists: [], minutes: 0 })
            function load() { Sound.send("stats", { days: days }, r => { if (!r.err) fp.data = r; }); }
            onDaysChanged: load()
            Component.onCompleted: load()
            contentHeight: col.implicitHeight + 50
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                x: 28; y: 24; width: fp.width - 56; spacing: 18
                Text { text: Theme.tr("Statistics"); color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 30; font.weight: Font.ExtraBold }
                Seg { options: [{ v: 7, t: "7 d" }, { v: 30, t: "30 d" }, { v: 365, t: "1 y" }]; value: fp.days; onPicked: v => fp.days = v }
                Row {
                    spacing: 12
                    Repeater {
                        model: [{ n: fp.data.minutes, t: "minutes listened" }, { n: fp.data.tracks.length, t: "Tracks" }, { n: fp.data.artists.length, t: "Artists" }]
                        Rectangle {
                            required property var modelData
                            width: 180; height: 92; radius: 18; color: Theme.card
                            Column { x: 18; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                Text { text: modelData.n; color: Theme.accent; font.family: Theme.fontHead; font.pixelSize: 30; font.weight: Font.ExtraBold; font.features: { "tnum": 1 } }
                                Text { text: Theme.tr(modelData.t); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12 } }
                        }
                    }
                }
                Text { text: Theme.tr("Top artists"); color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 19; font.weight: Font.Bold; visible: fp.data.artists.length > 0 }
                Flow {
                    width: parent.width; spacing: 16
                    Repeater {
                        model: Math.min(8, fp.data.artists.length)
                        Column {
                            required property int index
                            readonly property var a: fp.data.artists[index]
                            width: 110; spacing: 6
                            Cover { width: 110; height: 110; style: "circle"; src: Theme.small(a.art, 300)
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pl.api.openArtist(a.id) } }
                            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: a.name; elide: Text.ElideRight; color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: a.plays + "×"; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11 }
                        }
                    }
                }
                Text { text: Theme.tr("Top tracks"); color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 19; font.weight: Font.Bold; visible: fp.data.tracks.length > 0 }
                Column {
                    width: parent.width
                    Repeater {
                        model: Math.min(20, fp.data.tracks.length)
                        Row2 {
                            required property int index
                            width: col.width
                            item: fp.data.tracks[index].track
                            num: index + 1
                            onActivated: { const all = fp.data.tracks.map(x => x.track); Sound.playList(all, index); }
                            onMenu: (x, y) => { if (pl.api && pl.api.app) pl.api.app.menuFor(item, mapToItem(pl.api.app, x, y)); }
                        }
                    }
                }
                Text { visible: !fp.data.tracks.length; text: Theme.tr("Nothing found"); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 13 }
            }
        }
    }
}
