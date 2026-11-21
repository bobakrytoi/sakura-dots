// Icon by name (Symbols Nerd Font, Material Design range).
import QtQuick

Text {
    id: ic
    property string name: ""
    property int size: 18
    readonly property var map: ({
        play: 0xF040A, pause: 0xF03E4, next: 0xF04AD, prev: 0xF04AE, shuffle: 0xF049D,
        repeat: 0xF0456, repeatOne: 0xF0458, repeatOff: 0xF0457,
        vol: 0xF057E, volMid: 0xF0580, volLow: 0xF057F, volOff: 0xF0581,
        heart: 0xF02D1, heartO: 0xF02D5, search: 0xF0349, home: 0xF02DC, queue: 0xF0CB8,
        library: 0xF0333, back: 0xF0141, down: 0xF0140, more: 0xF01D9, close: 0xF0156,
        user: 0xF0004, users: 0xF000E, palette: 0xF03D8, cog: 0xF0493, history: 0xF02DA,
        radio: 0xF0439, link: 0xF0337, open: 0xF03CC, plus: 0xF0415, playNext: 0xF0412,
        album: 0xF0025, timer: 0xF051B, moon: 0xF0594, lyrics: 0xF10D, expand: 0xF065,
        collapse: 0xF066, plug: 0xF1E6, feed: 0xF09E, chart: 0xF080, eq: 0xF1DE, menu: 0xF0C9
    })
    text: map[name] ? String.fromCodePoint(map[name]) : name
    font.family: Theme.fIcon
    font.pixelSize: size
    color: Theme.fg
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
