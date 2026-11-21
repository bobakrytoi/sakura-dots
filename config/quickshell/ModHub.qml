// sakura mono - drag & drop of ordered lists in Settings (bar wings, island, start menu, keyboard layouts).
// One hub per page: DropSlot = an ordered list (a Flow of chips), DragArea = the grip inside a chip,
// ModPalette = the items not in use (drop a chip there = take it away). The hub draws the caret where a chip
// lands and the chip under the mouse. A chip only moves inside its own list (lists may share ids, e.g. "lock").
// Put the hub anywhere on the page with a high z; it has no size, everything is mapped into it.
import QtQuick

Item {
    id: hub
    width: 0; height: 0
    z: 100

    property var slots: []
    property var palettes: []
    function register(s) { if (!slots.includes(s)) slots = slots.concat([s]); }
    function registerPalette(p) { if (!palettes.includes(p)) palettes = palettes.concat([p]); }

    // a click on a chip in a list (not dragged): the page may open its options
    property var selSlot: null
    property string sel: ""
    function click(slot, id) { if (selSlot === slot && sel === id) { sel = ""; selSlot = null; } else { selSlot = slot; sel = id; } }
    function isSel(slot, id) { return selSlot === slot && sel === id; }

    property string dragId: ""
    property var dragSlot: null
    property bool fromPalette: false
    property real gx: 0
    property real gy: 0
    property int dropIdx: -1
    property real caretX: 0
    property real caretY: 0
    property real caretH: 0
    property var overPalette: null
    property string ghostGlyph: ""
    property string ghostText: ""

    function begin(id, slot, pal) {
        dragId = id; dragSlot = slot; fromPalette = pal; sel = ""; selSlot = null;
        const c = slot.catalog.find(x => x.id === id) || { name: id, icon: "" };
        const lk = slot.look ? slot.look(id) : null;
        ghostGlyph = lk && lk.glyph !== undefined ? lk.glyph : (c.icon || "");
        ghostText = lk && lk.label ? lk.label : Cfg.tr(c.name);
    }
    function inside(it, x, y, pad) {
        const a = it.mapToItem(hub, 0, 0), b = it.mapToItem(hub, it.width, it.height);
        return x >= a.x - pad && x <= b.x + pad && y >= a.y - pad && y <= b.y + pad;
    }
    function move(item, mx, my) {
        const p = item.mapToItem(hub, mx, my), x = p.x, y = p.y;
        gx = x; gy = y; dropIdx = -1;
        overPalette = null;
        if (!fromPalette) for (const pl of palettes) if (pl.visible && pl.slots.includes(dragSlot) && inside(pl, x, y, 6)) overPalette = pl;
        const s = dragSlot;
        if (!s || overPalette) return;
        if (fromPalette && s.max > 0 && s.value.length >= s.max) return;
        // the list's area (an empty one still takes drops)
        const a = s.mapToItem(hub, 0, 0), b = s.mapToItem(hub, Math.max(s.width, 40), Math.max(s.height, 20));
        if (x < a.x - 50 || x > b.x + 50 || y < a.y - 30 || y > b.y + 30) return;
        const chips = [];
        for (const ch of s.chips()) {
            if (ch.mid === dragId) continue;
            const c0 = ch.mapToItem(hub, 0, 0), c1 = ch.mapToItem(hub, ch.width, ch.height);
            chips.push({ x: c0.x, y: c0.y, w: c1.x - c0.x, h: c1.y - c0.y });
        }
        const rtl = s.rtl;
        let idx = 0;
        for (const c of chips) {
            const above = c.y + c.h < y, sameRow = !above && c.y <= y + c.h / 2;
            if (above || (sameRow && (rtl ? c.x + c.w / 2 > x : c.x + c.w / 2 < x))) idx++;
        }
        dropIdx = idx;
        if (chips.length === 0) { caretX = a.x + 4; caretY = a.y; caretH = Math.max(18, b.y - a.y); return; }
        const ref = idx === 0 ? chips[0] : chips[idx - 1];
        caretY = ref.y; caretH = ref.h;
        if (idx === 0) caretX = rtl ? ref.x + ref.w + 2 : ref.x - 2;
        else caretX = rtl ? ref.x - 2 : ref.x + ref.w + 2;
    }
    function end() {
        const s = dragSlot, id = dragId;
        if (s) {
            if (dropIdx >= 0) { const v = s.value.filter(x => x !== id); v.splice(dropIdx, 0, id); s.changed(v); }
            else if (overPalette) s.remove(id);
        }
        dragId = ""; dragSlot = null; dropIdx = -1; overPalette = null;
    }

    Rectangle {     // where it lands
        visible: hub.dragId !== "" && hub.dropIdx >= 0
        x: hub.caretX - 1.5; y: hub.caretY - 2
        width: 3; height: hub.caretH + 4; radius: 1.5
        color: Cfg.accent
    }
    Rectangle {     // the chip under the mouse
        visible: hub.dragId !== ""
        x: hub.gx - width / 2; y: hub.gy - height / 2
        width: gRow.implicitWidth + 22; height: 30; radius: 10
        color: Qt.rgba(15 / 255, 17 / 255, 25 / 255, 0.92); border.width: 1; border.color: Cfg.acc(0.8)
        Row {
            id: gRow; anchors.centerIn: parent; spacing: 6
            Text { visible: text !== ""; text: hub.ghostGlyph; font.family: "Symbols Nerd Font"; font.pixelSize: 13; color: Cfg.accent; anchors.verticalCenter: parent.verticalCenter }
            Text { text: hub.ghostText; color: "#eceef4"; font.family: Cfg.fontUi; font.pixelSize: 12; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
