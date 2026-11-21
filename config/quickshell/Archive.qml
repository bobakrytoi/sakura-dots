// sakura mono - Compress dialog (and the password ask for encrypted archives) for Dolphin's right-click menu.
// Right-click → Compress… (~/.local/share/kio/servicemenus/sakura-archive.desktop → hypr/scripts/archive.sh ui)
// qs ipc call archive compress "<paths, one per line>" | password <here|folder> <file>
// Enter = go · Esc = close · ←/→ = format · last format and level are remembered (Cfg archiveFmt / archiveLvl).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

Scope {
    id: ar
    property bool shown: false
    property string mode: "compress"          // compress | password
    property var files: []
    property string pwHow: "here"
    property var screen0: Quickshell.screens[0]
    property string fmt: Cfg.data.archiveFmt || "zip"
    property string lvl: Cfg.data.archiveLvl || "normal"
    property bool lock: false                 // password on (zip / 7z)

    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cCard:   "#14ffffff"
    readonly property color cHover:  "#24ffffff"
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string sh:     Quickshell.env("HOME") + "/.config/hypr/scripts/archive.sh"

    readonly property var formats: [
        { id: "zip",     name: "ZIP",     icon: "\uf1c6", note: "Opens everywhere",   pw: true },
        { id: "7z",      name: "7Z",      icon: "\uf187", note: "Smallest, encrypts",  pw: true },
        { id: "tar.zst", name: "TAR.ZST", icon: "\uf0e7", note: "Fast, small",        pw: false },
        { id: "tar.gz",  name: "TAR.GZ",  icon: "\uf1b2", note: "Classic Linux",      pw: false },
        { id: "tar.xz",  name: "TAR.XZ",  icon: "\uf066", note: "Small but slow",     pw: false }
    ]
    readonly property var curFmt: formats.find(f => f.id === fmt) || formats[0]
    readonly property bool canPw: curFmt.pw

    function base(p) { return String(p).replace(/\/+$/, "").split("/").pop(); }
    function stem(p) {
        const b = base(p);
        if (files.length > 1) { const d = String(files[0]).split("/"); return d.length > 1 ? (d[d.length - 2] || "archive") : "archive"; }
        return b.replace(/\.(tar\.(zst|gz|xz|bz2)|[a-z0-9]{1,5})$/i, "") || b;
    }
    function pick() {
        const fm = Hyprland.focusedMonitor;
        screen0 = (fm && Quickshell.screens.find(s => s.name === fm.name)) || Cfg.mainScreen || Quickshell.screens[0];
    }
    function openCompress(list) {
        files = String(list).split("\n").filter(s => s !== "");
        if (!files.length) return;
        mode = "compress"; lock = false; pick();
        nameIn.input.text = stem(files[0]); pwIn.input.text = "";
        shown = true;
    }
    function openPassword(how, file) {
        files = [file]; pwHow = how === "folder" ? "folder" : "here";
        mode = "password"; pick(); pwIn.input.text = "";
        shown = true;
    }
    function close() { shown = false; pwIn.input.text = ""; }
    function go() {
        if (mode === "compress") {
            Cfg.set("archiveFmt", fmt); Cfg.set("archiveLvl", lvl);
            job.pw = canPw && lock ? pwIn.input.text : "";
            job.command = [sh, "compress", fmt, lvl, nameIn.input.text.trim()].concat(files);
        } else {
            if (pwIn.input.text === "") return;
            job.pw = pwIn.input.text;
            job.command = [sh, "extractpw", pwHow, files[0]];
        }
        job.running = true;
        close();
    }
    function step(d) {
        const i = formats.findIndex(f => f.id === fmt);
        fmt = formats[(i + d + formats.length) % formats.length].id;
    }

    // the password goes over stdin - never on a command line others can see in ps
    Process {
        id: job
        property string pw: ""
        stdinEnabled: true
        onStarted: { write(pw + "\n"); pw = ""; }
    }

    IpcHandler {
        target: "archive"
        function compress(paths: string): void { ar.openCompress(paths); }
        function password(how: string, file: string): void { ar.openPassword(how, file); }
        function close(): void { ar.close(); }
        function confirm(): void { if (ar.shown) ar.go(); }
    }

    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool primary: false
        signal clicked()
        width: bt.implicitWidth + 40; height: 40; radius: 13
        color: primary ? (bma.containsMouse ? Qt.lighter(Cfg.accent, 1.08) : Cfg.accent) : (bma.containsMouse ? ar.cHover : ar.cCard)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { id: bt; anchors.centerIn: parent; text: Cfg.tr(b.label); font.family: ar.fUi; font.pixelSize: 13; font.weight: Font.DemiBold
               color: b.primary ? Cfg.accFg : ar.cFg }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
    component Field: Rectangle {
        id: fl
        property alias input: ti
        property string icon: ""
        property string hint: ""
        property string suffix: ""
        property bool secret: false
        height: 42; radius: 13; color: ar.cCard
        border.width: ti.activeFocus ? 1 : 0; border.color: Cfg.acc(0.5)
        Text { id: fic; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
               text: fl.icon; font.family: ar.fIcon; font.pixelSize: 13; color: Cfg.accent }
        TextInput {
            id: ti
            anchors { left: fic.right; leftMargin: 12; right: suf.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
            color: ar.cFg; font.family: ar.fUi; font.pixelSize: 14; clip: true; selectionColor: Cfg.acc(0.4); selectByMouse: true
            echoMode: fl.secret ? TextInput.Password : TextInput.Normal; passwordCharacter: "•"
            Keys.onReturnPressed: ar.go()
            Keys.onEnterPressed: ar.go()
            Keys.onEscapePressed: ar.close()
            Text { visible: ti.text === ""; text: Cfg.tr(fl.hint); color: ar.cMuted; font: ti.font }
        }
        Text { id: suf; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
               text: fl.suffix; color: ar.cMuted; font.family: ar.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
    }

    PanelWindow {
        id: win
        screen: ar.screen0
        visible: ar.shown || panel.opacity > 0
        implicitWidth: 560; implicitHeight: panel.height + 40
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "archive"
        WlrLayershell.keyboardFocus: ar.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        property bool grabOn: false
        onVisibleChanged: { grabOn = false; if (visible) regrab.restart(); }
        Timer { id: regrab; interval: 60; onTriggered: if (ar.shown) { win.grabOn = true; (ar.mode === "password" ? pwIn.input : nameIn.input).forceActiveFocus(); } }
        HyprlandFocusGrab { windows: [ win ]; active: win.grabOn && ar.shown; onCleared: ar.close() }

        Rectangle {
            id: panel
            x: 20; y: 20; width: parent.width - 40
            height: col.implicitHeight + 44
            radius: 26; color: Cfg.glass
            border.width: 1; border.color: "#14ffffff"
            opacity: ar.shown ? 1 : 0
            scale: ar.shown ? 1 : 0.95
            Behavior on opacity { NumberAnimation { duration: 170 } }
            Behavior on scale { NumberAnimation { duration: 260 * Cfg.anim; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on height { NumberAnimation { duration: 200 * Cfg.anim; easing.type: Easing.OutCubic } }
            focus: true
            Keys.onEscapePressed: ar.close()
            Keys.onLeftPressed: ar.step(-1)
            Keys.onRightPressed: ar.step(1)
            Keys.onReturnPressed: ar.go()

            Column {
                id: col
                x: 22; y: 22; width: parent.width - 44
                spacing: 16

                // header: icon tile + what we're packing
                Row {
                    spacing: 14; width: parent.width
                    Rectangle {
                        width: 46; height: 46; radius: 15; color: Cfg.acc(0.16)
                        border.width: 1; border.color: Cfg.acc(0.3)
                        Text { anchors.centerIn: parent; text: ar.mode === "password" ? "\uf023" : "\uf1c6"; font.family: ar.fIcon; font.pixelSize: 19; color: Cfg.accent }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60; spacing: 3
                        Text { text: ar.mode === "password" ? Cfg.tr("Password needed") : ar.files.length > 1 ? Cfg.tr("Compress") + " " + ar.files.length + " " + Cfg.tr("items") : Cfg.tr("Compress")
                               font.family: ar.fUi; font.pixelSize: 16; font.weight: Font.Bold; color: ar.cFg }
                        Text { width: parent.width; elide: Text.ElideMiddle
                               text: ar.files.slice(0, 4).map(ar.base).join(" · ") + (ar.files.length > 4 ? " …" : "")
                               font.family: ar.fUi; font.pixelSize: 12; color: ar.cMuted }
                    }
                }

                // name
                Field { id: nameIn; visible: ar.mode === "compress"; width: parent.width; icon: "\uf040"; hint: "Archive name"; suffix: "." + ar.fmt }

                // formats
                Grid {
                    visible: ar.mode === "compress"
                    width: parent.width; columns: 5; spacing: 8
                    Repeater {
                        model: ar.formats
                        Rectangle {
                            required property var modelData
                            readonly property bool on: ar.fmt === modelData.id
                            width: (col.width - 32) / 5; height: 86; radius: 16
                            color: on ? Cfg.acc(0.16) : fma.containsMouse ? ar.cHover : ar.cCard
                            border.width: on ? 1 : 0; border.color: Cfg.acc(0.55)
                            scale: fma.pressed ? 0.96 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            Column {
                                anchors.centerIn: parent; spacing: 5; width: parent.width - 10
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; font.family: ar.fIcon; font.pixelSize: 18
                                       color: parent.parent.on ? Cfg.accent : ar.cMuted }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; font.family: ar.fUi; font.pixelSize: 12; font.weight: Font.Bold
                                       color: parent.parent.on ? Cfg.accent : ar.cFg }
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: Cfg.tr(modelData.note); wrapMode: Text.WordWrap
                                       font.family: ar.fUi; font.pixelSize: 10; color: ar.cMuted; lineHeight: 0.9 }
                            }
                            MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ar.fmt = modelData.id }
                        }
                    }
                }

                // level: a segmented pill with a sliding knob
                Rectangle {
                    visible: ar.mode === "compress"
                    width: parent.width; height: 40; radius: 13; color: ar.cCard
                    readonly property var lv: [["fast", "Fast", "\uf0e7"], ["normal", "Balanced", "\uf24e"], ["max", "Smallest", "\uf066"]]
                    readonly property int idx: Math.max(0, lv.findIndex(l => l[0] === ar.lvl))
                    Rectangle {
                        x: 4 + parent.idx * (parent.width - 8) / 3; y: 4; width: (parent.width - 8) / 3; height: parent.height - 8; radius: 10
                        color: Cfg.accent
                        Behavior on x { NumberAnimation { duration: 220 * Cfg.anim; easing.type: Easing.OutCubic } }
                    }
                    Row {
                        x: 4; y: 4
                        Repeater {
                            model: parent.parent.lv
                            Item {
                                required property var modelData
                                required property int index
                                width: (col.width - 8) / 3; height: 32
                                readonly property bool on: ar.lvl === modelData[0]
                                Row { anchors.centerIn: parent; spacing: 7
                                    Text { text: modelData[2]; font.family: ar.fIcon; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
                                           color: parent.parent.on ? Cfg.accFg : ar.cMuted }
                                    Text { text: Cfg.tr(modelData[1]); font.family: ar.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter
                                           color: parent.parent.on ? Cfg.accFg : ar.cFg } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ar.lvl = modelData[0] }
                            }
                        }
                    }
                }

                // password: a switch for zip / 7z, always open in the "password needed" mode
                Rectangle {
                    visible: ar.mode === "compress"
                    width: parent.width; height: 40; radius: 13
                    color: lma.containsMouse && ar.canPw ? ar.cHover : ar.cCard
                    opacity: ar.canPw ? 1 : 0.45
                    Text { id: lic; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                           text: "\uf023"; font.family: ar.fIcon; font.pixelSize: 13; color: ar.lock && ar.canPw ? Cfg.accent : ar.cMuted }
                    Text { anchors { left: lic.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                           text: ar.canPw ? Cfg.tr("Protect with a password") : Cfg.tr("Password - ZIP and 7Z only")
                           font.family: ar.fUi; font.pixelSize: 13; color: ar.cFg }
                    Rectangle {
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 38; height: 22; radius: 11
                        color: ar.lock && ar.canPw ? Cfg.accent : "#33ffffff"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle { width: 16; height: 16; radius: 8; y: 3; x: ar.lock && ar.canPw ? 19 : 3; color: ar.lock && ar.canPw ? Cfg.accFg : "#ffffff"
                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
                    }
                    MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; enabled: ar.canPw; cursorShape: Qt.PointingHandCursor
                                onClicked: { ar.lock = !ar.lock; if (ar.lock) pwIn.input.forceActiveFocus(); } }
                }
                Field {
                    id: pwIn
                    visible: ar.mode === "password" || (ar.lock && ar.canPw)
                    width: parent.width; icon: "\uf084"; secret: true
                    hint: ar.mode === "password" ? "Archive password" : "Password"
                }

                // actions
                Item {
                    width: parent.width; height: 40
                    Row {
                        anchors.right: parent.right; spacing: 8
                        Btn { label: "Cancel"; onClicked: ar.close() }
                        Btn { label: ar.mode === "password" ? "Extract" : "Compress"; primary: true; onClicked: ar.go() }
                    }
                }
            }
        }
    }
}
