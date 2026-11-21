// Unit / currency picker: dim backdrop + glass sheet with a grid; typing filters.
import QtQuick
import "Calc.js" as Calc

Item {
    id: pk
    property bool open: false
    property string side: "from"
    property string filter: ""
    visible: k > 0.01
    property real k: open ? 1 : 0
    Behavior on k { NumberAnimation { duration: Theme.ms(240); easing.type: Easing.OutCubic } }

    readonly property string cur: side === "from" ? app.fromU : app.toU
    readonly property var items: {
        let l = [];
        if (app.convCat === "currency") {
            const all = app.fx ? Object.keys(app.fx) : [];
            const top = Calc.CURRENCY_TOP.filter(c => !app.fx || app.fx[c]);
            l = top.concat(all.filter(c => top.indexOf(c) < 0).sort()).map(c => {
                const n = Calc.CURRENCY_NAMES[c];
                return { id: c, name: n ? n[Theme.lang === "ru" ? 0 : 1] : "" };
            });
        } else if (app.cat) {
            l = app.cat.units.map(u => ({ id: u[0], name: u[Theme.lang === "ru" ? 2 : 3] }));
        }
        const f = filter.toLowerCase();
        return f ? l.filter(u => u.id.toLowerCase().indexOf(f) >= 0 || u.name.toLowerCase().indexOf(f) >= 0) : l;
    }

    function show(s) { side = s; filter = ""; open = true; grab.forceActiveFocus(); }
    function hide() { open = false; app.focusInput(); }
    function choose(id) { app.setUnit(side, id); hide(); }
    function handleKey(ev) {
        if (ev.key === Qt.Key_Escape) { if (filter) filter = ""; else hide(); }
        else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { if (items.length) choose(items[Math.max(0, grid.currentIndex)].id); }
        else if (ev.key === Qt.Key_Backspace) filter = filter.slice(0, -1);
        else if (ev.key === Qt.Key_Left) grid.moveCurrentIndexLeft();
        else if (ev.key === Qt.Key_Right) grid.moveCurrentIndexRight();
        else if (ev.key === Qt.Key_Up) grid.moveCurrentIndexUp();
        else if (ev.key === Qt.Key_Down) grid.moveCurrentIndexDown();
        else if (ev.text && /\S/.test(ev.text) && !(ev.modifiers & Qt.ControlModifier)) filter += ev.text;
        ev.accepted = true;
    }
    onFilterChanged: grid.currentIndex = 0

    Item { id: grab; focus: pk.open; Keys.onPressed: ev => pk.handleKey(ev) }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45 * pk.k)
        MouseArea { anchors.fill: parent; enabled: pk.open; onClicked: pk.hide() }
    }

    Rectangle {
        id: sheet
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 14 + (1 - pk.k) * 40
        opacity: pk.k
        width: Math.min(parent.width - 28, 520)
        height: Math.min(parent.height * 0.72, 470)
        radius: 22
        color: Qt.tint(Qt.rgba(17 / 255, 19 / 255, 28 / 255, 0.985), Theme.a(Theme.accent, 0.05))
        border.width: 1; border.color: Theme.a(Theme.accent, 0.14)
        MouseArea { anchors.fill: parent }   // swallow clicks

        Text {
            id: ftext
            x: 18; y: 14
            width: parent.width - 36
            height: pk.filter ? 30 : 4
            text: pk.filter
            font.family: Theme.fDisplay; font.pixelSize: 22
            color: Theme.accent
            Behavior on height { NumberAnimation { duration: 140 } }
        }

        GridView {
            id: grid
            anchors { fill: parent; topMargin: ftext.y + ftext.height + 6; leftMargin: 10; rightMargin: 10; bottomMargin: 10 }
            clip: true
            cellWidth: width / Math.max(2, Math.floor(width / 150))
            cellHeight: 58
            model: pk.items
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: 0
            highlightFollowsCurrentItem: true
            delegate: Item {
                id: ud
                required property var modelData
                required property int index
                width: grid.cellWidth; height: grid.cellHeight
                readonly property bool sel: modelData.id === pk.cur
                Rectangle {
                    anchors.fill: parent; anchors.margins: 3
                    radius: 14
                    color: ud.sel ? Theme.a(Theme.accent, 0.2)
                        : uma.containsMouse || (grid.currentIndex === ud.index && pk.filter) ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03)
                    border.width: 1; border.color: ud.sel ? Theme.a(Theme.accent, 0.3) : "transparent"
                    scale: uma.pressed ? 0.95 : 1
                    Behavior on scale { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.002 } }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12; width: parent.width - 20
                        spacing: 1
                        Text {
                            text: ud.modelData.id
                            font.family: Theme.fUi; font.pixelSize: 15; font.weight: Font.DemiBold
                            color: ud.sel ? Theme.accent : Theme.fg
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: ud.modelData.name
                            visible: text !== ""
                            font.family: Theme.fUi; font.pixelSize: 11
                            color: Theme.faint
                        }
                    }
                    MouseArea { id: uma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pk.choose(ud.modelData.id) }
                }
            }
        }
    }
}
