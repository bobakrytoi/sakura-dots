// sakura mono - the drawn mascot used by Mascot.qml: a round sakura spirit with petal ears and a hand on the edge.
// Drawing space 120×150, peeking from the RIGHT edge (hand on the right); Mascot.qml scales / mirrors / rotates it.
// Poses: idle happy sleepy surprised sing shy wave pout run held (caught, feet dangle) fly (thrown) dizzy (landed). Only plain Rectangles/Text - no Canvas, so the idle
// motions (bob, ear wiggle, blink, floating z / notes) are cheap transforms, and they only run while `active`.
// More poses: sit (on a window edge, legs dangling), hot (♨, sweat), box (hauls a box). `beat` (0-1, music bass)
// makes her bounce; `outfit` umbrella | scarf | shades; `particles` rain | snow | petals | leaves fall around her;
// `tint` recolours her (the friend). `custom` = a picture to show instead of the drawing (it still bobs).
import QtQuick

Item {
    id: a
    width: 120; height: 150
    property string pose: "idle"
    property bool talking: false
    property bool active: true
    property bool flip: false       // drawn mirrored: keep glyphs readable
    property real textRot: 0        // drawn upside down (top edge): keep glyphs upright
    property string custom: ""
    property real beat: 0
    property real pulse: beat       // the beat clock for props (fan shake, counting flips) - even when the body keeps still
    property string outfit: ""
    property string particles: ""
    property string tint: ""
    // flex (Mascot.qml, triple Shift): props in her paw, a gold chain, standing on her feet
    property string prop: ""        // "" | fan (a fan of bills, shaken) | gun (money gun) | count (counting a stack)
    property bool bling: false
    property bool stand: false
    property bool girl: false       // a bow on the head and lashes (the flex finale's girls)
    property bool hearts: false     // ♥ floating up
    readonly property point muzzle: Qt.point(166, 61)   // the money gun's mouth, in drawing coordinates
    component Bill: Rectangle {     // a banknote in her style: mint, soft border, a $ medallion
        width: 36; height: 18; radius: 3
        color: "#9fd8a8"; border.width: 1.5; border.color: "#4e9a62"
        Rectangle { anchors.centerIn: parent; width: 14; height: 12; radius: 6; color: "#c8ecd0"; border.width: 1; border.color: "#4e9a62"
            Text { anchors.centerIn: parent; text: "$"; font.pixelSize: 9; font.weight: Font.Black; color: "#3d7a4e" } }
        Rectangle { x: 3; y: 3; width: 5; height: 12; radius: 2; color: "#c8ecd0"; opacity: 0.8 }
        Rectangle { x: 28; y: 3; width: 5; height: 12; radius: 2; color: "#c8ecd0"; opacity: 0.8 }
    }
    readonly property color acc: tint !== "" ? tint : Cfg.accent

    readonly property color ink: "#2a2230"
    readonly property color skin: "#fff4f8"
    readonly property color edge: Qt.darker(a.acc, 1.25)

    readonly property string eyes: ({ happy: "happy", sleepy: "closed", surprised: "wide", sing: "happy", shy: "shy", wave: "happy", held: "wide", fly: "shy", dizzy: "closed", hot: "shy", box: "wide", glide: "happy", whistle: "open" })[pose] || "open"
    readonly property string mouth: (pose === "idle" || pose === "run" || pose === "sit" || pose === "glide") ? (talking ? "open" : "w")
        : (({ happy: "open", sleepy: "small", surprised: "o", sing: "o", shy: "flat", wave: "open", pout: "frown", held: "o", fly: "open", dizzy: "flat", hot: "open", box: "o", whistle: "small" })[pose] || "w")
    readonly property real droop: ({ happy: -6, sleepy: 26, surprised: -16, shy: 14, wave: -4, pout: 10, run: -10, held: -18, fly: 24, dizzy: 18, hot: 16, box: 6, glide: -8, whistle: -6 })[pose] || 0
    readonly property real blush: ({ happy: 0.8, shy: 1, sleepy: 0.4, surprised: 0.45, pout: 0.85, held: 0.9, fly: 1, hot: 1 })[pose] || 0.55
    readonly property bool feet: pose === "run" || pose === "held" || pose === "fly" || pose === "sit" || pose === "glide" || stand
    readonly property bool still: (pose === "sit" || stand) && pose !== "run"     // legs not moving

    // ── idle motions ──
    property real bob: 0
    readonly property int bobMs: pose === "sleepy" ? 1900 : pose === "sing" ? 430 : pose === "run" ? 110 : pose === "wave" ? 520 : 1250
    SequentialAnimation on bob {
        id: bobA
        running: a.active; loops: Animation.Infinite
        NumberAnimation { to: a.pose === "run" ? -7 : a.pose === "sleepy" ? -2 : (a.pose === "sit" || a.stand) ? -1 : -3.5; duration: a.bobMs; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: a.bobMs; easing.type: a.pose === "run" ? Easing.InQuad : Easing.InOutSine }
    }
    property real sway: 0           // singing: head sways with the beat
    SequentialAnimation on sway {
        running: a.active && a.pose === "sing"; loops: Animation.Infinite
        NumberAnimation { to: 5; duration: 430; easing.type: Easing.InOutSine }
        NumberAnimation { to: -5; duration: 860; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 430; easing.type: Easing.InOutSine }
        onStopped: a.sway = 0
    }
    property real wig: 0            // ear wiggle now and then
    SequentialAnimation {
        id: wiggle
        NumberAnimation { target: a; property: "wig"; to: 13; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: a; property: "wig"; to: -9; duration: 150; easing.type: Easing.InOutQuad }
        NumberAnimation { target: a; property: "wig"; to: 5; duration: 130; easing.type: Easing.InOutQuad }
        NumberAnimation { target: a; property: "wig"; to: 0; duration: 180; easing.type: Easing.OutQuad }
    }
    Timer { running: a.active && a.pose !== "sleepy"; repeat: true; interval: 4200
            onTriggered: { interval = 3000 + Math.random() * 5000; wiggle.restart(); } }
    property bool blinking: false
    Timer { running: a.active && a.eyes === "open"; repeat: true; interval: 3200
            onTriggered: { interval = 2200 + Math.random() * 3600; a.blinking = true; reopenT.restart(); } }
    Timer { id: reopenT; interval: 130; onTriggered: a.blinking = false }
    property real t: 0              // floating z / notes / sparkles
    NumberAnimation on t { running: a.active && (["sleepy", "sing", "happy", "surprised", "dizzy", "hot", "glide", "whistle"].includes(a.pose) || a.particles !== "" || a.prop !== "" || a.bling || a.hearts); from: 0; to: 1; duration: 2400; loops: Animation.Infinite }
    property real pop: 0            // "!" pops in
    property real wave: 0
    SequentialAnimation on wave {
        running: a.active && a.pose === "wave"; loops: Animation.Infinite
        NumberAnimation { to: 24; duration: 240; easing.type: Easing.InOutSine }
        NumberAnimation { to: -18; duration: 240; easing.type: Easing.InOutSine }
    }
    property real step: 0           // running feet
    NumberAnimation on step { id: stepA; running: a.active && a.feet && !a.still; from: 0; to: 1; duration: a.pose === "run" ? 220 : a.pose === "fly" ? 360 : a.pose === "sit" ? 1100 : a.pose === "glide" ? 1500 : 760; loops: Animation.Infinite }
    onPoseChanged: {
        if (pose === "happy" || pose === "surprised" || pose === "wave") wiggle.restart();
        if (pose === "surprised") { pop = 0; popA.restart(); }
        bobA.restart(); if (feet) stepA.restart();
    }
    NumberAnimation { id: popA; target: a; property: "pop"; from: 0; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }

    component Glyph: Text {         // (inline components can't see `a`: flip / rot are passed in)
        id: g
        property bool flip: false
        property real rot: 0
        font.family: Cfg.fontUi; font.weight: Font.Bold; color: Qt.darker(Cfg.accent, 1.15)
        rotation: rot
        transform: Scale { origin.x: g.width / 2; origin.y: g.height / 2; xScale: g.flip ? -1 : 1 }
    }

    Item {
        id: fig
        width: 120; height: 150
        y: a.bob + a.beat * 3                // the beat: a soft nod down with a little squash, not a hop
        rotation: a.sway
        transformOrigin: Item.Bottom
        transform: Scale { origin.x: 60; origin.y: 128; xScale: 1 + a.beat * 0.03; yScale: 1 - a.beat * 0.05 }

        Image {
            anchors.fill: parent; visible: a.custom !== ""
            source: a.custom !== "" ? "file://" + a.custom : ""; fillMode: Image.PreserveAspectFit; mipmap: true; asynchronous: true
        }

        Item {
            anchors.fill: parent; visible: a.custom === ""
            // gliding down: an open umbrella held up at her side, swaying a little
            Item {
                visible: a.pose === "glide"
                x: 98; y: 66; width: 1; height: 1
                rotation: Math.sin(a.t * Math.PI * 2) * 5
                Rectangle { x: -1.5; y: -104; width: 3; height: 104; radius: 1.5; color: "#5d4d60" }
                Item { x: -72; y: -132; width: 144; height: 38; clip: true
                    Rectangle { width: 144; height: 144; radius: 72; color: Qt.darker(a.acc, 1.12); border.width: 2; border.color: a.edge
                        Repeater { model: 3
                            Rectangle { required property int index
                                x: 34 + index * 36; y: 2; width: 2; height: 38; color: a.edge; opacity: 0.6 } } } }
                Rectangle { x: -2; y: -140; width: 4; height: 9; radius: 2; color: "#5d4d60" }
                Rectangle { x: -11; y: -10; width: 22; height: 20; radius: 10; color: a.skin; border.width: 2; border.color: a.edge }   // her hand on the handle
            }
            // umbrella (rain) - drawn first, the head hides the shaft
            Item {
                visible: a.outfit === "umbrella" && !a.feet && a.pose !== "box"
                Rectangle { x: 59; y: -12; width: 3; height: 70; radius: 1.5; color: "#5d4d60" }
                Item { x: -10; y: -44; width: 132; height: 34; clip: true
                    Rectangle { width: 132; height: 132; radius: 66; color: Qt.darker(a.acc, 1.12); border.width: 2; border.color: a.edge
                        Repeater { model: 3
                            Rectangle { required property int index
                                x: 30 + index * 30; y: 2; width: 2; height: 34; color: a.edge; opacity: 0.6 } } } }
                Rectangle { x: 58.5; y: -50; width: 4; height: 8; radius: 2; color: "#5d4d60" }
            }
            // petal ears (each droops / wiggles around its base)
            Repeater {
                model: 2
                Item {
                    required property int index
                    readonly property real sgn: index === 0 ? -1 : 1
                    x: index === 0 ? 18 : 62; y: 4 + Math.max(0, a.droop) * 0.2; width: 30; height: 40
                    rotation: index === 0 ? -28 : 22
                    Rectangle {
                        anchors.fill: parent; radius: 15; transformOrigin: Item.Bottom
                        rotation: parent.sgn * (a.droop + a.wig + a.beat * 6)
                        color: Qt.lighter(a.acc, 1.05); border.width: 2; border.color: a.edge
                        Rectangle { x: 10; y: 9; width: 10; height: 20; radius: 5; color: Qt.lighter(a.acc, 1.18); opacity: 0.8 }
                    }
                }
            }
            // feet (running / dangling while caught or flying)
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    visible: a.feet
                    readonly property real ph: a.still ? 0 : Math.sin((a.step + index * 0.5) * Math.PI * 2)   // sitting: legs just hang
                    x: (index === 0 ? 30 : 62) + ph * 7; y: (a.pose === "sit" ? 120 : 116) - Math.max(0, ph) * 6
                    width: 20; height: 12; radius: 6
                    color: a.skin; border.width: 2; border.color: a.edge
                }
            }
            // head
            Rectangle {
                id: head
                x: 4; y: 26; width: 104; height: 96; radius: 48
                color: a.skin; border.width: 2; border.color: a.edge
                // eyes
                Repeater {
                    model: 2
                    Item {
                        required property int index
                        readonly property bool lft: index === 0
                        x: (lft ? 36 : 70) - 9; y: 38; width: 18; height: 20
                        Rectangle {          // open (blinks)
                            visible: a.eyes === "open"
                            anchors.centerIn: parent; width: 12; height: a.blinking ? 2 : 16; radius: Math.min(6, height / 2); color: a.ink
                            Behavior on height { NumberAnimation { duration: 60 } }
                            Rectangle { x: 6; y: 3; width: 4; height: 4; radius: 2; color: "#ffffff"; visible: parent.height > 8 }
                        }
                        Rectangle {          // wide (surprised)
                            visible: a.eyes === "wide"
                            anchors.centerIn: parent; width: 15; height: 19; radius: 7.5; color: a.ink
                            Rectangle { x: 7.5; y: 3; width: 5; height: 5; radius: 2.5; color: "#ffffff" }
                            Rectangle { x: 3; y: 12; width: 3; height: 3; radius: 1.5; color: "#ffffff" }
                        }
                        Item {               // happy ∩ / closed ∪
                            visible: a.eyes === "happy" || a.eyes === "closed"
                            x: 1; y: a.eyes === "happy" ? 5 : 10; width: 16; height: 8; clip: true
                            Rectangle { y: a.eyes === "happy" ? 0 : -8; width: 16; height: 16; radius: 8; color: "transparent"; border.width: 2.6; border.color: a.ink }
                        }
                        Repeater {           // shy  > <
                            model: 2
                            Rectangle {
                                required property int index
                                visible: a.eyes === "shy"
                                x: parent.lft ? 3 : 4; y: 8.7; width: 11; height: 2.8; radius: 1.4; color: a.ink
                                transformOrigin: parent.lft ? Item.Right : Item.Left
                                rotation: (index === 0 ? 1 : -1) * (parent.lft ? 30 : -30)
                            }
                        }
                        Rectangle {          // a lash at the outer corner (girl)
                            visible: a.girl && (a.eyes === "open" || a.eyes === "happy")
                            x: parent.lft ? -3 : 15; y: 2; width: 7; height: 2.4; radius: 1.2; color: a.ink
                            rotation: parent.lft ? 35 : -35
                        }
                        Rectangle {          // brow (pout)
                            visible: a.pose === "pout"
                            x: 3; y: -4; width: 13; height: 2.8; radius: 1.4; color: a.ink
                            rotation: parent.lft ? 18 : -18
                        }
                    }
                }
                // blush (+ "///" when shy)
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        readonly property real w: a.pose === "shy" || a.pose === "pout" ? 21 : 16
                        x: (index === 0 ? 24 : 82) - w / 2; y: 60; width: w; height: a.pose === "pout" ? 10 : 8; radius: height / 2
                        color: a.acc; opacity: a.blush
                        Behavior on width { NumberAnimation { duration: 160 } }
                        Repeater {
                            model: a.pose === "shy" ? 3 : 0
                            Rectangle { required property int index
                                x: 4 + index * 5; y: 1; width: 1.6; height: 6; radius: 0.8; rotation: 25; color: "#ffffff"; opacity: 0.85 }
                        }
                    }
                }
                // mouth
                Item {
                    x: 53 - 8; y: 60; width: 16; height: 12
                    Repeater {           // ω
                        model: a.mouth === "w" ? 2 : 0
                        Item { required property int index
                            x: index * 7; y: 2; width: 9; height: 5; clip: true
                            Rectangle { y: -4.5; width: 9; height: 9; radius: 4.5; color: "transparent"; border.width: 2; border.color: a.ink } }
                    }
                    Item {               // open smile (talking / happy)
                        visible: a.mouth === "open"
                        x: 1; y: 1; width: 14; height: 8; clip: true
                        Rectangle { y: -7; width: 14; height: 14; radius: 7; color: a.ink
                            Rectangle { x: 4; y: 10.5; width: 6; height: 4; radius: 2; color: "#f08aa8" } }
                    }
                    Rectangle {          // o (surprised / singing to the beat)
                        visible: a.mouth === "o"
                        anchors.horizontalCenter: parent.horizontalCenter; y: 1
                        width: 8; height: a.pose === "sing" ? 6 + Math.abs(a.sway) : 10; radius: 4; color: a.ink
                    }
                    Rectangle { visible: a.mouth === "small"; x: 5.5; y: 3; width: 5; height: 5; radius: 2.5; color: a.ink }
                    Rectangle { visible: a.mouth === "flat"; x: 4; y: 4; width: 8; height: 2.4; radius: 1.2; color: a.ink }
                    Item {               // frown ∩
                        visible: a.mouth === "frown"
                        x: 3; y: 3; width: 10; height: 5; clip: true
                        Rectangle { width: 10; height: 10; radius: 5; color: "transparent"; border.width: 2; border.color: a.ink }
                    }
                }
                // sunglasses (sunny and warm)
                Item {
                    visible: a.outfit === "shades" && a.pose !== "sleepy"
                    Rectangle { x: 22; y: 40; width: 26; height: 16; radius: 6; color: "#221a26"
                        Rectangle { x: 5; y: 3; width: 8; height: 2.5; radius: 1.2; color: "#ffffff"; opacity: 0.6; rotation: -15 } }
                    Rectangle { x: 57; y: 40; width: 26; height: 16; radius: 6; color: "#221a26"
                        Rectangle { x: 5; y: 3; width: 8; height: 2.5; radius: 1.2; color: "#ffffff"; opacity: 0.6; rotation: -15 } }
                    Rectangle { x: 46; y: 44; width: 13; height: 3; radius: 1.5; color: "#221a26" }
                }
            }
            // scarf (cold / snow)
            Item {
                visible: a.outfit === "scarf"
                Rectangle { x: 72; y: 108; width: 16; height: 30; radius: 7; rotation: -12; color: "#e98c96"; border.width: 2; border.color: "#b8606b" }
                Rectangle { x: 12; y: 102; width: 90; height: 15; radius: 7.5; color: "#e98c96"; border.width: 2; border.color: "#b8606b"
                    Repeater { model: 4
                        Rectangle { required property int index
                            x: 16 + index * 18; y: 2; width: 4; height: 11; radius: 2; color: "#ffffff"; opacity: 0.7 } } }
            }
            // a box to haul (full disk)
            Item {
                visible: a.pose === "box"
                Rectangle { x: -26; y: 74; width: 46; height: 36; radius: 4; color: "#c9a27a"; border.width: 2; border.color: "#8a6a48"
                    Rectangle { x: 0; y: 6; width: 46; height: 6; color: "#e3c79f" }
                    Rectangle { x: 19; y: 0; width: 8; height: 36; color: "#e3c79f"; opacity: 0.7 } }
                Rectangle { x: -32; y: 86; width: 13; height: 13; radius: 6.5; color: a.skin; border.width: 2; border.color: a.edge }
                Rectangle { x: 14; y: 86; width: 13; height: 13; radius: 6.5; color: a.skin; border.width: 2; border.color: a.edge }
            }
            // sweat drop (hot)
            Rectangle { visible: a.pose === "hot"; x: 18; y: 54 + a.t * 10; width: 8; height: 11; radius: 4; color: "#9fd0f0"; opacity: 1 - a.t * 0.6 }
            // little hand on the edge
            Rectangle { visible: !a.feet && a.pose !== "dizzy" && a.pose !== "box" && a.prop === ""; x: 92; y: 94; width: 26; height: 22; radius: 11; color: a.skin; border.width: 2; border.color: a.edge }
            // a bow between the ears (girl)
            Item {
                visible: a.girl
                Rectangle { x: 33; y: 16; width: 20; height: 15; radius: 7; rotation: -18; color: "#ff7fb0"; border.width: 2; border.color: "#d24e86" }
                Rectangle { x: 55; y: 16; width: 20; height: 15; radius: 7; rotation: 18; color: "#ff7fb0"; border.width: 2; border.color: "#d24e86" }
                Rectangle { x: 48; y: 18; width: 12; height: 12; radius: 6; color: "#ff9cc4"; border.width: 2; border.color: "#d24e86" }
            }
            // arms around the two girls' shoulders (flex finale)
            Item {
                visible: a.prop === "hug"
                Rectangle { x: -40; y: 84; width: 52; height: 17; radius: 8.5; rotation: -24; transformOrigin: Item.Right; color: a.skin; border.width: 2; border.color: a.edge }
                Rectangle { x: 100; y: 84; width: 52; height: 17; radius: 8.5; rotation: 24; transformOrigin: Item.Left; color: a.skin; border.width: 2; border.color: a.edge }
            }
            // gold chain with a $ medallion
            Item {
                visible: a.bling
                Repeater { model: 11
                    Rectangle { required property int index
                        readonly property real k: index / 10
                        x: 20 + k * 68 - 4; y: 104 + Math.sin(k * Math.PI) * 14 - 4; width: 9; height: 9; radius: 4.5
                        color: "#f0cd62"; border.width: 1.5; border.color: "#b48a2a" } }
                Rectangle { x: 44; y: 112; width: 22; height: 22; radius: 11; color: "#f0cd62"; border.width: 2; border.color: "#b48a2a"
                    rotation: Math.sin(a.t * Math.PI * 2) * 8
                    Text { anchors.centerIn: parent; text: "$"; font.pixelSize: 13; font.weight: Font.Black; color: "#8a6418" }
                    Rectangle { x: 4; y: 4; width: 5; height: 3; radius: 1.5; color: "#ffffff"; opacity: 0.7; rotation: -30 } }
            }
            // a fan of bills, shaken right at you
            Item {
                visible: a.prop === "fan"
                x: -14; y: 76; width: 1; height: 1
                rotation: -16 + a.pulse * 32          // snaps on every beat (Mascot.qml flex)
                Repeater { model: 5
                    Item { required property int index
                        rotation: -40 + index * 20; width: 1; height: 1
                        Bill { x: -6; y: -40; rotation: 90 } } }
                Rectangle { x: -12; y: -10; width: 24; height: 22; radius: 11; color: a.skin; border.width: 2; border.color: a.edge }
            }
            // money gun: pink body, a bill sticking out of the magazine, her paw on the grip
            Item {
                visible: a.prop === "gun"
                x: 92; y: 52
                Bill { x: 14; y: -14; rotation: -8; scale: 0.8 }
                Rectangle { x: 6; y: 12; width: 14; height: 26; radius: 5; rotation: 12; color: Qt.darker(a.acc, 1.2); border.width: 2; border.color: a.edge }
                Rectangle { x: 0; y: 0; width: 56; height: 20; radius: 7; color: Qt.lighter(a.acc, 1.05); border.width: 2; border.color: a.edge
                    Rectangle { x: 8; y: 5; width: 30; height: 4; radius: 2; color: "#ffffff"; opacity: 0.6 }
                    Text { x: 40; y: 1; text: "$"; font.pixelSize: 13; font.weight: Font.Black; color: a.edge } }
                Rectangle { x: 54; y: 3; width: 20; height: 14; radius: 4; color: Qt.darker(a.acc, 1.1); border.width: 2; border.color: a.edge }
                Rectangle { x: 2; y: 14; width: 20; height: 18; radius: 9; color: a.skin; border.width: 2; border.color: a.edge }
            }
            // counting a stack: the top bill flips over and over
            Item {
                visible: a.prop === "count"
                x: -26; y: 80
                Repeater { model: 4
                    Bill { required property int index; x: index * 1.5; y: 14 - index * 3 } }
                Bill { x: 6; y: 0; transformOrigin: Item.Left; transform: Scale { origin.x: 0; xScale: Math.cos(Math.PI * Math.min(1, a.pulse * 1.4)) } }   // a flip on each beat
                Rectangle { x: 30; y: 4; width: 20; height: 18; radius: 9; color: a.skin; border.width: 2; border.color: a.edge }
            }
            // waving hand (screen side)
            Rectangle {
                visible: a.pose === "wave"
                x: -12; y: 52; width: 22; height: 26; radius: 11; color: a.skin; border.width: 2; border.color: a.edge
                transformOrigin: Item.Bottom; rotation: a.wave
            }
        }

        // ── extras (glyphs stay readable when mirrored / upside down) ──
        Glyph { flip: a.flip; rot: a.textRot             // z z
            visible: a.pose === "sleepy"
            x: -4 - a.t * 16; y: 26 - a.t * 30; opacity: 1 - a.t; text: "z"; font.pixelSize: 12 + a.t * 8
        }
        Glyph { flip: a.flip; rot: a.textRot
            readonly property real k: (a.t + 0.5) % 1
            visible: a.pose === "sleepy"
            x: -4 - k * 16; y: 26 - k * 30; opacity: 1 - k; text: "z"; font.pixelSize: 12 + k * 8
        }
        Glyph { flip: a.flip; rot: a.textRot             // ♪ ♫
            visible: a.pose === "sing" || a.pose === "whistle"
            x: -8 - a.t * 20; y: 72 - a.t * 56; opacity: Math.min(1, (1 - a.t) * 2); text: "♪"; font.pixelSize: 18
        }
        Glyph { flip: a.flip; rot: a.textRot
            readonly property real k: (a.t + 0.5) % 1
            visible: a.pose === "sing" || a.pose === "whistle"
            x: 6 - k * 22; y: 60 - k * 58; opacity: Math.min(1, (1 - k) * 2); text: "♫"; font.pixelSize: 15
        }
        Glyph { flip: a.flip; rot: a.textRot             // ✦ sparkles
            visible: a.pose === "happy"
            x: -10; y: 22; text: "✦"; font.pixelSize: 14; opacity: 0.35 + 0.65 * Math.abs(Math.sin(a.t * Math.PI * 2))
        }
        Glyph { flip: a.flip; rot: a.textRot
            visible: a.pose === "happy"
            x: 2; y: 2; text: "✦"; font.pixelSize: 10; opacity: 0.35 + 0.65 * Math.abs(Math.cos(a.t * Math.PI * 2))
        }
        Repeater {          // stars circling a dizzy head
            model: a.pose === "dizzy" ? 3 : 0
            Glyph { required property int index
                flip: a.flip; rot: a.textRot
                readonly property real ang: (a.t + index / 3) * Math.PI * 2
                x: 50 + Math.cos(ang) * 34; y: 8 + Math.sin(ang) * 7; z: Math.sin(ang) > 0 ? 1 : -1
                text: "✦"; font.pixelSize: 12 }
        }
        Glyph { flip: a.flip; rot: a.textRot             // ♥ ♥
            visible: a.hearts
            x: 4 - a.t * 10; y: 20 - a.t * 34; opacity: Math.min(1, (1 - a.t) * 2); text: "♥"; font.pixelSize: 16; color: "#ff6f9f"
        }
        Glyph { flip: a.flip; rot: a.textRot
            readonly property real k: (a.t + 0.5) % 1
            visible: a.hearts
            x: 84 + k * 10; y: 14 - k * 30; opacity: Math.min(1, (1 - k) * 2); text: "♥"; font.pixelSize: 13; color: "#ff6f9f"
        }
        Glyph { flip: a.flip; rot: a.textRot             // ♨ (overheating)
            visible: a.pose === "hot"
            x: -12; y: 14 - a.t * 12; text: "♨"; font.pixelSize: 20; opacity: 1 - a.t * 0.5; color: "#e0705a"
        }
        Repeater {          // weather / season: rain, snow, petals, leaves falling around her
            model: a.particles !== "" && a.textRot === 0 && a.custom === "" ? 7 : 0
            Rectangle {
                required property int index
                readonly property real k: (a.t * (a.particles === "rain" ? 2 : 1) + index * 0.37) % 1
                x: -70 + index * 30 + Math.sin(a.t * Math.PI * 2 + index) * (a.particles === "rain" ? 0 : 9)
                y: -40 + k * 200
                width: a.particles === "rain" ? 1.6 : a.particles === "snow" ? 5 : 8
                height: a.particles === "rain" ? 9 : a.particles === "snow" ? 5 : 11
                radius: a.particles === "rain" ? 0.8 : a.particles === "snow" ? 2.5 : 5
                rotation: a.particles === "rain" ? 12 : k * 300 + index * 40
                color: a.particles === "rain" ? "#9fc3e8" : a.particles === "snow" ? "#ffffff" : a.particles === "leaves" ? (index % 2 ? "#e0915a" : "#d9a441") : Qt.lighter(Cfg.accent, 1.1)
                opacity: Math.min(1, k * 5, (1 - k) * 4) * (a.particles === "rain" ? 0.6 : 0.9)
            }
        }
        Glyph { flip: a.flip; rot: a.textRot             // !
            visible: a.pose === "surprised"
            x: -14; y: 6; text: "!"; font.pixelSize: 28; scale: a.pop
        }
    }
}
