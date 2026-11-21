// sakura mono - the pocket card next to the edge drum: a field on top (type, Enter = keep, Shift+Enter = new line,
// Ctrl+V a picture), the rows below (click = copy, × = throw away). Kept for 24 h.
import QtQuick

Item {
    id: pp
    required property var pocket
    required property var tab           // EdgeTab: keeps the drum open while you type
    readonly property color cFg: "#eceef4"
    readonly property color cMuted: "#8a8fa3"
    readonly property int rowH: 48
    readonly property int maxRows: 6
    readonly property int n: pocket.items.length
    implicitWidth: 300
    implicitHeight: 14 + 24 + 10 + field.height + 10 + (n === 0 ? 0 : Math.min(n, maxRows) * (rowH + 4) - 4 + 10) + 4

    Component.onCompleted: Qt.callLater(() => input.forceActiveFocus())
    Component.onDestruction: tab.typing = false

    Item {
        id: head
        x: 14; y: 14; width: parent.width - 28; height: 24
        Row {
            anchors.verticalCenter: parent.verticalCenter; spacing: 8
            Text { id: title; text: Cfg.tr("Pocket"); color: pp.cFg; font.family: Cfg.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text { visible: pp.n > 0; text: pp.n; color: Cfg.accent; font.family: Cfg.fontUi; font.pixelSize: 12; font.weight: Font.Bold; anchors.baseline: title.baseline }
        }
        Rectangle {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            visible: pp.n > 0
            width: clrRow.implicitWidth + 16; height: 24; radius: 12
            color: ca.containsMouse ? Cfg.acc(0.28) : "#10ffffff"
            Behavior on color { ColorAnimation { duration: 120 } }
            Row {
                id: clrRow; anchors.centerIn: parent; spacing: 5
                Text { text: ""; font.family: "Symbols Nerd Font"; font.pixelSize: 10; color: ca.containsMouse ? Cfg.accent : pp.cMuted; anchors.verticalCenter: parent.verticalCenter }
                Text { text: Cfg.tr("Clear all"); font.family: Cfg.fontUi; font.pixelSize: 11; color: pp.cFg; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: ca; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pp.pocket.clear() }
        }
    }

    // ── the field ──
    Rectangle {
        id: field
        x: 14; y: head.y + head.height + 10; width: parent.width - 28
        height: Math.min(96, Math.max(40, input.contentHeight + 20))
        radius: 12
        color: "#0cffffff"
        border.width: 1; border.color: input.activeFocus ? Cfg.acc(0.7) : "#22ffffff"
        Behavior on border.color { ColorAnimation { duration: 140 } }
        Flickable {
            id: fl
            x: 12; y: 10; width: parent.width - 24 - 26; height: parent.height - 20
            contentHeight: input.contentHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds
            TextEdit {
                id: input
                width: fl.width
                wrapMode: TextEdit.Wrap
                color: pp.cFg; selectionColor: Cfg.acc(0.5); selectedTextColor: "#ffffff"
                font.family: Cfg.fontUi; font.pixelSize: 12
                onActiveFocusChanged: pp.tab.typing = activeFocus
                onCursorRectangleChanged: {
                    if (cursorRectangle.y < fl.contentY) fl.contentY = cursorRectangle.y;
                    else if (cursorRectangle.y + cursorRectangle.height > fl.contentY + fl.height) fl.contentY = cursorRectangle.y + cursorRectangle.height - fl.height;
                }
                Keys.onPressed: e => {
                    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                        e.accepted = true; pp.keep();
                    } else if (e.matches(StandardKey.Paste)) {
                        e.accepted = true;
                        pp.pocket.paste(() => input.paste());       // a picture → the pocket, text → into the field
                    } else if (e.key === Qt.Key_Escape) {
                        e.accepted = true; pp.tab.close();
                    }
                }
            }
        }
        Text {
            visible: input.text === "" && !input.preeditText
            x: 12; anchors.verticalCenter: parent.verticalCenter; width: fl.width
            text: Cfg.tr("Type a note · Ctrl+V a picture"); elide: Text.ElideRight
            color: pp.cMuted; font.family: Cfg.fontUi; font.pixelSize: 12
        }
        // keep
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 7; anchors.bottom: parent.bottom; anchors.bottomMargin: 7
            width: 26; height: 26; radius: 9
            opacity: input.text.trim() !== "" ? 1 : 0.35
            color: ka.containsMouse ? Cfg.accent : Cfg.acc(0.22)
            Text { anchors.centerIn: parent; text: ""; font.family: "Symbols Nerd Font"; font.pixelSize: 11; color: ka.containsMouse ? Cfg.accFg : Cfg.accent }
            MouseArea { id: ka; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pp.keep() }
        }
        MouseArea { anchors.fill: fl; anchors.margins: -10; z: -1; cursorShape: Qt.IBeamCursor; onPressed: input.forceActiveFocus() }
    }
    function keep() {
        if (input.text.trim() === "") return;
        pocket.addText(input.text);
        input.text = "";
        input.forceActiveFocus();
    }

    // ── the rows ──
    ListView {
        id: list
        visible: pp.n > 0
        x: 14; y: field.y + field.height + 10; width: parent.width - 28
        height: Math.min(pp.n, pp.maxRows) * (pp.rowH + 4) - 4
        clip: true; spacing: 4
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: pp.pocket.items
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property var it: modelData
            readonly property bool hot: ma.containsMouse || xa.containsMouse
            readonly property bool pic: it.kind === "image"
            property bool copied: false
            width: list.width; height: pp.rowH; radius: 12
            color: copied ? Cfg.acc(0.30) : hot ? "#16ffffff" : "#0affffff"
            Behavior on color { ColorAnimation { duration: 140 } }
            Timer { id: copiedT; interval: 900; onTriggered: row.copied = false }

            Rectangle {
                id: thumb
                x: 7; anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 34; radius: 9; clip: true
                color: row.pic ? "#22000000" : Cfg.acc(0.14)
                Image {
                    anchors.fill: parent
                    visible: row.pic
                    source: row.pic ? pp.pocket.fileUrl(row.it.path) + "?r=" + pp.pocket.rev : ""
                    sourceSize.width: 68; sourceSize.height: 68
                    fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
                }
                Text { anchors.centerIn: parent; visible: !row.pic; text: ""; font.family: "Symbols Nerd Font"; font.pixelSize: 14; color: Cfg.accent }
            }
            Column {
                x: thumb.x + thumb.width + 10; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - (row.hot ? 34 : 10); spacing: 2
                Text {
                    width: parent.width; elide: Text.ElideRight; maximumLineCount: 1
                    text: row.copied ? Cfg.tr("Copied") : row.pic ? Cfg.tr("Picture") : row.it.text.replace(/\s+/g, " ").trim()
                    color: pp.cFg; font.family: Cfg.fontUi; font.pixelSize: 12
                }
                Text {
                    text: Cfg.tr(row.pic ? "Picture" : "Text") + " · " + pp.pocket.ago(row.it.t)
                    color: pp.cMuted; font.family: Cfg.fontUi; font.pixelSize: 10
                }
            }
            MouseArea {
                id: ma
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { pp.pocket.copy(row.it); row.copied = true; copiedT.restart(); }
            }
            Rectangle {      // ×
                visible: row.hot
                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 11
                color: xa.containsMouse ? "#40f28fad" : "#14ffffff"
                Text { anchors.centerIn: parent; text: ""; font.family: "Symbols Nerd Font"; font.pixelSize: 10; color: xa.containsMouse ? "#f28fad" : pp.cMuted }
                MouseArea { id: xa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pp.pocket.remove(row.it.id) }
            }
        }
    }
}
