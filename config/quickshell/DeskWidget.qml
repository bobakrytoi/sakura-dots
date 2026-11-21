// sakura mono - one desktop widget, by kind. Used on the wallpaper (DesktopWidgets.qml)
// and, scaled down, in Settings > Desktop widgets (preview: true - no clicks, no shadow).
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

Item {
    id: w
    property string kind: "clock"
    property bool preview: false
    property string style: ""              // one of Cfg.widgetStyles[kind]; "" = the first
    readonly property string st: style !== "" ? style : ((Cfg.widgetStyles[kind] || [""])[0])
    implicitWidth: body.item ? body.item.implicitWidth : 10
    implicitHeight: body.item ? body.item.implicitHeight : 10

    // plain-text widgets (no glass card) switch to dark text over a light part of the wallpaper
    property bool darkText: false
    readonly property bool dk: darkText && ["clock", "date", "weather", "greeting"].includes(kind)
    readonly property color cFg:     dk ? "#22242e" : "#eceef4"       // solid ink, no glow (variant B)
    readonly property color cSoft:   dk ? "#353846" : "#cfd2de"
    readonly property color cMuted:  dk ? "#4a4d5c" : "#8a8fa3"
    readonly property color cAccent: dk ? Qt.darker(Cfg.accent, 2.4) : Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property color cCard:   Cfg.glass
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"

    Component.onCompleted: { if (kind === "sysmon") Desk.users++; if (kind === "visualizer") Desk.vizUsers++; if (kind === "hardware" || kind === "user") Desk.hwUsers++; }
    Component.onDestruction: { if (kind === "sysmon") Desk.users--; if (kind === "visualizer") Desk.vizUsers--; if (kind === "hardware" || kind === "user") Desk.hwUsers--; }

    Loader {
        id: body
        sourceComponent: w.kind === "clock" ? cClock : w.kind === "date" ? cDate : w.kind === "weather" ? cWeather
                       : w.kind === "player" ? cPlayer : w.kind === "forecast" ? cForecast : w.kind === "sysmon" ? cSys
                       : w.kind === "calendar" ? cCal : w.kind === "analog" ? cAnalog : w.kind === "greeting" ? cGreet
                       : w.kind === "visualizer" ? cViz : w.kind === "worldclock" ? cWorld : w.kind === "dayprogress" ? cProg
                       : w.kind === "note" ? cNote : w.kind === "todo" ? cTodo : w.kind === "timer" ? cTimer
                       : w.kind === "hardware" ? cHw : w.kind === "user" ? cUser : w.kind === "screentime" ? cScreen : null
        // soft blurred shadow so text stays readable on bright wallpapers (same look as before)
        layer.enabled: !w.preview && !w.dk && (w.kind === "clock" || w.kind === "date" || w.kind === "weather" || w.kind === "greeting")
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: w.dk ? "#33ffffff" : "#66000000"; shadowBlur: 0.3; shadowVerticalOffset: 1; shadowHorizontalOffset: 0; blurMax: 12 }   // tight, soft: readable without a grey halo
    }

    component Glass: Rectangle { radius: 22; color: w.cCard; border.width: 1; border.color: "#1fffffff" }

    Component {
        id: cClock
        Item {
            readonly property string ts: Cfg.timeStr(Desk.now, Cfg.data.seconds === true).replace(/ [AP]M$/, "")
            implicitWidth: w.st === "stacked" ? stk.implicitWidth : w.st === "minimal" ? mini.implicitWidth : big.implicitWidth
            implicitHeight: w.st === "stacked" ? stk.implicitHeight : w.st === "minimal" ? mini.implicitHeight : big.implicitHeight
            Text { id: big; visible: w.st === "big"; text: parent.ts
                   font.features: { "tnum": 1 }; font.family: "Inter Display"; font.pixelSize: 128; font.weight: Font.Black; color: w.cFg }
            Column {
                id: stk; visible: w.st === "stacked"; spacing: -28
                Text { text: parent.parent.ts.split(":")[0]; font.features: { "tnum": 1 }; font.family: "Inter Display"; font.pixelSize: 120; font.weight: Font.Black; color: w.cFg }
                Text { text: parent.parent.ts.split(":")[1]; font.features: { "tnum": 1 }; font.family: "Inter Display"; font.pixelSize: 120; font.weight: Font.Black; color: w.cAccent }
            }
            Row {
                id: mini; visible: w.st === "minimal"; spacing: 14
                Text { text: parent.parent.ts; font.features: { "tnum": 1 }; font.family: "Inter Display"; font.pixelSize: 64; font.weight: Font.Light; color: w.cFg }
                Rectangle { width: 3; height: 52; radius: 2; color: w.cAccent; anchors.verticalCenter: parent.verticalCenter }
                Column { anchors.verticalCenter: parent.verticalCenter
                    Text { text: Cfg.cap(Cfg.locale.toString(Desk.now, "dddd")); font.family: w.fUi; font.pixelSize: 18; font.weight: Font.Bold; color: w.cFg }
                    Text { text: Cfg.locale.toString(Desk.now, "d MMMM"); font.family: w.fUi; font.pixelSize: 15; color: w.cSoft } }
            }
        }
    }
    Component {
        id: cDate
        Text { text: Cfg.dateLong(Desk.now); font.family: w.fUi; font.pixelSize: 26; font.weight: Font.DemiBold; color: w.cSoft }
    }
    Component {
        id: cGreet
        Text { text: Desk.greeting() + ", " + Quickshell.env("USER"); font.family: w.fUi; font.pixelSize: 30; font.weight: Font.Bold; color: w.cFg }
    }
    Component {
        id: cWeather
        Row {
            spacing: 10
            Text { text: Desk.weather ? Cfg.temp(Desk.weather.current.temperature_2m) : "-"; font.family: w.fUi; font.pixelSize: 22; font.weight: Font.Bold; color: w.cAccent }
            Text { text: Desk.weather ? Cfg.wText(Desk.weather.current.weather_code) + " · " + Desk.weather.city : Cfg.tr("loading…")
                   font.family: w.fUi; font.pixelSize: 17; color: w.cSoft; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    Component {
        id: cForecast
        Glass {
            implicitWidth: 380; implicitHeight: 118
            Row {
                anchors.centerIn: parent; spacing: 6
                Repeater {
                    model: 5
                    Column {
                        required property int index
                        readonly property var d: Desk.weather ? Desk.weather.daily : null
                        width: 66; spacing: 4
                        Text { anchors.horizontalCenter: parent.horizontalCenter; font.family: w.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: w.cMuted
                               text: !parent.d ? "" : index === 0 ? Cfg.tr("Today") : Cfg.dayShort(new Date(parent.d.time[index] + "T12:00")) }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; font.family: w.fIcon; font.pixelSize: 22; color: w.cAccent
                               text: { const c = parent.d ? parent.d.weather_code[index] : 0;   // Material weather icons (Symbols Nerd Font)
                                       return String.fromCodePoint(c === 0 ? 0xF0599 : c <= 2 ? 0xF0595 : c === 3 ? 0xF0590 : c <= 48 ? 0xF0591
                                            : (c <= 67 || (c >= 80 && c <= 82)) ? 0xF0597 : c <= 86 ? 0xF0598 : 0xF0593); } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; font.family: w.fUi; font.pixelSize: 13; font.weight: Font.Bold; color: w.cFg
                               text: parent.d ? Cfg.temp(parent.d.temperature_2m_max[index]) : "" }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; font.family: w.fUi; font.pixelSize: 11; color: w.cMuted
                               text: parent.d ? Cfg.temp(parent.d.temperature_2m_min[index]) : "" }
                    }
                }
            }
        }
    }
    Component {
        id: cPlayer
        Glass {
            implicitWidth: 380; implicitHeight: 96
            readonly property var p: Desk.player
            opacity: p || w.preview ? 1 : 0
            ClippingRectangle {
                id: art
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                width: 72; height: 72; radius: 16; color: "#1fffffff"
                Image { anchors.fill: parent; source: Desk.player ? (Desk.player.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                Text { anchors.centerIn: parent; visible: !Desk.player || (Desk.player.trackArtUrl || "") === ""; text: ""; font.family: w.fIcon; font.pixelSize: 24; color: w.cMuted }
            }
            Column {
                anchors { left: art.right; leftMargin: 14; right: ctl.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 3
                Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.p ? (parent.parent.p.trackTitle || "") : Cfg.tr("Nothing playing")
                       font.family: w.fUi; font.pixelSize: 15; font.weight: Font.Bold; color: w.cFg }
                Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.p ? (parent.parent.p.trackArtist || "") : ""
                       font.family: w.fUi; font.pixelSize: 12; color: w.cAccent }
            }
            Row {
                id: ctl
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 2
                Repeater {
                    model: [ "prev", "play", "next" ]
                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool big: modelData === "play"
                        width: big ? 40 : 30; height: big ? 40 : 30; radius: big ? 20 : 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: big ? w.cAccent : (ba.containsMouse ? "#22ffffff" : "transparent")
                        Text { anchors.centerIn: parent; font.family: w.fIcon; font.pixelSize: big ? 15 : 12
                               color: big ? w.cAccFg : w.cFg
                               text: modelData === "prev" ? "" : modelData === "next" ? "" : (Desk.player && Desk.player.isPlaying ? "" : "") }
                        MouseArea { id: ba; anchors.fill: parent; hoverEnabled: true; enabled: !w.preview; cursorShape: Qt.PointingHandCursor
                            onClicked: { const p = Desk.player; if (!p) return;
                                if (modelData === "prev") p.previous(); else if (modelData === "next") p.next(); else p.togglePlaying(); } }
                    }
                }
            }
        }
    }
    Component {
        id: cSys
        Glass {
            implicitWidth: 300; implicitHeight: 150
            Column {
                anchors { fill: parent; margins: 18 }
                spacing: 10
                Repeater {
                    model: [ { t: "CPU", v: Desk.cpu, s: Math.round(Desk.cpu * 100) + "%" },
                             { t: "RAM", v: Desk.ram, s: Desk.ramUsed.toFixed(1) + " / " + Desk.ramTotal.toFixed(0) + " GB" },
                             { t: "Disk", v: Desk.disk, s: Math.round(Desk.disk * 100) + "%" } ]
                    Column {
                        required property var modelData
                        width: parent.width; spacing: 5
                        Item { width: parent.width; height: 16
                            Text { text: Cfg.tr(modelData.t); font.family: w.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: w.cFg }
                            Text { anchors.right: parent.right; text: modelData.s; font.family: w.fUi; font.pixelSize: 12; color: w.cMuted } }
                        Rectangle { width: parent.width; height: 6; radius: 3; color: "#26ffffff"
                            Rectangle { width: parent.width * Math.max(0.02, modelData.v); height: 6; radius: 3; color: w.cAccent
                                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } } }
                    }
                }
            }
        }
    }
    Component {
        id: cCal
        Glass {
            implicitWidth: 300; implicitHeight: w.st === "compact" ? 104 : 290
            // compact: just this week
            Row {
                visible: w.st === "compact"
                anchors.centerIn: parent; spacing: 4
                Repeater {
                    model: 7
                    Rectangle {
                        required property int index
                        readonly property var d: { const ws = Cfg.data.weekStart === 0 ? 0 : 1; const n = Desk.now; const back = (n.getDay() - ws + 7) % 7;
                                                   return new Date(n.getFullYear(), n.getMonth(), n.getDate() - back + index); }
                        readonly property bool today: d.getDate() === Desk.now.getDate() && d.getMonth() === Desk.now.getMonth()
                        width: 36; height: 64; radius: 12; color: today ? w.cAccent : "transparent"
                        Column { anchors.centerIn: parent; spacing: 4
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Cfg.dayShort(parent.parent.d).slice(0, 2)
                                   font.family: w.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: parent.parent.today ? w.cAccFg : w.cMuted }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.d.getDate()
                                   font.family: w.fUi; font.pixelSize: 16; font.weight: Font.Bold; color: parent.parent.today ? w.cAccFg : w.cFg } }
                    }
                }
            }
            readonly property var first: new Date(Desk.now.getFullYear(), Desk.now.getMonth(), 1)
            readonly property int ws: Cfg.data.weekStart === 0 ? 0 : 1
            readonly property int lead: (first.getDay() - ws + 7) % 7
            readonly property int days: new Date(Desk.now.getFullYear(), Desk.now.getMonth() + 1, 0).getDate()
            Column {
                visible: w.st !== "compact"
                anchors { fill: parent; margins: 16 }
                spacing: 8
                Text { text: Cfg.cap(Cfg.locale.toString(Desk.now, "LLLL yyyy")); font.family: w.fUi; font.pixelSize: 16; font.weight: Font.Bold; color: w.cFg }
                Grid {
                    columns: 7; columnSpacing: 2; rowSpacing: 2
                    Repeater {
                        model: 7
                        Text { required property int index; width: 36; height: 22; horizontalAlignment: Text.AlignHCenter
                               text: Cfg.cap(Cfg.locale.dayName((index + parent.parent.parent.ws) % 7, Locale.ShortFormat)).slice(0, 2)
                               font.family: w.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: w.cMuted }
                    }
                    Repeater {
                        model: 42
                        Rectangle {
                            required property int index
                            readonly property int day: index - parent.parent.parent.lead + 1
                            readonly property bool real: day >= 1 && day <= parent.parent.parent.days
                            readonly property bool today: real && day === Desk.now.getDate()
                            visible: index < Math.ceil((parent.parent.parent.lead + parent.parent.parent.days) / 7) * 7
                            width: 36; height: 30; radius: 10
                            color: today ? w.cAccent : "transparent"
                            Text { anchors.centerIn: parent; text: parent.real ? parent.day : ""
                                   font.family: w.fUi; font.pixelSize: 12; font.weight: parent.today ? Font.Bold : Font.Normal
                                   color: parent.today ? w.cAccFg : w.cFg }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: cAnalog
        Item {
            implicitWidth: 200; implicitHeight: 200
            Rectangle { visible: w.st !== "minimal"; anchors.fill: parent; radius: width / 2; color: w.cCard; border.width: 1; border.color: "#1fffffff" }
            Repeater {
                model: w.st === "minimal" ? [0, 3, 6, 9] : 12
                Rectangle { required property var modelData
                    readonly property int index: modelData
                    x: 100 - width / 2 + Math.sin(index * Math.PI / 6) * 82; y: 100 - height / 2 - Math.cos(index * Math.PI / 6) * 82
                    width: index % 3 === 0 ? 6 : 4; height: width; radius: width / 2; color: index % 3 === 0 ? w.cAccent : w.cMuted }
            }
            component Hand: Rectangle {
                property real angle: 0
                x: 100 - width / 2; y: 100 - height
                radius: width / 2; antialiasing: true
                rotation: angle; transformOrigin: Item.Bottom
            }
            Hand { width: 7; height: 58; color: w.cFg; angle: (Desk.now.getHours() % 12 + Desk.now.getMinutes() / 60) * 30 }
            Hand { width: 5; height: 80; color: w.cSoft; angle: (Desk.now.getMinutes() + Desk.now.getSeconds() / 60) * 6 }
            Hand { width: 2; height: 86; color: w.cAccent; angle: Desk.now.getSeconds() * 6 }
            Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: w.cAccent }
        }
    }

    // ── visualizer (cava) ───────────────────────────────────
    Component {
        id: cViz
        Glass {
            implicitWidth: 420; implicitHeight: 120
            readonly property var b: Desk.bars.length ? Desk.bars : (w.preview ? Array.from({ length: 48 }, (x, i) => 0.25 + 0.6 * Math.abs(Math.sin(i / 4))) : [])
            readonly property int n: Math.max(8, b.length || (Cfg.data.vizBars || 48))
            Row {
                visible: w.st !== "line"
                anchors { fill: parent; margins: 16 }
                spacing: 2
                Repeater {
                    model: parent.parent.n
                    Item {
                        required property int index
                        readonly property real v: Math.max(0.03, parent.parent.b[index] || 0)
                        width: (parent.width - 2 * (parent.parent.n - 1)) / parent.parent.n; height: parent.height
                        Rectangle {
                            width: parent.width; radius: width / 2
                            height: Math.max(width, parent.height * (w.st === "mirror" ? parent.v : parent.v))
                            anchors.bottom: w.st === "mirror" ? undefined : parent.bottom
                            anchors.verticalCenter: w.st === "mirror" ? parent.verticalCenter : undefined
                            color: Cfg.data.vizColor === "rainbow" ? Qt.hsla((parent.index / parent.parent.parent.n + 0.9) % 1, 0.75, 0.72, 0.45 + 0.55 * parent.v)
                                 : Cfg.acc(0.35 + 0.65 * parent.v)
                            Behavior on height { NumberAnimation { duration: 60 } }
                        }
                    }
                }
            }
            Canvas {
                id: vline
                visible: w.st === "line"
                anchors { fill: parent; margins: 16 }
                readonly property var b: parent.b
                onBChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d"); c.reset();
                    const n = b.length; if (n < 2) return;
                    c.beginPath();
                    for (let i = 0; i < n; i++) {
                        const x = i * width / (n - 1), y = height - Math.max(0.02, b[i]) * height;
                        if (i === 0) c.moveTo(x, y); else { const px = (i - 0.5) * width / (n - 1); c.quadraticCurveTo(px, height - Math.max(0.02, b[i - 1]) * height, x, y); }
                    }
                    c.lineWidth = 3; c.strokeStyle = w.cAccent; c.lineCap = "round"; c.stroke();
                    c.lineTo(width, height); c.lineTo(0, height); c.closePath();
                    c.fillStyle = Qt.rgba(w.cAccent.r, w.cAccent.g, w.cAccent.b, 0.18); c.fill();
                }
            }
        }
    }

    // ── world clock ─────────────────────────────────────────
    Component {
        id: cWorld
        Glass {
            implicitWidth: 300; implicitHeight: wcol.implicitHeight + 28
            Column {
                id: wcol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 2
                Repeater {
                    model: Cfg.worldClocks
                    Item {
                        required property var modelData
                        readonly property var d: Desk.timeIn(modelData.tz)
                        readonly property int diff: d ? Math.round((d.getTime() - Desk.now.getTime()) / 3600000) : 0
                        width: parent.width; height: 44
                        Column { anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            Text { text: Cfg.tr(parent.parent.modelData.name); font.family: w.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: w.cFg }
                            Text { text: parent.parent.diff === 0 ? Cfg.tr("Today") : (parent.parent.diff > 0 ? "+" : "") + parent.parent.diff + " " + Cfg.tr("h")
                                   font.family: w.fUi; font.pixelSize: 11; color: w.cMuted } }
                        Row { anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            Text { anchors.verticalCenter: parent.verticalCenter; font.family: w.fIcon; font.pixelSize: 13
                                   readonly property int h: parent.parent.d ? parent.parent.d.getHours() : 12
                                   text: h >= 7 && h < 19 ? "" : ""; color: h >= 7 && h < 19 ? w.cAccent : w.cMuted }
                            Text { text: parent.parent.d ? Cfg.timeStr(parent.parent.d, false) : "--:--"; font.family: w.fUi; font.pixelSize: 22; font.weight: Font.Bold; color: w.cFg } }
                    }
                }
            }
        }
    }

    // ── day / week / month / year progress ──────────────────
    Component {
        id: cProg
        Glass {
            readonly property var vals: {
                const n = Desk.now, y = n.getFullYear();
                const day = (n.getHours() * 3600 + n.getMinutes() * 60 + n.getSeconds()) / 86400;
                const ws = Cfg.data.weekStart === 0 ? 0 : 1;
                const week = (((n.getDay() - ws + 7) % 7) + day) / 7;
                const dim = new Date(y, n.getMonth() + 1, 0).getDate();
                const month = (n.getDate() - 1 + day) / dim;
                const y0 = new Date(y, 0, 1), y1 = new Date(y + 1, 0, 1);
                const year = (n - y0) / (y1 - y0);
                return [ { t: "Day", v: day }, { t: "Week", v: week }, { t: "Month", v: month }, { t: "Year", v: year } ];
            }
            implicitWidth: w.st === "rings" ? 380 : 300; implicitHeight: w.st === "rings" ? 130 : 170
            Column {
                visible: w.st !== "rings"
                anchors { fill: parent; margins: 18 }
                spacing: 10
                Repeater {
                    model: 4
                    Column {
                        required property int index
                        readonly property var modelData: parent.parent.vals[index]
                        width: parent.width; spacing: 5
                        Item { width: parent.width; height: 15
                            Text { text: Cfg.tr(modelData.t); font.family: w.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: w.cFg }
                            Text { anchors.right: parent.right; text: Math.floor(modelData.v * 100) + "%"; font.family: w.fUi; font.pixelSize: 12; color: w.cMuted } }
                        Rectangle { width: parent.width; height: 6; radius: 3; color: "#26ffffff"
                            Rectangle { width: parent.width * Math.max(0.02, modelData.v); height: 6; radius: 3; color: w.cAccent } }
                    }
                }
            }
            Row {
                visible: w.st === "rings"
                anchors.centerIn: parent; spacing: 14
                Repeater {
                    model: 4
                    Item {
                        required property int index
                        readonly property var modelData: parent.parent.vals[index]
                        width: 74; height: 96
                        Canvas {
                            width: 74; height: 74
                            readonly property real v: modelData.v
                            onVChanged: requestPaint()
                            Component.onCompleted: requestPaint()
                            onPaint: {
                                const c = getContext("2d"); c.reset(); c.lineWidth = 7; c.lineCap = "round";
                                c.beginPath(); c.arc(37, 37, 32, 0, 2 * Math.PI); c.strokeStyle = "rgba(255,255,255,0.15)"; c.stroke();
                                c.beginPath(); c.arc(37, 37, 32, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0.01, v)); c.strokeStyle = w.cAccent; c.stroke();
                            }
                            Text { anchors.centerIn: parent; text: Math.floor(modelData.v * 100) + "%"; font.family: w.fUi; font.pixelSize: 14; font.weight: Font.Bold; color: w.cFg }
                        }
                        Text { anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                               text: Cfg.tr(modelData.t); font.family: w.fUi; font.pixelSize: 11; color: w.cMuted }
                    }
                }
            }
        }
    }

    // ── sticky note ─────────────────────────────────────────
    Component {
        id: cNote
        Glass {
            implicitWidth: 280; implicitHeight: 220
            Rectangle { x: 18; y: 18; height: 3; radius: 2; width: 36; color: w.cAccent }
            Flickable {
                id: nf
                anchors { fill: parent; margins: 18; topMargin: 30 }
                contentHeight: ned.implicitHeight; clip: true
                boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                    id: ned
                    width: nf.width
                    readOnly: w.preview
                    wrapMode: TextEdit.Wrap
                    color: w.cFg; selectionColor: Cfg.acc(0.4); font.family: w.fUi; font.pixelSize: 14
                    text: Desk.note
                    onTextChanged: if (activeFocus && text !== Desk.note) Desk.setNote(text)
                    Text { visible: ned.text === ""; text: Cfg.tr("Write something…"); color: w.cMuted; font: ned.font }
                }
            }
        }
    }

    // ── to-do ───────────────────────────────────────────────
    Component {
        id: cTodo
        Glass {
            implicitWidth: 300; implicitHeight: Math.max(160, tcol.implicitHeight + 32)
            Column {
                id: tcol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 4
                Row { spacing: 8; bottomPadding: 4
                    Text { text: Cfg.tr("To-do list"); font.family: w.fUi; font.pixelSize: 15; font.weight: Font.Bold; color: w.cFg }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Desk.todos.filter(x => !x.done).length; font.family: w.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: w.cAccent } }
                Text { visible: Desk.todos.length === 0; text: Cfg.tr("Nothing to do"); font.family: w.fUi; font.pixelSize: 12; color: w.cMuted; bottomPadding: 4 }
                Repeater {
                    model: Desk.todos
                    Item {
                        required property var modelData
                        required property int index
                        width: tcol.width; height: Math.max(28, tt.implicitHeight + 8)
                        Rectangle { anchors.fill: parent; radius: 8; color: tma.containsMouse ? "#14ffffff" : "transparent" }
                        Rectangle {
                            id: box
                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                            width: 16; height: 16; radius: 5
                            color: modelData.done ? w.cAccent : "transparent"; border.width: modelData.done ? 0 : 1.5; border.color: w.cMuted
                            Text { anchors.centerIn: parent; visible: modelData.done; text: ""; font.family: w.fIcon; font.pixelSize: 9; color: w.cAccFg }
                        }
                        Text { id: tt; anchors { left: box.right; leftMargin: 10; right: del.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                               text: modelData.t; wrapMode: Text.Wrap; font.family: w.fUi; font.pixelSize: 13; font.strikeout: modelData.done
                               color: modelData.done ? w.cMuted : w.cFg }
                        MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; enabled: !w.preview; cursorShape: Qt.PointingHandCursor; onClicked: Desk.toggleTodo(index) }
                        Text { id: del; anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                               visible: tma.containsMouse || dma.containsMouse; text: ""; font.family: w.fIcon; font.pixelSize: 11; color: dma.containsMouse ? w.cAccent : w.cMuted
                               MouseArea { id: dma; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; enabled: !w.preview; cursorShape: Qt.PointingHandCursor; onClicked: Desk.removeTodo(index) } }
                    }
                }
                Rectangle {
                    width: tcol.width; height: 32; radius: 10; color: "#14ffffff"
                    border.width: tin.activeFocus ? 1 : 0; border.color: Cfg.acc(0.5)
                    Text { id: plus; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: ""; font.family: w.fIcon; font.pixelSize: 10; color: w.cAccent }
                    TextInput {
                        id: tin
                        anchors { left: plus.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        readOnly: w.preview; clip: true
                        color: w.cFg; selectionColor: Cfg.acc(0.4); font.family: w.fUi; font.pixelSize: 13
                        onAccepted: { Desk.addTodo(text); text = ""; }
                        Keys.onEscapePressed: { text = ""; focus = false; }
                        Text { visible: tin.text === ""; text: Cfg.tr("Add a task"); color: w.cMuted; font: tin.font }
                    }
                }
            }
        }
    }

    // ── timer (the dashboard's, Timers.qml) ─────────────────
    Component {
        id: cTimer
        Glass {
            implicitWidth: 260; implicitHeight: 150
            Timer { interval: 250; repeat: true; running: Timers.tRunning || Timers.swRunning; onTriggered: Timers.now = Date.now() }
            readonly property bool sw: Timers.swRunning || (!Timers.tRunning && Timers.swElapsed(Timers.now) > 0)
            readonly property real ms: sw ? Timers.swElapsed(Timers.now) : Timers.tRemain
            function fmt(ms) { const s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
                               return (h > 0 ? h + ":" + String(m).padStart(2, "0") : String(m).padStart(2, "0")) + ":" + String(x).padStart(2, "0"); }
            Column {
                anchors.centerIn: parent; spacing: 8
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Timers.pomo ? Cfg.tr(Timers.pomoPhase === "focus" ? "Focus" : "Break") + " · " + (Timers.pomoDone % (Cfg.data.pomoCycles || 4) + (Timers.pomoPhase === "focus" ? 1 : 0)) + "/" + (Cfg.data.pomoCycles || 4)
                                                                     : Cfg.tr(parent.parent.sw ? "Stopwatch" : "Timer"); font.family: w.fUi; font.pixelSize: 11; font.weight: Font.Bold; color: w.cMuted }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.fmt(parent.parent.ms); font.family: "Inter Display"; font.pixelSize: 42; font.weight: Font.Black; color: w.cFg }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                    Repeater {
                        model: [ { k: "reset", i: "" }, { k: "play", i: "" }, { k: "add", i: "+1" } ]
                        Rectangle {
                            required property var modelData
                            readonly property bool big: modelData.k === "play"
                            readonly property bool running: Timers.tRunning || Timers.swRunning
                            width: big ? 40 : 32; height: big ? 40 : 32; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
                            color: big ? w.cAccent : (bm.containsMouse ? "#22ffffff" : "#14ffffff")
                            Text { anchors.centerIn: parent; text: parent.big ? (parent.running ? "" : "") : parent.modelData.i
                                   font.family: parent.modelData.k === "add" ? w.fUi : w.fIcon; font.pixelSize: parent.big ? 14 : 12; font.weight: Font.Bold
                                   color: parent.big ? w.cAccFg : w.cFg }
                            MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; enabled: !w.preview; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const g = parent.parent.parent.parent, k = parent.modelData.k;
                                    if (g.sw) { if (k === "play") Timers.swToggle(); else if (k === "reset") Timers.swReset(); else Timers.swLap(); }
                                    else { if (k === "play") { if (Timers.tRunning) Timers.tPause(); else Timers.tStart(); } else if (k === "reset") Timers.tReset(); else Timers.tAdd(60000); }
                                } }
                        }
                    }
                }
            }
        }
    }

    // ── hardware ────────────────────────────────────────────
    Component {
        id: cHw
        Glass {
            implicitWidth: 340; implicitHeight: 132
            readonly property var h: Desk.hw
            readonly property var items: {
                        const h = Desk.hw;
                        return [ { t: "CPU", i: String.fromCodePoint(0xF035B), v: h ? h.cpu : 0, tmp: h ? h.cpuTemp : null },
                                 { t: "GPU", i: String.fromCodePoint(0xf0379), v: h && h.gpu ? h.gpu.usage : 0, tmp: h && h.gpu ? h.gpu.temp : null },
                                 { t: "RAM", i: String.fromCodePoint(0xF061A), v: h ? 100 * h.memUsed / h.memTotal : 0, tmp: null, sub: h ? (h.memUsed / 1073741824).toFixed(1) + " GB" : "" } ];
            }
            Row {
                anchors.centerIn: parent; spacing: 10
                Repeater {
                    model: 3
                    Item {
                        required property int index
                        readonly property var modelData: parent.parent.items[index]
                        width: 100; height: 100
                        Canvas {
                            id: rc; width: 70; height: 70; anchors.horizontalCenter: parent.horizontalCenter
                            readonly property real v: modelData.v
                            onVChanged: requestPaint()
                            Component.onCompleted: requestPaint()
                            onPaint: {
                                const c = getContext("2d"); c.reset(); c.lineWidth = 6; c.lineCap = "round";
                                c.beginPath(); c.arc(35, 35, 30, 0.75 * Math.PI, 2.25 * Math.PI); c.strokeStyle = "rgba(255,255,255,0.15)"; c.stroke();
                                c.beginPath(); c.arc(35, 35, 30, 0.75 * Math.PI, 0.75 * Math.PI + 1.5 * Math.PI * Math.max(0.01, v / 100)); c.strokeStyle = w.cAccent; c.stroke();
                            }
                            Column { anchors.centerIn: parent
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.v) + "%"; font.family: w.fUi; font.pixelSize: 15; font.weight: Font.Bold; color: w.cFg }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.i; font.family: w.fIcon; font.pixelSize: 13; color: w.cMuted } }
                        }
                        Text { anchors { top: rc.bottom; topMargin: 2; horizontalCenter: parent.horizontalCenter }
                               text: modelData.t + (modelData.tmp !== null && modelData.tmp !== undefined ? " · " + Math.round(modelData.tmp) + "°" : modelData.sub ? " · " + modelData.sub : "")
                               font.family: w.fUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: w.cSoft }
                    }
                }
            }
        }
    }

    // ── user card ───────────────────────────────────────────
    Component {
        id: cUser
        Glass {
            implicitWidth: 320; implicitHeight: 104
            ClippingRectangle {
                id: av
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                width: 68; height: 68; radius: 34; color: w.cAccent
                Avatar { anchors.fill: parent; ring: 3; ringColor: "transparent" }
            }
            Column {
                anchors { left: av.right; leftMargin: 16; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 5
                Text { text: Desk.greeting() + ", " + Quickshell.env("USER"); elide: Text.ElideRight; width: parent.width; font.family: w.fUi; font.pixelSize: 16; font.weight: Font.Bold; color: w.cFg }
                Row { spacing: 6
                    Rectangle { width: dl.implicitWidth + 16; height: 22; radius: 8; color: "#14ffffff"
                        Row { id: dl; anchors.centerIn: parent; spacing: 5
                            Text { text: ""; font.family: w.fIcon; font.pixelSize: 11; color: w.cAccent; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Arch · Hyprland"; font.family: w.fUi; font.pixelSize: 11; color: w.cFg; anchors.verticalCenter: parent.verticalCenter } } } }
                Text { readonly property real up: Desk.hw ? Desk.hw.uptime : 0
                       text: Cfg.tr("Uptime") + " " + (Math.floor(up / 3600) > 0 ? Math.floor(up / 3600) + " " + Cfg.tr("h") + " " : "") + Math.floor(up % 3600 / 60) + " " + Cfg.tr("min")
                       font.family: w.fUi; font.pixelSize: 11; color: w.cMuted }
            }
        }
    }

    // ── screen time (ScreenTime.qml) ────────────────────────
    Component {
        id: cScreen
        Glass {
            implicitWidth: 320; implicitHeight: w.st === "week" ? 190 : Math.max(120, sc.implicitHeight + 32)
            Timer { id: stTick; interval: 60000; running: true; repeat: true; property int n: 0; onTriggered: n++ }
            readonly property var tops: (stTick.n, ScreenTime.days, ScreenTime.top(w.st === "week" ? "week" : "today"))
            readonly property real tot: tops.reduce((s, x) => s + x.secs, 0)
            Column {
                id: sc
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 8
                Item { width: parent.width; height: 20
                    Text { text: Cfg.tr("Screen time") + " · " + Cfg.tr(w.st === "week" ? "Week" : "Today"); font.family: w.fUi; font.pixelSize: 12; font.weight: Font.Bold; color: w.cMuted; anchors.verticalCenter: parent.verticalCenter }
                    Text { anchors.right: parent.right; text: ScreenTime.fmt(parent.parent.parent.tot); font.family: w.fUi; font.pixelSize: 15; font.weight: Font.Bold; color: w.cFg; anchors.verticalCenter: parent.verticalCenter } }
                // today: top apps
                Repeater {
                    model: w.st === "week" ? [] : parent.parent.tops.slice(0, 5)
                    Item {
                        required property var modelData
                        width: sc.width; height: 30
                        IconImage { id: ai; anchors.verticalCenter: parent.verticalCenter; implicitSize: 20; source: ScreenTime.appIcon(modelData.app) }
                        Column { anchors { left: ai.right; leftMargin: 10; right: parent.right; verticalCenter: parent.verticalCenter } spacing: 4
                            Item { width: parent.width; height: 14
                                Text { text: ScreenTime.appName(modelData.app); width: parent.width - 70; elide: Text.ElideRight; font.family: w.fUi; font.pixelSize: 12; color: w.cFg }
                                Text { anchors.right: parent.right; text: ScreenTime.fmt(modelData.secs); font.family: w.fUi; font.pixelSize: 11; color: w.cMuted } }
                            Rectangle { width: parent.width; height: 4; radius: 2; color: "#26ffffff"
                                Rectangle { width: parent.width * Math.max(0.02, modelData.secs / Math.max(1, sc.parent.tops[0].secs)); height: 4; radius: 2; color: w.cAccent } } }
                    }
                }
                Text { visible: w.st !== "week" && parent.parent.tops.length === 0; text: Cfg.tr("Nothing counted yet"); font.family: w.fUi; font.pixelSize: 12; color: w.cMuted }
                // week: a bar per day
                Row {
                    visible: w.st === "week"
                    width: sc.width; height: 120; spacing: 8
                    readonly property var wk: (stTick.n, ScreenTime.days, ScreenTime.week())
                    readonly property real mx: Math.max(3600, ...wk.map(x => x.secs))
                    Repeater {
                        model: parent.wk
                        Item {
                            required property var modelData
                            required property int index
                            width: (sc.width - 48) / 7; height: 120
                            Rectangle {
                                anchors { bottom: lbl.top; bottomMargin: 6; horizontalCenter: parent.horizontalCenter }
                                width: parent.width; radius: 6
                                height: Math.max(6, (parent.height - 24) * modelData.secs / parent.parent.mx)
                                color: index === 6 ? w.cAccent : Cfg.acc(0.4)
                            }
                            Text { id: lbl; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                                   text: Cfg.dayShort(modelData.date).slice(0, 2); font.family: w.fUi; font.pixelSize: 11; color: index === 6 ? w.cFg : w.cMuted }
                        }
                    }
                }
            }
        }
    }
}
