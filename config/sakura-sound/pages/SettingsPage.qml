// Settings: account · themes + live editor · plugins · behaviour
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Item {
    id: st
    property var app: null
    property var page: ({})
    clip: true

    property var themes: []
    // account: installed browsers, "checking…" while the backend re-reads cookies
    property var browsers: ["brave"]
    property bool checking: false
    property var pickedBrowser: null
    function bname(b) { return ({ brave: "Brave", chromium: "Chromium", chrome: "Chrome", vivaldi: "Vivaldi", firefox: "Firefox", zen: "Zen" })[b] || b; }
    function check(args) {
        checking = true;
        Sound.send("auth", args, r => { st.checking = false; st.pickedBrowser = null; });
    }
    Timer { running: st.checking; interval: 20000; onTriggered: st.checking = false }
    function loadThemes() { Sound.send("themes", {}, r => { if (!r.err) st.themes = r.themes; }); }
    Component.onCompleted: Qt.callLater(() => { Sound.send("browsers", {}, r => { if (r.browsers) st.browsers = r.browsers; }); loadThemes(); if (page.edit) startEdit(); })
    Component.onDestruction: if (editing) Theme.preview = null

    // ── theme editor state ──────────────────────────────────────
    property bool editing: false
    property var draft: ({})
    property string newName: ""
    readonly property bool builtin: ["sakura", "vinyl", "paper"].indexOf(Theme.themeName) >= 0
    function startEdit() {
        draft = JSON.parse(JSON.stringify(Theme.t || {}));
        if (!draft.colors) draft.colors = {};
        newName = builtin ? "" : (draft.name || Theme.themeName);
        editing = true;
        Theme.preview = draft;
    }
    function setD(k, v) { const d = Object.assign({}, draft); d[k] = v; draft = d; Theme.preview = d; }
    function setColor(role, spec) {
        const d = Object.assign({}, draft); d.colors = Object.assign({}, d.colors || {}); d.colors[role] = spec;
        draft = d; Theme.preview = d;
    }
    function cancelEdit() { editing = false; Theme.preview = null; }
    function saveEdit(asNew) {
        const name = (asNew || builtin) ? (newName.trim() || "My theme") : (draft.name || Theme.themeName);
        const d = Object.assign({}, draft, { name: name });
        if (asNew || builtin) delete d.about;
        const id = (asNew || builtin) ? name : Theme.themeName;
        Sound.send("theme_save", { theme: id, data: d }, r => {
            if (r.err) return;
            Theme.preview = null; editing = false;
            Theme.setCfg("theme", r.id);
            loadThemes();
        });
    }
    Process {
        id: picker
        command: ["zenity", "--file-selection", "--file-filter=*.zip", "--title=Sakura Sound"]
        stdout: StdioCollector { onStreamFinished: { const p = text.trim(); if (p) Sound.send("theme_import", { path: p }, r => { if (!r.err) { Theme.setCfg("theme", r.id); st.loadThemes(); } }); } }
    }

    component Head: Text {
        color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 19; font.weight: Font.Bold
        topPadding: 18
    }
    component Pill: Rectangle {
        id: pl
        property string text: ""
        property bool strong: false
        signal clicked()
        width: plT.implicitWidth + 26; height: 32; radius: 16
        color: strong ? Theme.accent : plMa.containsMouse ? Theme.cardHi : Theme.card
        Text { id: plT; anchors.centerIn: parent; text: pl.text; color: pl.strong ? Theme.accFg : Theme.fg; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
        MouseArea { id: plMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pl.clicked() }
    }
    component Box: Rectangle {
        default property alias inner: boxCol.data
        width: parent ? parent.width : 400
        height: boxCol.implicitHeight + 24
        radius: 18; color: Theme.card
        Column { id: boxCol; x: 16; y: 12; width: parent.width - 32; spacing: 2 }
    }

    // live preview: sits outside the scrolling area, so it stays in view while you scroll the editor
    ThemePreview {
        id: preview
        z: 2
        visible: opacity > 0
        opacity: st.editing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(180) } }
        width: 300
        height: Math.min(st.height - 48, 660)
        anchors.right: parent.right; anchors.rightMargin: 24
        anchors.top: parent.top; anchors.topMargin: 24
    }

    Flickable {
    id: flick
    anchors.fill: parent
    contentHeight: col.implicitHeight + 60
    boundsBehavior: Flickable.StopAtBounds
    Column {
        id: col
        x: 28; y: 24
        width: Math.min(820, st.width - 56 - (st.editing ? 344 : 0))
        Behavior on width { NumberAnimation { duration: Theme.dur(200); easing.type: Easing.OutCubic } }
        spacing: 12

        Text { text: Theme.tr("Settings"); color: Theme.fg; font.family: Theme.fontHead; font.pixelSize: 30; font.weight: Font.ExtraBold }

        // ── account ─────────────────────────────────────────────
        Head { text: Theme.tr("Account") }
        Box {
            SetRow {
                label: st.checking ? Theme.tr("Checking…") : Sound.signedIn ? Theme.tr("Signed in as") + " " + Sound.me.name : Theme.tr("Not signed in")
                sub: st.checking ? "" : Sound.signedIn ? (Sound.auth.go ? "Go+ · " : "") + (Sound.auth.likes || 0) + " " + Theme.tr("Likes").toLowerCase()
                     : Sound.auth.err ? Theme.tr("Couldn't read cookies from") + " " + (Sound.auth.browser || "?") + ": " + Sound.auth.err
                     : !Sound.auth.browser ? Theme.tr("Guest") : Theme.tr("Sign in to SoundCloud in") + " " + st.bname(Sound.auth.browser)
                Pill { text: st.checking ? "…" : Theme.tr("Check again"); onClicked: st.check({}) }
                Pill { visible: !Sound.signedIn; text: "soundcloud.com"; strong: true; onClicked: Sound.openUrl("https://soundcloud.com/signin") }
            }
            SetRow {
                label: Theme.tr("Cookies from")
                Seg {
                    options: st.browsers.map(b => ({ v: b, t: st.bname(b) })).concat([{ v: "", t: "Guest" }])
                    value: st.pickedBrowser !== null ? st.pickedBrowser : (Sound.auth.browser !== undefined ? Sound.auth.browser : "brave")
                    onPicked: v => { st.pickedBrowser = v; st.check({ browser: v }); }
                }
            }
        }

        // ── themes ──────────────────────────────────────────────
        Head { text: Theme.tr("Themes") }
        Flow {
            width: parent.width
            spacing: 12
            Repeater {
                model: st.themes
                Rectangle {
                    id: tc
                    required property var modelData
                    readonly property var d: modelData.data
                    readonly property bool on: Theme.themeName === modelData.id
                    width: (col.width - 24) / 3; height: 148; radius: 18
                    color: on ? Theme.a(Theme.accent, 0.12) : tcH.hovered ? Theme.cardHi : Theme.card
                    border.width: on ? 1 : 0; border.color: Theme.a(Theme.accent, 0.6)
                    HoverHandler { id: tcH }
                    MouseArea { id: tcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (st.editing) st.cancelEdit(); Theme.setCfg("theme", tc.modelData.id); } }
                    Row {
                        x: 14; y: 14; spacing: 12
                        Cover { width: 58; height: 58; src: Sound.track ? Theme.small(Sound.track.art, 80) : ""; style: tc.d.cover || "rounded" }
                        Column {
                            spacing: 3; width: tc.width - 98
                            Text { text: tc.d.name || tc.modelData.id; color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 14; font.weight: Font.Bold; width: parent.width; elide: Text.ElideRight }
                            Text { text: tc.d.about || ""; color: Theme.muted; font.family: Theme.fontUi; font.pixelSize: 11; width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                        }
                    }
                    Row {
                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 14
                        spacing: 6
                        Repeater {
                            model: ["accent", "glass", "fg", "muted", "card"]
                            Rectangle {
                                required property string modelData
                                width: 16; height: 16; radius: 8; border.width: 1; border.color: Theme.line
                                color: Theme.role((tc.d.colors || {})[modelData], ({ accent: Theme.sysAccent, glass: Theme.sysGlass, fg: "#e6e8ef", muted: "#8b90a0", card: "#14ffffff" })[modelData])
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 10
                        spacing: 2
                        opacity: tcH.hovered ? 1 : 0.0
                        Btn { size: 28; icon: "open"; iconSize: 13; tint: Theme.muted
                              onClicked: Sound.send("theme_export", { theme: tc.modelData.id }, r => { if (r.path) Sound.error(r.path); }) }
                        Btn { size: 28; icon: "close"; iconSize: 13; tint: Theme.muted
                              visible: ["sakura", "vinyl", "paper"].indexOf(tc.modelData.id) < 0
                              onClicked: Sound.send("theme_delete", { theme: tc.modelData.id }, r => { if (tc.on) Theme.setCfg("theme", "sakura"); st.loadThemes(); }) }
                    }
                }
            }
        }
        Row {
            spacing: 8
            Pill { text: st.editing ? Theme.tr("Save") : Theme.tr("Appearance"); strong: st.editing
                   onClicked: st.editing ? st.saveEdit(false) : st.startEdit() }
            Pill { visible: st.editing; text: Theme.tr("Back"); onClicked: st.cancelEdit() }
            Pill { text: Theme.tr("Import"); onClicked: picker.running = true }
        }

        // ── editor (edits are live: the whole window is the preview) ─
        Box {
            visible: st.editing
            SetRow { label: Theme.tr("Cover")
                Seg { options: [{ v: "square", t: "Square" }, { v: "rounded", t: "Rounded" }, { v: "circle", t: "Circle" }, { v: "vinyl", t: "Vinyl" }, { v: "spin", t: "Spinning" }, { v: "cd", t: "CD" }]
                      value: st.draft.cover || "rounded"; onPicked: v => st.setD("cover", v) } }
            SetRow { label: Theme.tr("Background")
                Seg { options: [{ v: "glass", t: "Glass" }, { v: "blur", t: "Blurred cover" }, { v: "wallpaper", t: "Wallpaper" }, { v: "gradient", t: "Cover gradient" }]
                      value: st.draft.background || "glass"; onPicked: v => st.setD("background", v) } }
            SetRow { label: Theme.tr("Density")
                Seg { options: [{ v: "compact", t: "Compact" }, { v: "normal", t: "Normal" }, { v: "comfy", t: "Comfy" }]
                      value: st.draft.density || "normal"; onPicked: v => st.setD("density", v) } }
            SetRow { label: Theme.tr("Player")
                Seg { options: [{ v: "compact", t: "Compact" }, { v: "big", t: "Big" }]
                      value: st.draft.player || "big"; onPicked: v => st.setD("player", v) } }
            SetRow { label: Theme.tr("Wave")
                Seg { options: [{ v: "bars", t: "Bars" }, { v: "line", t: "Line" }, { v: "mirror", t: "Mirror" }, { v: "off", t: "Off" }]
                      value: st.draft.wave || "bars"; onPicked: v => st.setD("wave", v) } }
            SetRow { label: Theme.tr("Visualizer")
                Seg { options: [{ v: "bars", t: "Bars" }, { v: "mirror", t: "Mirror" }, { v: "circle", t: "Circle" }, { v: "off", t: "Off" }]
                      value: st.draft.visualizer === false ? "off" : (st.draft.vizStyle || "bars")
                      onPicked: v => { st.setD("visualizer", v !== "off"); st.setD("vizStyle", v); } } }
            SetRow { label: Theme.tr("Now playing layout")
                Seg { options: [{ v: "side", t: "Side by side" }, { v: "center", t: "Centered" }]; value: st.draft.npLayout || "side"; onPicked: v => st.setD("npLayout", v) } }
            SetRow { label: Theme.tr("Particles")
                Seg { options: [{ v: "off", t: "Off" }, { v: "petals", t: "Petals" }, { v: "snow", t: "Snow" }, { v: "stars", t: "Stars" }]; value: st.draft.particles || "off"; onPicked: v => st.setD("particles", v) } }
            SetRow { label: Theme.tr("Cover glow")
                Toggle { on: st.draft.glow === true; onToggled: st.setD("glow", st.draft.glow !== true) } }
            SetRow { label: Theme.tr("Pulse to the beat")
                Toggle { on: st.draft.pulse === true; onToggled: st.setD("pulse", st.draft.pulse !== true) } }
            SetRow { label: Theme.tr("Moving background")
                Toggle { on: st.draft.bgMotion === true; onToggled: st.setD("bgMotion", st.draft.bgMotion !== true) } }
            SetRow { label: Theme.tr("Background blur")
                Slider2 { from: 0; to: 1; step: 0.05; decimals: 2; value: typeof st.draft.bgBlur === "number" ? st.draft.bgBlur : 0.8; onMoved: v => st.setD("bgBlur", v) } }
            SetRow { label: Theme.tr("Background dim")
                Slider2 { from: 0; to: 0.9; step: 0.05; decimals: 2; value: typeof st.draft.bgDim === "number" ? st.draft.bgDim : 0.35; onMoved: v => st.setD("bgDim", v) } }
            SetRow { label: Theme.tr("Scrolling titles")
                Toggle { on: st.draft.marquee !== false; onToggled: st.setD("marquee", st.draft.marquee === false) } }
            SetRow { label: Theme.tr("Heading font")
                Seg { options: [{ v: "", t: "Follow system" }, { v: "Inter Display", t: "Inter Display" }, { v: "JetBrainsMono Nerd Font", t: "Mono" }, { v: "Noto Serif", t: "Serif" }]
                      value: st.draft.fontHead || ""; onPicked: v => st.setD("fontHead", v) } }
            SetRow { label: Theme.tr("Sidebar width")
                Slider2 { from: 160; to: 300; step: 4; value: st.draft.sideW || 208; onMoved: v => st.setD("sideW", v) } }
            SetRow { label: Theme.tr("Queue width")
                Slider2 { from: 260; to: 440; step: 4; value: st.draft.queueW || 320; onMoved: v => st.setD("queueW", v) } }
            SetRow { label: Theme.tr("Corner radius")
                Slider2 { from: 8; to: 32; step: 1; value: st.draft.radius || 22; onMoved: v => st.setD("radius", v) } }

            SetRow { label: Theme.tr("Accent from cover")
                Toggle { on: (st.draft.colors || {}).accent === "cover"
                         onToggled: st.setColor("accent", (st.draft.colors || {}).accent === "cover" ? "auto" : "cover") } }
            Repeater {
                model: [{ r: "accent", t: "Accent" }, { r: "glass", t: "Glass" }, { r: "fg", t: "Text" }, { r: "muted", t: "Muted" }, { r: "card", t: "Card" }]
                Column {
                    id: rc
                    required property var modelData
                    readonly property var spec: (st.draft.colors || {})[modelData.r]
                    readonly property bool auto: spec === undefined || spec === "auto"
                    readonly property bool hex: typeof spec === "string" && spec !== "auto" && spec !== "cover"
                    visible: !(modelData.r === "accent" && spec === "cover")
                    width: parent.width
                    SetRow {
                        label: Theme.tr(rc.modelData.t)
                        sub: rc.auto ? Theme.tr("Follow system") : rc.hex ? rc.spec : Theme.tr("Hue shift")
                        Toggle { on: rc.auto; onToggled: st.setColor(rc.modelData.r, rc.auto ? { hue: 0, light: 0, sat: 0 } : "auto") }
                        Rectangle { width: 24; height: 24; radius: 12; border.width: 1; border.color: Theme.line; color: Theme[rc.modelData.r] }
                    }
                    Column {
                        visible: !rc.auto && !rc.hex
                        width: parent.width
                        SetRow { label: "H"
                            Slider2 { from: -180; to: 180; step: 1; value: (rc.spec && rc.spec.hue) || 0; suffix: "°"
                                      onMoved: v => st.setColor(rc.modelData.r, Object.assign({}, rc.spec, { hue: v })) } }
                        SetRow { label: "S"
                            Slider2 { from: -0.5; to: 0.5; step: 0.01; decimals: 2; value: (rc.spec && rc.spec.sat) || 0
                                      onMoved: v => st.setColor(rc.modelData.r, Object.assign({}, rc.spec, { sat: v })) } }
                        SetRow { label: "L"
                            Slider2 { from: -0.4; to: 0.4; step: 0.01; decimals: 2; value: (rc.spec && rc.spec.light) || 0
                                      onMoved: v => st.setColor(rc.modelData.r, Object.assign({}, rc.spec, { light: v })) } }
                    }
                }
            }

            SetRow {
                label: Theme.tr("Theme name")
                Pill { text: Theme.tr("Save as new theme"); strong: true; onClicked: st.saveEdit(true) }
                Rectangle {
                    width: 180; height: 32; radius: 16; color: Theme.cardHi
                    TextInput { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; verticalAlignment: TextInput.AlignVCenter
                                text: st.newName; onTextEdited: st.newName = text; color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 13; clip: true }
                }
            }
        }

        // ── plugins (manager comes from Plugins.qml through app) ─
        Head { text: Theme.tr("Plugins"); visible: plugLoader.status === Loader.Ready }
        Loader {
            id: plugLoader
            width: parent.width
            active: !!(st.app && st.app.pluginManager)
            sourceComponent: st.app ? st.app.pluginManager : null
        }
    }
    }
}
