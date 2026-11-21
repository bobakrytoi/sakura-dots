// sakura mono - Mic Studio: live voice processing for your microphone
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick

Scope {
    id: mic

    readonly property color cBg:     Cfg.glass
    readonly property color cSide:   "#26000000"
    readonly property color cCard:   "#14ffffff"
    readonly property color cCard2:  "#1fffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property color cWarn:   "#f28fad"
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string home:   Quickshell.env("HOME")
    readonly property string script: home + "/.config/hypr/scripts/mic.py"

    property bool shown: false
    function toggle() { shown = !shown; if (shown) refresh(); }
    IpcHandler {
        target: "mic"
        function toggle(): void { mic.toggle(); }
        function open(): void { if (!mic.shown) mic.toggle(); }
    }

    // ── state from the backend ──────────────────────────────
    property var cfg: ({ enabled: true, device: "", deviceDesc: "", autoDefault: true, live: false,
        denoise: 55, gateOn: true, gate: -42, pitch: 0, hpf: 90,
        bass: 0, mud: -1, mid: 0, presence: 3, air: 2,
        compOn: true, compThresh: -20, compRatio: 3, gain: 0 })
    property bool running: false
    property bool isDefault: false
    property bool live: false
    property var sources: []
    property var plugins: ({ ns: false, pitch: false, comp: false, gate: false })
    property bool busy: false
    property bool pickDev: false

    Process {
        id: statusProc
        command: ["python3", "-I", mic.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text);
                    mic.cfg = Object.assign({}, mic.cfg, d.config);
                    mic.running = d.running; mic.isDefault = d.isDefault;
                    mic.live = d.live; mic.sources = d.sources; mic.plugins = d.plugins;
                } catch (e) {}
                mic.busy = false;
            }
        }
    }
    function refresh() { statusProc.running = true }
    Timer { interval: 2500; running: mic.shown; repeat: true; onTriggered: mic.refresh() }

    // ── changing values (batched, so dragging a slider stays smooth) ──
    property var pending: ({})
    Process { id: setProc; onExited: if (Object.keys(mic.pending).length) flushTimer.restart() }
    Timer { id: flushTimer; interval: 90; onTriggered: mic.flush() }
    function set(k, v) {
        const c = Object.assign({}, cfg); c[k] = v; cfg = c;
        const p = Object.assign({}, pending); p[k] = v; pending = p;
        flushTimer.restart();
    }
    function flush() {
        if (setProc.running) { flushTimer.restart(); return; }
        const keys = Object.keys(pending);
        if (!keys.length) return;
        const args = ["python3", "-I", script, "set"];
        keys.forEach(k => {
            const v = pending[k];
            args.push(k, typeof v === "boolean" ? (v ? "1" : "0") : String(v));
        });
        pending = ({});
        setProc.command = args;
        setProc.running = true;
        slowRefresh.restart();
    }
    Timer { id: slowRefresh; interval: 900; onTriggered: mic.refresh() }
    function cmd(args) { Quickshell.execDetached(["python3", "-I", script].concat(args)); slowRefresh.restart(); }
    function preset(p) {
        const c = Object.assign({}, cfg); c.preset = p;
        Quickshell.execDetached(["python3", "-I", script, "set", "preset", p]);
        slowRefresh.restart();
    }

    // ── live level meter ────────────────────────────────────
    property real rms: -90
    property real peak: -90
    property real peakHold: -90
    Process {
        id: meter
        running: mic.shown && mic.running
        command: ["python3", "-I", mic.script, "levels"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    mic.rms = d.rms; mic.peak = d.peak;
                    if (d.peak > mic.peakHold) mic.peakHold = d.peak;
                } catch (e) {}
            }
        }
        onRunningChanged: if (!running) { mic.rms = -90; mic.peak = -90; }
    }
    Timer { interval: 1200; running: mic.shown; repeat: true; onTriggered: mic.peakHold = Math.max(-90, mic.peakHold - 6) }
    function lvl(db) { return Math.max(0, Math.min(1, (db + 60) / 60)); }

    // ── bits ────────────────────────────────────────────────
    component Card: Rectangle { radius: 18; color: mic.cCard; border.width: 1; border.color: mic.cBorder }
    component Head: Text { color: mic.cAccent; font.family: mic.fUi; font.pixelSize: 12; font.weight: Font.Bold; topPadding: 10; bottomPadding: 2 }
    component Toggle: Rectangle {
        id: tg
        property bool on: false
        signal toggled()
        width: 46; height: 26; radius: 13
        color: on ? mic.cAccent : "#33ffffff"
        Behavior on color { ColorAnimation { duration: 160 } }
        Rectangle {
            width: 20; height: 20; radius: 10; y: 3
            x: tg.on ? tg.width - width - 3 : 3
            color: tg.on ? mic.cAccFg : "#ffffff"
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
    }
    component Btn: Rectangle {
        id: b
        property string text: ""
        property bool primary: false
        signal clicked()
        width: bt.implicitWidth + 26; height: 32; radius: 11
        color: primary ? (ba.containsMouse ? "#ffffff" : mic.cAccent) : (ba.containsMouse ? mic.cCard2 : "#14ffffff")
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { id: bt; anchors.centerIn: parent; text: b.text; color: b.primary ? mic.cAccFg : mic.cFg
            font.family: mic.fUi; font.pixelSize: 12; font.weight: Font.DemiBold }
        MouseArea { id: ba; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
    // label + value + slider on one row
    component Knob: Item {
        id: kn
        property string label: ""
        property string hint: ""
        property real from: -12
        property real to: 12
        property real step: 0.5
        property real value: 0
        property string suffix: " dB"
        property bool enabled: true
        signal moved(real v)
        width: parent ? parent.width : 0
        height: 46
        opacity: enabled ? 1 : 0.4
        Column {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 150
            Text { text: kn.label; color: mic.cFg; font.family: mic.fUi; font.pixelSize: 13 }
            Text { text: kn.hint; visible: text !== ""; color: mic.cMuted; font.family: mic.fUi; font.pixelSize: 10 }
        }
        Text {
            id: val
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 62; horizontalAlignment: Text.AlignRight
            text: (kn.value > 0 && kn.suffix === " dB" ? "+" : "") + (kn.step < 1 ? kn.value.toFixed(1) : Math.round(kn.value)) + kn.suffix
            color: mic.cFg; font.family: mic.fUi; font.pixelSize: 12; font.weight: Font.DemiBold
        }
        Item {
            anchors { left: parent.left; leftMargin: 158; right: val.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            height: 20
            readonly property real frac: Math.max(0, Math.min(1, (kn.value - kn.from) / (kn.to - kn.from)))
            readonly property real zero: Math.max(0, Math.min(1, (0 - kn.from) / (kn.to - kn.from)))
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: "#2a2e40" }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter; height: 6; radius: 3; color: mic.cAccent
                x: kn.from < 0 ? Math.min(parent.frac, parent.zero) * parent.width : 0
                width: kn.from < 0 ? Math.abs(parent.frac - parent.zero) * parent.width : parent.frac * parent.width
            }
            Rectangle { x: parent.width * parent.frac - 8; anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16; radius: 8; color: "#ffffff" }
            MouseArea {
                anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; enabled: kn.enabled
                function at(x) {
                    let v = kn.from + Math.max(0, Math.min(1, x / width)) * (kn.to - kn.from);
                    v = Math.round(v / kn.step) * kn.step;
                    kn.moved(Math.round(v * 100) / 100);
                }
                // no wheel handling on purpose: scrolling the page must never change a value
                onPressed: m => at(m.x)
                onPositionChanged: m => { if (pressed) at(m.x); }
            }
        }
    }

    // ── window ──────────────────────────────────────────────
    FloatingWindow {
        id: win
        visible: mic.shown
        title: "Mic Studio"
        implicitWidth: 1000
        implicitHeight: 700
        color: mic.cBg
        onVisibleChanged: if (!visible) mic.shown = false

        Flickable {
            anchors.fill: parent
            contentHeight: root.implicitHeight + 48
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: root
                x: 26; y: 22
                width: parent.width - 52
                spacing: 10

                // header
                Item {
                    width: parent.width; height: 46
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Text { text: ""; font.family: mic.fIcon; font.pixelSize: 22; color: mic.cAccent; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: "Mic Studio"; color: mic.cFg; font.family: mic.fUi; font.pixelSize: 24; font.weight: Font.ExtraBold }
                            Text { color: mic.cMuted; font.family: mic.fUi; font.pixelSize: 11
                                text: mic.running ? (mic.isDefault ? "Processing your voice · used by every app"
                                                                   : "Processing your voice · not selected as system input")
                                                  : "Off - apps hear the raw microphone" }
                        }
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Text { text: mic.cfg.enabled ? "On" : "Off"; color: mic.cFg; font.family: mic.fUi; font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter }
                        Toggle { anchors.verticalCenter: parent.verticalCenter; on: mic.cfg.enabled === true
                            onToggled: mic.set("enabled", !(mic.cfg.enabled === true)) }
                    }
                }

                // device + live monitor + meter
                Card {
                    width: parent.width; height: devCol.implicitHeight + 24
                    Column {
                        id: devCol
                        x: 16; y: 12; width: parent.width - 32; spacing: 10

                        // device picker
                        Rectangle {
                            width: parent.width; height: 40; radius: 12
                            color: dma.containsMouse ? mic.cCard2 : "#14ffffff"
                            Text { anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                text: ""; font.family: mic.fIcon; font.pixelSize: 13; color: mic.cAccent }
                            Text { anchors { left: parent.left; leftMargin: 40; right: parent.right; rightMargin: 34; verticalCenter: parent.verticalCenter }
                                text: mic.cfg.deviceDesc || "Pick a microphone"; elide: Text.ElideRight
                                color: mic.cFg; font.family: mic.fUi; font.pixelSize: 13 }
                            Text { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                text: mic.pickDev ? "" : ""; font.family: mic.fIcon; font.pixelSize: 11; color: mic.cMuted }
                            MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: mic.pickDev = !mic.pickDev }
                        }
                        Column {
                            width: parent.width; spacing: 3; visible: mic.pickDev
                            Repeater {
                                model: mic.sources
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: modelData.name === mic.cfg.device
                                    width: parent.width; height: 34; radius: 10
                                    color: sel ? Cfg.acc(0.15) : (sma.containsMouse ? mic.cCard2 : "transparent")
                                    Text { anchors { left: parent.left; leftMargin: 40; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                        text: modelData.desc; elide: Text.ElideRight
                                        color: sel ? mic.cAccent : mic.cFg; font.family: mic.fUi; font.pixelSize: 12 }
                                    MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { mic.pickDev = false; mic.set("device", modelData.name); } }
                                }
                            }
                        }

                        // level meter
                        Item {
                            width: parent.width; height: 34
                            Text { id: lvlLabel; anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                text: "Level"; color: mic.cFg; font.family: mic.fUi; font.pixelSize: 13; width: 60 }
                            Item {
                                anchors { left: lvlLabel.right; right: lvlNum.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                height: 16
                                Rectangle { anchors.fill: parent; radius: 8; color: "#2a2e40" }
                                ClippingRectangle {
                                    anchors.fill: parent; radius: 8; color: "transparent"
                                    Rectangle {
                                        width: parent.width * mic.lvl(mic.rms); height: parent.height
                                        Behavior on width { NumberAnimation { duration: 70 } }
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: Cfg.accent }
                                            GradientStop { position: 0.75; color: Cfg.accent }
                                            GradientStop { position: 1.0; color: "#f28fad" }
                                        }
                                    }
                                }
                                Rectangle { x: Math.min(parent.width - 3, parent.width * mic.lvl(mic.peakHold)); width: 3; height: parent.height
                                    color: "#ffffff"; opacity: 0.85; visible: mic.peakHold > -60
                                    Behavior on x { NumberAnimation { duration: 120 } } }
                            }
                            Text { id: lvlNum; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: 70; horizontalAlignment: Text.AlignRight
                                text: mic.running ? (mic.rms <= -60 ? "silent" : Math.round(mic.rms) + " dB") : "-"
                                color: mic.cMuted; font.family: mic.fUi; font.pixelSize: 12 }
                        }

                        Row {
                            width: parent.width; spacing: 10
                            Btn { text: mic.live ? "  Stop listening" : "  Hear myself"
                                primary: mic.live; onClicked: mic.set("live", !mic.live) }
                            Btn { text: mic.isDefault ? "  Used by all apps" : "Use for all apps"
                                primary: mic.isDefault; onClicked: mic.cmd(["default", mic.isDefault ? "off" : "on"]) }
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: mic.live
                                text: "use headphones, or it will howl"; color: mic.cWarn; font.family: mic.fUi; font.pixelSize: 11 }
                        }
                    }
                }

                // presets
                Head { text: "Presets" }
                Row {
                    width: parent.width; spacing: 8
                    Repeater {
                        model: [ { v: "natural", t: "Natural" }, { v: "clear", t: "Clear" }, { v: "bright", t: "Bright + high" },
                                 { v: "deep", t: "Deep" }, { v: "radio", t: "Radio" }, { v: "flat", t: "No effects" } ]
                        delegate: Btn { required property var modelData; text: modelData.t; onClicked: mic.preset(modelData.v) }
                    }
                }

                // two columns
                Row {
                    width: parent.width; spacing: 14

                    Column {
                        width: (parent.width - 14) / 2
                        spacing: 10
                        Head { text: "Voice" }
                        Card {
                            width: parent.width; height: voiceCol.implicitHeight + 16
                            Column {
                                id: voiceCol
                                x: 16; y: 8; width: parent.width - 32
                                Knob {
                                    label: "Pitch"; suffix: " st"; from: -8; to: 8; step: 0.5
                                    hint: mic.plugins.pitch ? "higher or lower voice" : "needs the plugin pack - run 18-mic.sh"
                                    enabled: mic.plugins.pitch === true
                                    value: mic.cfg.pitch; onMoved: v => mic.set("pitch", v)
                                }
                                Knob { label: "Clarity"; hint: "3.5 kHz - makes words crisp"
                                    value: mic.cfg.presence; onMoved: v => mic.set("presence", v) }
                                Knob { label: "Air"; hint: "9 kHz - light and open"
                                    value: mic.cfg.air; onMoved: v => mic.set("air", v) }
                                Knob { label: "Bass"; hint: "150 Hz - body and weight"
                                    value: mic.cfg.bass; onMoved: v => mic.set("bass", v) }
                                Knob { label: "Boxiness"; hint: "400 Hz - lower it to clean up mud"
                                    value: mic.cfg.mud; onMoved: v => mic.set("mud", v) }
                                Knob { label: "Mids"; hint: "1.2 kHz - presence of the voice"
                                    value: mic.cfg.mid; onMoved: v => mic.set("mid", v) }
                                Knob { label: "Low cut"; suffix: " Hz"; from: 20; to: 200; step: 5
                                    hint: "removes rumble and bumps"
                                    value: mic.cfg.hpf; onMoved: v => mic.set("hpf", v) }
                            }
                        }
                    }

                    Column {
                        width: (parent.width - 14) / 2
                        spacing: 10
                        Head { text: "Cleanup" }
                        Card {
                            width: parent.width; height: dynCol.implicitHeight + 16
                            Column {
                                id: dynCol
                                x: 16; y: 8; width: parent.width - 32
                                Knob {
                                    label: "Noise removal"; suffix: " %"; from: 0; to: 95; step: 5
                                    hint: mic.plugins.ns ? "kills fans, keyboard, hiss" : "needs the plugin pack - run 18-mic.sh"
                                    enabled: mic.plugins.ns === true
                                    value: mic.cfg.denoise; onMoved: v => mic.set("denoise", v)
                                }
                                Item {
                                    width: parent.width; height: 46
                                    opacity: mic.plugins.gate ? 1 : 0.4
                                    Column {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        Text { text: "Noise gate"; color: mic.cFg; font.family: mic.fUi; font.pixelSize: 13 }
                                        Text { text: mic.plugins.gate ? "mutes the mic when you are silent" : "needs the plugin pack"
                                            color: mic.cMuted; font.family: mic.fUi; font.pixelSize: 10 }
                                    }
                                    Toggle { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        on: mic.cfg.gateOn === true; onToggled: mic.set("gateOn", !(mic.cfg.gateOn === true)) }
                                }
                                Knob { label: "Gate threshold"; from: -70; to: -20; step: 1
                                    hint: "raise it if background still gets through"
                                    enabled: mic.plugins.gate === true && mic.cfg.gateOn === true
                                    value: mic.cfg.gate; onMoved: v => mic.set("gate", v) }

                                Item {
                                    width: parent.width; height: 46
                                    opacity: mic.plugins.comp ? 1 : 0.4
                                    Column {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        Text { text: "Compressor"; color: mic.cFg; font.family: mic.fUi; font.pixelSize: 13 }
                                        Text { text: mic.plugins.comp ? "evens out loud and quiet words" : "needs the plugin pack"
                                            color: mic.cMuted; font.family: mic.fUi; font.pixelSize: 10 }
                                    }
                                    Toggle { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        on: mic.cfg.compOn === true; onToggled: mic.set("compOn", !(mic.cfg.compOn === true)) }
                                }
                                Knob { label: "Comp. threshold"; from: -40; to: -5; step: 1
                                    enabled: mic.plugins.comp === true && mic.cfg.compOn === true
                                    value: mic.cfg.compThresh; onMoved: v => mic.set("compThresh", v) }
                                Knob { label: "Comp. amount"; suffix: " : 1"; from: 1; to: 10; step: 0.5
                                    enabled: mic.plugins.comp === true && mic.cfg.compOn === true
                                    value: mic.cfg.compRatio; onMoved: v => mic.set("compRatio", v) }
                                Knob { label: "Output volume"; from: -12; to: 18; step: 0.5
                                    hint: "final loudness of your voice"
                                    value: mic.cfg.gain; onMoved: v => mic.set("gain", v) }
                            }
                        }
                    }
                }

                // missing plugins hint
                Rectangle {
                    width: parent.width; height: 44; radius: 14
                    visible: !(mic.plugins.ns && mic.plugins.pitch && mic.plugins.comp && mic.plugins.gate)
                    color: "#26f28fad"
                    Text {
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        text: "Pitch, noise removal, gate and compressor need the plugin pack:  bash ~/.config/rice/18-mic.sh"
                        color: mic.cFg; font.family: mic.fUi; font.pixelSize: 12
                    }
                }
                Item { width: 1; height: 6 }
            }
        }
    }
}
