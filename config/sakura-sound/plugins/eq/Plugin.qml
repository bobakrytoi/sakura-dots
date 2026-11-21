import QtQuick
import "../.."

Item {
    id: pl
    property var api: null
    readonly property var freqs: [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    readonly property var presets: ({
        "Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass": [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
        "Bass+treble": [5, 4, 2, 0, -1, -1, 0, 2, 4, 5],
        "Vocal": [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
        "Phonk": [7, 6, 3, 0, -2, -1, 1, 3, 4, 3],
        "Lo-fi": [2, 2, 1, 0, -1, -2, -3, -4, -6, -8],
        "Night": [-3, -2, -1, 0, 0, 0, -1, -2, -4, -6]
    })
    readonly property var bands: api ? (api.config.bands || presets["Flat"]) : presets["Flat"]
    readonly property string norm: api ? api.get("norm", "off") : "off"
    onApiChanged: if (api) {
        api.addSideTab({ id: "eq", icon: "eq", label: "Equalizer", component: panel });
        api.addPlayerButton({ icon: "eq", on: () => pl.api.app.side === "eq", act: () => pl.api.app.toggleSide("eq") });
        apply();
    }
    onNormChanged: apply()
    function setBand(i, g) { const b = bands.slice(); b[i] = g; api.set("bands", b); api.set("preset", ""); applyT.restart(); }
    function setPreset(n) { api.set("bands", presets[n].slice()); api.set("preset", n); applyT.restart(); }
    Timer { id: applyT; interval: 120; onTriggered: pl.apply() }
    function apply() {
        if (!api) return;
        const parts = [];
        for (let i = 0; i < 10; i++) if (Math.abs(bands[i]) > 0.05) parts.push("equalizer=f=" + freqs[i] + ":t=o:w=1:g=" + bands[i]);
        api.af("eq", parts.length ? "@eq:lavfi=[" + parts.join(",") + "]" : "");
        api.af("norm", norm === "dyn" ? "@norm:lavfi=[dynaudnorm=f=250:g=15:p=0.9]" : norm === "loud" ? "@norm:lavfi=[loudnorm=I=-14:TP=-1.5:LRA=11]" : "");
    }
    Component.onDestruction: if (api) { api.af("eq", ""); api.af("norm", ""); }

    Component {
        id: panel
        Item {
            Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Theme.line }
            Text { x: 20; y: 18; text: Theme.tr("Equalizer"); color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 17; font.weight: Font.Bold }
            Flow {
                x: 20; y: 56; width: parent.width - 40; spacing: 6
                Repeater {
                    model: Object.keys(pl.presets)
                    Rectangle {
                        required property string modelData
                        readonly property bool on: pl.api && pl.api.config.preset === modelData
                        width: pT.implicitWidth + 20; height: 28; radius: 14
                        color: on ? Theme.accent : pMa.containsMouse ? Theme.cardHi : Theme.card
                        Text { id: pT; anchors.centerIn: parent; text: modelData; color: parent.on ? Theme.accFg : Theme.fg; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
                        MouseArea { id: pMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pl.setPreset(modelData) }
                    }
                }
            }
            Row {
                id: sliders
                anchors.horizontalCenter: parent.horizontalCenter
                y: 160; height: parent.height - 250
                spacing: (parent.width - 40 - 10 * 16) / 9
                Repeater {
                    model: 10
                    Item {
                        required property int index
                        readonly property real g: pl.bands[index] || 0
                        width: 16; height: sliders.height
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4; height: parent.height - 24; radius: 2; color: Theme.cardHi }
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: parent.width; height: 1; y: (parent.height - 24) / 2; color: Theme.line }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 4; radius: 2; color: Theme.accent
                            readonly property real mid: (parent.parent.height - 24) / 2
                            y: g > 0 ? mid - mid * g / 12 : mid
                            height: Math.abs(mid * g / 12)
                        }
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 14; height: 14; radius: 7; color: Theme.fg
                                    y: (parent.height - 24) / 2 * (1 - g / 12) - 7 }
                        Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                               text: pl.freqs[index] >= 1000 ? pl.freqs[index] / 1000 + "k" : pl.freqs[index]; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 10 }
                        MouseArea {
                            anchors.fill: parent; anchors.bottomMargin: 24; anchors.leftMargin: -6; anchors.rightMargin: -6
                            cursorShape: Qt.PointingHandCursor
                            function at(y) { return Math.round(Math.max(-12, Math.min(12, (1 - y / (height / 2)) * 12))); }
                            onPressed: m => pl.setBand(index, at(m.y))
                            onPositionChanged: m => { if (pressed) pl.setBand(index, at(m.y)); }
                            onDoubleClicked: pl.setBand(index, 0)
                        }
                    }
                }
            }
            Column {
                x: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 20; spacing: 8
                Text { text: Theme.tr("Normalization"); color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 12 }
                Seg { options: [{ v: "off", t: "Off" }, { v: "dyn", t: "Dynamic" }, { v: "loud", t: "Loudness" }]; value: pl.norm; onPicked: v => pl.api.set("norm", v) }
            }
        }
    }
}
