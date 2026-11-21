// sakura-calc UI: basic / scientific / converter, live preview, history.
import Quickshell
import Quickshell.Io
import QtQuick
import "Calc.js" as Calc

Item {
    id: app
    focus: true

    // ── state ────────────────────────────────────────────────────────
    property string mode: "calc"            // calc | sci | conv
    property bool deg: true
    property bool histOpen: false
    property var history: []                // newest first: { e, r, p, t }
    property real ans: 0
    property string prevExpr: ""
    property bool justCommitted: false
    property int histIdx: -1
    property string draft: ""
    property string convCat: "length"
    property var convUnits: ({ length: ["km", "mi"], mass: ["kg", "lb"], temp: ["°C", "°F"], volume: ["l", "gal"],
                               area: ["m²", "ft²"], speed: ["km/h", "mph"], data: ["GB", "GiB"], time: ["h", "min"],
                               currency: ["USD", "RUB"] })
    property var sizes: ({ calc: [400, 640], sci: [740, 640], conv: [430, 680] })
    property bool loaded: false
    property real sizeHold: 0
    readonly property real histW: 290
    signal wantSize(int w, int h)

    // engine
    property bool hasQalc: false
    property string qalcFor: ""
    property string qalcOut: ""
    property var fx: null
    property real fxTime: 0
    readonly property var res: Calc.evaluate(input.text, { deg: app.deg, ans: app.ans, fx: app.fx })
    readonly property string previewText: res.ok ? res.s + (res.unit ? " " + res.unit : "")
        : (qalcOut && qalcFor === input.text.trim() ? qalcOut : "")

    readonly property string stateFile: Quickshell.env("SAKURA_CALC_STATE") || (Theme.dir + "/state.json")
    readonly property string cacheDir: Theme.home + "/.cache/sakura-calc"

    // ── persistence ──────────────────────────────────────────────────
    FileView {
        id: stFile
        path: app.stateFile
        blockLoading: true
        atomicWrites: true
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (Array.isArray(d.history)) app.history = d.history.slice(0, 200);
                if (["calc", "sci", "conv"].indexOf(d.mode) >= 0) app.mode = d.mode;
                if (typeof d.deg === "boolean") app.deg = d.deg;
                if (typeof d.histOpen === "boolean") app.histOpen = d.histOpen;
                if (typeof d.ans === "number") app.ans = d.ans;
                if (d.convCat && Calc.catById(d.convCat)) app.convCat = d.convCat;
                if (d.convUnits) app.convUnits = Object.assign({}, app.convUnits, d.convUnits);
                if (d.sizes) app.sizes = Object.assign({}, app.sizes, d.sizes);
            } catch (e) {}
        }
    }
    Timer { id: saveT; interval: 500; onTriggered: app.saveNow() }
    function save() { if (loaded) saveT.restart(); }
    function saveNow() {
        stFile.setText(JSON.stringify({ mode, deg, histOpen, ans, convCat, convUnits, sizes, history: history.slice(0, 200) }, null, 1));
    }
    onModeChanged: { save(); requestSize(); focusInput(); }
    onHistOpenChanged: { save(); requestSize(); }
    onDegChanged: save()
    onConvCatChanged: { save(); if (convCat === "currency") ensureFx(); }

    function requestSize() {
        if (!loaded) return;
        const s = sizes[mode] || [420, 640];
        sizeHold = Date.now() + 900;   // the resize we asked for is not a user resize
        wantSize(s[0] + (histOpen ? histW : 0), s[1]);
    }
    // the user resized → remember it for this mode
    Timer {
        id: sizeT; interval: 400
        onTriggered: {
            if (!app.loaded || app.width < 100) return;
            if (Date.now() < app.sizeHold) { sizeT.restart(); return; }
            const w = Math.round(app.width - (app.histOpen ? app.histW : 0)), h = Math.round(app.height);
            const minW = app.mode === "sci" ? 600 : 340;
            if (w < minW || w > 1500 || h < 500 || h > 1200) return;   // tiled / maximized / mid-transition
            const s = app.sizes[app.mode];
            if (s && s[0] === w && s[1] === h) return;
            const n = Object.assign({}, app.sizes); n[app.mode] = [w, h]; app.sizes = n; app.save();
        }
    }
    onWidthChanged: sizeT.restart()
    onHeightChanged: sizeT.restart()

    // ── qalc (optional, used when the built-in parser gives up) ─────
    Process {
        running: true
        command: ["sh", "-c", "command -v qalc"]
        onExited: code => app.hasQalc = code === 0
    }
    Process {
        id: qalcProc
        property string forText: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text.trim().split("\n").pop().trim();
                if (out && !/^(error|warning)/i.test(out) && out !== qalcProc.forText) {
                    app.qalcFor = qalcProc.forText; app.qalcOut = out.replace(/^≈\s*/, "≈ ");
                }
            }
        }
    }
    Timer {
        id: qalcT; interval: 220
        onTriggered: {
            const t = input.text.trim();
            if (!app.hasQalc || !t || app.res.ok || qalcProc.running) return;
            qalcProc.forText = t;
            qalcProc.command = ["qalc", "-t", Calc.normalize(t)];
            qalcProc.running = true;
        }
    }

    // ── currency rates (cached 6 h) ──────────────────────────────────
    FileView {
        id: fxFile
        path: app.cacheDir + "/fx.json"
        blockLoading: true
        printErrors: false
        onLoaded: { try { const d = JSON.parse(text()); if (d.rates) { app.fx = d.rates; app.fxTime = d.time || 0; } } catch (e) {} }
    }
    Process {
        id: fxProc
        command: ["curl", "-s", "--max-time", "8", "https://open.er-api.com/v6/latest/USD"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text);
                    if (!d.rates) return;
                    app.fx = d.rates;
                    app.fxTime = Date.now();
                    Quickshell.execDetached(["mkdir", "-p", app.cacheDir]);
                    fxSaveT.restart();
                } catch (e) {}
            }
        }
    }
    Timer { id: fxSaveT; interval: 300; onTriggered: fxFile.setText(JSON.stringify({ time: app.fxTime, rates: app.fx })) }
    function ensureFx() { if ((!fx || Date.now() - fxTime > 6 * 3600e3) && !fxProc.running) fxProc.running = true; }

    // ── actions ──────────────────────────────────────────────────────
    function focusInput() { Qt.callLater(() => (mode === "conv" ? convIn : input).forceActiveFocus()); }
    function closeParens(t) {
        const o = (t.match(/\(/g) || []).length - (t.match(/\)/g) || []).length;
        return o > 0 ? t + ")".repeat(o) : t;
    }
    function field() { return mode === "conv" ? convIn : input; }

    function insert(s) {
        const f = field();
        if (f === input && justCommitted) {
            justCommitted = false;
            if (/^[0-9.(a-zA-Zπ√e]/.test(s) && !/^(mod|e\^)/.test(s)) f.text = "";
            f.cursorPosition = f.text.length;
        }
        if (f.selectedText) f.remove(f.selectionStart, f.selectionEnd);
        f.insert(f.cursorPosition, s);
        histIdx = -1;
    }
    function backspace() {
        const f = field();
        justCommitted = false;
        if (f.selectedText) { f.remove(f.selectionStart, f.selectionEnd); return; }
        const c = f.cursorPosition;
        if (c <= 0) return;
        // remove a whole function name with its bracket: "sin(" → ""
        const m = /(asinh|acosh|atanh|asin|acos|atan|sinh|cosh|tanh|sin|cos|tan|ln|log|abs|sqrt|cbrt)\($|mod $/.exec(f.text.slice(0, c));
        f.remove(m ? c - m[0].length : c - 1, c);
    }
    function clearAll() {
        const f = field();
        if (!f.text && mode !== "conv") { prevExpr = ""; return; }
        f.text = "";
        justCommitted = false; histIdx = -1;
        if (f === input) clearAnim.restart();
    }
    function negate() {
        const f = field();
        let t = f.text.trim();
        if (!t) { insert("−"); return; }
        let m;
        if ((m = /^−\((.*)\)$/.exec(t))) t = m[1];
        else if (/^−?[0-9., ]+(e−?\d+)?$/.test(t)) t = t[0] === "−" ? t.slice(1) : "−" + t;
        else t = "−(" + t + ")";
        f.text = t; f.cursorPosition = t.length; justCommitted = false;
    }
    function wrap(pre, post) {   // 1/x, |x| around what is there
        const f = field();
        const t = f.text.trim();
        if (!t || (!justCommitted && /[+\−×÷^(]$/.test(t))) { insert(pre); return; }
        f.text = pre + t + post; f.cursorPosition = f.text.length; justCommitted = false;
    }

    function commit() {
        if (mode === "conv") { convCommit(); return; }
        const t = input.text.trim();
        if (!t) return;
        let raw, shown, v;
        if (res.ok) {
            v = res.v; raw = Calc.raw(res.v); shown = res.s + (res.unit ? " " + res.unit : "");
        } else if (qalcOut && qalcFor === t) {
            raw = qalcOut; shown = qalcOut; v = parseFloat(qalcOut);
        } else { shake.restart(); return; }
        const e = closeParens(t.replace(/[+−×÷^,\s]+$/, ""));
        if (Calc.pretty(raw) === e) { justCommitted = true; return; }
        pushHistory({ e: e, r: raw, p: shown, t: Date.now() });
        prevExpr = e;
        input.text = Calc.pretty(raw);
        input.cursorPosition = input.text.length;
        if (typeof v === "number" && isFinite(v)) ans = v;
        justCommitted = true;
        histIdx = -1;
        commitAnim.restart();
    }
    function pushHistory(h) {
        if (history.length && history[0].e === h.e && history[0].r === h.r) return;
        history = [h].concat(history).slice(0, 200);
        save();
    }
    function useHistory(h) {
        if (h.c) {   // converter entry
            mode = "conv"; convCat = h.c; const u = Object.assign({}, convUnits); u[h.c] = [h.f, h.to]; convUnits = u;
            convIn.text = h.v; return;
        }
        if (mode === "conv") mode = "calc";
        input.text = h.e; input.cursorPosition = input.text.length;
        justCommitted = false; focusInput();
    }
    function histStep(d) {
        if (!history.length || mode === "conv") return;
        if (histIdx === -1) draft = input.text;
        let i = histIdx + d;
        while (i >= 0 && i < history.length && history[i].c) i += d;
        if (i < -1 || i >= history.length) return;
        histIdx = i;
        input.text = i === -1 ? draft : history[i].e;
        input.cursorPosition = input.text.length; justCommitted = false;
    }
    function copy(s) {
        if (!s) return;
        Quickshell.execDetached(["wl-copy", "--", String(s).replace(/[ ]/g, "")]);
        copiedAnim.restart();
    }
    function copyResult() {
        const f = field();
        if (f.selectedText) { copy(f.selectedText); return; }
        if (mode === "conv") { copy(Calc.raw(convOut)); return; }
        if (res.ok) copy(Calc.raw(res.v));
        else if (previewText) copy(previewText);
        else copy(input.text);
    }

    signal flashKey(string id)
    function flashFor(ev) {
        const map = { "*": "×", "/": "÷", "-": "−", ",": ".", "x": "×" };
        let id = "";
        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) id = "=";
        else if (ev.key === Qt.Key_Backspace) id = "back";
        else if (ev.key === Qt.Key_Escape) id = "clear";
        else if (ev.text) id = map[ev.text] || ev.text;
        if (id) { calcPad.flash(id); sciPad.flash(id); convPad.flash(id); }
    }

    // IPC / tests: type text as if from the keyboard, press a key by id
    function typeText(s) {
        for (const ch of s) {
            insert(ch === "*" ? "×" : ch === "/" ? "÷" : ch === "-" ? "−" : ch);
            flashFor({ key: 0, text: ch });
        }
    }
    function press(id) { calcPad.flash(id); sciPad.flash(id); convPad.flash(id); onKey(id); }

    function onKey(id) {
        switch (id) {
        case "=": commit(); break;
        case "back": backspace(); break;
        case "clear": clearAll(); break;
        case "neg": negate(); break;
        case "deg": deg = !deg; break;
        case "sq": insert("²"); break;
        case "pow": insert("^"); break;
        case "inv": wrap("1÷(", ")"); break;
        case "abs": wrap("abs(", ")"); break;
        case "exp": insert("e^"); break;
        case "fact": insert("!"); break;
        case "swap": swapUnits(); break;
        case "sin": case "cos": case "tan": case "ln": case "log": insert(id + "("); break;
        case "asin": case "acos": case "atan": insert(id + "("); break;
        case "sqrt": insert("√("); break;
        default: insert(id);
        }
        if (id !== "=" || mode === "conv") focusInput();
    }

    // keyboard: shared by both inputs
    function handleKey(ev) {
        const ctrl = ev.modifiers & Qt.ControlModifier;
        if (picker.open) { picker.handleKey(ev); return; }
        if (ctrl && ev.key === Qt.Key_C) { copyResult(); ev.accepted = true; return; }
        if (ctrl && ev.key === Qt.Key_H) { histOpen = !histOpen; ev.accepted = true; return; }
        if (ctrl && ev.key >= Qt.Key_1 && ev.key <= Qt.Key_3) { mode = ["calc", "sci", "conv"][ev.key - Qt.Key_1]; ev.accepted = true; return; }
        if (ctrl && ev.key === Qt.Key_D) { deg = !deg; ev.accepted = true; return; }
        if (ctrl) return;
        flashFor(ev);
        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { commit(); ev.accepted = true; return; }
        if (ev.key === Qt.Key_Escape) { clearAll(); ev.accepted = true; return; }
        if (ev.key === Qt.Key_Up) { histStep(1); ev.accepted = true; return; }
        if (ev.key === Qt.Key_Down) { histStep(-1); ev.accepted = true; return; }
        if (ev.key === Qt.Key_Backspace && !ev.text.length) return;
        if (justCommitted && ev.text && field() === input && ev.key !== Qt.Key_Backspace && ev.key !== Qt.Key_Delete) {
            justCommitted = false;
            if (/^[0-9.,(a-zA-Zπ√]$/.test(ev.text)) input.text = "";
            input.cursorPosition = input.text.length;
        }
        if (ev.key === Qt.Key_Backspace) justCommitted = false;
    }
    // operators typed as ASCII become math glyphs
    function prettify(f) {
        const c = f.cursorPosition;
        const t = f.text.replace(/\*/g, "×").replace(/(^|[^a-zA-Zа-я])\/(?=[^a-zA-Zа-я]|$)/g, "$1÷").replace(/-/g, "−");
        if (t !== f.text) { f.text = t; f.cursorPosition = c; }
    }

    // ── converter ───────────────────────────────────────────────────
    readonly property var cat: Calc.catById(convCat)
    readonly property string fromU: (convUnits[convCat] || ["", ""])[0]
    readonly property string toU: (convUnits[convCat] || ["", ""])[1]
    readonly property var convRes: Calc.evaluate(convIn.text, { deg: deg, ans: ans })
    readonly property real convOut: convRes.ok ? Calc.convert(convRes.v, convCat, fromU, toU, fx) : NaN
    function unitName(id) {
        if (convCat === "currency") { const n = Calc.CURRENCY_NAMES[id]; return n ? n[Theme.lang === "ru" ? 0 : 1] : id; }
        const us = cat ? cat.units : [];
        for (let i = 0; i < us.length; i++) if (us[i][0] === id) return us[i][Theme.lang === "ru" ? 2 : 3];
        return id;
    }
    function setUnit(side, id) {
        const u = Object.assign({}, convUnits);
        const p = (u[convCat] || [id, id]).slice();
        p[side === "from" ? 0 : 1] = id;
        u[convCat] = p; convUnits = u; save();
    }
    function pickUnit(side) { if (side === "close") picker.hide(); else picker.show(side); }
    function swapUnits() {
        const u = Object.assign({}, convUnits);
        const p = u[convCat].slice();
        u[convCat] = [p[1], p[0]]; convUnits = u; save();
        if (convRes.ok && isFinite(convOut)) { convIn.text = Calc.raw(convOut); convIn.cursorPosition = convIn.text.length; }
        swapSpin.restart();
    }
    function convCommit() {
        if (!convRes.ok || !isFinite(convOut)) { shake.restart(); return; }
        pushHistory({ c: convCat, f: fromU, to: toU, v: convIn.text, e: convIn.text + " " + fromU + " → " + toU,
                      r: Calc.raw(convOut), p: Calc.fmt(convOut) + " " + toU, t: Date.now() });
        convCommitAnim.restart();
    }

    // ── layout ──────────────────────────────────────────────────────
    readonly property real pad: 18
    readonly property real histShown: histOpen ? 1 : 0
    property real histK: histShown
    Behavior on histK { NumberAnimation { duration: Theme.ms(320); easing.type: Easing.OutCubic } }
    readonly property real mainW: width - pad * 2 - histK * (Math.min(histW, width * 0.42))

    // header: mode switch + history
    Item {
        id: header
        x: app.pad; y: app.pad - 2
        width: app.width - app.pad * 2
        height: 36

        Rectangle {
            id: seg
            height: 34
            width: segRow.width + 8
            radius: 13
            color: Qt.rgba(1, 1, 1, 0.05)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.05)
            Rectangle {
                id: segInd
                property Item cur: segRow.children[["calc", "sci", "conv"].indexOf(app.mode)] || null
                x: 4 + (cur ? cur.x : 0); y: 4
                width: cur ? cur.width : 0; height: 26
                radius: 10
                color: Theme.a(Theme.accent, 0.2)
                border.width: 1; border.color: Theme.a(Theme.accent, 0.25)
                Behavior on x { NumberAnimation { duration: Theme.ms(300); easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: Theme.ms(300); easing.type: Easing.OutCubic } }
            }
            Row {
                id: segRow
                x: 4; y: 4
                Repeater {
                    model: [["calc", "Basic", 0xF00EC], ["sci", "Scientific", 0xF0871], ["conv", "Convert", 0xF04E1]]
                    Item {
                        required property var modelData
                        readonly property bool on: app.mode === modelData[0]
                        width: segLbl.implicitWidth + segIco.implicitWidth + 28
                        height: 26
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                id: segIco
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCodePoint(modelData[2])
                                font.family: Theme.fIcon; font.pixelSize: 14
                                color: parent.parent.on ? Theme.accent : Theme.dim
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            Text {
                                id: segLbl
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.tr(modelData[1])
                                font.family: Theme.fUi; font.pixelSize: 13; font.weight: Font.Medium
                                color: parent.parent.on ? Theme.accent : Theme.dim
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.mode = modelData[0] }
                    }
                }
            }
        }

        IconBtn {
            anchors.right: parent.right
            anchors.verticalCenter: seg.verticalCenter
            glyph: 0xF02DA
            on: app.histOpen
            onClicked: app.histOpen = !app.histOpen
        }
    }

    // ── calculator body ─────────────────────────────────────────────
    Item {
        id: body
        x: app.pad
        y: header.y + header.height + 10
        width: app.mainW
        height: app.height - y - app.pad + 4
        visible: opacity > 0
        opacity: app.mode === "conv" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.ms(200) } }

        // display
        Item {
            id: display
            width: parent.width
            height: Math.max(150, Math.min(240, parent.height * 0.32))

            // copied tick
            Text {
                id: copiedTick
                anchors.left: parent.left; anchors.leftMargin: 6
                anchors.bottom: inputBox.bottom; anchors.bottomMargin: 14
                text: String.fromCodePoint(0xF012C)
                font.family: Theme.fIcon; font.pixelSize: 20
                color: Theme.accent
                opacity: 0
                SequentialAnimation {
                    id: copiedAnim
                    NumberAnimation { target: copiedTick; property: "opacity"; to: 1; duration: Theme.ms(120) }
                    PauseAnimation { duration: 700 }
                    NumberAnimation { target: copiedTick; property: "opacity"; to: 0; duration: Theme.ms(400) }
                }
            }

            Text {
                id: prevLine
                anchors.right: parent.right; anchors.rightMargin: 6
                anchors.bottom: inputBox.top; anchors.bottomMargin: 2
                width: parent.width - 12
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: app.prevExpr ? app.prevExpr + "  =" : ""
                color: Theme.faint
                font.family: Theme.fUi; font.pixelSize: 16
                font.features: { "tnum": 1 }
            }

            Item {
                id: inputBox
                anchors.right: parent.right
                anchors.bottom: previewLine.top
                anchors.bottomMargin: -2
                width: parent.width
                height: 74
                clip: true
                transform: Translate { id: inputShift }

                TextMetrics { id: tm; font.family: Theme.fDisplay; font.pixelSize: 64; font.weight: Font.Light; font.features: { "tnum": 1 }; text: input.text || "0" }
                TextInput {
                    id: input
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 12
                    horizontalAlignment: TextInput.AlignRight
                    font.family: Theme.fDisplay
                    font.weight: Font.Light
                    font.pixelSize: Math.max(26, Math.min(64, 64 * (width - 18) / Math.max(1, tm.advanceWidth * 1.04)))
                    font.features: { "tnum": 1 }
                    Behavior on font.pixelSize { NumberAnimation { duration: Theme.ms(140); easing.type: Easing.OutCubic } }
                    color: Theme.fg
                    selectionColor: Theme.a(Theme.accent, 0.35)
                    selectedTextColor: Theme.fg
                    selectByMouse: true
                    cursorDelegate: Rectangle {
                        width: 2; radius: 1; color: Theme.accent
                        visible: input.activeFocus
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite; running: input.activeFocus
                            NumberAnimation { to: 0; duration: 520; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutQuad }
                        }
                    }
                    focus: app.mode !== "conv"
                    Keys.onPressed: ev => app.handleKey(ev)
                    onTextEdited: { app.prettify(input); app.histIdx = -1; }
                    onTextChanged: { app.qalcOut = ""; qalcT.restart(); }
                    // "0" ghost when empty
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: "0"
                        font: input.font
                        color: Theme.a(Theme.fg, 0.22)
                    }
                }
            }

            Text {
                id: previewLine
                anchors.right: parent.right; anchors.rightMargin: 6
                anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                width: parent.width - 12
                height: 30
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                readonly property bool show: !!app.previewText && !app.justCommitted && Calc.pretty(app.previewText.replace(/ /g, "")) !== input.text.trim()
                text: show ? "= " + app.previewText : ""
                color: Theme.accent
                opacity: show ? 0.95 : 0
                font.family: Theme.fDisplay; font.pixelSize: 24; font.weight: Font.Normal
                font.features: { "tnum": 1 }
                Behavior on opacity { NumberAnimation { duration: Theme.ms(160) } }
            }

            // animations
            ParallelAnimation {
                id: commitAnim
                NumberAnimation { target: inputShift; property: "y"; from: 26; to: 0; duration: Theme.ms(380); easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                NumberAnimation { target: input; property: "opacity"; from: 0.2; to: 1; duration: Theme.ms(260) }
                NumberAnimation { target: prevLine; property: "opacity"; from: 0; to: 1; duration: Theme.ms(380) }
            }
            NumberAnimation { id: clearAnim; target: input; property: "opacity"; from: 0.3; to: 1; duration: Theme.ms(220) }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: inputShift; property: "x"; to: -10; duration: 50 }
                NumberAnimation { target: inputShift; property: "x"; to: 8; duration: 60 }
                NumberAnimation { target: inputShift; property: "x"; to: -5; duration: 60 }
                NumberAnimation { target: inputShift; property: "x"; to: 0; duration: 80; easing.type: Easing.OutCubic }
            }
        }

        // keys
        Item {
            id: keysArea
            anchors.top: display.bottom; anchors.topMargin: 10
            anchors.bottom: parent.bottom
            x: -4
            width: parent.width + 8
            readonly property real sciK: app.mode === "sci" ? 1 : 0
            property real sciA: sciK
            Behavior on sciA { NumberAnimation { duration: Theme.ms(300); easing.type: Easing.OutCubic } }

            Pad {
                id: sciPad
                width: (keysArea.width - 10) * 0.5 * keysArea.sciA
                height: parent.height
                opacity: keysArea.sciA
                visible: opacity > 0.01
                clip: true
                onKey: id => app.onKey(id)
                keys: [
                    { k: "(", c: 0, r: 0, t: "sci" }, { k: ")", c: 1, r: 0, t: "sci" },
                    { k: app.deg ? "DEG" : "RAD", id: "deg", c: 2, r: 0, t: "on" }, { k: "π", c: 3, r: 0, t: "sci" },
                    { k: "sin", c: 0, r: 1, t: "sci" }, { k: "cos", c: 1, r: 1, t: "sci" }, { k: "tan", c: 2, r: 1, t: "sci" }, { k: "e", c: 3, r: 1, t: "sci" },
                    { k: "sin⁻¹", id: "asin", c: 0, r: 2, t: "sci" }, { k: "cos⁻¹", id: "acos", c: 1, r: 2, t: "sci" },
                    { k: "tan⁻¹", id: "atan", c: 2, r: 2, t: "sci" }, { k: "x!", id: "fact", c: 3, r: 2, t: "sci" },
                    { k: "ln", c: 0, r: 3, t: "sci" }, { k: "log", c: 1, r: 3, t: "sci" }, { k: "√", id: "sqrt", c: 2, r: 3, t: "sci" }, { k: "x²", id: "sq", c: 3, r: 3, t: "sci" },
                    { k: "xʸ", id: "pow", c: 0, r: 4, t: "sci" }, { k: "eˣ", id: "exp", c: 1, r: 4, t: "sci" },
                    { k: "1/x", id: "inv", c: 2, r: 4, t: "sci" }, { k: "|x|", id: "abs", c: 3, r: 4, t: "sci" }
                ]
            }
            Pad {
                id: calcPad
                x: sciPad.width + 10 * keysArea.sciA
                width: keysArea.width - x
                height: parent.height
                onKey: id => app.onKey(id)
                keys: [
                    { k: "AC", id: "clear", c: 0, r: 0, t: "fn" }, { i: 0xF0B5C, id: "back", c: 1, r: 0, t: "fn" },
                    { k: "%", c: 2, r: 0, t: "fn" }, { k: "÷", c: 3, r: 0, t: "op" },
                    { k: "7", c: 0, r: 1 }, { k: "8", c: 1, r: 1 }, { k: "9", c: 2, r: 1 }, { k: "×", c: 3, r: 1, t: "op" },
                    { k: "4", c: 0, r: 2 }, { k: "5", c: 1, r: 2 }, { k: "6", c: 2, r: 2 }, { k: "−", c: 3, r: 2, t: "op" },
                    { k: "1", c: 0, r: 3 }, { k: "2", c: 1, r: 3 }, { k: "3", c: 2, r: 3 }, { k: "+", c: 3, r: 3, t: "op" },
                    { k: "±", id: "neg", c: 0, r: 4, t: "fn" }, { k: "0", c: 1, r: 4 }, { k: ".", c: 2, r: 4 }, { k: "=", c: 3, r: 4, t: "eq" }
                ]
            }
        }
    }

    // ── converter body ──────────────────────────────────────────────
    Item {
        id: convBody
        x: app.pad
        y: header.y + header.height + 12
        width: app.mainW
        height: app.height - y - app.pad + 4
        visible: opacity > 0
        opacity: app.mode === "conv" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.ms(200) } }

        Flow {
            id: chips
            width: parent.width
            spacing: 6
            Repeater {
                model: Calc.CATS
                Rectangle {
                    required property var modelData
                    readonly property bool on: app.convCat === modelData.id
                    width: chipT.implicitWidth + 22; height: 28; radius: 10
                    color: on ? Theme.a(Theme.accent, 0.2) : chipMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.045)
                    border.width: 1; border.color: on ? Theme.a(Theme.accent, 0.28) : Qt.rgba(1, 1, 1, 0.04)
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Text {
                        id: chipT
                        anchors.centerIn: parent
                        text: Theme.lang === "ru" ? modelData.ru : modelData.en
                        font.family: Theme.fUi; font.pixelSize: 12; font.weight: Font.Medium
                        color: parent.on ? Theme.accent : Theme.dim
                    }
                    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { app.convCat = modelData.id; app.focusInput(); } }
                }
            }
        }

        Column {
            id: cards
            anchors.top: chips.bottom; anchors.topMargin: 14
            width: parent.width
            spacing: 8
            transform: Translate { id: convShift }

            ConvCard {
                id: fromCard
                width: parent.width
                unit: app.fromU; unitName: app.unitName(app.fromU)
                onPick: picker.show("from")
                TextInput {
                    id: convIn
                    anchors.fill: parent
                    horizontalAlignment: TextInput.AlignRight
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fDisplay; font.weight: Font.Light
                    font.pixelSize: Math.max(20, Math.min(40, 40 * (width - 14) / Math.max(1, ctm.advanceWidth * 1.04)))
                    font.features: { "tnum": 1 }
                    color: Theme.fg
                    selectionColor: Theme.a(Theme.accent, 0.35)
                    selectByMouse: true
                    clip: true
                    focus: app.mode === "conv"
                    text: "1"
                    Keys.onPressed: ev => app.handleKey(ev)
                    onTextEdited: app.prettify(convIn)
                    cursorDelegate: Rectangle { width: 2; radius: 1; color: Theme.accent; visible: convIn.activeFocus }
                    TextMetrics { id: ctm; font.family: Theme.fDisplay; font.pixelSize: 40; font.weight: Font.Light; font.features: { "tnum": 1 }; text: convIn.text || "0" }
                }
            }
            ConvCard {
                id: toCard
                width: parent.width
                unit: app.toU; unitName: app.unitName(app.toU)
                accentValue: true
                value: isFinite(app.convOut) ? Calc.fmt(app.convCat === "currency" && Math.abs(app.convOut) >= 1 ? Math.round(app.convOut * 100) / 100 : app.convOut) : ""
                onPick: picker.show("to")
                onValueClicked: app.copy(Calc.raw(app.convOut))
            }
        }
        // swap button between the cards
        Rectangle {
            id: swapBtn
            width: 38; height: 38; radius: 19
            anchors.horizontalCenter: cards.horizontalCenter
            y: cards.y + fromCard.height + cards.spacing / 2 - height / 2
            color: swapMa.containsMouse ? Qt.lighter(Theme.pop, 1.3) : Theme.pop
            border.width: 1; border.color: Theme.a(Theme.accent, 0.35)
            Text {
                id: swapIco
                anchors.centerIn: parent
                text: String.fromCodePoint(0xF04E2)
                font.family: Theme.fIcon; font.pixelSize: 18
                color: Theme.accent
                RotationAnimation on rotation { id: swapSpin; running: false; from: 0; to: 180; duration: Theme.ms(380); easing.type: Easing.OutBack }
            }
            MouseArea { id: swapMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { app.swapUnits(); app.focusInput(); } }
        }

        Text {
            id: rateLine
            anchors.top: cards.bottom; anchors.topMargin: 10
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            readonly property real one: Calc.convert(1, app.convCat, app.fromU, app.toU, app.fx)
            text: app.fromU && app.toU && app.fromU !== app.toU && app.convCat !== "temp" && isFinite(one)
                ? "1 " + app.fromU + " = " + Calc.fmt(one) + " " + app.toU : ""
            color: Theme.faint
            font.family: Theme.fUi; font.pixelSize: 13
            font.features: { "tnum": 1 }
        }

        Pad {
            id: convPad
            anchors.top: rateLine.bottom; anchors.topMargin: 10
            anchors.bottom: parent.bottom
            x: -4
            width: parent.width + 8
            rows: 4
            onKey: id => app.onKey(id)
            keys: [
                { k: "7", c: 0, r: 0 }, { k: "8", c: 1, r: 0 }, { k: "9", c: 2, r: 0 }, { i: 0xF0B5C, id: "back", c: 3, r: 0, t: "fn" },
                { k: "4", c: 0, r: 1 }, { k: "5", c: 1, r: 1 }, { k: "6", c: 2, r: 1 }, { k: "AC", id: "clear", c: 3, r: 1, t: "fn" },
                { k: "1", c: 0, r: 2 }, { k: "2", c: 1, r: 2 }, { k: "3", c: 2, r: 2 }, { k: "±", id: "neg", c: 3, r: 2, t: "fn" },
                { k: "0", c: 0, r: 3, cs: 2 }, { k: ".", c: 2, r: 3 }, { i: 0xF04E2, id: "swap", c: 3, r: 3, t: "op" }
            ]
        }
        NumberAnimation { id: convCommitAnim; target: convShift; property: "y"; from: -6; to: 0; duration: Theme.ms(380); easing.type: Easing.OutBack }
    }

    // ── history panel ───────────────────────────────────────────────
    Item {
        id: hist
        readonly property real w: Math.min(app.histW, app.width * 0.42) - 12
        x: app.width - app.pad - w + (1 - app.histK) * (w + app.pad)
        y: header.y + header.height + 10
        width: w
        height: app.height - y - app.pad
        opacity: app.histK
        visible: app.histK > 0.01

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.035)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.05)
        }
        Text {
            x: 16; y: 14
            text: Theme.tr("History")
            font.family: Theme.fUi; font.pixelSize: 12; font.weight: Font.DemiBold
            font.letterSpacing: 0.4
            color: Theme.faint
        }
        IconBtn {
            anchors.right: parent.right; anchors.rightMargin: 8; y: 6
            size: 30
            glyph: 0xF09E7
            visible: app.history.length > 0
            onClicked: { app.history = []; app.save(); }
        }
        ListView {
            id: hl
            anchors { fill: parent; topMargin: 42; bottomMargin: 8; leftMargin: 6; rightMargin: 6 }
            clip: true
            spacing: 2
            model: app.history
            boundsBehavior: Flickable.StopAtBounds
            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.ms(260) }
                    NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: Theme.ms(300); easing.type: Easing.OutBack }
                }
            }
            displaced: Transition { NumberAnimation { property: "y"; duration: Theme.ms(260); easing.type: Easing.OutCubic } }
            delegate: Rectangle {
                id: hd
                required property var modelData
                required property int index
                width: hl.width
                height: hcol.implicitHeight + 16
                radius: 12
                color: hma.pressed ? Theme.a(Theme.accent, 0.14) : hma.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                Behavior on color { ColorAnimation { duration: 140 } }
                Column {
                    id: hcol
                    x: 10; y: 8
                    width: parent.width - 20
                    spacing: 2
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                        text: hd.modelData.e
                        color: Theme.dim
                        font.family: Theme.fUi; font.pixelSize: 13
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                        text: hd.modelData.p || hd.modelData.r
                        color: hma.containsMouse ? Theme.accent : Theme.fg
                        font.family: Theme.fDisplay; font.pixelSize: 19
                        font.features: { "tnum": 1 }
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                }
                MouseArea {
                    id: hma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: m => {
                        if (m.button === Qt.RightButton) app.copy(hd.modelData.r);
                        else app.useHistory(hd.modelData);
                    }
                }
            }
        }
    }

    UnitPicker { id: picker; anchors.fill: parent }

    Component.onCompleted: {
        loaded = true;
        if (mode === "conv" && convCat === "currency") ensureFx();
        focusInput();
    }
}
