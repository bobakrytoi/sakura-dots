// sakura mono - one ordered list for ModHub: a Flow of chips (row or grid), order = how they stand.
// chip: a Component whose root has `property string mid` and `property var slot` (set here) and a DragArea inside.
import QtQuick

Flow {
    id: ds
    property var hub: null
    property var catalog: []          // [{ id, name, icon, needs? }]
    property var value: []            // ids in order
    property int max: 0               // 0 = no limit
    property int min: 0
    property bool rtl: false
    property var look: null           // optional id → { glyph, label } for the dragged chip
    property Component chip
    signal changed(var v)
    layoutDirection: rtl ? Qt.RightToLeft : Qt.LeftToRight

    readonly property var unused: catalog.filter(c => !value.includes(c.id) && Cfg.available(c)).map(c => c.id)
    readonly property bool full: max > 0 && value.length >= max
    function add(id) { if (!value.includes(id) && !full) changed(value.concat([id])); }
    function remove(id) { if (value.length > min) changed(value.filter(x => x !== id)); }
    // width of all chips in one line (a one-row list sets width: rowWidth)
    readonly property real rowWidth: {
        let w = 0;
        for (let k = 0; k < rep.count; k++) { const l = rep.itemAt(k); if (l) w += l.width + (k > 0 ? spacing : 0); }
        return Math.ceil(w) + 1;
    }
    function chips() { const out = []; for (let k = 0; k < rep.count; k++) { const l = rep.itemAt(k); if (l && l.item) out.push(l.item); } return out; }
    function nameOf(id) { const c = catalog.find(x => x.id === id); return c ? Cfg.tr(c.name) : id; }
    function iconOf(id) { const c = catalog.find(x => x.id === id); return c ? (c.icon || "") : ""; }

    Component.onCompleted: if (hub) hub.register(ds)
    onHubChanged: if (hub) hub.register(ds)

    Repeater {
        id: rep
        model: ds.value
        delegate: Loader {
            required property string modelData
            sourceComponent: ds.chip
            onLoaded: { item.slot = ds; item.mid = modelData; }
        }
    }
}
