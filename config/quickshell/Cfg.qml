pragma Singleton
// sakura mono - shared settings for the whole shell (~/.config/sakura/settings.json)
// language + translations, time format, units, main monitor, desktop widgets, start menu layout.
// Nothing here is tied to one PC: an empty/missing file means "sensible defaults for this machine".
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: cfg
    readonly property string home: Quickshell.env("HOME")
    readonly property string path: home + "/.config/sakura/settings.json"

    // ── catalogs ────────────────────────────────────────────
    // desktop widgets: default spot = where the old fixed widgets sat (left column of the main monitor)
    readonly property var widgetCatalog: [
        { id: "clock",    name: "Clock",          icon: "", on: true,  x: 70,   y: 130 },
        { id: "date",     name: "Date",           icon: "", on: true,  x: 70,   y: 287 },
        { id: "weather",  name: "Weather",        icon: "", on: true,  x: 70,   y: 331 },
        { id: "player",   name: "Music player",   icon: "", on: true,  x: 70,   y: 384 },
        { id: "forecast", name: "Forecast",       icon: "", on: false, x: 70,   y: 520 },
        { id: "sysmon",   name: "System monitor", icon: "", on: false, x: 1560, y: 130 },
        { id: "calendar", name: "Calendar",       icon: "", on: false, x: 1560, y: 330 },
        { id: "analog",   name: "Analog clock",   icon: "", on: false, x: 1600, y: 640 },
        { id: "greeting", name: "Greeting",       icon: "", on: false, x: 70,   y: 60  },
        { id: "visualizer",  name: "Visualizer",   on: false, x: 1480, y: 880 },
        { id: "worldclock",  name: "World clock",  on: false, x: 1560, y: 130 },
        { id: "dayprogress", name: "Day progress", on: false, x: 1560, y: 420 },
        { id: "note",        name: "Sticky note",  on: false, x: 1560, y: 600 },
        { id: "todo",        name: "To-do list",   on: false, x: 1180, y: 130 },
        { id: "timer",       name: "Timer",        on: false, x: 1180, y: 520 },
        { id: "hardware",    name: "Hardware",     on: false, x: 1560, y: 760 },
        { id: "user",        name: "User card",    on: false, x: 70,   y: 720 },
        { id: "screentime",  name: "Screen time",  on: false, x: 1180, y: 700 }
    ]
    // looks a widget can switch between (desktop editor: the style button); the first one is the default
    readonly property var widgetStyles: ({
        clock: ["big", "stacked", "minimal"], analog: ["classic", "minimal"], calendar: ["full", "compact"],
        visualizer: ["bars", "mirror", "line"], dayprogress: ["bars", "rings"], screentime: ["today", "week"]
    })
    readonly property var worldClocks: data.worldClocks || [
        { tz: "Europe/Kyiv", name: "Kyiv" }, { tz: "Europe/London", name: "London" },
        { tz: "America/New_York", name: "New York" }, { tz: "Asia/Tokyo", name: "Tokyo" }
    ]
    // start menu pieces
    readonly property var toggleCatalog: [
        { id: "vpn",        name: "VPN",        icon: "", needs: "mullvad" },
        { id: "dnd",        name: "Do not disturb", icon: "" },
        { id: "screenshot", name: "Screenshot", icon: "" },
        { id: "color",      name: "Color picker", icon: "", needs: "hyprpicker" },
        { id: "clipboard",  name: "Clipboard",  icon: "" },
        { id: "mic",        name: "Microphone", icon: "" },
        { id: "night",      name: "Night light", icon: "" },
        { id: "taskmgr",    name: "Task Manager", icon: "" },
        { id: "barpos",     name: "Bar position", icon: "" },
        { id: "lock",       name: "Lock",       icon: "" }
    ]
    readonly property var shortcutCatalog: [
        { id: "sound",      name: "Sound",          icon: "" },
        { id: "display",    name: "Displays",       icon: "" },
        { id: "network",    name: "Network & VPN",  icon: "" },
        { id: "appearance", name: "Appearance",     icon: "" },
        { id: "wallpaper",  name: "Wallpaper",      icon: "" },
        { id: "widgets",    name: "Desktop widgets", icon: "" },
        { id: "input",      name: "Keyboard & Mouse", icon: "" },
        { id: "time",       name: "Time & Language", icon: "" },
        { id: "menu",       name: "Start menu",     icon: "\uf0c9" },
        { id: "taskbar",    name: "Taskbar",        icon: "\uf2d0" },
        { id: "notify",     name: "Notifications",  icon: "\uf0f3" },
        { id: "apps",       name: "Default apps",   icon: "\uf00a" },
        { id: "power",      name: "Power & Sleep",  icon: "" },
        { id: "storage",    name: "Storage",        icon: "" },
        { id: "color",      name: "Color Control",  icon: "" },
        { id: "about",      name: "About",          icon: "" }
    ]
    readonly property var powerCatalog: [
        { id: "lock",     name: "Lock",      icon: "" },
        { id: "logout",   name: "Log out",   icon: "" },
        { id: "sleep",    name: "Sleep",     icon: "" },
        { id: "restart",  name: "Restart",   icon: "" },
        { id: "shutdown", name: "Shut down", icon: "" }
    ]

    function defaults() {
        return {
            lang: "en", clock24: true, seconds: false, units: "c", weekStart: 1,
            mainMonitor: "",
            widgets: widgetCatalog.map(w => ({ id: w.id, on: w.on, x: w.x, y: w.y, scale: 1.0 })),
            menu: {
                banner: true, pinned: true, pinnedRows: 2, volume: true, toggles: true, shortcuts: true, media: true, user: true,
                toggleList: ["vpn", "dnd", "screenshot", "color", "clipboard"],
                shortcutList: ["sound", "display", "network", "appearance", "input", "about"],
                powerList: ["lock", "logout", "sleep", "restart", "shutdown"]
            }
        };
    }

    property var data: defaults()
    property bool loaded: false
    FileView {
        id: file
        path: cfg.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: cfg.merge(text())
        onLoadFailed: cfg.loaded = true
    }
    function merge(t) {
        let j = {};
        try { j = JSON.parse(t); } catch (e) { loaded = true; return; }
        const d = defaults();
        for (const k in j) if (k !== "widgets" && k !== "menu") d[k] = j[k];
        if (j.menu) for (const k in j.menu) d.menu[k] = j.menu[k];
        if (Array.isArray(j.widgets)) {
            // keep the saved order/positions, add widgets that are new in the catalog
            const saved = j.widgets.filter(w => widgetCatalog.some(c => c.id === w.id));
            for (const c of d.widgets) if (!saved.some(w => w.id === c.id)) saved.push(c);
            d.widgets = saved.map(w => Object.assign({ scale: 1.0 }, w));
        }
        data = d; loaded = true;
    }
    Timer { id: saveT; interval: 250; onTriggered: file.setText(JSON.stringify(cfg.data, null, 2)) }
    function save() { saveT.restart(); }
    function set(k, v) { const d = Object.assign({}, data); d[k] = v; data = d; save(); }
    function setMenu(k, v) { const m = Object.assign({}, data.menu); m[k] = v; set("menu", m); }
    // a widget may live on another monitor ("mon": "DP-1"); if that monitor is gone it falls back to the main one
    function widgetScreen(w) { const n = w && w.mon; return (n && Quickshell.screens.find(s => s.name === n)) || mainScreen; }
    function onMain(w) { return widgetScreen(w) === mainScreen; }
    // put a widget on a monitor at x/y (kept inside it); "mon" stays empty for the main monitor so it follows mainMonitor
    function placeWidget(id, scr, x, y, extra) {
        const p = Object.assign({ x: Math.max(0, Math.round(x)), y: Math.max(0, Math.round(y)), mon: scr === mainScreen ? "" : scr.name }, extra || {});
        setWidget(id, p);
    }
    function widget(id) { return data.widgets.find(w => w.id === id) || null; }
    function setWidget(id, patch) {
        set("widgets", data.widgets.map(w => w.id === id ? Object.assign({}, w, patch) : w));
    }
    function resetWidgets() {
        const d = defaults().widgets;
        set("widgets", data.widgets.map(w => { const c = d.find(x => x.id === w.id); return c ? Object.assign({}, w, { x: c.x, y: c.y, scale: 1.0 }) : w; }));
    }

    // ── accent color (Settings > Appearance; hypr/scripts/accent.sh also recolors waybar, kitty, …) ──
    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(data.accent || "") ? data.accent : "#f2b8d0"
    // text on top of the accent: dark on light colors, white on dark ones
    readonly property color accFg: (0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b) > 0.55 ? "#1a121a" : "#ffffff"
    function acc(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }

    // ── your picture (Settings > About > Change; hypr/scripts/avatar.sh) - "?r" makes Qt reload it after a change ──
    readonly property string avatar: "file://" + home + "/.config/hypr/assets/avatar.png?r=" + (data.avatarRev || 0)
    // ── look (Settings > Appearance > Shell) ────────────────
    // glass = the panels, bar, dock, menus: dark tint + hyprland blur behind it
    readonly property real glassAlpha: typeof data.glass === "number" ? Math.max(0.15, Math.min(0.95, data.glass)) : 0.55
    readonly property color glass: Qt.rgba(15 / 255, 17 / 255, 25 / 255, glassAlpha)
    readonly property string fontUi: data.font || "Inter"
    // animation speed: duration multiplier (0.6 fast · 1 normal · 1.6 slow)
    readonly property real anim: typeof data.animSpeed === "number" ? data.animSpeed : 1.0

    // ── top bar (Settings > Taskbar) ────────────────────────
    readonly property var barLeftCatalog: [
        { id: "barpos",   name: "Bar position",  icon: "\uf078" },
        { id: "launcher", name: "Start menu",    icon: "\uf303" },
        { id: "tray",     name: "Tray icons",    icon: "\uf106" },
        { id: "windows",  name: "Open windows",  icon: "\uf2d0" },
        { id: "minimized",name: "Minimized windows", icon: "\uf2d1" },
        { id: "track",    name: "Now playing",   icon: "\uf001" }
    ]
    readonly property var barRightCatalog: [
        { id: "capture",  name: "Recording",     icon: "\uf03d" },
        { id: "layout",   name: "Keyboard layout", icon: "\uf11c" },
        { id: "volume",   name: "Sound",         icon: "\uf028" },
        { id: "network",  name: "Network",       icon: "\uf1eb" },
        { id: "cpu",      name: "CPU",           icon: "\uf2db" },
        { id: "ram",      name: "RAM",           icon: "\u{F035B}" },
        { id: "updates",  name: "Updates",       icon: "\uf021" },
        { id: "notify",   name: "Notifications", icon: "\uf0f3" },
        { id: "devices",  name: "Device battery", icon: "\u{F0079}" },
        { id: "power",    name: "Power",         icon: "\uf011" }
    ]
    // ── corner island (CornerIsland.qml, Settings > Taskbar) ──
    readonly property var islandCatalog: [
        { id: "clock",      name: "Time and date", icon: "\uf017" },
        { id: "layout",     name: "Keyboard layout", icon: "\uf11c" },
        { id: "volume",     name: "Sound",         icon: "\uf028" },
        { id: "network",    name: "Network",       icon: "\uf1eb" },
        { id: "cpu",        name: "CPU",           icon: "\uf2db" },
        { id: "ram",        name: "RAM",           icon: "\u{F035B}" },
        { id: "notify",     name: "Notifications", icon: "\uf0f3" },
        { id: "track",      name: "Now playing",   icon: "\uf001" },
        { id: "capture",    name: "Recording",     icon: "\uf03d" },
        { id: "updates",    name: "Updates",       icon: "\uf021" },
        { id: "devices",    name: "Device battery", icon: "\u{F0079}" },
        { id: "screenshot", name: "Screenshot",    icon: "\uf030" },
        { id: "vpn",        name: "VPN",           icon: "\uf023", needs: "mullvad" },
        { id: "dnd",        name: "Do not disturb", icon: "\uf1f6" },
        { id: "mixer",      name: "Mixer",         icon: "\uf1de" },
        { id: "mic",        name: "Microphone",    icon: "\uf130" },
        { id: "night",      name: "Night light",   icon: "\uf186" },
        { id: "clipboard",  name: "Clipboard",     icon: "\uf0ea" },
        { id: "color",      name: "Color picker",  icon: "\uf1fb", needs: "hyprpicker" },
        { id: "wallpaper",  name: "Wallpaper",     icon: "\uf03e" },
        { id: "lock",       name: "Lock",          icon: "\uf023" },
        { id: "power",      name: "Power",         icon: "\uf011" }
    ]
    readonly property var islandDefault: ["layout", "volume", "network", "cpu", "ram", "screenshot", "dnd", "notify"]
    // per-module look (Settings > Taskbar, click a module in the preview): settings.json "modOpts" = { volume: { pct: false }, … }
    readonly property var modOptCatalog: ({
        clock:   [ { k: "date",  t: "Date",            def: true } ],
        volume:  [ { k: "pct",   t: "Percent",         def: true } ],
        network: [ { k: "name",  t: "Connection name", def: false } ],
        cpu:     [ { k: "pct",   t: "Percent",         def: true } ],
        ram:     [ { k: "pct",   t: "Percent",         def: true } ],
        notify:  [ { k: "count", t: "Unread count",    def: true } ],
        track:   [ { k: "text",  t: "Track name",      def: true }, { k: "art", t: "Cover", def: true } ],
        layout:  [ { k: "long",  t: "Full name",       def: false } ],
        devices: [ { k: "pct", t: "Percent", def: true }, { k: "headset", t: "Headset", def: true },
                   { k: "mouse", t: "Mouse", def: true }, { k: "keyboard", t: "Keyboard", def: true } ]
    })
    function mo(id, k) {
        const o = (data.modOpts || {})[id];
        if (o && o[k] !== undefined) return o[k];
        const d = (modOptCatalog[id] || []).find(x => x.k === k);
        return d ? d.def : true;
    }
    function setMo(id, k, v) { const all = Object.assign({}, data.modOpts || {}); const o = Object.assign({}, all[id] || {}); o[k] = v; all[id] = o; set("modOpts", all); }
    // a saved list as a plain JS array (Array.isArray is false for lists that went through a QML var), or def
    function list(v, def) {
        if (v && typeof v === "object" && typeof v.length === "number") { const out = []; for (let i = 0; i < v.length; i++) out.push(String(v[i])); return out; }
        return def;
    }
    readonly property var barLeft: list(data.barLeft, barLeftCatalog.map(c => c.id))
    readonly property var barRight: list(data.barRight, barRightCatalog.map(c => c.id))
    readonly property var islandItems: list(data.islandItems, islandDefault).filter(i => islandCatalog.some(c => c.id === i))
    readonly property bool barAlways: data.barMode === "always"      // wings always out (default: on hover)

    // ── language ────────────────────────────────────────────
    readonly property string lang: data.lang || "en"
    readonly property var locale: Qt.locale(lang === "ru" ? "ru_RU" : "en_US")
    function tr(s) { return lang === "ru" && ru[s] !== undefined ? ru[s] : s; }
    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

    // ── time & units ────────────────────────────────────────
    function timeStr(d, withSec) {
        const f = (data.clock24 !== false ? "HH:mm" : "h:mm") + (withSec ? ":ss" : "");
        let s = locale.toString(d, f);
        if (data.clock24 === false) s += (d.getHours() < 12 ? " AM" : " PM");
        return s;
    }
    // Settings > Time & Language > Date: long "Tuesday, 10 November" · short "Tue, 10 Nov" · numeric "10.11.2026"
    function dateLong(d) {
        const s = data.dateStyle || "long";
        return cap(locale.toString(d, s === "short" ? "ddd, d MMM" : s === "numeric" ? (lang === "en" ? "MM/dd/yyyy" : "dd.MM.yyyy") : "dddd, d MMMM"));
    }
    function dayShort(d) { return cap(locale.toString(d, "ddd")); }
    function temp(c) {
        if (c === undefined || c === null) return "";
        return data.units === "f" ? Math.round(c * 9 / 5 + 32) + "°F" : Math.round(c) + "°";
    }
    function wText(code) {
        let t;
        if (code === 0) t = "Clear"; else if (code <= 2) t = "Partly cloudy"; else if (code === 3) t = "Cloudy";
        else if (code <= 48) t = "Fog"; else if (code <= 57) t = "Drizzle"; else if (code <= 67) t = "Rain";
        else if (code <= 77) t = "Snow"; else if (code <= 82) t = "Showers"; else if (code <= 86) t = "Snow showers"; else t = "Thunderstorm";
        return tr(t);
    }

    // ── monitors ────────────────────────────────────────────
    // main monitor = chosen in Settings; otherwise the one at 0,0 (or simply the first)
    readonly property var mainScreen: {
        const ss = Quickshell.screens, n = data.mainMonitor || "";
        return (n !== "" && ss.find(s => s.name === n)) || ss.find(s => s.x === 0 && s.y === 0) || ss[0] || null;
    }
    readonly property string mainName: mainScreen ? mainScreen.name : ""

    // ── what is installed (so a friend's PC without e.g. Mullvad just hides those bits) ──
    property var has: ({})
    Process {
        command: ["sh", "-c", "for c in mullvad openrgb swaync-client hyprpicker pavucontrol nm-connection-editor nwg-look awww cliphist; do command -v $c >/dev/null && echo $c; done"]
        running: true
        stdout: StdioCollector { onStreamFinished: { const h = {}; this.text.split("\n").forEach(x => { if (x) h[x] = true; }); cfg.has = h; } }
    }
    function available(item) { return !item.needs || has[item.needs] === true; }

    // ── Russian ─────────────────────────────────────────────
    readonly property var ru: ({
        // file converter (Convert.qml)
        "File converter": "Конвертер файлов",
        "File converter: drag files from Dolphin into that corner and drop them on a petal. The screen-edge catchers are off while a corner has it.": "Конвертер файлов: перетащи файлы из Dolphin в этот угол и брось на лепесток. Пока он назначен углу, зоны по краям экрана выключены.",
        "Converter": "Конвертер",
        "Nothing to convert": "Нечего конвертировать",
        "Pictures, PDF, video and audio only": "Только картинки, PDF, видео и аудио",
        "Convert": "Конвертация",
        "Tools": "Инструменты",
        "hold…": "задержись…",
        "files": "файлов",
        "Needs rembg - drop for the install command": "Нужен rembg - брось, покажу команду установки",
        "Lossless, keeps transparency": "Без потерь, с прозрачностью",
        "Photos, opens everywhere": "Фото, открывается везде",
        "Small, made for the web": "Лёгкий, для веба",
        "Smallest, modern": "Самый лёгкий, современный",
        "The iPhone photo format": "Формат фото iPhone",
        "Animation, 256 colours": "Анимация, 256 цветов",
        "Windows icon": "Иконка Windows",
        "Plain bitmap, no compression": "Битмап без сжатия",
        "Lossless, for print": "Без потерь, для печати",
        "Document": "Документ",
        "All of them into one PDF": "Все в один PDF",
        "Video, much smaller": "Видео, намного легче",
        "Web video": "Видео для веба",
        "One picture per page": "Картинка на каждую страницу",
        "Plays everywhere (H.264)": "Играет везде (H.264)",
        "Open web video (VP9)": "Открытое веб-видео (VP9)",
        "Repack, no quality loss": "Перепаковка без потерь",
        "Animated GIF · first 30 s": "Анимированный GIF · первые 30 с",
        "Just the sound · MP3": "Только звук · MP3",
        "Just the sound · Vorbis": "Только звук · Vorbis",
        "Just the sound · lossless": "Только звук · без потерь",
        "Just the sound · uncompressed": "Только звук · без сжатия",
        "Extract the sound as it is": "Вытащить звук как есть",
        "Plays everywhere": "Играет везде",
        "Open format (Vorbis)": "Открытый формат (Vorbis)",
        "Lossless": "Без потерь",
        "Uncompressed": "Без сжатия",
        "Smallest, great quality": "Самый лёгкий, отличное качество",
        "AAC, Apple-friendly": "AAC, дружит с Apple",
        "Info": "Инфо",
        "Camera, date, location, size": "Камера, дата, геометка, размер",
        "View": "Смотреть",
        "Show the metadata": "Показать метаданные",
        "Remove": "Удалить",
        "Strip EXIF and location": "Убрать EXIF и геометку",
        "Compress": "Сжать",
        "Smaller file, same look": "Меньше файл, тот же вид",
        "Light": "Слегка",
        "Barely visible": "Почти незаметно",
        "Strong": "Сильно",
        "Much smaller, max 2560 px": "Намного меньше, до 2560 px",
        "Resize": "Размер",
        "Make the picture smaller": "Уменьшить картинку",
        "Half the size": "Вдвое меньше",
        "Short side 1080 px": "Короткая сторона 1080 px",
        "Short side 720 px": "Короткая сторона 720 px",
        "Short side 480 px": "Короткая сторона 480 px",
        "A quarter": "Четверть",
        "Drag the frame's edges · Enter saves": "Тяни края рамки · Enter сохранит",
        "Rotate": "Поворот",
        "Turn or mirror": "Повернуть или отразить",
        "Clockwise": "По часовой",
        "Counter-clockwise": "Против часовой",
        "Upside down": "Вверх ногами",
        "Mirror left-right": "Отразить по горизонтали",
        "Mirror top-bottom": "Отразить по вертикали",
        "No BG": "Без фона",
        "Cut the background out": "Вырезать фон",
        "Add BG": "Фон",
        "Put it on a background": "Подложить фон",
        "Soft accent card with a shadow": "Мягкая карточка в цвет акцента с тенью",
        "Fill transparency with white": "Залить прозрачное белым",
        "Black": "Чёрный",
        "Fill transparency with black": "Залить прозрачное чёрным",
        "Edit": "Править",
        "Arrows, text, steps, marker": "Стрелки, текст, метки, маркер",
        "Black out, blur or pixelate": "Закрасить, размыть, пикселизовать",
        "Codecs, resolution, length": "Кодеки, разрешение, длина",
        "Smaller MP4 for sharing": "Лёгкий MP4, чтобы отправить",
        "Up to 1080p": "До 1080p",
        "Up to 720p, tiny": "До 720p, крошечный",
        "Lower the resolution": "Понизить разрешение",
        "Full HD": "Full HD",
        "HD": "HD",
        "SD": "SD",
        "Trim": "Обрезать",
        "Cut a piece out by time": "Вырезать кусок по времени",
        "Mute": "Без звука",
        "Remove the sound (no re-encode)": "Убрать звук (без перекодирования)",
        "Turn the video": "Повернуть видео",
        "Speed": "Скорость",
        "Faster or slower": "Быстрее или медленнее",
        "Twice as fast": "Вдвое быстрее",
        "A bit faster": "Чуть быстрее",
        "Slow motion": "Замедленно",
        "Slower": "Медленнее",
        "Frame": "Кадр",
        "Save the middle frame as PNG": "Сохранить средний кадр в PNG",
        "Codec, bitrate, tags": "Кодек, битрейт, теги",
        "Smaller MP3": "Лёгкий MP3",
        "Good for music": "Для музыки",
        "Voice, podcasts": "Голос, подкасты",
        "Louder": "Громкость",
        "Even out the loudness (−14 LUFS)": "Выровнять громкость (−14 LUFS)",
        "Silence": "Тишина",
        "Cut silence at the start and end": "Срезать тишину в начале и конце",
        "Enter saves next to the original": "Enter сохранит рядом с оригиналом",
        // screenshot editor (Shot.qml)
        "Arrow": "Стрелка", "Rectangle": "Прямоугольник", "Ellipse": "Эллипс", "Pencil": "Карандаш", "Marker": "Маркер", "Numbered step": "Нумерованная метка",
        "Pixelate": "Пикселизация", "Redact": "Закрасить", "Move": "Перемещение", "Blocks": "Блоки", "Redo": "Повторить", "Pin to screen": "Закрепить на экране",
        "Copy text (OCR)": "Скопировать текст (OCR)", "Beautify": "Украсить", "Close": "Закрыть", "Beautify on": "Украшение включено", "Beautify off": "Украшение выключено",
        "Saved": "Сохранено", "Could not render the image": "Не удалось собрать картинку", "No previous area": "Нет прошлой области",
        "Pick a colour - Shift for rgb()": "Выбери цвет - Shift для rgb()", "Select an area": "Выдели область", "Screenshot editor": "Редактор скриншотов",
        "Freeze, select, draw, then Enter copies · Ctrl+S saves (HolyScreen style)": "Замереть, выделить, порисовать: Enter копирует · Ctrl+S сохраняет (как HolyScreen)",
        "Without the screenshot editor: open satty after selecting": "Без редактора скриншотов: открывать satty после выделения",
        "Live activities": "Живые активности", "Cover and bars beside the clock": "Обложка и полоски рядом с часами", "Track change": "Смена трека",
        "Title and artist for a moment": "Ненадолго название и исполнитель", "Timer and stopwatch": "Таймер и секундомер", "Screen sharing": "Демонстрация экрана",
        "Microphone in use": "Микрофон занят", "Which app listens": "Какое приложение слушает", "Instant Replay": "Мгновенный повтор", "It runs all the time": "Он работает всегда",
        "Replay": "Повтор",
        "Notch at rest": "Вырез в покое","Comet runs along the edge with the hour, tide fills up with the day, rings: day, week, month": "Комета бежит по кромке вместе с часом, прилив растёт с днём, кольца: день, неделя, месяц",
        "Plain": "Простой", "Comet": "Комета", "Tide": "Прилив", "mute": "без звука",
        "Screenshot saved": "Скриншот сохранён", "Screenshot copied": "Скриншот скопирован", "Do not disturb on": "Не беспокоить: вкл", "Do not disturb off": "Не беспокоить: выкл",
        "Wallpaper changed": "Обои сменились", "Instant Replay saved": "Повтор сохранён", "Recording saved": "Запись сохранена", "Copied": "Скопировано",
        "Percent": "Проценты", "Connection name": "Имя подключения", "Unread count": "Число непрочитанных", "Track name": "Название трека", "Cover": "Обложка", "Full name": "Полное название", "Available": "Доступные", "Bar": "Бар",
        "Corner island": "Угловой островок", "Glass with indicators and buttons in a screen corner, tinted by the wallpaper": "Стекло с показателями и кнопками в углу экрана, в цвет обоев",
        "Corner": "Угол", "Monitor": "Монитор", "Main": "Главный", "Second": "Второй", "Both": "Оба", 
        "Island modules": "Модули островка", "Time and date": "Время и дата", "Mixer": "Микшер",
        // weather
        "Clear": "Ясно", "Partly cloudy": "Переменная облачность", "Cloudy": "Облачно", "Fog": "Туман", "Drizzle": "Морось",
        "Rain": "Дождь", "Snow": "Снег", "Showers": "Ливни", "Snow showers": "Снегопад", "Thunderstorm": "Гроза",
        "Today": "Сегодня", "Feels like": "Ощущается как", "Humidity": "Влажность", "Wind": "Ветер", "loading…": "загрузка…",
        // widgets
        "Clock": "Часы", "Date": "Дата", "Weather": "Погода", "Music player": "Плеер", "Forecast": "Прогноз",
        "System monitor": "Монитор системы", "Calendar": "Календарь", "Analog clock": "Аналоговые часы", "Greeting": "Приветствие",
        "Good morning": "Доброе утро", "Good afternoon": "Добрый день", "Good evening": "Добрый вечер", "Good night": "Доброй ночи",
        "Nothing playing": "Ничего не играет", "CPU": "ЦП", "RAM": "ОЗУ", "GPU": "ГП", "Disk": "Диск",
        // start menu
        "Pinned": "Закреплённые", "All apps": "Все приложения", "Settings": "Настройки",
        "Search apps, files, 2+2, 1000 jpy to usd…": "Приложения, файлы, 2+2, 1000 jpy to usd…",
        "VPN": "VPN", "VPN on": "VPN вкл", "VPN off": "VPN выкл", "VPN…": "VPN…", "Do not disturb": "Не беспокоить", "Silent": "Тихо", "Alerts": "Уведомл.",
        "Screenshot": "Скриншот", "Color picker": "Пипетка", "Color": "Цвет", "Clipboard": "Буфер", "Microphone": "Микрофон",
        "Night light": "Ночной свет", "Task Manager": "Диспетчер задач", "Bar position": "Панель вниз/вверх", "Lock": "Блокировка",
        "Log out": "Выйти", "Sleep": "Сон", "Restart": "Перезагрузка", "Shut down": "Выключение", "up": "работает",
        "Open": "Открыть", "Pin to Start": "Закрепить в Пуске", "Unpin from Start": "Открепить от Пуска",
        "Pin to dock": "Закрепить в доке", "Unpin from dock": "Открепить от дока",
        "Search the web for": "Искать в интернете", "Enter to copy": "Enter - скопировать", "command": "команда",
        // tray
        "Hidden icons": "Скрытые значки", "Pin to bar": "Закрепить на панели", "Unpin from bar": "Открепить от панели",
        "Bar is full": "Панель заполнена", "right click - pin to bar · menu": "ПКМ - закрепить · меню",
        "Everything is on the bar": "Всё уже на панели", "Tray icons": "Значки трея", "Done": "Готово", "On the bar": "На панели",
        "the rest hide behind ^": "остальные прячутся за ^", "idle - hidden by the app": "неактивен - скрыт приложением", "Empty": "Пусто",
        // settings: pages & groups
        "System": "Система", "Personalization": "Персонализация", "Time & Language": "Время и язык", "Devices": "Устройства",
        "Apps": "Приложения", "Sound": "Звук", "Displays": "Дисплеи", "Network & VPN": "Сеть и VPN", "Appearance": "Оформление",
        "Wallpaper": "Обои", "Desktop widgets": "Виджеты", "Start menu": "Меню Пуск", "Taskbar": "Панель задач",
        "Keyboard & Mouse": "Клавиатура и мышь", "Power & Sleep": "Питание и сон", "Storage": "Память", "Color Control": "Цвет экрана",
        "Lighting": "Подсветка", "Floating Lyrics": "Текст песен", "About": "О системе", "Notifications": "Уведомления",
        "Default apps": "Приложения по умолчанию", "Startup": "Автозагрузка", "Search settings": "Поиск настроек",
        "Music": "Музыка", "SoundCloud player": "Плеер SoundCloud", "Open": "Открыть", "Music in the notch opens": "Музыка в вырезе открывает", "Cookies from": "Cookies из", "Browser signed in to SoundCloud": "Браузер, где выполнен вход в SoundCloud", "Start with the session": "Запускать со входом", "Waits hidden, so music starts at once": "Ждёт скрытым, музыка включается сразу", "Sign in to SoundCloud in Brave": "Войди в SoundCloud в Brave",
        // settings: common words
        "Output": "Вывод", "Input (microphone)": "Ввод (микрофон)", "Volume": "Громкость", "Mic level": "Уровень микрофона",
        "Advanced mixer": "Расширенный микшер", "Main monitor": "Главный монитор", "Resolution": "Разрешение",
        "Refresh rate": "Частота", "Scale": "Масштаб", "Position": "Положение", "Apply": "Применить", "Revert": "Отменить",
        "Language": "Язык", "Time zone": "Часовой пояс", "Location": "Местоположение", "Detect automatically": "Определить автоматически",
        "24-hour clock": "24-часовой формат", "Show seconds": "Показывать секунды", "Temperature": "Температура",
        "First day of week": "Первый день недели", "Monday": "Понедельник", "Sunday": "Воскресенье",
        "Use the location's time zone": "Взять пояс из местоположения", "Search city…": "Найти город…", "Search…": "Поиск…",
        "Reset positions": "Сбросить позиции", "Drag widgets on the preview to move them.": "Перетаскивайте виджеты на превью, чтобы двигать их.",
        "Sections": "Разделы", "Quick toggles": "Быстрые кнопки", "Settings shortcuts": "Ярлыки настроек", "Power buttons": "Кнопки питания",
        "Banner": "Баннер", "Pinned apps": "Закреплённые приложения", "Volume slider": "Ползунок громкости",
        "Media player": "Медиаплеер", "User": "Пользователь", "Rows of pinned apps": "Рядов закреплённых",
        "Click to add or remove. Order = the order you pick them in.": "Нажмите, чтобы добавить или убрать. Порядок = порядок выбора.",
        "Effects": "Эффекты", "Windows": "Окна", "Blur": "Размытие", "Animations": "Анимации", "Size": "Размер",
        "Never": "Никогда", "min": "мин", "h": "ч", "d": "д", "On": "Вкл", "Off": "Выкл", "Reset": "Сбросить", "Change": "Изменить",
        "Bar at the top": "Панель сверху", "Bar at the bottom": "Панель снизу", "Restart needed": "Нужен перезапуск",
        "Apply to apps too (after re-login)": "Применять к приложениям (после перезахода)",
        "Changes apply right away.": "Изменения применяются сразу.",
        "Center horizontally": "По центру ↔", "Center vertically": "По центру ↕", "To the left": "Влево", "To the right": "Вправо",
        "Widgets stick to the screen centre, the edges and each other. Hold Shift to move freely.": "Виджеты прилипают к центру экрана, краям и друг к другу. Shift - двигать свободно.",
        "Adjust": "Настройка",
        "Adjust desktop color like the NVIDIA control panel. Changes apply live to every monitor and are kept after reboot.": "Цвет рабочего стола как в панели NVIDIA. Применяется сразу ко всем мониторам и сохраняется после перезагрузки.",
        "Animation": "Анимация",
        "Animation speed": "Скорость анимации",
        "Apply at login": "Применять при входе",
        "At the bottom the bar splits into two pills next to the dock": "Внизу панель делится на две части по бокам от дока",
        "Border width": "Толщина рамки",
        "Bottom": "Снизу",
        "Breathing": "Дыхание",
        "Brightness": "Яркость",
        "Choose which icons sit on the bar and which hide behind ^ (or right-click an icon)": "Какие значки на панели, а какие за ^ (или ПКМ по значку)",
        "Cinema": "Кино",
        "Clear all": "Очистить всё",
        "Connect": "Подключить",
        "Connected": "Подключено",
        "Connections": "Подключения",
        "Content follows your fingers, like on a phone": "Содержимое двигается за пальцами, как на телефоне",
        "Contrast": "Контраст",
        "Corner rounding": "Скругление углов",
        "Custom color": "Свой цвет",
        "Default": "По умолчанию",
        "Digital Vibrance": "Цифровая яркость цвета",
        "Dim inactive windows": "Затемнять неактивные окна",
        "Disconnect": "Отключить",
        "Disconnected": "Отключено",
        "Edit connections": "Изменить подключения",
        "Effect": "Эффект",
        "File manager": "Файловый менеджер",
        "Firm": "Упругий",
        "Frosted glass behind panels, menus and transparent windows": "Матовое стекло за панелями, меню и прозрачными окнами",
        "GTK theme & icons": "Тема GTK и значки",
        "Gaming": "Игры",
        "Gamma": "Гамма",
        "Gap around windows": "Отступ вокруг окон",
        "Gap between windows": "Отступ между окнами",
        "Highlight the current word": "Подсвечивать текущее слово",
        "Hot pink": "Ярко-розовый",
        "Ice": "Лёд",
        "In a row": "В ряд",
        "Inactive window opacity": "Прозрачность неактивных окон",
        "Jelly": "Желе",
        "Jelly style": "Стиль желе",
        "Jelly windows": "Желейные окна",
        "Keep": "Оставить",
        "Keep these display settings?": "Оставить эти настройки дисплея?",
        "Keyboard": "Клавиатура",
        "Large": "Большой",
        "Lavender": "Лаванда",
        "Layout": "Раскладка",
        "Layouts": "Раскладки",
        "Lock the screen after": "Блокировать экран через",
        "Make main": "Сделать главным",
        "Medium": "Средний",
        "Menus, widgets, dates and weather": "Меню, виджеты, даты и погода",
        "Mouse": "Мышь",
        "Mullvad is not running": "Mullvad не запущен",
        "Natural scrolling": "Естественная прокрутка",
        "Natural+": "Натуральный+",
        "Night": "Ночь",
        "Not set": "Не выбрано",
        "Notification panel": "Панель уведомлений",
        "Notifications stay silent and only collect in the panel": "Уведомления не всплывают и только копятся в панели",
        "Off = raw 1:1 movement (good for games)": "Выкл = движение 1:1 (лучше для игр)",
        "Open OpenRGB (per-device control)": "Открыть OpenRGB (по устройствам)",
        "Open app": "Открыть приложение",
        "Open file manager": "Открыть файлы",
        "Open the menu": "Открыть меню",
        "PDF viewer": "Просмотр PDF",
        "Photos": "Фото",
        "Pick a picture": "Выберите картинку",
        "Pointer acceleration": "Ускорение указателя",
        "Pointer speed": "Скорость указателя",
        "Pop + blur": "Всплытие + размытие",
        "Presets": "Пресеты",
        "Preview": "Предпросмотр",
        "Put your pictures into ~/Pictures/Wallpapers to see them here.": "Положите картинки в ~/Pictures/Wallpapers, и они появятся здесь.",
        "RGB on the motherboard and other OpenRGB devices. Changes take a few seconds to reach the hardware.": "RGB на материнской плате и других устройствах OpenRGB. Изменения доходят до железа за пару секунд.",
        "Rainbow": "Радуга",
        "Repeat delay": "Задержка повтора",
        "Repeat rate": "Скорость повтора",
        "Reset to defaults": "Сбросить по умолчанию",
        "Restore these lights every time you log in": "Включать эту подсветку при каждом входе",
        "Reverting in": "Откат через",
        "Sakura": "Сакура",
        "Scattered": "Вразброс",
        "Sets LANG for every app; no root needed": "Задаёт LANG всем приложениям, root не нужен",
        "Show all keybinds": "Все сочетания клавиш",
        "Show floating lyrics": "Показывать текст песен",
        "Sleep (suspend) after": "Сон через",
        "Slide up": "Выезд вверх",
        "Small": "Маленький",
        "Soft": "Мягкий",
        "Soft pink tint on the word being sung": "Розовый оттенок на звучащем слове",
        "Soft sounds for notifications, screenshots, clips, volume and login": "Тихие звуки для уведомлений, скриншотов, клипов, громкости и входа",
        "Static": "Статичный",
        "Switch layout with": "Переключение раскладки",
        "System sounds": "Системные звуки",
        "Terminal": "Терминал",
        "Text editor": "Текстовый редактор",
        "The main monitor holds the dock, the start menu, desktop widgets and workspaces 1-5.": "На главном мониторе док, меню Пуск, виджеты и рабочие столы 1-5.",
        "Time": "Время",
        "Timing offset": "Сдвиг по времени",
        "Top": "Сверху",
        "Turn off monitors after": "Выключать мониторы через",
        "Used for the weather": "Для погоды",
        "Video player": "Видеоплеер",
        "Vivid": "Сочный",
        "Warm": "Тёплый",
        "Wave": "Волна",
        "Web browser": "Браузер",
        "What happens when you leave the PC alone. Never = it stays on.": "Что происходит, когда ПК простаивает. Никогда = остаётся включённым.",
        "What the Win key menu shows. The preview updates as you change things.": "Что показывает меню по клавише Win. Превью меняется сразу.",
        "Which app opens links and files of each kind.": "Какое приложение открывает ссылки и файлы каждого типа.",
        "While music plays, the words of the current line pop up one by one in liquid-glass pills. Hidden in fullscreen games and when nothing is playing.": "Пока играет музыка, слова текущей строки всплывают по одному в стеклянных плашках. Скрыто в полноэкранных играх и когда ничего не играет.",
        "White": "Белый",
        "Window, menu and workspace animations": "Анимации окон, меню и рабочих столов",
        "Windows wobble like jelly while you drag them": "Окна покачиваются как желе при перетаскивании",
        "asking for your password…": "запрос пароля…",
        "free of": "свободно из",
        "used": "занято",
        "Edit tray": "Значки трея",
        "Kernel": "Ядро",
        "OS": "ОС",
        "Memory": "Память",
        "Uptime": "Время работы",
        "Packages": "Пакеты",
        "Choose a picture": "Выберите картинку",
        "Images": "Картинки",
        "Could not save": "Не удалось сохранить",
        "Copied - paste it anywhere": "Скопировано - вставляйте куда угодно",
        "Saved to": "Сохранено в",
        "Select / move (V)": "Выделить / двигать (V)",
        "Brush (B)": "Кисть (B)",
        "Eraser (E)": "Ластик (E)",
        "Line (L)": "Линия (L)",
        "Arrow (A)": "Стрелка (A)",
        "Rectangle (R)": "Прямоугольник (R)",
        "Ellipse (O)": "Эллипс (O)",
        "Text (T)": "Текст (T)",
        "Import picture (Ctrl+O, or Ctrl+V / drop a file)": "Вставить картинку (Ctrl+O, Ctrl+V или перетащить файл)",
        "Undo (Ctrl+Z)": "Отменить (Ctrl+Z)",
        "Redo (Ctrl+Shift+Z)": "Повторить (Ctrl+Shift+Z)",
        "Clear (undo brings it back)": "Очистить (Ctrl+Z вернёт)",
        "Copy": "Копировать",
        "Save": "Сохранить",
        "B brush · E eraser · L line · A arrow · R rect · O ellipse · T text · V move · [ ] size · Shift = straight · Ctrl+V paste picture": "B кисть · E ластик · L линия · A стрелка · R прямоуг. · O эллипс · T текст · V двигать · [ ] размер · Shift = ровно · Ctrl+V вставить картинку",
        "Move the view (H, Space or middle mouse)": "Двигать вид (H, пробел или средняя кнопка)",
        "Eraser (E) - pictures stay": "Ластик (E) - картинки не стираются",
        "Eyedropper (I)": "Пипетка (I)",
        "Pick a color anywhere on the screen": "Взять цвет с любого места экрана",
        "Fit": "Вписать",
        "Page size": "Размер холста",
        "Fit the page to the picture": "Холст по размеру картинки",
        "Or drag the corner of the page.": "Или тяните за уголок холста.",
        "No picture on the page": "На холсте нет картинки",
        "Sketch pad": "Рисовалка",
        "Notes": "Заметки",
        // edge drum (EdgeTab / Ambient / Pocket)
        "Ambient sounds": "Фоновые звуки", "Pocket": "Карман", "Campfire": "Костёр", "Cafe": "Кафе", "Forest": "Лес",
        "Waves": "Волны", "Noise": "Шум", "white": "белый", "pink": "розовый", "brown": "коричневый", "Stop all": "Выключить всё",
        "Scroll = volume · click = on/off": "Колесо - громкость · клик - вкл/выкл",
        "Type a note · Ctrl+V a picture": "Пиши текст · Ctrl+V - картинка",
        "Enter = keep · click = copy · kept 24 h": "Enter - в карман · клик - копировать · живёт сутки",
        "Link": "Ссылка", "File": "Файл", "just now": "только что",
        "Empty note": "Пустая заметка",
        "Search notes": "Поиск по заметкам",
        "Nothing found": "Ничего не найдено",
        "Note deleted": "Заметка удалена",
        "Copied": "Скопировано",
        "Pin": "Закрепить",
        "Delete": "Удалить",
        "Write something… the first line becomes the title": "Пишите… первая строка станет заголовком",
        "Timers": "Таймеры",
        "Lyrics": "Текст песни", "No lyrics found": "Текст не найден", "Only unsynced lyrics found": "Есть только текст без синхронизации", "Loading lyrics…": "Ищу текст…", "Unknown": "Без названия", "Player": "Плеер",
        "Timer": "Таймер",
        "running": "идёт",
        "paused": "пауза",
        "m": "м",
        "Pause": "Пауза",
        "Start": "Старт",
        "Pomodoro": "Помодоро",
        "Alarm sound": "Звук будильника", "Timers and alarms. Pomodoro phases use a shorter soft chime.": "Таймеры и будильники. Для фаз помодоро - короткий мягкий сигнал.",
        "Bubbles": "Пузырьки", "Deep bubbles": "Глубокие пузырьки", "Bubbling": "Бульканье",
        "Notification sound": "Звук уведомлений", "Bup-bip": "Буп-бип", "Bubble": "Пузырёк", "Deep bubble": "Глубокий пузырёк",
        "Plays when a notification arrives. Volume and mute: Notifications > Sounds.": "Звучит при новом уведомлении. Громкость и отключение - Уведомления → Звуки.",
        "Focus": "Фокус",
        "Short break": "Короткий перерыв",
        "Long break": "Длинный перерыв",
        "Break": "Перерыв",
        "Long": "Длинный",
        "Alarms": "Будильники",
        "Add alarm": "Добавить будильник",
        "Scroll or click the hours / minutes to change them (right click = back).": "Крутите колесо или кликайте по часам/минутам (ПКМ - назад).",
        "Timer is up": "Таймер истёк",
        "Time for a break": "Время перерыва",
        "Back to focus": "Снова за работу",
        "Round": "Раунд",
        "done": "готов",
        "Alarm": "Будильник",
        "Accent color": "Цвет акцента",
        "Menus, bar, dock, window borders, terminal, lock screen": "Меню, панель, док, рамки окон, терминал, экран блокировки",
        "From the wallpaper": "Из обоев",
        "Pick a matching color from your current wallpaper": "Подобрать цвет под текущие обои",
        "Pick now": "Подобрать",
        "Follow wallpaper": "Следовать за обоями",
        "Stopwatch": "Секундомер",
        "Lap": "Круг",
        "Backup": "Резервная копия",
        "Back up the rice": "Бэкап райса",
        "All configs and your own apps (new ones are found automatically), login theme, icons, sounds and wallpapers in one archive with an installer - to restore after a reinstall or to give to a friend": "Все конфиги и твои приложения (новые находятся сами), тема входа, иконки, звуки и обои в одном архиве с установщиком - восстановиться после переустановки или отдать другу",
        "Packing…": "Упаковываю…",
        "Make backup": "Сделать бэкап",
        "Include my notes, drawings and location": "Включить мои заметки, рисунки и город",
        "Off = safe to share": "Выкл - можно смело отдавать другим",
        "No backups yet": "Бэкапов пока нет",
        "the 5 newest are kept": "хранятся 5 последних",
        "Open folder": "Открыть папку",
        "Laps show up here": "Здесь появятся круги",
        "No alarms set": "Будильников нет",
        "in": "через",
        "All": "Все", "Pictures": "Картинки", "Videos": "Видео", "Random": "Случайные",
        "Nothing here yet": "Здесь пока пусто",
        "Change wallpaper": "Сменить обои", "Random wallpaper": "Случайные обои",
        "Color from wallpaper": "Цвет из обоев", "Reload shell": "Перезапустить оболочку",
        "Open picker": "Открыть выбор",
        "Pause the video": "Пауза видео", "It holds the frame; covered = windows fill the screen": "Кадр замирает; «закрыт» - окна заполняют экран", "When covered": "Когда закрыт окнами", "Only fullscreen": "Только во весь экран",
        "Change avatar": "Сменить аватарку", "Undo": "Вернуть прежнюю",
        "Video on the desktop": "Видео на рабочем столе", "Fitted to your screen looks the same but is much lighter; Original plays the file as it is (e.g. 4K)": "«Под экран» выглядит так же, но намного легче; «Оригинал» играет файл как есть (например, 4K)", "Fitted to the screen": "Под экран", "Original file": "Оригинал",
        "Video smoothness": "Плавность видео", "Plays a light copy made for your screen; fewer frames = lighter on the PC": "Играет облегчённая копия под твой экран; меньше кадров - меньше нагрузка", "Play the video on": "Видео на", "All monitors": "Всех мониторах", "Main monitor only": "Только главном мониторе",
        "How often": "Как часто", "Rarely": "Редко", "Sometimes": "Иногда", "Often": "Часто", "Edge": "Край", "Right": "Справа", "Left": "Слева", "Height on the screen": "Высота на экране", "Reacts to": "Реагирует на", "Music": "Музыку",
        "Date style": "Формат даты", "Update every": "Обновлять каждые", "Cities for the World clock widget. Time zone like Europe/Paris or America/Los_Angeles.": "Города для виджета «Мировое время». Часовой пояс вида Europe/Paris или America/Los_Angeles.", "Name (optional)": "Название (необязательно)", "Add": "Добавить", "Long break after": "Длинный перерыв через", "rounds": "раундов", "Not running": "Не запущен", "Shows in the Timer widget and the dashboard. Each phase starts the next one by itself.": "Видно в виджете «Таймер» и в дашборде. Каждая фаза сама запускает следующую.", "Stop": "Стоп", "Nice song!": "Классная песня!", "You've got a message": "Тебе пришло сообщение",
        "Screenshots & recording": "Скриншоты и запись", "File name": "Имя файла", "Freeze the screen while selecting": "Замораживать экран при выделении", "Videos and games stop moving under the selection": "Видео и игры не двигаются, пока выделяешь", "Copy to the clipboard": "Копировать в буфер", "Notification": "Уведомление", "Draw on it right away": "Сразу рисовать поверх", "Open the editor (satty) after selecting an area": "Открывать редактор (satty) после выделения", "Take one": "Сделать", "Recording & instant replay": "Запись и повтор", "The same settings as the Alt+Z overlay. Replay restarts with the new settings.": "Те же настройки, что в оверлее Alt+Z. Повтор перезапускается с новыми настройками.", "Quality": "Качество", "High": "Высокое", "Very high": "Очень высокое", "Ultra": "Ультра", "System + mic": "Система + микрофон", "Replay length": "Длина повтора", "Replay on at login": "Повтор при входе", "Open Capture (Alt+Z)": "Открыть Capture (Alt+Z)", "entries in the history": "записей в истории", "Pictures too": "И картинки", "Skip passwords": "Пропускать пароли", "Copies from password managers don't go into the history": "Копии из менеджеров паролей не попадают в историю", "Start each session empty": "Очищать при каждом входе", "Open (Super+V)": "Открыть (Super+V)", "Clear history": "Очистить историю",
        "Volume keys": "Клавиши громкости", "Step": "Шаг", "How much one press or one wheel notch changes": "Насколько меняет одно нажатие или щелчок колеса", "Ear protection": "Защита ушей", "Keys, bar and wheel never go above": "Клавиши, бар и колесо не поднимут выше", "Per-app volume": "Громкость приложений", "Open mixer": "Открыть микшер", "Auto sensitivity": "Автоматическая чувствительность", "Keeps the bars in range on quiet and loud songs": "Держит полосы в пределах и на тихих, и на громких песнях", "Sensitivity": "Чувствительность", "Smoothness": "Плавность", "Soft peaks": "Мягкие пики", "Neighbouring bars lean on each other (monstercat)": "Соседние полосы сглаживают друг друга (monstercat)", "Frames per second": "Кадров в секунду", "Colors": "Цвета", "Accent": "Акцент",
        "Search": "Поиск", "Web search with": "Искать в интернете через", "Apps in the results": "Приложений в результатах", "Files": "Файлы", "Look through your home folder and /mnt": "Искать в домашней папке и /mnt", "Commands": "Команды", "lock, restart, settings, screenshot…": "блокировка, перезагрузка, настройки, скриншот…", "Web search at the end": "Поиск в интернете в конце списка", "Prefixes": "Префиксы", "> run a command · ? search the web · / files only · = calculator": "> выполнить команду · ? поиск в интернете · / только файлы · = калькулятор", "Run commands in the terminal": "Запускать команды в терминале", "For > : see the output in kitty": "Для >: вывод видно в kitty", "Type a command to run": "Введите команду", "Run in the terminal": "Запустить в терминале", "Run": "Запустить",
        "Window switcher": "Переключатель окон", "Look": "Вид", "Previews": "Превью", "Icons only": "Только иконки", "Only this monitor": "Только этот монитор", "Windows of the monitor you are on": "Окна монитора, на котором ты сейчас", "Minimized windows too": "И свёрнутые окна", "Window titles": "Заголовки окон", "Hot corners": "Горячие углы", "Push the mouse into a corner and hold it there for a moment. Off while a game is fullscreen.": "Задвинь мышь в угол и задержи на мгновение. Не работают, пока игра на весь экран.", "Dashboard": "Дашборд", "Bottom left": "Слева снизу", "Hold for": "Задержка",
        "Mouse wheel on the bar": "Колесо мыши на баре", "Workspaces": "Рабочие столы", "Nothing": "Ничего", "Dock": "Док", "Icon size": "Размер иконок", "Grow under the mouse": "Увеличение под мышкой", "Hide automatically": "Скрывать автоматически", "Slides into the bottom edge; comes back under the mouse": "Уезжает в нижний край и выезжает под мышкой", "Running apps marker": "Метка запущенных", "Dots": "Точки", "Notification badges": "Значки уведомлений", "Number of unread notifications on the app icon": "Число непрочитанных уведомлений на иконке", "Accent color in other apps": "Акцент в других приложениях", "Where the accent color is copied to. Off = that app keeps its own colors.": "Куда копируется акцентный цвет. Выкл - приложение остаётся со своими цветами.", "Terminal (kitty)": "Терминал (kitty)", "Launcher (rofi)": "Лаунчер (rofi)", "Change by itself": "Менять сами", "A random wallpaper from the folder every so often": "Случайные обои из папки через интервал", "15 min": "15 мин", "30 min": "30 мин", "1 h": "1 ч", "3 h": "3 ч",
        "Lock screen look": "Вид экрана блокировки", "Wallpaper blur": "Размытие обоев", "Darken": "Затемнение", "Thin": "Тонкие", "Seconds": "Секунды", "What is playing": "Что играет", "Night light on a schedule": "Ночной свет по расписанию", "Warmer screen in the evening, back to normal in the morning": "Вечером экран теплее, утром снова обычный", "Warmth": "Теплота",
        "Popups": "Всплывающие", "Show for": "Показывать", "s": "с", "Ignore the app's own time": "Игнорировать время приложения", "Some apps ask to stay for minutes - use the time above for all": "Некоторые приложения просят висеть минутами - для всех будет время выше", "Urgent ones stay": "Срочные не исчезают", "Critical notifications wait until you close them": "Критические уведомления висят, пока не закроешь", "Top right": "Справа сверху", "Top left": "Слева сверху", "Bottom right": "Справа снизу", "Center": "По центру", "Test": "Проверка", "Send a test notification": "Отправить тестовое", "This is how notifications look": "Так выглядят уведомления", "Quiet hours": "Тихие часы", "Quiet right now": "Сейчас тихо", "No popups or sounds at night": "Ночью без всплывашек и звуков", "From": "С", "To": "До", "Muted apps": "Заглушённые приложения", "Their notifications don't pop up or play a sound, but still land in the panel. Apps appear here after they send something.": "Их уведомления не всплывают и не звучат, но попадают в панель. Приложение появится здесь, когда что-нибудь пришлёт.", "Sounds": "Звуки", "Volume of system sounds": "Громкость системных звуков", "Screenshots": "Скриншоты", "Volume change": "Смена громкости", "Saved clip": "Сохранён клип", "Login": "Вход", "Errors": "Ошибки", "Volume & brightness popup": "Окно громкости и яркости",
        "Mascot": "Маскот", "Peeks out from the right edge now and then. Your own: ~/.config/sakura/mascot.png": "Иногда выглядывает из-за правого края. Свой: ~/.config/sakura/mascot.png", "Hello after login": "Приветствие при входе", "Animations at login": "Анимации при входе", "The bar, dock and widgets flow in one after another": "Бар, док и виджеты появляются друг за другом", "Greeting with the time and weather when you sign in": "Приветствие со временем и погодой после входа", "Show": "Показать", "Hi!": "Привет!", "Drink some water": "Попей водички", "Take a short break?": "Может, перерыв?", "Looking good today": "Отлично выглядишь сегодня", "Don't forget to stretch": "Не забудь размяться", "What are we listening to?": "Что слушаем?", "Nice wallpaper": "Классные обои",
        "Device battery": "Батарея устройств", "Headset": "Наушники", "Gamepad": "Геймпад", "charging": "заряжается", "asleep": "спит", "connected": "подключено", "disconnected": "отключено",
        "Screen time": "Экранное время", "Nothing counted yet": "Пока ничего не посчитано",
        "Sound off": "Выключенный звук", "Login and unlock": "Вход и разблокировку", "Long work": "Долгую работу", "Late night": "Позднюю ночь", "After games": "Конец игры", "Break reminder after": "Напомнить о перерыве через", "45 min": "45 мин", "1.5 h": "1,5 ч", "2 h": "2 ч", "Can be caught and thrown": "Можно ловить и кидать", "Hold her and drag, let go with a flick": "Зажми и тащи, отпусти с размаху - полетит", "Hey! Let go!": "Эй! Пусти!", "Where are you taking me?": "Куда тащишь?", "Aaaaa!": "Ааааа!", "Whoosh!": "Вжух!", "Ouch!": "Ай!", "That hurts…": "Больно же…", "My head is spinning…": "Голова кружится…", "Again!": "Ещё раз!", "That's it, I'm offended": "Всё, я обиделась", "No more throwing!": "Хватит меня кидать!", "Overheating": "Перегрев", "Full disk": "Полный диск", "She also": "А ещё она", "Dances to music": "Танцует под музыку", "Dresses for the weather": "Одевается по погоде", "Sits on windows": "Сидит на окнах", "Leaves notes": "Оставляет записки", "Brings a friend": "Приводит подружку", "It's getting hot in here!": "Что-то жарковато!", "Your computer is melting…": "Компьютер сейчас расплавится…", "Your disk is almost full!": "Диск почти забит!", "Where do I put all this?": "Куда мне всё это девать?", "Updates are waiting - maybe update?": "Ждут обновления - может, обновишься?", "%1 updates are waiting - maybe update?": "Обновлений ждёт: %1 - может, обновишься?", "I left you a note on the desktop": "Я оставила тебе записку на рабочем столе", "Nice view from up here": "Отсюда отличный вид", "Mind if I sit here?": "Можно я тут посижу?", "Comfy!": "Удобненько!", "Whoa!": "Ой-ой!", "Hey, I was sitting there!": "Эй, я же тут сидела!", "Bye!": "Пока!", "You're doing great today": "Ты сегодня молодец", "Rest your eyes for a minute": "Дай глазам отдохнуть минутку", "Proud of you": "Горжусь тобой", "Today is a good day": "Сегодня хороший день", "Have you eaten?": "Ты сегодня ел?", "Stretch your back": "Разомни спину", "I believe in you": "Я в тебя верю", "Did you see that window?": "Видела это окно?", "Shh, they're watching!": "Тсс, на нас смотрят!", "Race you!": "Наперегонки!", "No fair, you started first!": "Нечестно, ты раньше начала!", "Is it lunch yet?": "Уже обед?", "It's always lunch somewhere": "Где-то всегда обед", "Look, a cursor!": "Смотри, курсор!", "Don't make eye contact": "Не смотри ему в глаза", "Nice desktop, huh?": "Классный рабочий стол, да?", "Could use more petals": "Лепестков маловато", "Wheee~": "Уиии~", "Gently does it": "Потихонечку", "Mary Poppins mode": "Режим Мэри Поппинс", "Soft landing!": "Мягкая посадка!", "Ta-da!": "Та-да!", "Deal with it": "Смирись", "Who's rich? I'm rich": "Кто богатая? Я богатая", "Money talks": "Деньги решают", "Make it rain!": "Денежный дождь!", "Pew pew": "Пиу-пиу", "Catch!": "Лови!", "Ten, twenty, thirty… a lot": "Десять, двадцать, тридцать… много", "Petals? No - cash": "Лепестки? Не, кэш", "Don't touch, it's limited edition": "Руками не трогать, лимитка", "Okay, enough showing off": "Ладно, хватит выпендриваться", "Thank you, thank you": "Спасибо, спасибо", "Autographs later": "Автографы потом", "No photos!": "Без фото!", "Wait for it…": "Щас будет…", "Fiu-fiu!": "Фьють-фьють!", "Ladies…": "Дамы…", "Hiii~": "Приве-ет~", "We're out": "Мы погнали", "Chaos mode": "Режим хаоса", "Now and then she runs along the bottom edge and peeks from any edge or corner": "Иногда пробегает по нижнему краю и выглядывает из любых краёв и углов", "Run now": "Пробежать", "Boo!": "Бу!", "Peekaboo!": "Ку-ку!", "It's late… time for bed?": "Уже поздно… может, спать?", "Yawn… still up?": "Ааах… ещё не спишь?", "Hehe, that tickles": "Хи-хи, щекотно", "Okay, pats are allowed": "Ладно, гладить можно", "…again?": "…опять?", "Hey! Enough poking!": "Эй! Хватит тыкать!", "I'm off!": "Всё, я ушла!", "…What?": "…Что?", "Staring is rude": "Пялиться невежливо", "Hehe, hi": "Хи-хи, привет", "Catch me!": "Догони!", "Can't stop, busy!": "Некогда, бегу!", "Wheee!": "Уиии!", "Just passing by": "Я тут мимо пробегала", "♪ La-la-la…": "♪ Ла-ла-ла…", "This one's a bop": "Вот это трек!", "Ooh, pretty!": "Ой, красиво!", "Say cheese!": "Улыбочку!", "Did you get my good side?": "Я хорошо получилась?", "Shh… the sound is off": "Тсс… звук выключен", "Time's up!": "Время вышло!", "Back to focus - you've got this": "Снова за дело - у тебя получится", "Break time! Stretch a little": "Перерыв! Потянись немного", "Welcome back!": "С возвращением!", "Missed you!": "Я скучала!", "Hello again!": "И снова привет!", "You've been at it a while - time for a little break?": "Ты давно за компьютером - может, перерыв?", "Stretch time!": "Пора размяться!", "Your eyes need a rest too": "Глазам тоже нужен отдых", "GG!": "GG!", "Good game?": "Хорошо поиграли?", "Sakura was here": "Здесь была Сакура", "Nothing happened. Don't check your widgets.": "Ничего не случилось. Виджеты не проверяй.",
        "Wrong password": "Неверный пароль", "Can't check the password": "Не удалось проверить пароль", "Checking…": "Проверка…", "Password": "Пароль", "notifications": "уведомлений", "Lock screen": "Экран блокировки", "Try it": "Попробовать",
        "All caught up": "Новых уведомлений нет", "now": "сейчас", "Wi-Fi": "Wi‑Fi",
        "Search the clipboard": "Поиск в буфере", "Text": "Текст",
        "Shell": "Оболочка", "Glass opacity": "Плотность стекла", "Panels, bar, dock and menus": "Панели, бар, дока и меню", "Blur strength": "Сила размытия", "Font": "Шрифт", "Fast": "Быстро", "Normal": "Обычно", "Slow": "Медленно", "Open windows": "Открытые окна", "Now playing": "Сейчас играет", "Recording": "Запись", "Keyboard layout": "Раскладка", "Network": "Сеть", "Updates": "Обновления", "Power": "Питание", "Left wing": "Левое крыло", "Right wing": "Правое крыло", "Click to show or hide. The numbers are the order.": "Клик показывает или прячет. Цифры - порядок.", "Wings": "Крылья", "On hover": "При наведении", "Always": "Всегда", "Folder": "Папка", "Transition": "Переход", "Transition length": "Длина перехода", "Fill": "Заполнение", "Crop": "Обрезать", "Video wallpapers": "Видео-обои", "Play videos; off = a still frame": "Проигрывать видео; выкл - стоп-кадр", "Pause in fullscreen": "Пауза в полноэкранном режиме", "Games and films get the GPU": "Игры и фильмы получают видеокарту", "Fade": "Растворение", "Grow": "Круг", "Wipe": "Шторка", "Outer": "Сжатие", "None": "Нет", "Reset look": "Сбросить вид", "Where the picker and the random wallpaper look first": "Откуда берутся обои для выбора и случайных",
        "Edit on the desktop": "Редактировать на рабочем столе", "Drag, resize and restyle widgets right where they live": "Двигайте, меняйте размер и вид виджетов прямо на столе", "Open editor": "Открыть редактор", "Big": "Большие", "Stacked": "В две строки", "Minimal": "Минимальные", "Classic": "Классика", "Full": "Месяц", "Compact": "Неделя", "Bars": "Полоски", "Mirror": "Зеркало", "Line": "Линия", "Rings": "Кольца",
        "Visualizer": "Визуализатор", "World clock": "Мировое время", "Day progress": "Прогресс дня", "Sticky note": "Заметка", "To-do list": "Список дел", "Hardware": "Железо", "User card": "Карточка пользователя", "Edit widgets": "Редактировать виджеты", "Grid": "Сетка", "Add widget": "Добавить виджет", "Style": "Стиль", "Hide": "Скрыть", "Day": "День", "Week": "Неделя", "Month": "Месяц", "Year": "Год", "Add a task": "Новая задача", "Nothing to do": "Дел нет", "Write something…": "Напишите что-нибудь…", "All widgets are on the desktop": "Все виджеты уже на столе", "People": "Люди", "General": "Общее", "Hot": "Популярное", "Video": "Видео", "Photo": "Фото",
        "Library": "Библиотека", "Live": "Живые", "Live wallpapers": "Живые обои", "Wallpapers": "Обои", "Downloads": "Загрузки", "Home": "Домой", "Latest": "Новые", "Anime": "Аниме", "Search Wallhaven": "Поиск на Wallhaven", "Search, or type a path": "Поиск или путь к папке", "In use": "Сейчас", "Picture": "Картинка", "Loading…": "Загрузка…", "Downloading…": "Скачивание…", "Download & apply": "Скачать и применить"
    })
}
