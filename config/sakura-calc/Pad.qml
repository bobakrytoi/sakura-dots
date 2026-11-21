// Keypad laid out on a cols × rows grid; model items: { k: label, i: icon, id, t: kind, c, r, cs }
import QtQuick

Item {
    id: pad
    property var keys: []
    property int cols: 4
    property int rows: 5
    signal key(string id)
    readonly property real cw: width / cols
    readonly property real ch: height / rows

    function flash(id) {
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i);
            if (it && it.kid === id) it.flash();
        }
    }

    Repeater {
        id: rep
        model: pad.keys
        Key {
            required property var modelData
            x: modelData.c * pad.cw
            y: modelData.r * pad.ch
            width: (modelData.cs || 1) * pad.cw
            height: pad.ch
            label: modelData.k || ""
            icon: modelData.i ? String.fromCodePoint(modelData.i) : ""
            kid: modelData.id || modelData.k
            kind: modelData.t || "num"
            onActivated: pad.key(kid)
        }
    }
}
