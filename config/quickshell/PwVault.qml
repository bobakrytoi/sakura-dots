pragma Singleton
// sakura mono - Password helper backend glue (port of the Windows "Password helper").
// Runs ~/.config/hypr/scripts/pwhelper.py (vault, keyring key, generator, clipboard + history) and keeps its state.
// Settings live in ~/.config/sakura/settings.json → "pw" (Settings > Password helper). Passwords never come here
// unless the UI asks to show one (details "show"); copies are done by the helper itself.
// The hotkey: ~/.config/hypr/pwhelper.lua (generated here, loaded by hyprland.lua) + live hl.bind via hyprctl eval.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: pv
    readonly property string home: Quickshell.env("HOME")
    readonly property string py: home + "/.config/hypr/scripts/pwhelper.py"
    readonly property string bindFile: home + "/.config/hypr/pwhelper.lua"
    readonly property string clickWav: home + "/.local/share/sounds/sakura/pw-click.wav"
    readonly property string defaultSymbols: "!@#$%^&*()-_=+[]{};:,.?"

    // ── settings ────────────────────────────────────────────
    readonly property var defaults: ({
        hotkey: "CTRL + SHIFT + P",
        closeOnSelect: true, closeOnOutside: true, sound: true, placement: "pointer",
        length: 32, upper: true, lower: true, digits: true, symbols: true, noAmbiguous: false, symbolSet: defaultSymbols,
        history: true, historyLimit: 20, clearAfter: 90,
        ignored: ["keepassxc", "org.keepassxc.KeePassXC", "bitwarden", "1password", "proton-pass", "enpass", "nordpass",
                  "org.kde.kwalletmanager5", "seahorse", "org.gnome.World.Secrets"],
        lockOnScreenLock: true, autoLock: 0,
        glass: true, glassOpacity: 0.78, blur: 0.6, animations: true, animSpeed: 1.0, reducedMotion: false,
        buttonSize: "m", maxRadial: 10, volume: 0.45
    })
    readonly property var o: Object.assign({}, defaults, Cfg.data.pw || {})
    function set(k, v) { const p = Object.assign({}, Cfg.data.pw || {}); p[k] = v; Cfg.set("pw", p); }
    function resetSection(keys) { const p = Object.assign({}, Cfg.data.pw || {}); for (const k of keys) delete p[k]; Cfg.set("pw", p); }
    readonly property var policy: ({ length: o.length, upper: o.upper, lower: o.lower, digits: o.digits, symbols: o.symbols,
                                     excludeAmbiguous: o.noAmbiguous, symbolSet: o.symbolSet })

    // ── state from the helper ───────────────────────────────
    property string state: "loading"        // loading | ready | locked | nokeyring | corrupt | down
    property string problem: ""
    property string code: ""
    property bool hasBak: false
    property var entries: []                 // {id, title, username, url, notes, pinned, created, modified}
    property var history: []                 // {id, text, ts} newest first
    readonly property bool ready: state === "ready"
    readonly property var sorted: entries.slice().sort((a, b) => (b.pinned - a.pinned) || String(b.modified).localeCompare(String(a.modified)))
    signal changed()

    // ── talking to the helper ───────────────────────────────
    property int nextId: 1
    property var pending: ({})
    function req(cmd, args, cb) {
        if (!proc.running) { if (cb) cb({ ok: false, error: tr("The password helper is not running.") }); return; }
        const id = nextId++;
        const m = Object.assign({}, args || {}, { id: id, cmd: cmd });
        if (cb) pending[id] = cb;
        proc.write(JSON.stringify(m) + "\n");
    }
    function onLine(line) {
        let m;
        try { m = JSON.parse(line); } catch (e) { return; }
        if (m.ev === "state") {
            state = m.state; problem = m.problem || ""; code = m.code || ""; hasBak = !!m.hasBak; entries = m.entries || [];
            changed();
        } else if (m.ev === "history") {
            history = m.items || [];
        } else if (m.ev === "toast") {
            notice(m.icon === "clear" ? "clip" : "info", tr(m.text));
        } else if (m.re !== undefined) {
            const cb = pending[m.re]; delete pending[m.re];
            if (cb) cb(m);
        }
    }
    Process {
        id: proc
        command: ["python3", "-I", pv.py]
        running: true
        stdinEnabled: true
        stdout: SplitParser { onRead: data => pv.onLine(data) }
        stderr: SplitParser { onRead: data => console.log(data) }     // fixed status lines only, never secrets
        onStarted: { pv.state = "loading"; cfgT.restart(); }
        onExited: (code, status) => { pv.state = "down"; pv.entries = []; pv.history = []; const p = pv.pending; pv.pending = {};
                                      for (const k in p) p[k]({ ok: false, error: pv.tr("The password helper stopped.") }); restartT.restart(); }
    }
    Timer { id: restartT; interval: 3000; onTriggered: proc.running = true }
    // settings → helper (debounced)
    Timer { id: cfgT; interval: 200; onTriggered: pv.pushConfig() }
    onOChanged: cfgT.restart()
    function pushConfig() {
        req("config", { clip: { history: o.history, limit: o.historyLimit, clearAfter: o.clearAfter, ignored: o.ignored }, autoLock: o.autoLock });
    }

    // ── actions ─────────────────────────────────────────────
    function notice(kind, text) { Notch.notice(kind, text); }
    function clearsNote() { return o.clearAfter > 0 ? " · " + tr("clears in") + " " + o.clearAfter + " s" : ""; }
    function click() { if (o.sound) Quickshell.execDetached(["pw-play", "--volume", String(o.volume), clickWav]); }

    function generateCopy(cb) {
        req("generate", { policy: policy, copy: true }, r => {
            if (r.ok) notice("copy", tr("Password copied") + " · " + strengthOfBits(r.bits).label + clearsNote());
            else notice("info", r.error);
            if (cb) cb(r);
        });
    }
    function generate(cb, pol) { req("generate", { policy: pol || policy, copy: false }, cb); }
    function policyInfo(pol, cb) { req("policyInfo", { policy: pol }, cb); }
    function copyPassword(e, cb) {
        req("copy", { entryId: e.id, field: "password" }, r => {
            notice(r.ok ? "copy" : "info", r.ok ? e.title + " · " + tr("password copied") + clearsNote() : r.error);
            if (cb) cb(r);
        });
    }
    function copyUsername(e) { req("copy", { entryId: e.id, field: "username" }, r => notice(r.ok ? "copy" : "info", r.ok ? tr("Username copied") : r.error)); }
    function copyText(text, sensitive, msg) { req("copyText", { text: text, sensitive: sensitive }, r => notice(r.ok ? "copy" : "info", r.ok ? msg : r.error)); }
    function copyHistory(h, cb) { req("copyHistory", { histId: h.id }, r => { notice(r.ok ? "copy" : "info", r.ok ? tr("Copied") : r.error); if (cb) cb(r); }); }
    function histRemove(h) { req("histRemove", { histId: h.id }); }
    function histClear() { req("histClear", {}); }
    function add(entry, cb) { req("add", { entry: entry }, r => { if (r.ok) notice("info", tr("Password saved")); if (cb) cb(r); }); }
    function update(id, entry, replace, cb) { req("update", { entryId: id, entry: entry, replacePassword: replace }, r => { if (r.ok) notice("info", tr("Changes saved")); if (cb) cb(r); }); }
    function remove(id, cb) { req("delete", { entryId: id }, r => { notice("info", r.ok ? tr("Password deleted") : r.error); if (cb) cb(r); }); }
    function reveal(id, cb) { req("reveal", { entryId: id }, cb); }
    function lock() { req("lock", {}); }
    function unlock(cb) { req("unlock", {}, cb); }
    function recover(action, cb) { req("recover", { action: action }, r => { if (!r.ok) notice("info", r.error); if (cb) cb(r); }); }
    function wipe(cb) { req("wipe", {}, r => { notice("info", r.ok ? tr("All password data deleted") : r.error); if (cb) cb(r); }); }

    // ── strength (port of PasswordStrengthEstimator) ────────
    function strengthOfBits(bits) {
        const lv = bits < 40 ? 1 : bits < 60 ? 2 : bits < 80 ? 3 : 4;
        return { level: lv, bits: bits, frac: Math.max(0, Math.min(1, bits / 100)), label: tr(["", "Weak", "Fair", "Good", "Strong"][lv]),
                 color: ["#8a8fa3", "#ff7a7a", "#ffb86b", "#c3e88d", Cfg.accent][lv] };
    }
    function strength(pw) {
        if (!pw || !pw.length) return { level: 0, bits: 0, frac: 0, label: "", color: "#8a8fa3" };
        let lo = false, up = false, di = false, sy = false;
        for (const c of pw) { if (c >= "a" && c <= "z") lo = true; else if (c >= "A" && c <= "Z") up = true; else if (c >= "0" && c <= "9") di = true; else sy = true; }
        const a = (lo ? 26 : 0) + (up ? 26 : 0) + (di ? 10 : 0) + (sy ? 32 : 0);
        let bits = a <= 1 ? 0 : pw.length * Math.log2(a);
        if (pw.length < 8) bits = Math.min(bits, 34);
        return strengthOfBits(bits);
    }

    // ── hotkey ──────────────────────────────────────────────
    // canonical "CTRL + SHIFT + P"; needs Ctrl, Alt or Super + one real key (like RegisterHotKey on Windows)
    readonly property var modBits: ({ SHIFT: 1, CTRL: 4, ALT: 8, SUPER: 64 })
    function parseCombo(s) {
        const parts = String(s).toUpperCase().split("+").map(x => x.trim()).filter(x => x);
        let mask = 0, key = "";
        for (const p of parts) {
            const m = p === "CONTROL" ? "CTRL" : p === "WIN" || p === "META" || p === "MOD4" ? "SUPER" : p;
            if (modBits[m] !== undefined) mask |= modBits[m]; else key = p;
        }
        return { mask: mask, key: key };
    }
    function comboText(mask, key) {
        const l = [];
        if (mask & 64) l.push("SUPER"); if (mask & 4) l.push("CTRL"); if (mask & 8) l.push("ALT"); if (mask & 1) l.push("SHIFT");
        l.push(key);
        return l.join(" + ");
    }
    function pretty(s) {
        const c = parseCombo(s);
        const n = { SUPER: "Super", CTRL: "Ctrl", ALT: "Alt", SHIFT: "Shift" };
        const l = []; if (c.mask & 4) l.push("Ctrl"); if (c.mask & 8) l.push("Alt"); if (c.mask & 64) l.push("Super"); if (c.mask & 1) l.push("Shift");
        l.push(c.key.length === 1 ? c.key : c.key.charAt(0) + c.key.slice(1).toLowerCase());
        return l.join(" + ");
    }
    function validCombo(s) {
        const c = parseCombo(s);
        if (!c.key) return tr("Add a key, not only modifiers.");
        if (!(c.mask & (4 | 8 | 64))) return tr("Use Ctrl, Alt or Super with the key.");
        return "";
    }
    function luaBind(s) {
        return "pcall(hl.bind, \"" + s + "\", hl.dsp.exec_cmd(\"qs ipc call pwhelper toggle\"), { desc = \"Password helper\" })";
    }
    property string hotkeyMsg: ""
    property bool recording: false
    // checks Hyprland's binds for a clash, then rebinds live and saves the file; cb(error or "")
    property var hkJob: null
    function setHotkey(s, cb) {
        const err = validCombo(s);
        if (err) { if (cb) cb(err); return; }
        const c = parseCombo(s);
        hkJob = { combo: comboText(c.mask, c.key), mask: c.mask, key: c.key, cb: cb, old: o.hotkey };
        bindsP.running = false; bindsP.running = true;
    }
    Process {
        id: bindsP
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { onStreamFinished: pv.finishHotkey(this.text) }
    }
    function finishHotkey(txt) {
        const j = hkJob; hkJob = null; if (!j) return;
        let binds = [];
        try { binds = JSON.parse(txt); } catch (e) {}
        const clash = binds.find(b => b.modmask === j.mask && String(b.key).toUpperCase() === j.key && b.description !== "Password helper" && !b.release && !b.mouse);
        if (clash) { if (j.cb) j.cb(tr("Already used by") + " “" + (clash.description || clash.dispatcher) + "”"); return; }
        applyBind(j.old, j.combo);
        set("hotkey", j.combo);
        if (j.cb) j.cb("");
    }
    function applyBind(oldCombo, combo) {
        const lua = (oldCombo ? "pcall(hl.unbind, \"" + oldCombo + "\"); " : "") + (combo ? luaBind(combo) : "");
        Quickshell.execDetached(["hyprctl", "eval", lua]);
        if (combo) bindView.setText("-- generated by quickshell (Settings > Password helper > Shortcut); edit there\n" + luaBind(combo) + "\n");
    }
    // while recording a new shortcut the old one must not fire
    function pauseBind(on) { Quickshell.execDetached(["hyprctl", "eval", on ? "pcall(hl.unbind, \"" + o.hotkey + "\")" : luaBind(o.hotkey)]); }
    FileView { id: bindView; path: pv.bindFile; blockLoading: true; printErrors: false }
    // first run (or the file got lost): write it and bind once
    Component.onCompleted: {
        const t = bindView.text();
        if (!t || t.indexOf(o.hotkey) < 0) applyBind(t ? "" : "", o.hotkey);
    }

    // ── text ────────────────────────────────────────────────
    function tr(s) { return Cfg.lang === "ru" && ru[s] !== undefined ? ru[s] : Cfg.tr(s); }
    readonly property var ru: ({
        "Password helper": "Помощник паролей", "Generate": "Создать", "Clipboard": "Буфер", "Saved": "Сохранённые", "Add": "Добавить",
        "More": "Ещё", "Close": "Закрыть", "Password copied": "Пароль скопирован", "password copied": "пароль скопирован",
        "Username copied": "Логин скопирован", "Copied": "Скопировано", "clears in": "очистится через", "Clipboard cleared": "Буфер очищен",
        "Password saved": "Пароль сохранён", "Changes saved": "Изменения сохранены", "Password deleted": "Пароль удалён",
        "All password data deleted": "Все данные паролей удалены", "Weak": "Слабый", "Fair": "Средний", "Good": "Хороший", "Strong": "Сильный",
        "Saved passwords": "Сохранённые пароли", "Clipboard history": "История буфера", "Search passwords…": "Поиск паролей…",
        "Search clipboard…": "Поиск в буфере…", "No saved passwords yet.": "Сохранённых паролей пока нет.", "No clipboard history yet.": "История буфера пуста.",
        "Clipboard history is turned off.": "История буфера выключена.", "The vault is locked.": "Хранилище заблокировано.",
        "Unlock": "Разблокировать", "Lock": "Заблокировать", "Title": "Название", "Username": "Логин", "Password": "Пароль",
        "Website (optional)": "Сайт (необязательно)", "Notes (optional)": "Заметки (необязательно)", "Pin to the ring": "Закрепить на кольце",
        "Cancel": "Отмена", "Save": "Сохранить", "Edit": "Изменить", "Delete": "Удалить", "Show": "Показать", "Hide": "Скрыть",
        "Copy": "Копировать", "Add password": "Добавить пароль", "Edit password": "Изменить пароль", "Delete password?": "Удалить пароль?",
        "This cannot be undone.": "Это нельзя отменить.", "Leave empty to keep the current one": "Оставьте пустым, чтобы не менять",
        "Generate a secure password": "Сгенерировать надёжный пароль", "Recent clipboard items": "Недавнее из буфера",
        "Pick, edit, delete": "Выбрать, изменить, удалить", "Save a new one": "Сохранить новый", "Copy its password": "Скопировать пароль",
        "Clear history": "Очистить историю", "The vault does not open": "Хранилище не открывается", "Restore backup": "Восстановить из копии",
        "Start new": "Начать заново", "Leave it": "Оставить как есть", "Keyring unavailable": "Связка ключей недоступна",
        "Vault locked - click Saved to unlock": "Хранилище заблокировано - откройте «Сохранённые»", "characters": "символов",
        "just now": "только что", "Details": "Подробнее", "Created": "Создан", "Modified": "Изменён", "Back": "Назад",
        "Enter a title.": "Введите название.", "Enter a password.": "Введите пароль."
    })
}
