// Page header: optional art, kicker, big title, subtitle, Play / Shuffle.
import QtQuick
import ".."

Item {
    id: ph
    property string title: ""
    property string kicker: ""
    property string sub: ""
    property string art: ""
    property bool round: false
    property var tracks: []
    default property alias extra: extraRow.data
    height: (art ? 220 : 140) + 8

    Row {
        x: 28; y: 24
        spacing: 24
        Cover { visible: ph.art !== ""; width: 180; height: 180; src: ph.art; style: ph.round ? "circle" : "rounded"; forceRounded: !ph.round }
        Column {
            anchors.bottom: parent.bottom
            spacing: 8
            width: ph.width - (ph.art ? 260 : 56)
            Text { visible: ph.kicker !== ""; text: ph.kicker; color: Theme.accent; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.1; font.capitalization: Font.AllUppercase }
            Text { width: parent.width; text: ph.title; elide: Text.ElideRight; color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: ph.art ? 34 : 30; font.weight: Font.ExtraBold }
            Text { visible: ph.sub !== ""; width: parent.width; text: ph.sub; elide: Text.ElideRight; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 13 }
            Row {
                id: extraRow
                spacing: 10; topPadding: 6
                Rectangle {
                    visible: ph.tracks.length > 0
                    width: 104; height: 40; radius: 20; color: Theme.accent
                    Row { anchors.centerIn: parent; spacing: 6
                        Ico { name: "play"; size: 18; color: Theme.accFg }
                        Text { text: Theme.tr("Play"); color: Theme.accFg; font.family: Theme.fontUi; font.pixelSize: 14; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Sound.playList(ph.tracks, 0) }
                }
                Btn { visible: ph.tracks.length > 1; icon: "shuffle"; size: 40; tint: Theme.fg
                      onClicked: { const a = ph.tracks.slice(); const i = Math.floor(Math.random() * a.length); if (!Sound.shuffle) Sound.setShuffle(); Sound.playList(a, i); } }
            }
        }
    }
}
