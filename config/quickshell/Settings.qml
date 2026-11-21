// sakura mono - settings window (Windows-style: groups on the left, search, live previews)
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

Scope {
    id: st

    // palette (same as the menu)
    readonly property color cBg:     Cfg.glass
    readonly property color cSide:   "#26000000"
    readonly property color cCard:   "#14ffffff"
    readonly property color cHover:  "#29ffffff"
    readonly property color cBorder: "#1fffffff"
    readonly property color cFg:     "#eceef4"
    readonly property color cMuted:  "#8a8fa3"
    readonly property color cAccent: Cfg.accent
    readonly property color cAccFg:  Cfg.accFg
    readonly property string fUi:    Cfg.fontUi
    readonly property string fIcon:  "Symbols Nerd Font"
    readonly property string home:   Quickshell.env("HOME")
    readonly property string scripts: home + "/.config/hypr/scripts"
    function t(s) { return Cfg.tr(s); }

    property bool shown: false
    property string page: "sound"
    property string query: ""
    function openPage(p) { page = p; shown = true; refreshAll(); }
    function toggle()    { shown = !shown; if (shown) refreshAll(); }

    IpcHandler {
        target: "settings"
        function open(p: string): void { st.openPage(p === "" ? "sound" : p); }
        function toggle(): void { st.toggle(); }
    }

    // ── pages ───────────────────────────────────────────────────
    readonly property var groups: [
        { g: "System", pages: [
            { id: "sound",   icon: "", label: "Sound",        k: "audio volume mic звук громкость микрофон" },
            { id: "display", icon: "", label: "Displays",     k: "monitor screen resolution hz scale монитор экран разрешение частота" },
            { id: "notify",  icon: "", label: "Notifications", k: "dnd silent sounds уведомления звуки" },
            { id: "power",   icon: "", label: "Power & Sleep", k: "sleep lock screen off сон блокировка питание" },
            { id: "capture", icon: "\uf030", label: "Screenshots & recording", k: "screenshot record clip clipboard скриншот запись буфер" },
            { id: "storage", icon: "", label: "Storage",      k: "disk space диск память место" },
            { id: "about",   icon: "", label: "About",        k: "system info версия система" } ] },
        { g: "Personalization", pages: [
            { id: "wallpaper",  icon: "", label: "Wallpaper",     k: "background обои фон" },
            { id: "appearance", icon: "", label: "Appearance",    k: "blur gaps rounding animation размытие отступы анимации" },
            { id: "color",      icon: "", label: "Color Control", k: "vibrance contrast gamma night цвет контраст" },
            { id: "widgets",    icon: "", label: "Desktop widgets", k: "clock weather виджеты часы погода" },
            { id: "menu",       icon: "", label: "Start menu",    k: "start win пуск меню" },
            { id: "taskbar",    icon: "", label: "Taskbar",       k: "bar waybar tray clock corner island панель трей часы угол островок" },
            { id: "lighting",   icon: "", label: "Lighting",      k: "rgb openrgb подсветка", needs: "openrgb" },
            { id: "lyrics",     icon: "", label: "Floating Lyrics", k: "lyrics music текст песни" } ] },
        { g: "Time & Language", pages: [
            { id: "time", icon: "", label: "Time & Language", k: "language timezone location city date clock язык пояс город дата время" } ] },
        { g: "Devices", pages: [
            { id: "input",   icon: "", label: "Keyboard & Mouse", k: "layout keyboard mouse speed раскладка клавиатура мышь" },
            { id: "network", icon: "", label: "Network & VPN",    k: "wifi ethernet vpn сеть" } ] },
        { g: "Apps", pages: [
            { id: "apps", icon: "", label: "Default apps", k: "browser default open with браузер по умолчанию" },
            { id: "music", icon: "\uf001", label: "Music", k: "sakura sound soundcloud player music cookies музыка плеер саундклауд" },
            { id: "passwords", icon: "\uf084", label: "Password helper", k: "password vault keyring generator clipboard history hotkey пароль пароли хранилище генератор буфер история" } ] }
    ]
    function pageVisible(p) {
        if (p.needs && !Cfg.has[p.needs]) return false;
        const q = query.trim().toLowerCase();
        if (q === "") return true;
        return (p.label + " " + st.t(p.label) + " " + p.k + " " + (st.extraKeys[p.id] || "")).toLowerCase().includes(q);
    }
    // what is inside each page, so the search finds a page by any of its options (English + Russian)
    readonly property var extraKeys: ({
        sound: "volume keys step ear protection mixer per-app шаг громкости защита ушей микшер",
        notify: "popups position quiet hours muted apps sounds osd test всплывашки положение тихие часы заглушить звуки окно громкости",
        power: "lock screen sakura hyprlock blur darken clock night light schedule warmth блокировка размытие затемнение часы ночной свет расписание",
        capture: "screenshot folder file name freeze copy satty recording replay fps quality audio clipboard history passwords скриншот папка запись повтор качество буфер история пароли",
        storage: "disk drive space диск место", about: "version system версия",
        wallpaper: "picker video folder transition fill shuffle timer обои видео папка переход заполнение смена таймер",
        appearance: "glass opacity blur font animation speed accent mascot chaos greeting login анимации входа gaps rounding border стекло прозрачность шрифт анимации акцент маскот приветствие отступы скругление",
        color: "vibrance contrast warmth gamma night насыщенность контраст теплота",
        widgets: "editor grid style visualizer cava bars sensitivity редактор сетка стиль визуализатор полосы",
        menu: "search engine prefixes files commands web поиск поисковик префиксы файлы команды",
        taskbar: "bar wings modules wheel dock icons autohide badges switcher alt tab hot corners бар крылья модули колесо док иконки автоскрытие значки переключатель углы",
        time: "date format weather world clock pomodoro timezone alarm sound notification sound дата формат погода мировое время помодоро звук будильника звук уведомлений",
        input: "keyboard layout mouse speed клавиатура раскладка мышь", network: "wifi vpn mullvad сеть",
        passwords: "shortcut ctrl shift p length symbols look-alikes strength auto-clear ignored lock auto-lock delete glass blur ring сочетание длина символы сила автоочистка блокировка удалить стекло кольцо"
    })

    // ── user settings (persisted, applied through hyprland.lua) ────────
    property var cfg: ({
        blur: true, animations: true, dim: true, wobble: true, jelly: "jelly",
        gaps_in: 6, gaps_out: 14, rounding: 14, border: 2,
        inactive_opacity: 1.0, sensitivity: 0.0, kb_toggle: "grp:alt_shift_toggle",
        kb_layout: "us,ru", repeat_rate: 25, repeat_delay: 600, natural_scroll: false, accel: "adaptive",
        screenOff: 0, lockAfter: 0, suspendAfter: 0, sounds: true,
        vibrance: 0.35, contrast: 0.06, warmth: 0.0, brightness: 0.0, gamma: 1.0, shaderSlot: "a"
    })
    FileView {
        id: cfgFile
        path: st.home + "/.config/hypr/user-settings.json"
        blockLoading: true
        onLoaded: {
            try { const j = JSON.parse(text()); st.cfg = Object.assign({}, st.cfg, j); } catch (e) {}
        }
    }
    // ── power & sleep: writes ~/.config/hypr/hypridle.conf and restarts hypridle (0 = never)
    Process { id: idleProc }
    function setPower(key, val) {
        const c = Object.assign({}, cfg); c[key] = val; cfg = c;
        cfgFile.setText(JSON.stringify(c, null, 2));
        let conf = "# generated by Settings > Power & Sleep\n" +
            "general {\n    lock_cmd = ~/.config/hypr/scripts/lock.sh\n    before_sleep_cmd = loginctl lock-session\n" +
            "    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({action = \"on\"})'\n}\n";
        if (c.lockAfter > 0)    conf += "listener {\n    timeout = " + c.lockAfter * 60 + "\n    on-timeout = loginctl lock-session\n}\n";
        if (c.screenOff > 0)    conf += "listener {\n    timeout = " + c.screenOff * 60 + "\n    on-timeout = hyprctl dispatch 'hl.dsp.dpms({action = \"off\"})'\n    on-resume = hyprctl dispatch 'hl.dsp.dpms({action = \"on\"})'\n}\n";
        if (c.suspendAfter > 0) conf += "listener {\n    timeout = " + c.suspendAfter * 60 + "\n    on-timeout = systemctl suspend\n}\n";
        idleProc.command = ["sh", "-c", "cat > \"$HOME/.config/hypr/hypridle.conf\" <<'EOF'\n" + conf + "EOF\npkill -x hypridle; sleep 0.3; setsid hypridle >/dev/null 2>&1 &"];
        idleProc.running = true;
    }
    function setSounds(on) {
        const c = Object.assign({}, cfg); c.sounds = on; cfg = c;
        cfgFile.setText(JSON.stringify(c, null, 2));
        Quickshell.execDetached(["sh", "-c", on ? "rm -f $HOME/.config/sakura/sounds-off; $HOME/.config/hypr/scripts/sfx.sh notify"
                                                : "mkdir -p $HOME/.config/sakura && touch $HOME/.config/sakura/sounds-off"]);
    }
    // ── lighting (OpenRGB) ──────────────────────────────────
    property var rgb: ({ enabled: true, color: "f2b8d0", mode: "static", brightness: 100, atLogin: true })
    FileView {
        id: rgbFile
        path: st.home + "/.config/sakura/rgb.json"
        blockLoading: true
        onLoaded: { try { st.rgb = Object.assign({}, st.rgb, JSON.parse(text())); } catch (e) {} }
    }
    Timer { id: rgbTimer; interval: 350; onTriggered: { rgbFile.setText(JSON.stringify(st.rgb, null, 2)); Quickshell.execDetached([st.home + "/.config/hypr/scripts/rgb.sh", "apply"]); } }
    function setRgb(k, v) { const r = Object.assign({}, rgb); r[k] = v; rgb = r; rgbTimer.restart(); }
    function hueHex(h) { const c = Qt.hsva(h, 0.55, 1, 1); const x = n => ("0" + Math.round(n * 255).toString(16)).slice(-2); return x(c.r) + x(c.g) + x(c.b); }
    function jellyLua(j) {
        const p = j === "soft"  ? { s: 260, d: 12, m: 0.8,  i: 0.55 }
                : j === "firm"  ? { s: 650, d: 20, m: 0.55, i: 0.30 }
                :                 { s: 420, d: 15, m: 0.65, i: 0.45 };
        return ", mesh = 24, stiffness = " + p.s + ", damping = " + p.d + ", mass = " + p.m + ", intensity = " + p.i;
    }
    // ── floating lyrics (~/.config/sakura/lyrics.json, read live by LyricsOverlay) ──
    property var lyr: ({ enabled: true, style: "pop", size: "m", position: "top", speed: 1.0, highlight: true, offset: 0.0, layout: "scatter" })
    FileView {
        id: lyrFile
        path: st.home + "/.config/sakura/lyrics.json"
        blockLoading: true
        onLoaded: { try { st.lyr = Object.assign({}, st.lyr, JSON.parse(text())); } catch (e) {} }
    }
    Timer { id: lyrTimer; interval: 250; onTriggered: lyrFile.setText(JSON.stringify(st.lyr, null, 2)) }
    function setLyr(k, v) { const l = Object.assign({}, lyr); l[k] = v; lyr = l; lyrTimer.restart(); }
    function setCfg(key, val) {
        const c = Object.assign({}, cfg); c[key] = val; cfg = c;
        saveTimer.restart();
    }
    function preset(v, c, b, g, w) {
        const n = Object.assign({}, cfg); n.vibrance = v; n.contrast = c; n.brightness = b; n.gamma = g; n.warmth = w;
        cfg = n; saveTimer.restart();
    }
    Timer { id: saveTimer; interval: 350; onTriggered: st.applyCfg() }
    // night light on a schedule (Settings > Power & Sleep): switches only when the period changes, so a manual change sticks
    property int nightWas: -1
    function nightCheck() {
        if (Cfg.data.nightAuto !== true) { nightWas = -1; return; }
        const m = s => { const p = String(s).split(":"); return parseInt(p[0]) * 60 + parseInt(p[1] || 0); };
        const d = new Date(), now = d.getHours() * 60 + d.getMinutes(), a = m(Cfg.data.nightFrom || "21:00"), b = m(Cfg.data.nightTo || "07:00");
        const on = (a <= b ? (now >= a && now < b) : (now >= a || now < b)) ? 1 : 0;
        if (on === nightWas) return;
        nightWas = on;
        const w = on ? (Cfg.data.nightStrength || 0.5) : 0;
        if (Math.abs((cfg.warmth || 0) - w) > 0.01) setCfg("warmth", w);
    }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: st.nightCheck() }
    Process { id: applyProc }
    function applyCfg() {
        const c = Object.assign({}, cfg);
        if (c.brightness === undefined) c.brightness = 0.0;
        if (c.gamma === undefined) c.gamma = 1.0;
        const colorOn = c.vibrance > 0.001 || Math.abs(c.contrast) > 0.001 || c.warmth > 0.001 ||
                        Math.abs(c.brightness) > 0.001 || Math.abs(c.gamma - 1.0) > 0.001;
        // alternate between two files so Hyprland always re-reads the shader
        c.shaderSlot = c.shaderSlot === "a" ? "b" : "a";
        cfg = c;
        const shaderPath = st.home + "/.config/hypr/shaders/color-" + c.shaderSlot + ".glsl";
        const glsl =
            "#version 300 es\n" +
            "// generated by the Settings app\n" +
            "precision highp float;\nin vec2 v_texcoord;\nuniform sampler2D tex;\nout vec4 fragColor;\n" +
            "const float VIBRANCE = " + c.vibrance.toFixed(3) + ";\n" +
            "const float CONTRAST = " + c.contrast.toFixed(3) + ";\n" +
            "const float WARMTH = " + c.warmth.toFixed(3) + ";\n" +
            "const float BRIGHTNESS = " + c.brightness.toFixed(3) + ";\n" +
            "const float GAMMA = " + c.gamma.toFixed(3) + ";\n" +
            "void main() {\n" +
            "  vec4 c = texture(tex, v_texcoord); vec3 col = c.rgb;\n" +
            "  float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));\n" +
            "  float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));\n" +
            "  col = mix(vec3(luma), col, 1.0 + VIBRANCE * (1.0 - sat));\n" +
            "  col = (col - 0.5) * (1.0 + CONTRAST) + 0.5;\n" +
            "  col *= vec3(1.0, 1.0 - WARMTH * 0.18, 1.0 - WARMTH * 0.45);\n" +
            "  col = clamp(col + BRIGHTNESS, 0.0, 1.0);\n" +
            "  col = pow(col, vec3(1.0 / GAMMA));\n" +
            "  fragColor = vec4(clamp(col, 0.0, 1.0), c.a);\n}\n";
        const layouts = String(c.kb_layout || "us").split(",").map(s => s.trim()).filter(s => s !== "");
        const lua =
            "-- generated by the Settings app; edit there\n" +
            "hl.config({\n" +
            "  general = { gaps_in = " + c.gaps_in + ", gaps_out = " + c.gaps_out + ", border_size = " + c.border + " },\n" +
            "  decoration = { rounding = " + c.rounding + ", dim_inactive = " + c.dim + ", inactive_opacity = " + c.inactive_opacity.toFixed(2) +
            ", blur = { enabled = " + c.blur + ", size = " + (c.blur_size || 8) + ", passes = " + (c.blur_passes || 3) + " }, wobble = { enabled = " + (c.wobble === true) + st.jellyLua(c.jelly) + " }, screen_shader = \"" + (colorOn ? shaderPath : "") + "\" },\n" +
            "  animations = { enabled = " + c.animations + " },\n" +
            "  input = { sensitivity = " + c.sensitivity.toFixed(2) + ", kb_options = \"" + c.kb_toggle + "\"" +
            ", kb_layout = \"" + layouts.join(",") + "\", kb_variant = \"" + layouts.map(() => "").join(",") + "\"" +
            ", repeat_rate = " + Math.round(c.repeat_rate || 25) + ", repeat_delay = " + Math.round(c.repeat_delay || 600) +
            ", natural_scroll = " + (c.natural_scroll === true) + ", accel_profile = \"" + (c.accel === "flat" ? "flat" : "adaptive") + "\" },\n" +
            "})\n" +
            (Cfg.data.appsLang && Cfg.lang !== "en"
                ? "hl.env(\"LOCPATH\", \"" + st.home + "/.local/share/sakura-locale\")\nhl.env(\"LANG\", \"" + st.localeName() + "\")\n" : "");
        cfgFile.setText(JSON.stringify(c, null, 2));
        applyProc.command = ["sh", "-c",
            "mkdir -p \"$HOME/.config/hypr/shaders\"\n" +
            "cat > \"" + shaderPath + "\" <<'GLSL'\n" + glsl + "GLSL\n" +
            "cat > \"$HOME/.config/hypr/user-settings.lua\" <<'EOF'\n" + lua + "EOF\nhyprctl reload >/dev/null"];
        applyProc.running = true;
    }
    // accent color: quickshell follows settings.json live; accent.sh recolors waybar, kitty, hyprlock, borders…
    property string previewAccent: ""
    Process { id: accProc }
    Process { id: accPick; stdout: StdioCollector { onStreamFinished: { const h = this.text.trim(); if (/^#[0-9a-f]{6}$/.test(h)) st.applyAccent(h); } } }
    // Settings is the only writer of settings.json; accent.sh "apply" just recolors waybar, kitty, hyprlock, borders…
    function applyAccent(hex) { Cfg.set("accent", hex); accProc.command = [scripts + "/accent.sh", "apply", hex]; accProc.running = true; }
    function accentProc(arg) {
        if (arg === "auto") { accPick.running = false; accPick.command = [scripts + "/accent.sh", "pick"]; accPick.running = true; }
        else applyAccent(arg);
    }
    function setAccent(hex) { Cfg.set("accentAuto", false); applyAccent(hex); }
    function localeName() { return Cfg.lang === "ru" ? "ru_RU.UTF-8" : Cfg.lang === "uk" ? "uk_UA.UTF-8" : "en_US.UTF-8"; }

    // waybar re-reads clock format + date language on restart (hypr/scripts/waybar.sh)
    Timer { id: barRestart; interval: 700; onTriggered: Quickshell.execDetached(["sh", "-c", "touch \"${XDG_RUNTIME_DIR:-/tmp}/waybar-switch\"; pkill -x waybar"]) }
    function setLang(l) {
        Cfg.set("lang", l);
        Quickshell.execDetached([scripts + "/sakura-locale.sh", l]);
        barRestart.restart(); geoProc.running = false; geo = [];
        if (Cfg.data.appsLang) saveTimer.restart();
    }

    // ── system info ─────────────────────────────────────────────
    property var monitors: []
    property string netInfo: ""
    property string vpnStatus: ""
    property var about: []
    Process {
        id: monProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { st.monitors = JSON.parse(this.text); st.resetMonEdit(); } catch (e) {} } }
    }
    Process {
        id: netProc
        command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null | grep -v ':loopback:' | grep -v '^lo:'"]
        stdout: StdioCollector { onStreamFinished: st.netInfo = this.text.trim() }
    }
    Process {
        id: vpnProc
        command: ["sh", "-c", "mullvad status 2>/dev/null | head -2"]
        stdout: StdioCollector { onStreamFinished: st.vpnStatus = this.text.trim() }
    }
    Process {
        id: aboutProc
        command: ["sh", "-c",
            "echo \"OS|$(. /etc/os-release; echo $PRETTY_NAME)\";" +
            "echo \"Kernel|$(uname -r)\";" +
            "echo \"Hyprland|$(hyprctl version -j | python3 -c 'import json,sys;print(json.load(sys.stdin)[\"tag\"])' 2>/dev/null)\";" +
            "echo \"CPU|$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')\";" +
            "echo \"GPU|$(lspci | grep -iE 'vga|3d' | head -1 | sed 's/.*: //')\";" +
            "echo \"Memory|$(free -h | awk '/Mem:/{print $3\" / \"$2}')\";" +
            "echo \"Uptime|$(uptime -p | sed 's/^up //')\";" +
            "echo \"Packages|$(pacman -Qq 2>/dev/null | wc -l)\""]
        stdout: StdioCollector {
            onStreamFinished: st.about = this.text.trim().split("\n").map(l => { const i = l.indexOf("|"); return { k: l.slice(0, i), v: l.slice(i + 1) }; })
        }
    }
    // storage
    property var disks: []
    Process {
        id: diskProc
        command: ["sh", "-c", "df -P -T -B1 -x tmpfs -x devtmpfs -x efivarfs -x overlay -x squashfs 2>/dev/null | tail -n +2"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                st.disks = this.text.trim().split("\n").map(l => l.trim().split(/\s+/)).filter(f => f.length >= 7)
                    .filter(f => { if (seen[f[0]]) return false; seen[f[0]] = true; return !f[6].startsWith("/boot") || f[6] === "/boot"; })
                    .map(f => ({ dev: f[0], type: f[1], size: +f[2], used: +f[3], free: +f[4], mount: f.slice(6).join(" ") }));
            }
        }
    }
    function gb(b) { return b >= 1e12 ? (b / 1e12).toFixed(2) + " TB" : (b / 1e9).toFixed(1) + " GB"; }
    // time zone
    property string curTz: ""
    property var tzAll: []
    Process { id: tzProc; command: ["timedatectl", "show", "-p", "Timezone", "--value"]; stdout: StdioCollector { onStreamFinished: st.curTz = this.text.trim() } }
    Process { id: tzListProc; command: ["timedatectl", "list-timezones"]; stdout: StdioCollector { onStreamFinished: st.tzAll = this.text.trim().split("\n") } }
    Process { id: tzSet; onExited: { tzProc.running = true; barRestart.restart(); } }
    function setTz(z) { if (!z) return; tzSet.command = ["timedatectl", "set-timezone", z]; tzSet.running = true; }
    property string tzQuery: ""
    readonly property var tzHits: {
        const q = tzQuery.trim().toLowerCase().replace(/ /g, "_");
        if (q.length < 2) return [];
        return tzAll.filter(z => z.toLowerCase().includes(q)).slice(0, 8);
    }
    // location (weather): open-meteo geocoding, no key
    property var loc: null
    FileView { id: locFile; path: st.home + "/.config/sakura/weather.json"; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { st.loc = JSON.parse(text()); } catch (e) {} } }
    property var geo: []
    property string geoQuery: ""
    Process {
        id: geoProc
        stdout: StdioCollector { onStreamFinished: { try { st.geo = JSON.parse(this.text).results || []; } catch (e) { st.geo = []; } } }
    }
    Timer { id: geoT; interval: 400; onTriggered: {
        const q = st.geoQuery.trim(); if (q.length < 2) { st.geo = []; return; }
        geoProc.running = false;
        geoProc.command = ["curl", "-s", "--max-time", "6", "https://geocoding-api.open-meteo.com/v1/search?count=6&language=" + Cfg.lang + "&name=" + encodeURIComponent(q)];
        geoProc.running = true; } }
    function setLocation(r) {
        const j = JSON.stringify({ city: r.name, lat: r.latitude, lon: r.longitude, tz: r.timezone || "" });
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config/sakura\" && printf '%s\\n' \"$1\" > \"$HOME/.config/sakura/weather.json\" && \"$HOME/.config/hypr/scripts/weather.sh\"", "sh", j]);
        geo = []; geoQuery = "";
    }
    function detectLocation() {
        Quickshell.execDetached(["sh", "-c", "rm -f \"$HOME/.config/sakura/weather.json\"; \"$HOME/.config/hypr/scripts/weather.sh\""]);
    }
    // wallpapers
    property var walls: []
    Process { id: wallProc; command: [st.scripts + "/wallpaper.sh", "list"]; stdout: StdioCollector { onStreamFinished: st.walls = this.text.trim().split("\n").filter(x => x !== "") } }
    readonly property string wallpaper: Cfg.data.wallpaper || (st.home + "/Pictures/Wallpapers/main.jpg")
    function setWallpaper(f) {
        Cfg.set("wallpaper", f);
        if (Cfg.data.accentAuto === true) accentTimer.restart();
        // videos: awww shows a frame, Wallpaper.qml plays the video on top
        Quickshell.execDetached([scripts + "/wallpaper.sh", "show", f]);     // transition / fill from settings.json
    }
    Timer { id: accentTimer; interval: 600; onTriggered: st.accentProc("auto") }   // after settings.json has the new wallpaper
    // recording: ~/.config/capture/config.json (the same file the Alt+Z overlay edits); capture.sh apply restarts replay
    property var capCfg: ({})
    FileView {
        id: capFile
        path: st.home + "/.config/capture/config.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { st.capCfg = JSON.parse(text()); } catch (e) {} }
    }
    function setCap(k, v) {
        const c = Object.assign({}, capCfg); c[k] = v; capCfg = c;
        capFile.setText(JSON.stringify(c, null, 2)); capApply.restart();
    }
    Timer { id: capApply; interval: 800; onTriggered: Quickshell.execDetached([st.scripts + "/capture.sh", "apply"]) }
    Timer { id: clipApply; interval: 800; onTriggered: Quickshell.execDetached([st.scripts + "/clipwatch.sh"]) }
    // avatar: pick a picture (zenity), crop it square; bump the revision so every avatar on screen reloads
    Process { id: avProc; stdout: StdioCollector { onStreamFinished: if (this.text.trim() === "ok") Cfg.set("avatarRev", (Cfg.data.avatarRev || 0) + 1) } }
    // rice backup (hypr/scripts/rice-backup.sh)
    property bool backingUp: bkProc.running
    property bool backupPersonal: false
    property string lastBackup: ""
    Process { id: bkProc; stdout: StdioCollector { onStreamFinished: { const f = this.text.trim().split("\n").pop(); if (f.endsWith(".tar.gz")) st.lastBackup = f; } } }
    Process { id: bkList; command: ["sh", "-c", "ls -1t \"$HOME\"/sakura-backups/sakura-rice-*.tar.gz 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: st.lastBackup = this.text.trim() } }
    function makeBackup() { bkProc.command = [scripts + "/rice-backup.sh"].concat(backupPersonal ? ["--personal"] : []); bkProc.running = true; }
    // default apps
    property var defApps: ({})
    Process { id: defProc; command: ["python3", "-I", st.scripts + "/default-apps.py", "list"]
        stdout: StdioCollector { onStreamFinished: { try { st.defApps = JSON.parse(this.text); } catch (e) {} } } }
    Process { id: defSet; onExited: defProc.running = true }
    property string defOpen: ""
    // notifications
    property bool dnd: false
    Process { id: dndProc; command: ["true"]; stdout: StdioCollector { onStreamFinished: st.dnd = this.text.trim() === "true" } }
    // start menu pins (for the preview)
    property var menuPins: []
    FileView { path: st.home + "/.config/quickshell/menu.json"; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { st.menuPins = JSON.parse(text()).pinned || []; } catch (e) {} } }
    // bar position
    property string barpos: "top"
    FileView { path: st.home + "/.config/sakura/barpos"; watchChanges: true; onFileChanged: reload()
        onLoaded: st.barpos = text().trim() || "top"; onLoadFailed: st.barpos = "top" }

    function refreshAll() {
        monProc.running = true; netProc.running = true; vpnProc.running = true; aboutProc.running = true;
        diskProc.running = true; tzProc.running = true; if (tzAll.length === 0) tzListProc.running = true;
        wallProc.running = true; defProc.running = true; dndProc.running = true; bkList.running = true;
    }

    // ── displays: edit, apply, keep-or-revert ───────────────────
    property var monEdit: []
    property int monSel: 0
    function resetMonEdit() {
        monEdit = monitors.slice().sort((a, b) => a.x - b.x).map(m => ({
            name: m.name, desc: (m.make + " " + m.model).trim(), w: m.width, h: m.height,
            rate: Math.round(m.refreshRate), scale: m.scale,
            modes: (m.availableModes || []).map(s => { const r = s.match(/(\d+)x(\d+)@([\d.]+)/); return r ? { w: +r[1], h: +r[2], rate: Math.round(+r[3]) } : null; }).filter(x => x)
                .sort((a, b) => b.w * b.h - a.w * a.h || b.rate - a.rate)
        }));
        if (monSel >= monEdit.length) monSel = 0;
    }
    function editMon(i, patch) { const l = monEdit.slice(); l[i] = Object.assign({}, l[i], patch); monEdit = l; }
    function moveMon(i, d) { const j = i + d; if (j < 0 || j >= monEdit.length) return; const l = monEdit.slice(); const t = l[i]; l[i] = l[j]; l[j] = t; monEdit = l; monSel = j; }
    property string monBackup: ""
    property int keepLeft: 0
    Process { id: monBak; command: ["sh", "-c", "cat \"$HOME/.config/hypr/monitors.lua\" 2>/dev/null"]; stdout: StdioCollector { onStreamFinished: st.monBackup = this.text } }
    function applyMonitors() {
        let x = 0, lua = "-- generated by Settings > Displays - edit there\n";
        for (const m of monEdit) {
            lua += "hl.monitor({ output = \"" + m.name + "\", mode = \"" + m.w + "x" + m.h + "@" + m.rate + "\", position = \"" + x + "x0\", scale = " + m.scale + " })\n";
            x += Math.round(m.w / m.scale);
        }
        const main = Cfg.mainName, second = (monEdit.find(m => m.name !== main) || {}).name || "";
        const d = Object.assign({}, Cfg.data); d.mainMonitor = main; d.secondMonitor = second; Cfg.data = d; Cfg.save();
        Quickshell.execDetached(["sh", "-c", "cat > \"$HOME/.config/hypr/monitors.lua\" <<'EOF'\n" + lua + "EOF\nsleep 0.4; hyprctl reload >/dev/null"]);
        keepLeft = 15; keepT.restart(); monRefresh.restart();
    }
    function revertMonitors() {
        keepT.stop(); keepLeft = 0;
        Quickshell.execDetached(["sh", "-c", "cat > \"$HOME/.config/hypr/monitors.lua\" <<'EOF'\n" + monBackup + "EOF\nhyprctl reload >/dev/null"]);
        monRefresh.restart();
    }
    Timer { id: keepT; interval: 1000; repeat: true; onTriggered: { st.keepLeft--; if (st.keepLeft <= 0) st.revertMonitors(); } }
    Timer { id: monRefresh; interval: 1500; onTriggered: monProc.running = true }

    // ── audio ───────────────────────────────────────────────────
    readonly property var sinks:   Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    PwObjectTracker { objects: st.sinks.concat(st.sources) }
    function nodeName(n) { return n.description || n.nickname || n.name; }

    // ── reusable bits ───────────────────────────────────────────
    // wheel: ~140 px a notch (touchpads: their own pixels, a bit faster)
    function wheelScroll(f, e) {
        if (!f) return;
        const dy = e.pixelDelta.y !== 0 ? e.pixelDelta.y * 1.6 : e.angleDelta.y / 120 * 140;
        f.contentY = Math.max(0, Math.min(Math.max(0, f.contentHeight - f.height), f.contentY - dy));
    }
    // a thin scrollbar for a Flickable (sits over its right edge; drag the thumb or click the track)
    component VBar: Item {
        id: vb
        property var flick
        readonly property real ratio: flick && flick.contentHeight > 0 ? Math.min(1, flick.height / flick.contentHeight) : 1
        visible: ratio < 1
        width: 10
        anchors { right: flick ? flick.right : undefined; top: flick ? flick.top : undefined; bottom: flick ? flick.bottom : undefined; margins: 3 }
        readonly property real thumbH: Math.max(36, height * ratio)
        readonly property real maxY: Math.max(1, flick ? flick.contentHeight - flick.height : 1)
        Rectangle {
            id: thumb
            x: 2; width: vb.width - 4 + (va.containsMouse || va.drag.active ? 2 : 0); radius: width / 2
            height: vb.thumbH
            y: vb.flick ? (vb.height - height) * Math.min(1, vb.flick.contentY / vb.maxY) : 0
            color: va.containsMouse || va.pressed ? Cfg.acc(0.7) : "#40ffffff"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        MouseArea {
            id: va
            anchors.fill: parent; hoverEnabled: true; preventStealing: true
            property real grab: -1
            function to(my) { vb.flick.contentY = Math.max(0, Math.min(vb.maxY, (my - grab) / Math.max(1, vb.height - vb.thumbH) * vb.maxY)); }
            onPressed: m => { grab = (m.y >= thumb.y && m.y <= thumb.y + thumb.height) ? m.y - thumb.y : vb.thumbH / 2; to(m.y); }
            onPositionChanged: m => { if (pressed) to(m.y); }
        }
    }
    component Card: Rectangle {
        radius: 18; color: st.cCard
        border.width: 1; border.color: st.cBorder
        width: parent ? parent.width : 0
    }
    component Heading: Text {
        color: st.cFg; font.family: st.fUi; font.pixelSize: 13; font.weight: Font.Bold
        topPadding: 6
    }
    component Title: Text { color: st.cFg; font.family: st.fUi; font.pixelSize: 26; font.weight: Font.ExtraBold }
    component Note: Text { width: parent ? parent.width : 0; wrapMode: Text.WordWrap; color: st.cMuted; font.family: st.fUi; font.pixelSize: 12 }
    component Toggle: Rectangle {
        id: tg
        property bool on: false
        signal toggled()
        width: 46; height: 26; radius: 13
        color: on ? st.cAccent : "#33ffffff"
        Behavior on color { ColorAnimation { duration: 160 } }
        Rectangle {
            width: 20; height: 20; radius: 10; y: 3
            x: tg.on ? tg.width - width - 3 : 3
            color: tg.on ? st.cAccFg : "#ffffff"
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
    }
    component Slider: Item {
        id: sl
        property real from: 0
        property real to: 1
        property real value: 0
        property real step: 0.05
        signal moved(real v)
        height: 24
        readonly property real frac: Math.max(0, Math.min(1, (value - from) / (to - from)))
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: "#26ffffff" }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * sl.frac; height: 6; radius: 3; color: st.cAccent }
        Rectangle { x: parent.width * sl.frac - 9; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; radius: 9; color: "#ffffff" }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            function at(mx) {
                let v = sl.from + Math.max(0, Math.min(1, mx / width)) * (sl.to - sl.from);
                v = Math.round(v / sl.step) * sl.step;
                sl.moved(v);
            }
            onPressed: m => at(m.x)
            onPositionChanged: m => { if (pressed) at(m.x); }
        }
    }
    component Row2: Item {
        id: r2
        property string label: ""
        property string sub: ""
        default property alias content: slot.data
        width: parent ? parent.width : 0
        height: Math.max(52, txt.implicitHeight + 20, slot.height + 16)
        Column {
            id: txt
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter; right: slot.left; rightMargin: 12 }
            Text { text: r2.label; color: st.cFg; font.family: st.fUi; font.pixelSize: 14; width: parent.width; elide: Text.ElideRight }
            Text { text: r2.sub; visible: r2.sub !== ""; color: st.cMuted; font.family: st.fUi; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap }
        }
        Item { id: slot; anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter } width: childrenRect.width; height: childrenRect.height }
    }
    component Btn: Rectangle {
        id: b
        property string text: ""
        property bool primary: false
        signal clicked()
        width: bt.implicitWidth + 28; height: 34; radius: 11
        color: primary ? (ba.containsMouse ? "#ffffff" : st.cAccent) : (ba.containsMouse ? st.cHover : "#14ffffff")
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { id: bt; anchors.centerIn: parent; text: b.text; color: b.primary ? st.cAccFg : st.cFg; font.family: st.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
        MouseArea { id: ba; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
    component Field: Rectangle {
        id: fld
        property alias text: ti.text
        property string hint: ""
        property string icon: ""
        signal accepted()
        width: 300; height: 36; radius: 11; color: "#14ffffff"
        border.width: 1; border.color: ti.activeFocus ? st.cAccent : st.cBorder
        Text { id: fi; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: fld.icon; font.family: st.fIcon; font.pixelSize: 12; color: st.cAccent }
        TextInput {
            id: ti
            anchors { left: fi.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            color: st.cFg; font.family: st.fUi; font.pixelSize: 13; clip: true; selectionColor: st.cAccent
            onAccepted: fld.accepted()
            onEditingFinished: fld.accepted()
            Text { anchors.verticalCenter: parent.verticalCenter; text: fld.hint; color: st.cMuted; font: ti.font; visible: ti.text === "" }
        }
    }
    component PickRow: Rectangle {     // a row in a picker list
        id: pk
        property string text: ""
        property string sub: ""
        property string icon: ""
        property bool sel: false
        signal clicked()
        width: parent ? parent.width : 0; height: 42; radius: 11
        color: sel ? Cfg.acc(0.15) : (pka.containsMouse ? st.cHover : "transparent")
        IconImage { id: pki; visible: pk.icon !== ""; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    implicitSize: 22; source: pk.icon !== "" ? Quickshell.iconPath(pk.icon, "application-x-executable") : "" }
        Text { anchors { left: pk.icon !== "" ? pki.right : parent.left; leftMargin: 12; right: pks.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
               text: pk.text; elide: Text.ElideRight; color: pk.sel ? st.cAccent : st.cFg; font.family: st.fUi; font.pixelSize: 13 }
        Text { id: pks; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
               text: pk.sub; color: st.cMuted; font.family: st.fUi; font.pixelSize: 11 }
        MouseArea { id: pka; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pk.clicked() }
    }
    component DeviceList: Column {
        id: dl
        property var nodes: []
        property var current: null
        signal picked(var node)
        width: parent ? parent.width : 0
        spacing: 2
        Repeater {
            model: dl.nodes
            delegate: Rectangle {
                required property var modelData
                readonly property bool sel: dl.current !== null && modelData.id === dl.current.id
                width: dl.width; height: 46; radius: 12
                color: sel ? Cfg.acc(0.15) : (da.containsMouse ? st.cHover : "transparent")
                Rectangle {
                    id: dot
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    width: 18; height: 18; radius: 9
                    color: "transparent"; border.width: 2; border.color: sel ? st.cAccent : st.cMuted
                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: st.cAccent; visible: sel }
                }
                Text {
                    anchors { left: dot.right; leftMargin: 14; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: st.nodeName(modelData); elide: Text.ElideRight
                    color: sel ? st.cAccent : st.cFg; font.family: st.fUi; font.pixelSize: 14
                }
                MouseArea { id: da; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dl.picked(modelData) }
            }
        }
    }
    // chips you click in order: picked ones are numbered, the rest are dimmed
    component ChipPicker: Flow {
        id: cp
        property var catalog: []
        property var value: []
        signal changed(var v)
        width: parent ? parent.width : 0; spacing: 6
        Repeater {
            model: cp.catalog.filter(c => Cfg.available(c))
            delegate: Rectangle {
                required property var modelData
                readonly property int pos: cp.value.indexOf(modelData.id)
                width: chT.implicitWidth + chI.implicitWidth + (pos >= 0 ? 52 : 34); height: 34; radius: 11
                color: pos >= 0 ? st.cAccent : (chA.containsMouse ? st.cHover : "#14ffffff")
                Row {
                    anchors.centerIn: parent; spacing: 7
                    Rectangle { visible: parent.parent.pos >= 0; width: 16; height: 16; radius: 8; color: st.cAccFg; anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: parent.parent.parent.pos + 1; color: st.cAccent; font.family: st.fUi; font.pixelSize: 9; font.weight: Font.Bold } }
                    Text { id: chI; text: modelData.icon; font.family: st.fIcon; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter
                           color: parent.parent.pos >= 0 ? st.cAccFg : st.cAccent }
                    Text { id: chT; text: st.t(modelData.name); font.family: st.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter
                           color: parent.parent.pos >= 0 ? st.cAccFg : st.cFg }
                }
                MouseArea { id: chA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: cp.changed(parent.pos >= 0 ? cp.value.filter(x => x !== modelData.id) : cp.value.concat([modelData.id])) }
            }
        }
    }
    component Choice: Row {      // a row of exclusive buttons
        id: ch
        property var options: []     // [{v, t}]
        property var value
        signal picked(var v)
        spacing: 6
        Repeater { model: ch.options
            delegate: Btn { required property var modelData; text: st.t(modelData.t); primary: ch.value === modelData.v; onClicked: ch.picked(modelData.v) } }
    }

    // ── window ──────────────────────────────────────────────────
    FloatingWindow {
        id: win
        visible: st.shown
        title: "Settings"
        implicitWidth: 1120
        implicitHeight: 740
        color: st.cBg
        onVisibleChanged: if (!visible) st.shown = false

        Rectangle {
            id: side
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 250
            color: st.cSide
            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: st.cBorder }

            Text { id: sideTitle; x: 24; y: 22; text: st.t("Settings"); color: st.cFg; font.family: st.fUi; font.pixelSize: 22; font.weight: Font.ExtraBold }
            Field { id: search; x: 16; y: 62; width: side.width - 32; hint: st.t("Search settings"); onTextChanged: st.query = text }

            VBar { flick: navFlick; z: 10 }
            MouseArea { anchors.fill: navFlick; z: 9; acceptedButtons: Qt.NoButton; onWheel: w => st.wheelScroll(navFlick, w) }
            Flickable {
                anchors { top: search.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 10 }
                id: navFlick
                contentHeight: navCol.implicitHeight
                clip: true; boundsBehavior: Flickable.StopAtBounds
                interactive: false
                Column {
                    id: navCol
                    x: 12; width: side.width - 24
                    spacing: 2
                    Repeater {
                        model: st.groups
                        delegate: Column {
                            id: grp
                            required property var modelData
                            readonly property var vis: modelData.pages.filter(p => st.pageVisible(p))
                            visible: vis.length > 0
                            width: navCol.width; spacing: 2
                            Text { text: st.t(grp.modelData.g).toUpperCase(); color: st.cMuted; font.family: st.fUi; font.pixelSize: 10; font.weight: Font.Bold
                                   font.letterSpacing: 1; leftPadding: 12; topPadding: 10; bottomPadding: 4 }
                            Repeater {
                                model: grp.vis
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: st.page === modelData.id
                                    width: grp.width; height: 38; radius: 11
                                    color: sel ? st.cAccent : (na.containsMouse ? st.cHover : "transparent")
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Text { id: ni; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                        text: modelData.icon; font.family: st.fIcon; font.pixelSize: 14; color: sel ? st.cAccFg : st.cAccent; width: 20 }
                                    Text { anchors { left: ni.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        text: st.t(modelData.label); elide: Text.ElideRight; font.family: st.fUi; font.pixelSize: 13; font.weight: sel ? Font.Bold : Font.Normal
                                        color: sel ? st.cAccFg : st.cFg }
                                    MouseArea { id: na; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { st.page = modelData.id; st.refreshAll(); content.contentY = 0; } }
                                }
                            }
                        }
                    }
                }
            }
        }

        VBar { flick: content; z: 10 }
        MouseArea { anchors.fill: content; z: 9; acceptedButtons: Qt.NoButton; onWheel: w => st.wheelScroll(content, w) }   // wheel only; clicks and hover pass through
        Flickable {
            id: content
            anchors { left: side.right; right: parent.right; top: parent.top; bottom: parent.bottom }
            contentHeight: pages.implicitHeight + 60
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: false              // no dragging the page with the mouse: wheel and the scrollbar only

            Column {
                id: pages
                x: 32; y: 28
                width: content.width - 64
                spacing: 12

                // ── MUSIC (Sakura Sound, ~/.config/sakura-sound) ─
                Column {
                    visible: st.page === "music"; width: parent.width; spacing: 12
                    Title { text: st.t("Music") }
                    Card {
                        height: muCol.implicitHeight + 8
                        Column {
                            id: muCol; y: 4; width: parent.width
                            Row2 { label: "Sakura Sound"; sub: st.t("SoundCloud player")
                                Btn { text: st.t("Open"); onClicked: { st.shown = false; Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/sakura-sound"]); } } }
                            Row2 { label: st.t("Music in the notch opens")
                                Choice { options: [{ v: "sound", t: "Sakura Sound" }, { v: "media", t: "Media" }]; value: Cfg.data.musicNotch || "media"; onPicked: v => Cfg.set("musicNotch", v) } }
                            Row2 { label: st.t("Cookies from"); sub: st.t("Browser signed in to SoundCloud")
                                Choice { options: ["brave", "chromium", "chrome", "firefox"].map(b => ({ v: b, t: b.charAt(0).toUpperCase() + b.slice(1) }))
                                         value: Cfg.data.musicBrowser || "brave"
                                         onPicked: v => { Cfg.set("musicBrowser", v); Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/sakura-sound", "browser", v]); } } }
                            Row2 { label: st.t("Start with the session"); sub: st.t("Waits hidden, so music starts at once")
                                Toggle { on: Cfg.data.musicAutostart === true
                                         onToggled: { const on = Cfg.data.musicAutostart !== true; Cfg.set("musicAutostart", on);
                                                      Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/sakura-sound", on ? "autostart-on" : "autostart-off"]); } } }
                        }
                    }
                }

                // ── PASSWORD HELPER (PasswordHelper.qml + PwVault.qml, settings.json "pw") ─
                Column {
                    id: pwPage
                    visible: st.page === "passwords"; width: parent.width; spacing: 12
                    readonly property var p: PwVault.o
                    function t(s) { return PwVault.tr(s); }
                    property string sample: ""
                    property real sampleBits: 0
                    property string sampleProblem: ""
                    property string hkErr: ""
                    property bool wipeArmed: false
                    function regen() { PwVault.generate(r => { if (r.ok) { pwPage.sample = r.password; pwPage.sampleBits = r.bits; pwPage.sampleProblem = r.problem || ""; } }); }
                    onVisibleChanged: { if (visible) regen(); else { sample = ""; wipeArmed = false; if (PwVault.recording) stopRec(false); } }
                    Connections { target: PwVault; function onPolicyChanged() { if (pwPage.visible) pwPage.regen(); } }
                    // at least one character group stays on
                    function setClass(k) {
                        const on = !pwPage.p[k];
                        if (!on && ["upper", "lower", "digits", "symbols"].filter(x => pwPage.p[x]).length <= 1) return;
                        PwVault.set(k, on);
                    }
                    // shortcut recorder (Ctrl/Alt/Super + one key; the old shortcut is paused meanwhile)
                    function startRec() { hkErr = ""; PwVault.recording = true; PwVault.pauseBind(true); hkCap.forceActiveFocus(); }
                    function stopRec(restore) { PwVault.recording = false; if (restore) PwVault.pauseBind(false); }
                    readonly property var keyNames: ({ [Qt.Key_Space]: "SPACE", [Qt.Key_Slash]: "SLASH", [Qt.Key_Comma]: "COMMA", [Qt.Key_Period]: "PERIOD",
                        [Qt.Key_Minus]: "MINUS", [Qt.Key_Equal]: "EQUAL", [Qt.Key_QuoteLeft]: "GRAVE", [Qt.Key_BracketLeft]: "BRACKETLEFT",
                        [Qt.Key_BracketRight]: "BRACKETRIGHT", [Qt.Key_Semicolon]: "SEMICOLON", [Qt.Key_Apostrophe]: "APOSTROPHE",
                        [Qt.Key_Backslash]: "BACKSLASH", [Qt.Key_Insert]: "INSERT", [Qt.Key_Delete]: "DELETE", [Qt.Key_Home]: "HOME",
                        [Qt.Key_End]: "END", [Qt.Key_PageUp]: "PRIOR", [Qt.Key_PageDown]: "NEXT", [Qt.Key_Return]: "RETURN", [Qt.Key_Backspace]: "BACKSPACE" })
                    function keyName(k) {
                        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k);
                        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k);
                        if (k >= Qt.Key_F1 && k <= Qt.Key_F24) return "F" + (k - Qt.Key_F1 + 1);
                        return keyNames[k] || "";
                    }
                    Item {
                        id: hkCap
                        width: 0; height: 0
                        Keys.onPressed: ev => {
                            ev.accepted = true;
                            if (!PwVault.recording) return;
                            if (ev.key === Qt.Key_Escape) { pwPage.stopRec(true); return; }
                            if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_AltGr].includes(ev.key)) return;
                            const name = pwPage.keyName(ev.key);
                            if (!name) { pwPage.hkErr = pwPage.t("That key cannot be used - try a letter, a digit or F1-F24."); return; }
                            let mask = 0;
                            if (ev.modifiers & Qt.ControlModifier) mask |= 4;
                            if (ev.modifiers & Qt.AltModifier) mask |= 8;
                            if (ev.modifiers & Qt.ShiftModifier) mask |= 1;
                            if (ev.modifiers & Qt.MetaModifier) mask |= 64;
                            const combo = PwVault.comboText(mask, name);
                            const bad = PwVault.validCombo(combo);
                            if (bad) { pwPage.hkErr = bad; return; }
                            pwPage.stopRec(false);
                            PwVault.setHotkey(combo, err => { pwPage.hkErr = err; if (err) PwVault.pauseBind(false); });
                        }
                    }

                    Title { text: pwPage.t("Password helper") }
                    Note { text: pwPage.t("A glass ring around the pointer for passwords: generate a strong one, pick a saved one, or reuse something from the clipboard. Everything is only copied (never typed for you) and the notch says so.") }

                    Heading { text: pwPage.t("General") }
                    Card {
                        height: pgCol.implicitHeight + 8
                        Column {
                            id: pgCol; y: 4; width: parent.width
                            Row2 { label: pwPage.t("Open it now"); sub: PwVault.pretty(pwPage.p.hotkey)
                                Btn { text: pwPage.t("Open"); primary: true; onClicked: { st.shown = false; Quickshell.execDetached(["sh", "-c", "sleep 0.25; qs ipc call pwhelper open"]); } } }
                            Row2 { label: pwPage.t("Close after picking"); sub: pwPage.t("Otherwise the ring stays open after a copy")
                                Toggle { on: pwPage.p.closeOnSelect; onToggled: PwVault.set("closeOnSelect", !pwPage.p.closeOnSelect) } }
                            Row2 { label: pwPage.t("Close on a click outside")
                                Toggle { on: pwPage.p.closeOnOutside; onToggled: PwVault.set("closeOnOutside", !pwPage.p.closeOnOutside) } }
                            Row2 { label: pwPage.t("Button sound")
                                Row { spacing: 10
                                    Btn { text: "▶"; onClicked: Quickshell.execDetached(["pw-play", "--volume", String(pwPage.p.volume), PwVault.clickWav]) }
                                    Toggle { anchors.verticalCenter: parent.verticalCenter; on: pwPage.p.sound; onToggled: PwVault.set("sound", !pwPage.p.sound) } } }
                            Row2 { label: pwPage.t("Opens at")
                                Choice { options: [ { v: "pointer", t: "Mouse pointer" }, { v: "center", t: "Screen centre" } ]; value: pwPage.p.placement; onPicked: v => PwVault.set("placement", v) } }
                        }
                    }

                    Heading { text: pwPage.t("Shortcut") }
                    Card {
                        height: pkCol.implicitHeight + 8
                        Column {
                            id: pkCol; y: 4; width: parent.width
                            Row2 { label: pwPage.t("Activation shortcut")
                                   sub: PwVault.recording ? pwPage.t("Press the new combination… (Esc cancels)") : pwPage.t("Ctrl, Alt or Super plus one key")
                                Row { spacing: 8
                                    Rectangle {
                                        width: hkT.implicitWidth + 28; height: 34; radius: 11
                                        color: PwVault.recording ? Cfg.acc(0.18) : "#14ffffff"; border.width: 1; border.color: PwVault.recording ? st.cAccent : st.cBorder
                                        Text { id: hkT; anchors.centerIn: parent; text: PwVault.recording ? "…" : PwVault.pretty(pwPage.p.hotkey)
                                               color: st.cFg; font.family: st.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    }
                                    Btn { text: PwVault.recording ? pwPage.t("Cancel") : pwPage.t("Record"); onClicked: PwVault.recording ? pwPage.stopRec(true) : pwPage.startRec() }
                                    Btn { text: pwPage.t("Reset"); onClicked: PwVault.setHotkey("CTRL + SHIFT + P", err => pwPage.hkErr = err) } } }
                            Note { visible: pwPage.hkErr !== ""; x: 18; width: parent.width - 36; bottomPadding: 10; color: "#ff9a9a"; text: pwPage.hkErr }
                            Note { x: 18; width: parent.width - 36; bottomPadding: 12
                                   text: pwPage.t("Busy combinations are refused and the working one stays. Ctrl+Shift+P is also the private window in browsers and the command palette in code editors - pick another if you miss those.") }
                        }
                    }

                    Heading { text: pwPage.t("Passwords") }
                    Card {
                        height: ppCol.implicitHeight + 8
                        Column {
                            id: ppCol; y: 4; width: parent.width
                            Row2 { label: pwPage.t("Length"); sub: pwPage.p.length + " " + pwPage.t("characters")
                                Slider { width: 260; from: 8; to: 128; step: 1; value: pwPage.p.length; onMoved: v => PwVault.set("length", Math.round(v)) } }
                            Row2 { label: pwPage.t("Uppercase") + "  A-Z"; Toggle { on: pwPage.p.upper; onToggled: pwPage.setClass("upper") } }
                            Row2 { label: pwPage.t("Lowercase") + "  a-z"; Toggle { on: pwPage.p.lower; onToggled: pwPage.setClass("lower") } }
                            Row2 { label: pwPage.t("Digits") + "  0-9"; Toggle { on: pwPage.p.digits; onToggled: pwPage.setClass("digits") } }
                            Row2 { label: pwPage.t("Symbols"); Toggle { on: pwPage.p.symbols; onToggled: pwPage.setClass("symbols") } }
                            Row2 { label: pwPage.t("Exclude look-alikes"); sub: "I  l  1  |  O  0  o"
                                Toggle { on: pwPage.p.noAmbiguous; onToggled: PwVault.set("noAmbiguous", !pwPage.p.noAmbiguous) } }
                            Row2 { label: pwPage.t("Symbol set"); sub: pwPage.t("Printable symbols only; letters, digits and spaces are dropped")
                                Row { spacing: 8
                                    Field { id: symF; width: 230; text: pwPage.p.symbolSet
                                            onAccepted: { const s = Array.from(new Set(text.split("").filter(c => c > " " && c < "\x7f" && !/[A-Za-z0-9]/.test(c)))).join("");
                                                          PwVault.set("symbolSet", s || PwVault.defaultSymbols); text = s || PwVault.defaultSymbols; } }
                                    Btn { text: pwPage.t("Reset"); onClicked: { PwVault.set("symbolSet", PwVault.defaultSymbols); symF.text = PwVault.defaultSymbols; } } } }
                            // live preview
                            Rectangle {
                                x: 18; width: parent.width - 36; height: pvCol.implicitHeight + 24; radius: 14; color: "#10ffffff"
                                Column {
                                    id: pvCol; x: 14; y: 12; width: parent.width - 28; spacing: 8
                                    Row {
                                        width: parent.width; spacing: 8
                                        Text { width: parent.width - pvB.width - 8; anchors.verticalCenter: parent.verticalCenter
                                               text: pwPage.sampleProblem || pwPage.sample; wrapMode: Text.WrapAnywhere
                                               color: pwPage.sampleProblem ? "#ff9a9a" : st.cFg; font.family: "monospace"; font.pixelSize: 13 }
                                        Row { id: pvB; spacing: 6
                                            Btn { text: "↻"; onClicked: pwPage.regen() }
                                            Btn { text: pwPage.t("Copy"); onClicked: PwVault.copyText(pwPage.sample, true, PwVault.tr("Password copied") + PwVault.clearsNote()) } }
                                    }
                                    Row {
                                        width: parent.width; spacing: 10
                                        readonly property var s: PwVault.strengthOfBits(pwPage.sampleBits)
                                        Rectangle { width: parent.width - 130; height: 6; radius: 3; color: "#22ffffff"; anchors.verticalCenter: parent.verticalCenter
                                            Rectangle { width: parent.width * parent.parent.s.frac; height: 6; radius: 3; color: parent.parent.s.color; Behavior on width { NumberAnimation { duration: 160 } } } }
                                        Text { width: 120; horizontalAlignment: Text.AlignRight; text: parent.s.label + " · " + Math.round(pwPage.sampleBits) + " " + pwPage.t("bits")
                                               color: parent.s.color; font.family: st.fUi; font.pixelSize: 11 }
                                    }
                                }
                            }
                            Item { width: 1; height: 12 }
                        }
                    }

                    Heading { text: pwPage.t("Clipboard") }
                    Card {
                        height: pcCol.implicitHeight + 8
                        Column {
                            id: pcCol; y: 4; width: parent.width
                            Row2 { label: pwPage.t("Clipboard history"); sub: pwPage.t("In memory only, never written to disk; gone when the shell restarts")
                                Toggle { on: pwPage.p.history; onToggled: PwVault.set("history", !pwPage.p.history) } }
                            Row2 { label: pwPage.t("Entries to keep"); sub: String(pwPage.p.historyLimit); visible: pwPage.p.history
                                Slider { width: 260; from: 5; to: 100; step: 1; value: pwPage.p.historyLimit; onMoved: v => PwVault.set("historyLimit", Math.round(v)) } }
                            Row2 { label: pwPage.t("Clear copied passwords after"); sub: pwPage.t("Only if the clipboard still holds that password")
                                Choice { options: [ { v: 0, t: "Never" }, { v: 30, t: "30 s" }, { v: 90, t: "90 s" }, { v: 180, t: "3 min" }, { v: 600, t: "10 min" } ]
                                         value: pwPage.p.clearAfter; onPicked: v => PwVault.set("clearAfter", v) } }
                            Row2 { label: pwPage.t("Ignored apps"); sub: pwPage.t("Window classes, comma separated. Copies made while one of them is focused are skipped (Wayland does not say who copied), and so is anything marked as a password.")
                                Field { width: 300; text: pwPage.p.ignored.join(", ")
                                        onAccepted: PwVault.set("ignored", text.split(",").map(x => x.trim()).filter(x => x).filter((x, i, a) => a.indexOf(x) === i)) } }
                            Row2 { label: pwPage.t("History now"); sub: PwVault.history.length + " " + pwPage.t("items")
                                Btn { text: pwPage.t("Clear history"); onClicked: PwVault.histClear() } }
                        }
                    }

                    Heading { text: pwPage.t("Security") }
                    Card {
                        height: psCol.implicitHeight + 8
                        Column {
                            id: psCol; y: 4; width: parent.width
                            Row2 { label: pwPage.t("Vault")
                                   sub: PwVault.state === "ready" ? PwVault.entries.length + " " + pwPage.t("saved passwords") + " · " + pwPage.t("unlocked")
                                      : PwVault.state === "locked" ? pwPage.t("Locked") : PwVault.problem || PwVault.state
                                Row { spacing: 8
                                    Btn { visible: PwVault.state === "ready"; text: pwPage.t("Lock"); onClicked: PwVault.lock() }
                                    Btn { visible: PwVault.state !== "ready" && PwVault.state !== "corrupt"; primary: true; text: pwPage.t("Unlock"); onClicked: PwVault.unlock() } } }
                            Row2 { visible: PwVault.state === "corrupt"; label: pwPage.t("The vault does not open"); sub: pwPage.t("Nothing was deleted. Damaged files are kept as vault.dat.broken-…")
                                Row { spacing: 8
                                    Btn { visible: PwVault.hasBak && PwVault.code !== "nokey"; primary: true; text: pwPage.t("Restore backup"); onClicked: PwVault.recover("restore") }
                                    Btn { text: pwPage.t("Start new"); onClicked: PwVault.recover("new") } } }
                            Row2 { label: pwPage.t("Lock with the screen")
                                Toggle { on: pwPage.p.lockOnScreenLock; onToggled: PwVault.set("lockOnScreenLock", !pwPage.p.lockOnScreenLock) } }
                            Row2 { label: pwPage.t("Lock after not using it for")
                                Choice { options: [ { v: 0, t: "Never" }, { v: 5, t: "5 min" }, { v: 15, t: "15 min" }, { v: 30, t: "30 min" }, { v: 60, t: "1 h" } ]
                                         value: pwPage.p.autoLock; onPicked: v => PwVault.set("autoLock", v) } }
                            Row2 { label: pwPage.t("Storage"); sub: "~/.local/share/sakura/vault.dat (+ .bak) · AES-256-GCM · " + pwPage.t("key in the login keyring (Secret Service), opens with your login")
                                Btn { text: pwPage.t("Show"); onClicked: Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.local/share/sakura"]) } }
                            Row2 { label: pwPage.t("Delete all data"); sub: pwPage.wipeArmed ? pwPage.t("Click again: the vault, its backups, the key in the keyring and the clipboard history go for good.") : pwPage.t("Saved passwords, backups, the keyring key, clipboard history")
                                Row { spacing: 8
                                    Btn { visible: pwPage.wipeArmed; text: pwPage.t("Cancel"); onClicked: pwPage.wipeArmed = false }
                                    Rectangle {
                                        width: wpT.implicitWidth + 28; height: 34; radius: 11
                                        color: wpA.containsMouse || pwPage.wipeArmed ? "#66ff5c5c" : "#33ff5c5c"
                                        Text { id: wpT; anchors.centerIn: parent; text: pwPage.wipeArmed ? pwPage.t("Delete everything") : pwPage.t("Delete…"); color: "#ffd0d0"; font.family: st.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                                        MouseArea { id: wpA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { if (!pwPage.wipeArmed) { pwPage.wipeArmed = true; return; } pwPage.wipeArmed = false; PwVault.wipe(); } }
                                    } } }
                        }
                    }

                    Heading { text: pwPage.t("Appearance") }
                    Card {
                        height: paCol.implicitHeight + 8
                        Column {
                            id: paCol; y: 4; width: parent.width
                            Row2 { label: pwPage.t("Frosted glass"); sub: pwPage.t("Blurred desktop behind the ring; off = a solid dark backdrop")
                                Toggle { on: pwPage.p.glass; onToggled: PwVault.set("glass", !pwPage.p.glass) } }
                            Row2 { label: pwPage.t("Glass opacity"); sub: Math.round(pwPage.p.glassOpacity * 100) + "%"
                                Slider { width: 260; from: 0.4; to: 1; step: 0.02; value: pwPage.p.glassOpacity; onMoved: v => PwVault.set("glassOpacity", v) } }
                            Row2 { label: pwPage.t("Backdrop strength"); sub: Math.round(pwPage.p.blur * 100) + "% · " + pwPage.t("how much the blurred desktop is dimmed")
                                Slider { width: 260; from: 0; to: 1; step: 0.05; value: pwPage.p.blur; onMoved: v => PwVault.set("blur", v) } }
                            Row2 { label: pwPage.t("Animations")
                                Toggle { on: pwPage.p.animations; onToggled: PwVault.set("animations", !pwPage.p.animations) } }
                            Row2 { label: pwPage.t("Animation speed"); sub: pwPage.p.animSpeed.toFixed(2) + "×"; visible: pwPage.p.animations
                                Slider { width: 260; from: 0.5; to: 2; step: 0.05; value: pwPage.p.animSpeed; onMoved: v => PwVault.set("animSpeed", v) } }
                            Row2 { label: pwPage.t("Reduced motion"); sub: pwPage.t("No scaling or bouncing, just fades")
                                Toggle { on: pwPage.p.reducedMotion; onToggled: PwVault.set("reducedMotion", !pwPage.p.reducedMotion) } }
                            Row2 { label: pwPage.t("Button size")
                                Choice { options: [ { v: "s", t: "Small" }, { v: "m", t: "Medium" }, { v: "l", t: "Large" } ]; value: pwPage.p.buttonSize; onPicked: v => PwVault.set("buttonSize", v) } }
                            Row2 { label: pwPage.t("Saved passwords on the ring"); sub: pwPage.p.maxRadial === 0 ? pwPage.t("None - use Saved") : String(pwPage.p.maxRadial)
                                Slider { width: 260; from: 0; to: 16; step: 1; value: pwPage.p.maxRadial; onMoved: v => PwVault.set("maxRadial", Math.round(v)) } }
                            Row2 { label: pwPage.t("Sound volume"); sub: Math.round(pwPage.p.volume * 100) + "%"
                                Slider { width: 260; from: 0; to: 1; step: 0.05; value: pwPage.p.volume; onMoved: v => PwVault.set("volume", v) } }
                        }
                    }
                    Note { text: pwPage.t("Port of the Windows “Password helper” (C#/WPF). Backend: ~/.config/hypr/scripts/pwhelper.py · shortcut file: ~/.config/hypr/pwhelper.lua") }
                }

                // ── SOUND ───────────────────────────
                Column {
                    visible: st.page === "sound"; width: parent.width; spacing: 12
                    Title { text: st.t("Sound") }
                    Heading { text: st.t("Volume keys") }
                    Card {
                        height: vkCol.implicitHeight + 8
                        Column {
                            id: vkCol; y: 4; width: parent.width
                            Row2 { label: st.t("Step"); sub: st.t("How much one press or one wheel notch changes")
                                Choice { options: [1, 2, 5, 10].map(x => ({ v: x, t: x + "%" })); value: Cfg.data.volStep || 5; onPicked: v => Cfg.set("volStep", v) } }
                            Row2 { label: st.t("Ear protection"); sub: st.t("Keys, bar and wheel never go above") + " " + (Cfg.data.volMax || 100) + "%"
                                Slider { width: 260; from: 40; to: 150; step: 5; value: Cfg.data.volMax || 100; onMoved: v => Cfg.set("volMax", Math.round(v)) } }
                            Row2 { label: st.t("Per-app volume")
                                Btn { text: st.t("Open mixer"); onClicked: { st.shown = false; Quickshell.execDetached(["qs", "ipc", "call", "mixer", "toggle"]); } } }
                        }
                    }

                    Heading { text: st.t("Output") }
                    Card {
                        height: outCol.implicitHeight + 16
                        Column {
                            id: outCol; x: 8; y: 8; width: parent.width - 16; spacing: 6
                            Row2 {
                                label: st.t("Volume")
                                Row {
                                    spacing: 12
                                    Slider {
                                        width: 300; anchors.verticalCenter: parent.verticalCenter
                                        value: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Pipewire.defaultAudioSink.audio.volume : 0
                                        onMoved: v => { if (Pipewire.defaultAudioSink) Pipewire.defaultAudioSink.audio.volume = v; }
                                    }
                                    Text { width: 44; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight
                                        text: Math.round((Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Pipewire.defaultAudioSink.audio.volume : 0) * 100) + "%"
                                        color: st.cFg; font.family: st.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Toggle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        on: !(Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted)
                                        onToggled: if (Pipewire.defaultAudioSink) Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
                                    }
                                }
                            }
                            Rectangle { width: parent.width; height: 1; color: st.cBorder }
                            DeviceList {
                                nodes: st.sinks
                                current: Pipewire.defaultAudioSink
                                onPicked: n => Pipewire.preferredDefaultAudioSink = n
                            }
                        }
                    }

                    Heading { text: st.t("Input (microphone)") }
                    Card {
                        height: inCol.implicitHeight + 16
                        Column {
                            id: inCol; x: 8; y: 8; width: parent.width - 16; spacing: 6
                            Row2 {
                                label: st.t("Mic level")
                                Row {
                                    spacing: 12
                                    Slider {
                                        width: 300; anchors.verticalCenter: parent.verticalCenter
                                        value: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio ? Pipewire.defaultAudioSource.audio.volume : 0
                                        onMoved: v => { if (Pipewire.defaultAudioSource) Pipewire.defaultAudioSource.audio.volume = v; }
                                    }
                                    Text { width: 44; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight
                                        text: Math.round((Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio ? Pipewire.defaultAudioSource.audio.volume : 0) * 100) + "%"
                                        color: st.cFg; font.family: st.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Toggle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        on: !(Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio && Pipewire.defaultAudioSource.audio.muted)
                                        onToggled: if (Pipewire.defaultAudioSource) Pipewire.defaultAudioSource.audio.muted = !Pipewire.defaultAudioSource.audio.muted
                                    }
                                }
                            }
                            Rectangle { width: parent.width; height: 1; color: st.cBorder }
                            DeviceList {
                                nodes: st.sources
                                current: Pipewire.defaultAudioSource
                                onPicked: n => Pipewire.preferredDefaultAudioSource = n
                            }
                        }
                    }
                    Row {
                        spacing: 8
                        Btn { visible: Cfg.has.pavucontrol === true; text: st.t("Advanced mixer"); onClicked: Quickshell.execDetached(["pavucontrol"]) }
                    }
                }

                // ── DISPLAYS ────────────────────────
                Column {
                    visible: st.page === "display"; width: parent.width; spacing: 12
                    Title { text: st.t("Displays") }
                    // arrangement: click a monitor to edit it
                    Rectangle {
                        width: parent.width; height: 170; radius: 18; color: st.cCard; border.width: 1; border.color: st.cBorder
                        Row {
                            anchors.centerIn: parent; spacing: 10
                            Repeater {
                                model: st.monEdit
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    readonly property bool main: modelData.name === Cfg.mainName
                                    width: Math.round(modelData.w / modelData.scale / 14); height: Math.round(modelData.h / modelData.scale / 14)
                                    radius: 10; color: index === st.monSel ? Cfg.acc(0.20) : "#1fffffff"
                                    border.width: index === st.monSel ? 2 : 1; border.color: index === st.monSel ? st.cAccent : st.cBorder
                                    Column { anchors.centerIn: parent; spacing: 2
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: index + 1; color: st.cFg; font.family: st.fUi; font.pixelSize: 28; font.weight: Font.Black }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name + (parent.parent.main ? " · main" : ""); color: st.cMuted; font.family: st.fUi; font.pixelSize: 11 } }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.monSel = index }
                                }
                            }
                        }
                    }
                    Card {
                        visible: st.monEdit.length > 0
                        readonly property var m: st.monEdit[st.monSel] || null
                        height: dCol.implicitHeight + 8
                        Column {
                            id: dCol; y: 4; width: parent.width
                            Row2 { label: parent.parent.m ? parent.parent.m.name : ""; sub: parent.parent.m ? parent.parent.m.desc : ""
                                Row { spacing: 6
                                    Btn { text: "◀"; visible: st.monSel > 0; onClicked: st.moveMon(st.monSel, -1) }
                                    Btn { text: "▶"; visible: st.monSel < st.monEdit.length - 1; onClicked: st.moveMon(st.monSel, 1) }
                                    Btn { readonly property bool isMain: !!dCol.parent.m && dCol.parent.m.name === Cfg.mainName
                                          text: isMain ? st.t("Main monitor") : st.t("Make main"); primary: isMain
                                          onClicked: if (dCol.parent.m) Cfg.set("mainMonitor", dCol.parent.m.name) } } }
                            Row2 { label: st.t("Resolution")
                                Flow { width: 420; spacing: 6; layoutDirection: Qt.RightToLeft
                                    Repeater {
                                        model: { const m = dCol.parent.m; if (!m) return []; const seen = {}; return m.modes.filter(x => { const k = x.w + "x" + x.h; if (seen[k]) return false; seen[k] = true; return true; }).slice(0, 8); }
                                        delegate: Btn { required property var modelData; text: modelData.w + "×" + modelData.h
                                            primary: dCol.parent.m.w === modelData.w && dCol.parent.m.h === modelData.h
                                            onClicked: { const m = dCol.parent.m; const r = m.modes.filter(x => x.w === modelData.w && x.h === modelData.h).map(x => x.rate);
                                                         st.editMon(st.monSel, { w: modelData.w, h: modelData.h, rate: Math.max.apply(null, r) }); } } } } }
                            Row2 { label: st.t("Refresh rate")
                                Flow { width: 420; spacing: 6; layoutDirection: Qt.RightToLeft
                                    Repeater {
                                        model: { const m = dCol.parent.m; if (!m) return []; return m.modes.filter(x => x.w === m.w && x.h === m.h).map(x => x.rate).filter((r, i, a) => a.indexOf(r) === i).sort((a, b) => b - a); }
                                        delegate: Btn { required property var modelData; text: modelData + " Hz"; primary: dCol.parent.m.rate === modelData
                                            onClicked: st.editMon(st.monSel, { rate: modelData }) } } } }
                            Row2 { label: st.t("Scale")
                                Choice { options: [ { v: 1, t: "100%" }, { v: 1.25, t: "125%" }, { v: 1.5, t: "150%" }, { v: 2, t: "200%" } ]
                                         value: dCol.parent.m ? dCol.parent.m.scale : 1; onPicked: v => st.editMon(st.monSel, { scale: v }) } }
                        }
                    }
                    Row {
                        spacing: 8
                        Btn { primary: true; text: st.t("Apply"); onClicked: st.applyMonitors() }
                        Btn { text: st.t("Reset"); onClicked: monProc.running = true }
                    }
                    Card {
                        visible: st.keepLeft > 0
                        height: keepRow.height
                        Row2 { id: keepRow; label: st.t("Keep these display settings?"); sub: st.t("Reverting in") + " " + st.keepLeft + " s"
                            Row { spacing: 8
                                Btn { primary: true; text: st.t("Keep"); onClicked: { keepT.stop(); st.keepLeft = 0; } }
                                Btn { text: st.t("Revert"); onClicked: st.revertMonitors() } } }
                    }
                    Note { text: st.t("The main monitor holds the dock, the start menu, desktop widgets and workspaces 1-5.") }
                }

                // ── NETWORK ─────────────────────────
                Column {
                    visible: st.page === "network"; width: parent.width; spacing: 12
                    Title { text: st.t("Network & VPN") }
                    Heading { text: st.t("Connections") }
                    Card {
                        height: netCol.implicitHeight + 16
                        Column {
                            id: netCol; x: 8; y: 8; width: parent.width - 16
                            Repeater {
                                model: st.netInfo === "" ? [] : st.netInfo.split("\n")
                                delegate: Row2 {
                                    required property string modelData
                                    readonly property var f: modelData.split(":")
                                    label: (f[3] && f[3] !== "" && f[3] !== "--") ? f[3] : f[0]
                                    sub: f[0] + " · " + f[1]
                                    Rectangle {
                                        readonly property bool up: f[2] === "connected"
                                        width: stT.implicitWidth + 18; height: 26; radius: 9
                                        color: up ? st.cAccent : "#14ffffff"
                                        Text { id: stT; anchors.centerIn: parent; text: f[2]; color: parent.up ? st.cAccFg : st.cMuted
                                            font.family: st.fUi; font.pixelSize: 11; font.weight: Font.Bold }
                                    }
                                }
                            }
                        }
                    }
                    Btn { visible: Cfg.has["nm-connection-editor"] === true; text: st.t("Edit connections"); onClicked: Quickshell.execDetached(["nm-connection-editor"]) }

                    Heading { visible: Cfg.has.mullvad === true; text: "Mullvad VPN" }
                    Card {
                        visible: Cfg.has.mullvad === true
                        height: vpnRow.height
                        Row2 {
                            id: vpnRow
                            label: st.vpnStatus.startsWith("Connected") ? st.t("Connected") : (st.vpnStatus === "" ? st.t("Mullvad is not running") : st.t("Disconnected"))
                            sub: st.vpnStatus.split("\n").slice(1).join(" ")
                            Row {
                                spacing: 8
                                Btn {
                                    primary: true
                                    text: st.vpnStatus.startsWith("Connected") ? st.t("Disconnect") : st.t("Connect")
                                    onClicked: { Quickshell.execDetached(["mullvad", st.vpnStatus.startsWith("Connected") ? "disconnect" : "connect"]); vpnRefresh.restart(); }
                                }
                                Btn { text: st.t("Open app"); onClicked: Quickshell.execDetached(["mullvad-vpn"]) }
                            }
                        }
                    }
                    Timer { id: vpnRefresh; interval: 1500; onTriggered: vpnProc.running = true }
                }

                // ── COLOR CONTROL ───────────────────
                Column {
                    visible: st.page === "color"; width: parent.width; spacing: 12
                    Title { text: st.t("Color Control") }
                    Note { text: st.t("Adjust desktop color like the NVIDIA control panel. Changes apply live to every monitor and are kept after reboot.") }
                    Card {
                        height: 96
                        Rectangle {
                            anchors { fill: parent; margins: 14 }
                            radius: 12
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.00; color: "#ff4d4d" }
                                GradientStop { position: 0.17; color: "#ffb84d" }
                                GradientStop { position: 0.33; color: "#f5f55a" }
                                GradientStop { position: 0.50; color: "#5ad67a" }
                                GradientStop { position: 0.67; color: "#5ab8f5" }
                                GradientStop { position: 0.83; color: "#9b6cf0" }
                                GradientStop { position: 1.00; color: "#f2b8d0" }
                            }
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: parent.height / 2; radius: 12
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#000000" }
                                    GradientStop { position: 1.0; color: "#ffffff" }
                                }
                            }
                        }
                    }
                    Heading { text: st.t("Presets") }
                    Flow {
                        width: parent.width; spacing: 8
                        Repeater {
                            model: [
                                { t: "Default", v: 0.0,  c: 0.0,  b: 0.0,   g: 1.0,  w: 0.0 },
                                { t: "Natural+", v: 0.35, c: 0.06, b: 0.0,   g: 1.0,  w: 0.0 },
                                { t: "Vivid",   v: 0.65, c: 0.10, b: 0.0,   g: 1.0,  w: 0.0 },
                                { t: "Gaming",  v: 0.80, c: 0.12, b: 0.02,  g: 1.15, w: 0.0 },
                                { t: "Cinema",  v: 0.20, c: 0.15, b: -0.02, g: 0.95, w: 0.1 },
                                { t: "Night",   v: 0.20, c: 0.0,  b: -0.03, g: 1.0,  w: 0.6 }
                            ]
                            delegate: Btn {
                                required property var modelData
                                text: st.t(modelData.t)
                                primary: Math.abs(st.cfg.vibrance - modelData.v) < 0.01 && Math.abs(st.cfg.contrast - modelData.c) < 0.01 &&
                                         Math.abs((st.cfg.brightness || 0) - modelData.b) < 0.01 && Math.abs((st.cfg.gamma || 1) - modelData.g) < 0.01 &&
                                         Math.abs(st.cfg.warmth - modelData.w) < 0.01
                                onClicked: st.preset(modelData.v, modelData.c, modelData.b, modelData.g, modelData.w)
                            }
                        }
                    }
                    Heading { text: st.t("Adjust") }
                    Card {
                        height: ccCol.implicitHeight + 8
                        Column {
                            id: ccCol; y: 4; width: parent.width
                            Row2 { label: st.t("Digital Vibrance"); sub: Math.round(st.cfg.vibrance * 100) + "%"
                                Slider { width: 300; from: 0; to: 1; step: 0.01; value: st.cfg.vibrance; onMoved: v => st.setCfg("vibrance", v) } }
                            Row2 { label: st.t("Contrast"); sub: (st.cfg.contrast >= 0 ? "+" : "") + Math.round(st.cfg.contrast * 100) + "%"
                                Slider { width: 300; from: -0.3; to: 0.3; step: 0.01; value: st.cfg.contrast; onMoved: v => st.setCfg("contrast", v) } }
                            Row2 { label: st.t("Brightness"); sub: ((st.cfg.brightness || 0) >= 0 ? "+" : "") + Math.round((st.cfg.brightness || 0) * 100) + "%"
                                Slider { width: 300; from: -0.2; to: 0.2; step: 0.01; value: st.cfg.brightness || 0; onMoved: v => st.setCfg("brightness", v) } }
                            Row2 { label: st.t("Gamma"); sub: (st.cfg.gamma || 1).toFixed(2)
                                Slider { width: 300; from: 0.6; to: 1.6; step: 0.01; value: st.cfg.gamma || 1; onMoved: v => st.setCfg("gamma", v) } }
                            Row2 { label: st.t("Night light"); sub: st.cfg.warmth > 0 ? Math.round(st.cfg.warmth * 100) + "%" : st.t("Off")
                                Slider { width: 300; from: 0; to: 1; step: 0.01; value: st.cfg.warmth; onMoved: v => st.setCfg("warmth", v) } }
                        }
                    }
                }

                // ── WALLPAPER ───────────────────────
                Column {
                    visible: st.page === "wallpaper"; width: parent.width; spacing: 12
                    Title { text: st.t("Wallpaper") }
                    ClippingRectangle {
                        width: parent.width; height: width * 9 / 16 * 0.62; radius: 18; color: st.cCard
                        WallThumb { anchors.fill: parent; file: st.wallpaper; size: 900; live: st.shown && st.page === "wallpaper" }
                    }
                    Row {
                        width: parent.width; spacing: 10
                        Heading { text: st.t("Pick a picture"); anchors.verticalCenter: parent.verticalCenter }
                        Item { width: 1; height: 1 }
                        Btn { text: st.t("Open picker"); anchors.verticalCenter: parent.verticalCenter; onClicked: { st.shown = false; Quickshell.execDetached(["qs", "ipc", "call", "wallpicker", "toggle"]); } }
                    }
                    Flow {
                        width: parent.width; spacing: 10
                        Repeater {
                            model: st.page === "wallpaper" ? st.walls : []
                            delegate: ClippingRectangle {
                                required property string modelData
                                width: (pages.width - 30) / 4; height: width * 9 / 16; radius: 12; color: st.cCard
                                border.width: st.wallpaper === modelData ? 3 : 0; border.color: st.cAccent
                                WallThumb { anchors.fill: parent; file: modelData; size: 320 }
                                Text { visible: /\.(mp4|webm|mkv|mov)$/i.test(modelData); anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                                       text: "\uf04b"; color: "#ffffff"; font.family: st.fIcon; font.pixelSize: 13; style: Text.Outline; styleColor: "#80000000" }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.setWallpaper(modelData) }
                            }
                        }
                    }
                    Note { text: st.t("Put your pictures into ~/Pictures/Wallpapers to see them here.") }
                    Card {
                        height: wpCol.implicitHeight + 8
                        Column {
                            id: wpCol; y: 4; width: parent.width
                            Row2 { label: st.t("Folder"); sub: st.t("Where the picker and the random wallpaper look first")
                                Field { width: 260; text: Cfg.data.wallDir || "~/Pictures/Wallpapers"; hint: "~/Pictures/Wallpapers"
                                        onAccepted: { Cfg.set("wallDir", text.trim() || "~/Pictures/Wallpapers"); wallProc.running = true; } } }
                            Row2 { label: st.t("Transition")
                                Choice { options: [ { v: "grow", t: "Grow" }, { v: "fade", t: "Fade" }, { v: "wipe", t: "Wipe" }, { v: "wave", t: "Wave" }, { v: "outer", t: "Outer" }, { v: "none", t: "None" } ]
                                         value: Cfg.data.wallTransition || "grow"; onPicked: v => Cfg.set("wallTransition", v) } }
                            Row2 { label: st.t("Transition length"); sub: (Cfg.data.wallDuration || 1.2).toFixed(1) + " s"
                                Slider { width: 260; from: 0.3; to: 3; step: 0.1; value: Cfg.data.wallDuration || 1.2; onMoved: v => Cfg.set("wallDuration", Math.round(v * 10) / 10) } }
                            Row2 { label: st.t("Fill")
                                Choice { options: [ { v: "crop", t: "Crop" }, { v: "fit", t: "Fit" } ]
                                         value: Cfg.data.wallFill || "crop"; onPicked: v => { Cfg.set("wallFill", v); fillT.restart(); } } }
                            Row2 { label: st.t("Change by itself"); sub: st.t("A random wallpaper from the folder every so often")
                                Choice { options: [ { v: 0, t: "Off" }, { v: 15, t: "15 min" }, { v: 30, t: "30 min" }, { v: 60, t: "1 h" }, { v: 180, t: "3 h" } ]
                                         value: Cfg.data.wallShuffle || 0; onPicked: v => Cfg.set("wallShuffle", v) } }
                            Row2 { label: st.t("Video wallpapers"); sub: st.t("Play videos; off = a still frame")
                                Toggle { on: Cfg.data.wallVideo !== false; onToggled: Cfg.set("wallVideo", !(Cfg.data.wallVideo !== false)) } }
                            Row2 { label: st.t("Pause the video"); sub: st.t("It holds the frame; covered = windows fill the screen")
                                Choice { options: [ { v: "covered", t: "When covered" }, { v: "fullscreen", t: "Only fullscreen" }, { v: "never", t: "Never" } ]
                                         value: Cfg.data.videoPause || (Cfg.data.wallPause === false ? "never" : "covered"); onPicked: v => Cfg.set("videoPause", v) } }
                            Row2 { label: st.t("Color from wallpaper"); sub: st.t("Pick a matching color from your current wallpaper")
                                Toggle { on: Cfg.data.accentAuto === true
                                         onToggled: { const on = !(Cfg.data.accentAuto === true); Cfg.set("accentAuto", on); if (on) st.accentProc("auto"); } } }
                        }
                    }
                    // re-show the wallpaper with the new fill once settings.json has it
                    Timer { id: fillT; interval: 600; onTriggered: Quickshell.execDetached([st.scripts + "/wallpaper.sh", "show", st.wallpaper]) }
                }

                // ── APPEARANCE ──────────────────────
                Column {
                    visible: st.page === "appearance"; width: parent.width; spacing: 12
                    Title { text: st.t("Appearance") }
                    Heading { text: st.t("Accent color") }
                    Card {
                        height: acCol.implicitHeight + 8
                        Column {
                            id: acCol; y: 4; width: parent.width
                            Row2 { label: st.t("Color"); sub: st.t("Menus, bar, dock, window borders, terminal, lock screen")
                                Row { spacing: 8
                                    Repeater {
                                        model: [ "#f2b8d0", "#c8b6ff", "#a8e6cf", "#9fd8ff", "#ffcfa8", "#ffe59e", "#ff9fae", "#e8e8f0" ]
                                        Rectangle {
                                            required property string modelData
                                            width: 30; height: 30; radius: 15; color: modelData
                                            border.width: String(Cfg.accent) === modelData ? 3 : 1
                                            border.color: String(Cfg.accent) === modelData ? "#ffffff" : st.cBorder
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.setAccent(modelData) }
                                        }
                                    }
                                } }
                            Row2 { label: st.t("Custom color")
                                Item {
                                    width: 300; height: 24
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 10; radius: 5
                                        gradient: Gradient { orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0;  color: "#ffa8a8" } GradientStop { position: 0.17; color: "#ffe9a8" }
                                            GradientStop { position: 0.33; color: "#bfffa8" } GradientStop { position: 0.5;  color: "#a8fff0" }
                                            GradientStop { position: 0.67; color: "#a8c6ff" } GradientStop { position: 0.83; color: "#e9a8ff" }
                                            GradientStop { position: 1.0;  color: "#ffa8c8" } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        function hex(h) { const c = Qt.hsla(Math.max(0, Math.min(0.999, h)), 0.75, 0.82, 1); const x = n => ("0" + Math.round(n * 255).toString(16)).slice(-2); return "#" + x(c.r) + x(c.g) + x(c.b); }
                                        onPressed: m => st.previewAccent = hex(m.x / width)
                                        onPositionChanged: m => { if (pressed) st.previewAccent = hex(m.x / width); }
                                        onReleased: { st.setAccent(st.previewAccent); }
                                    }
                                } }
                            Row2 { label: st.t("From the wallpaper"); sub: st.t("Pick a matching color from your current wallpaper")
                                Row { spacing: 10
                                    Btn { text: st.t("Pick now"); onClicked: { Cfg.set("accentAuto", false); st.accentProc("auto"); } }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: st.t("Follow wallpaper"); color: st.cMuted; font.family: st.fUi; font.pixelSize: 12 }
                                    Toggle { anchors.verticalCenter: parent.verticalCenter; on: Cfg.data.accentAuto === true
                                             onToggled: { const on = !(Cfg.data.accentAuto === true); Cfg.set("accentAuto", on); if (on) st.accentProc("auto"); } }
                                } }
                        }
                    }
                    Heading { text: st.t("Effects") }
                    Card {
                        height: fxCol.implicitHeight + 8
                        Column {
                            id: fxCol; y: 4; width: parent.width
                            Row2 { label: st.t("Blur"); sub: st.t("Frosted glass behind panels, menus and transparent windows")
                                Toggle { on: st.cfg.blur; onToggled: st.setCfg("blur", !st.cfg.blur) } }
                            Row2 { label: st.t("Animations"); sub: st.t("Window, menu and workspace animations")
                                Toggle { on: st.cfg.animations; onToggled: st.setCfg("animations", !st.cfg.animations) } }
                            Row2 { label: st.t("Jelly windows"); sub: st.t("Windows wobble like jelly while you drag them")
                                Toggle { on: st.cfg.wobble === true; onToggled: st.setCfg("wobble", !(st.cfg.wobble === true)) } }
                            Row2 { label: st.t("Jelly style"); visible: st.cfg.wobble === true
                                Choice { options: [ { v: "soft", t: "Soft" }, { v: "jelly", t: "Jelly" }, { v: "firm", t: "Firm" } ]
                                         value: st.cfg.jelly || "jelly"; onPicked: v => st.setCfg("jelly", v) } }
                            Row2 { label: st.t("Dim inactive windows")
                                Toggle { on: st.cfg.dim; onToggled: st.setCfg("dim", !st.cfg.dim) } }
                            Row2 { label: st.t("Inactive window opacity"); sub: Math.round(st.cfg.inactive_opacity * 100) + "%"
                                Slider { width: 260; from: 0.7; to: 1.0; step: 0.01; value: st.cfg.inactive_opacity; onMoved: v => st.setCfg("inactive_opacity", v) } }
                        }
                    }
                    Heading { text: st.t("Accent color in other apps") }
                    Note { text: st.t("Where the accent color is copied to. Off = that app keeps its own colors.") }
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: [ { k: "kitty", t: "Terminal (kitty)" }, { k: "rofi", t: "Launcher (rofi)" }, { k: "hyprlock", t: "hyprlock" }, { k: "waybar", t: "Waybar" } ]
                            Rectangle {
                                required property var modelData
                                readonly property bool on: !(Cfg.data.accentSkip || []).includes(modelData.k)
                                width: atT.implicitWidth + 40; height: 32; radius: 10
                                color: on ? Cfg.acc(0.22) : am2.containsMouse ? st.cHover : "#14ffffff"
                                Row { anchors.centerIn: parent; spacing: 7
                                    Text { text: parent.parent.on ? "\uf00c" : "\uf00d"; font.family: st.fIcon; font.pixelSize: 10; color: parent.parent.on ? st.cAccent : st.cMuted; anchors.verticalCenter: parent.verticalCenter }
                                    Text { id: atT; text: st.t(parent.parent.modelData.t); font.family: st.fUi; font.pixelSize: 12; color: st.cFg; anchors.verticalCenter: parent.verticalCenter } }
                                MouseArea { id: am2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { const l = Cfg.data.accentSkip || [], k = parent.modelData.k; Cfg.set("accentSkip", parent.on ? l.concat([k]) : l.filter(x => x !== k)); } }
                            }
                        }
                    }
                    Heading { text: st.t("Shell") }
                    Card {
                        height: shCol.implicitHeight + 8
                        Column {
                            id: shCol; y: 4; width: parent.width
                            Row2 { label: st.t("Glass opacity"); sub: st.t("Panels, bar, dock and menus") + " · " + Math.round(Cfg.glassAlpha * 100) + "%"
                                Slider { width: 260; from: 0.25; to: 0.9; step: 0.01; value: Cfg.glassAlpha; onMoved: v => Cfg.set("glass", Math.round(v * 100) / 100) } }
                            Row2 { label: st.t("Blur strength"); sub: (st.cfg.blur_size || 8) + " px · " + (st.cfg.blur_passes || 3) + "×"
                                Slider { width: 260; from: 2; to: 16; step: 1; value: st.cfg.blur_size || 8; onMoved: v => st.setCfg("blur_size", Math.round(v)) } }
                            Row2 { label: st.t("Font")
                                Choice { options: [ { v: "Inter", t: "Inter" }, { v: "Adwaita Sans", t: "Adwaita" }, { v: "Noto Sans", t: "Noto" }, { v: "URW Gothic", t: "Gothic" } ]
                                         value: Cfg.fontUi; onPicked: v => Cfg.set("font", v) } }
                            Row2 { label: st.t("Animation speed")
                                Choice { options: [ { v: 0.6, t: "Fast" }, { v: 1.0, t: "Normal" }, { v: 1.6, t: "Slow" } ]
                                         value: Cfg.anim; onPicked: v => Cfg.set("animSpeed", v) } }
                            Row2 { label: st.t("Mascot"); sub: st.t("Peeks out from the right edge now and then. Your own: ~/.config/sakura/mascot.png")
                                Row { spacing: 8
                                    Btn { text: st.t("Show"); onClicked: Quickshell.execDetached(["qs", "ipc", "call", "mascot", "peek"]) }
                                    Toggle { anchors.verticalCenter: parent.verticalCenter; on: Cfg.data.mascot !== false; onToggled: Cfg.set("mascot", !(Cfg.data.mascot !== false)) } } }
                            Row2 { visible: Cfg.data.mascot !== false; label: st.t("How often")
                                Choice { options: [ { v: "rare", t: "Rarely" }, { v: "normal", t: "Sometimes" }, { v: "often", t: "Often" } ]; value: Cfg.data.mascotFreq || "normal"; onPicked: v => Cfg.set("mascotFreq", v) } }
                            Row2 { visible: Cfg.data.mascot !== false; label: st.t("Size"); sub: Math.round((Cfg.data.mascotSize || 1) * 100) + "%"
                                Slider { width: 260; from: 0.6; to: 1.6; step: 0.05; value: Cfg.data.mascotSize || 1; onMoved: v => Cfg.set("mascotSize", Math.round(v * 100) / 100) } }
                            Row2 { visible: Cfg.data.mascot !== false; label: st.t("Edge")
                                Choice { options: [ { v: "right", t: "Right" }, { v: "left", t: "Left" } ]; value: Cfg.data.mascotEdge || "right"; onPicked: v => Cfg.set("mascotEdge", v) } }
                            Row2 { visible: Cfg.data.mascot !== false; label: st.t("Height on the screen"); sub: Math.round((typeof Cfg.data.mascotHeight === "number" ? Cfg.data.mascotHeight : 0.28) * 100) + "%"
                                Slider { width: 260; from: 0.05; to: 0.75; step: 0.01; value: typeof Cfg.data.mascotHeight === "number" ? Cfg.data.mascotHeight : 0.28; onMoved: v => Cfg.set("mascotHeight", Math.round(v * 100) / 100) } }
                            Row2 { visible: Cfg.data.mascot !== false; label: st.t("Reacts to")
                                Flow { width: 420; spacing: 6; layoutDirection: Qt.RightToLeft
                                    Repeater {
                                        model: [ { k: "music", t: "Music" }, { k: "notify", t: "Notifications" }, { k: "wallpaper", t: "Wallpaper" },
                                                 { k: "screenshot", t: "Screenshots" }, { k: "mute", t: "Sound off" }, { k: "timer", t: "Timers" },
                                                 { k: "unlock", t: "Login and unlock" }, { k: "break", t: "Long work" }, { k: "late", t: "Late night" }, { k: "game", t: "After games" },
                                                 { k: "hot", t: "Overheating" }, { k: "disk", t: "Full disk" }, { k: "updates", t: "Updates" } ]
                                        Btn { required property var modelData
                                              readonly property var l: Cfg.data.mascotReact || ["music", "notify", "wallpaper", "screenshot", "mute", "timer", "unlock", "break", "late", "game", "hot", "disk", "updates"]
                                              text: st.t(modelData.t); primary: l.includes(modelData.k)
                                              onClicked: Cfg.set("mascotReact", l.includes(modelData.k) ? l.filter(x => x !== modelData.k) : l.concat([modelData.k])) }
                                    }
                                } }
                            Row2 { visible: Cfg.data.mascot !== false; label: st.t("She also")
                                Flow { width: 420; spacing: 6; layoutDirection: Qt.RightToLeft
                                    Repeater {
                                        model: [ { k: "dance", t: "Dances to music" }, { k: "outfit", t: "Dresses for the weather" }, { k: "sit", t: "Sits on windows" },
                                                 { k: "notes", t: "Leaves notes" }, { k: "friend", t: "Brings a friend" } ]
                                        Btn { required property var modelData
                                              readonly property var l: Cfg.data.mascotExtras || ["dance", "outfit", "sit", "notes", "friend"]
                                              text: st.t(modelData.t); primary: l.includes(modelData.k)
                                              onClicked: Cfg.set("mascotExtras", l.includes(modelData.k) ? l.filter(x => x !== modelData.k) : l.concat([modelData.k])) }
                                    }
                                } }
                            Row2 { visible: Cfg.data.mascot !== false && (Cfg.data.mascotReact || ["break"]).includes("break"); label: st.t("Break reminder after")
                                Choice { options: [ { v: 45, t: "45 min" }, { v: 60, t: "1 h" }, { v: 90, t: "1.5 h" }, { v: 120, t: "2 h" } ]; value: Cfg.data.mascotBreak || 90; onPicked: v => Cfg.set("mascotBreak", v) } }
                            Row2 { visible: Cfg.data.mascot !== false; label: st.t("Can be caught and thrown"); sub: st.t("Hold her and drag, let go with a flick")
                                Toggle { on: Cfg.data.mascotThrow !== false; onToggled: Cfg.set("mascotThrow", !(Cfg.data.mascotThrow !== false)) } }
                            Row2 { visible: Cfg.data.mascot !== false; label: st.t("Chaos mode"); sub: st.t("Now and then she runs along the bottom edge and peeks from any edge or corner")
                                Row { spacing: 8
                                    Btn { text: st.t("Run now"); onClicked: Quickshell.execDetached(["qs", "ipc", "call", "mascot", "chaos"]) }
                                    Toggle { anchors.verticalCenter: parent.verticalCenter; on: Cfg.data.mascotChaos === true; onToggled: Cfg.set("mascotChaos", !(Cfg.data.mascotChaos === true)) } } }
                            Row2 { label: st.t("Animations at login"); sub: st.t("The bar, dock and widgets flow in one after another")
                                Toggle { on: Cfg.data.animLogin !== false; onToggled: Cfg.set("animLogin", !(Cfg.data.animLogin !== false)) } }
                            Row2 { label: st.t("Hello after login"); sub: st.t("Greeting with the time and weather when you sign in")
                                Row { spacing: 8
                                    Btn { text: st.t("Show"); onClicked: Quickshell.execDetached(["qs", "ipc", "call", "greeting", "play"]) }
                                    Toggle { anchors.verticalCenter: parent.verticalCenter; on: Cfg.data.greet !== false; onToggled: Cfg.set("greet", !(Cfg.data.greet !== false)) } } }
                            Row2 { label: ""
                                Btn { text: st.t("Reset look"); onClicked: { Cfg.set("glass", 0.55); Cfg.set("font", "Inter"); Cfg.set("animSpeed", 1.0); st.setCfg("blur_size", 8); } } }
                        }
                    }
                    Heading { text: st.t("Windows") }
                    Card {
                        height: winCol.implicitHeight + 8
                        Column {
                            id: winCol; y: 4; width: parent.width
                            Row2 { label: st.t("Corner rounding"); sub: st.cfg.rounding + " px"
                                Slider { width: 260; from: 0; to: 24; step: 1; value: st.cfg.rounding; onMoved: v => st.setCfg("rounding", Math.round(v)) } }
                            Row2 { label: st.t("Gap around windows"); sub: st.cfg.gaps_out + " px"
                                Slider { width: 260; from: 0; to: 40; step: 1; value: st.cfg.gaps_out; onMoved: v => st.setCfg("gaps_out", Math.round(v)) } }
                            Row2 { label: st.t("Gap between windows"); sub: st.cfg.gaps_in + " px"
                                Slider { width: 260; from: 0; to: 20; step: 1; value: st.cfg.gaps_in; onMoved: v => st.setCfg("gaps_in", Math.round(v)) } }
                            Row2 { label: st.t("Border width"); sub: st.cfg.border + " px"
                                Slider { width: 260; from: 0; to: 5; step: 1; value: st.cfg.border; onMoved: v => st.setCfg("border", Math.round(v)) } }
                        }
                    }
                    Row {
                        spacing: 8
                        Btn { visible: Cfg.has["nwg-look"] === true; text: st.t("GTK theme & icons"); onClicked: Quickshell.execDetached(["nwg-look"]) }
                        Btn { text: st.t("Reset to defaults")
                            onClicked: { const c = Object.assign({}, st.cfg, { blur: true, animations: true, dim: true, gaps_in: 6, gaps_out: 14, rounding: 14, border: 2, inactive_opacity: 1.0 });
                                         st.cfg = c; st.applyCfg(); } }
                    }
                }

                // ── DESKTOP WIDGETS ─────────────────
                Column {
                    id: wPage
                    visible: st.page === "widgets"; width: parent.width; spacing: 12
                    Title { text: st.t("Desktop widgets") }
                    // the desktop editor (DesktopWidgets.qml) is the main way; this page mirrors the same settings
                    Card {
                        height: 76
                        Row {
                            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                            spacing: 14
                            Rectangle { width: 40; height: 40; radius: 12; color: Cfg.acc(0.18); anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; text: "\uf009"; font.family: st.fIcon; font.pixelSize: 16; color: st.cAccent } }
                            Column { anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                Text { text: st.t("Edit on the desktop"); color: st.cFg; font.family: st.fUi; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Text { text: st.t("Drag, resize and restyle widgets right where they live"); color: st.cMuted; font.family: st.fUi; font.pixelSize: 12 } }
                        }
                        Btn { anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                              primary: true; text: st.t("Open editor"); onClicked: { st.shown = false; Desk.edit(null); } }
                    }
                    Note { text: st.t("Drag widgets on the preview to move them.") + "  " + st.t("Changes apply right away.") }
                    property string sel: "clock"
                    // which monitor the preview shows (only matters with more than one)
                    property string scr: Cfg.mainName
                    readonly property var scrObj: Quickshell.screens.find(s => s.name === scr) || Cfg.mainScreen
                    Row {
                        visible: Quickshell.screens.length > 1; spacing: 6
                        Repeater {
                            model: Quickshell.screens
                            Rectangle {
                                required property var modelData
                                readonly property bool on: wPage.scrObj === modelData
                                width: scl.implicitWidth + 24; height: 30; radius: 10
                                color: on ? Cfg.acc(0.22) : scm.containsMouse ? st.cHover : "#14ffffff"
                                Text { id: scl; anchors.centerIn: parent; font.family: st.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: parent.on ? st.cAccent : st.cFg
                                       text: parent.modelData.name + (parent.modelData === Cfg.mainScreen ? " · " + st.t("Main") : "") }
                                MouseArea { id: scm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wPage.scr = parent.modelData.name }
                            }
                        }
                    }
                    // preview of the chosen monitor with the real widgets on it, scaled down
                    ClippingRectangle {
                        id: pv
                        readonly property real sw: wPage.scrObj ? wPage.scrObj.width : 1920
                        readonly property real sh: wPage.scrObj ? wPage.scrObj.height : 1080
                        readonly property real k: width / sw
                        width: parent.width; height: Math.round(width * sh / sw); radius: 16; color: "#1fffffff"
                        border.width: 1; border.color: st.cBorder
                        WallThumb { anchors.fill: parent; file: st.wallpaper; size: 900 }

                        // ── snapping: widget edges/centres stick to the screen centre, a margin from the
                        // screen edges, and to the edges/centres of the other widgets (hold Shift = free move)
                        property var guides: []            // [{ v: true = vertical line, p: position in preview px }]
                        readonly property real margin: 70 * k
                        function snap(item, x, y, free) {
                            x = Math.max(0, Math.min(width - item.width, x));
                            y = Math.max(0, Math.min(height - item.height, y));
                            if (free) { guides = []; return Qt.point(x, y); }
                            if (Desk.grid > 0) { const g = Desk.grid * k; guides = []; return Qt.point(Math.round(x / g) * g, Math.round(y / g) * g); }
                            const tx = [0, margin, width / 2, width - margin, width], ty = [0, margin, height / 2, height - margin, height];
                            for (let i = 0; i < wRep.count; i++) {
                                const o = wRep.itemAt(i);
                                if (!o || o === item) continue;
                                tx.push(o.x, o.x + o.width / 2, o.x + o.width);
                                ty.push(o.y, o.y + o.height / 2, o.y + o.height);
                            }
                            const th = 7;   // preview px (~17 real px)
                            function best(pos, size, targets) {
                                let r = null;
                                for (const off of [0, size / 2, size])
                                    for (const t of targets) {
                                        const d = t - (pos + off);
                                        if (Math.abs(d) <= th && (!r || Math.abs(d) < Math.abs(r.d))) r = { d: d, t: t };
                                    }
                                return r;
                            }
                            const bx = best(x, item.width, tx), by = best(y, item.height, ty), g = [];
                            if (bx) { x += bx.d; g.push({ v: true, p: bx.t }); }
                            if (by) { y += by.d; g.push({ v: false, p: by.t }); }
                            guides = g;
                            return Qt.point(x, y);
                        }
                        Repeater {
                            model: pv.guides
                            Rectangle {
                                required property var modelData
                                z: 5; color: st.cAccent; opacity: 0.9
                                x: modelData.v ? Math.round(modelData.p) : 0; y: modelData.v ? 0 : Math.round(modelData.p)
                                width: modelData.v ? 1 : pv.width; height: modelData.v ? pv.height : 1
                            }
                        }
                        Repeater {
                            id: wRep
                            model: st.page === "widgets" ? Cfg.data.widgets.filter(w => w.on && Cfg.widgetScreen(w) === wPage.scrObj) : []
                            delegate: Item {
                                id: wi
                                required property var modelData
                                readonly property real sc: (modelData.scale || 1) * pv.k
                                x: modelData.x * pv.k; y: modelData.y * pv.k
                                width: dwp.implicitWidth * sc; height: dwp.implicitHeight * sc
                                z: wPage.sel === modelData.id ? 2 : 1
                                DeskWidget { id: dwp; kind: wi.modelData.id; style: wi.modelData.style || ""; preview: true; scale: wi.sc; transformOrigin: Item.TopLeft }
                                Rectangle { anchors.fill: parent; anchors.margins: -4; radius: 8; color: wma.moving ? Cfg.acc(0.13) : "transparent"
                                    border.width: wPage.sel === wi.modelData.id || wma.containsMouse ? 2 : 0; border.color: st.cAccent }
                                MouseArea {
                                    id: wma; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; preventStealing: true
                                    property point off
                                    property bool moving: false
                                    cursorShape: moving ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    onPressed: m => { const p = mapToItem(pv, m.x, m.y); off = Qt.point(p.x - wi.x, p.y - wi.y);
                                                      moving = true; wPage.sel = wi.modelData.id; st.dragging = true; }
                                    onPositionChanged: m => {
                                        if (!moving) return;
                                        const p = mapToItem(pv, m.x, m.y);
                                        const r = pv.snap(wi, p.x - off.x, p.y - off.y, (m.modifiers & Qt.ShiftModifier) !== 0);
                                        wi.x = r.x; wi.y = r.y;
                                    }
                                    onReleased: {
                                        moving = false; st.dragging = false; pv.guides = [];
                                        Cfg.setWidget(wi.modelData.id, { x: Math.round(wi.x / pv.k), y: Math.round(wi.y / pv.k) });
                                    }
                                }
                            }
                        }
                    }
                    // quick alignment of the selected widget
                    Row {
                        spacing: 8
                        readonly property var it: { for (let i = 0; i < wRep.count; i++) { const o = wRep.itemAt(i); if (o && o.modelData.id === wPage.sel) return o; } return null; }
                        function put(nx, ny) { if (!it) return; const p = {}; if (nx !== null) p.x = Math.round(nx); if (ny !== null) p.y = Math.round(ny); Cfg.setWidget(wPage.sel, p); }
                        visible: it !== null
                        Text { anchors.verticalCenter: parent.verticalCenter; text: st.t(Cfg.widgetCatalog.find(c => c.id === wPage.sel) ? Cfg.widgetCatalog.find(c => c.id === wPage.sel).name : "") + ":"
                               color: st.cFg; font.family: st.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Btn { text: st.t("Center horizontally"); onClicked: parent.put((pv.sw - parent.it.width / pv.k) / 2, null) }
                        Btn { text: st.t("Center vertically"); onClicked: parent.put(null, (pv.sh - parent.it.height / pv.k) / 2) }
                        Btn { text: st.t("To the left"); onClicked: parent.put(70, null) }
                        Btn { text: st.t("To the right"); onClicked: parent.put(pv.sw - 70 - parent.it.width / pv.k, null) }
                    }
                    Note { text: st.t("Widgets stick to the screen centre, the edges and each other. Hold Shift to move freely.") }
                    Card {
                        height: wlCol.implicitHeight + 8
                        Column {
                            id: wlCol; y: 4; width: parent.width
                            Repeater {
                                model: Cfg.widgetCatalog
                                delegate: Row2 {
                                    id: wr
                                    required property var modelData
                                    readonly property var w: Cfg.widget(modelData.id) || ({ on: false, scale: 1 })
                                    label: st.t(modelData.name)
                                    Row { spacing: 12
                                        Row {
                                            readonly property var styles: Cfg.widgetStyles[wr.modelData.id] || []
                                            visible: wr.w.on && styles.length > 1; spacing: 4; anchors.verticalCenter: parent.verticalCenter
                                            Repeater {
                                                model: parent.styles
                                                Rectangle {
                                                    required property string modelData
                                                    required property int index
                                                    readonly property bool on: (wr.w.style || parent.styles[0]) === modelData
                                                    width: sl.implicitWidth + 18; height: 28; radius: 9
                                                    color: on ? Cfg.acc(0.22) : sm.containsMouse ? st.cHover : "#14ffffff"
                                                    Text { id: sl; anchors.centerIn: parent; text: st.t(Cfg.cap(modelData)); font.family: st.fUi; font.pixelSize: 11; font.weight: Font.DemiBold
                                                           color: parent.on ? st.cAccent : st.cFg }
                                                    MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                                onClicked: Cfg.setWidget(wr.modelData.id, { style: parent.modelData }) }
                                                }
                                            }
                                        }
                                        // which monitor it lives on
                                        Row {
                                            visible: wr.w.on && Quickshell.screens.length > 1; spacing: 4; anchors.verticalCenter: parent.verticalCenter
                                            Repeater {
                                                model: Quickshell.screens
                                                Rectangle {
                                                    required property var modelData
                                                    readonly property bool on: Cfg.widgetScreen(wr.w) === modelData
                                                    width: ml.implicitWidth + 18; height: 28; radius: 9
                                                    color: on ? Cfg.acc(0.22) : mm.containsMouse ? st.cHover : "#14ffffff"
                                                    Text { id: ml; anchors.centerIn: parent; text: parent.modelData.name; font.family: st.fUi; font.pixelSize: 11; font.weight: Font.DemiBold
                                                           color: parent.on ? st.cAccent : st.cFg }
                                                    MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: { const s = parent.modelData;
                                                                     Cfg.placeWidget(wr.modelData.id, s, Math.min(wr.w.x || 96, s.width - 300), Math.min(wr.w.y || 96, s.height - 200));
                                                                     wPage.sel = wr.modelData.id; wPage.scr = s.name; } }
                                                }
                                            }
                                        }
                                        Text { visible: wr.w.on; anchors.verticalCenter: parent.verticalCenter; text: st.t("Size"); color: st.cMuted; font.family: st.fUi; font.pixelSize: 12 }
                                        Slider { visible: wr.w.on; width: 160; anchors.verticalCenter: parent.verticalCenter; from: 0.5; to: 1.6; step: 0.05
                                                 value: wr.w.scale || 1; onMoved: v => Cfg.setWidget(wr.modelData.id, { scale: Math.round(v * 100) / 100 }) }
                                        Toggle { anchors.verticalCenter: parent.verticalCenter; on: wr.w.on
                                                 onToggled: { Cfg.setWidget(wr.modelData.id, { on: !wr.w.on }); wPage.sel = wr.modelData.id; } } }
                                }
                            }
                        }
                    }
                    Card {
                        height: 56
                        Row2 { anchors.verticalCenter: parent.verticalCenter; label: st.t("Grid"); sub: ""
                            Row { spacing: 4
                                Repeater {
                                    model: [0, 16, 32, 48, 64]
                                    Rectangle {
                                        required property int modelData
                                        readonly property bool on: Desk.grid === modelData
                                        width: gt.implicitWidth + 20; height: 30; radius: 10
                                        color: on ? Cfg.acc(0.22) : gm.containsMouse ? st.cHover : "#14ffffff"
                                        Text { id: gt; anchors.centerIn: parent; text: parent.modelData === 0 ? st.t("Off") : parent.modelData + " px"
                                               font.family: st.fUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: parent.on ? st.cAccent : st.cFg }
                                        MouseArea { id: gm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Cfg.set("deskGrid", parent.modelData) }
                                    }
                                }
                            }
                        }
                    }
                    Heading { text: st.t("Visualizer") }
                    Card {
                        height: vzCol.implicitHeight + 8
                        Column {
                            id: vzCol; y: 4; width: parent.width
                            Row2 { label: st.t("Bars"); sub: (Cfg.data.vizBars || 48) + ""
                                Slider { width: 260; from: 16; to: 96; step: 4; value: Cfg.data.vizBars || 48; onMoved: v => Cfg.set("vizBars", Math.round(v)) } }
                            Row2 { label: st.t("Auto sensitivity"); sub: st.t("Keeps the bars in range on quiet and loud songs")
                                Toggle { on: Cfg.data.vizAutosens !== false; onToggled: Cfg.set("vizAutosens", !(Cfg.data.vizAutosens !== false)) } }
                            Row2 { visible: Cfg.data.vizAutosens === false; label: st.t("Sensitivity"); sub: (Cfg.data.vizSens || 100) + "%"
                                Slider { width: 260; from: 20; to: 300; step: 10; value: Cfg.data.vizSens || 100; onMoved: v => Cfg.set("vizSens", Math.round(v)) } }
                            Row2 { label: st.t("Smoothness"); sub: (typeof Cfg.data.vizSmooth === "number" ? Cfg.data.vizSmooth : 70) + "%"
                                Slider { width: 260; from: 0; to: 100; step: 5; value: typeof Cfg.data.vizSmooth === "number" ? Cfg.data.vizSmooth : 70; onMoved: v => Cfg.set("vizSmooth", Math.round(v)) } }
                            Row2 { label: st.t("Soft peaks"); sub: st.t("Neighbouring bars lean on each other (monstercat)")
                                Toggle { on: Cfg.data.vizMonstercat === true; onToggled: Cfg.set("vizMonstercat", !(Cfg.data.vizMonstercat === true)) } }
                            Row2 { label: st.t("Frames per second")
                                Choice { options: [30, 60, 120].map(x => ({ v: x, t: String(x) })); value: Cfg.data.vizFps || 60; onPicked: v => Cfg.set("vizFps", v) } }
                            Row2 { label: st.t("Colors")
                                Choice { options: [ { v: "accent", t: "Accent" }, { v: "rainbow", t: "Rainbow" } ]; value: Cfg.data.vizColor || "accent"; onPicked: v => Cfg.set("vizColor", v) } }
                        }
                    }
                    Btn { text: st.t("Reset positions"); onClicked: Cfg.resetWidgets() }
                }

                // ── START MENU ──────────────────────
                Column {
                    visible: st.page === "menu"; width: parent.width; spacing: 12
                    Title { text: st.t("Start menu"); z: 100; ModHub { id: menuHub } }
                    Note { text: st.t("What the Win key menu shows. The preview updates as you change things.") }
                    Heading { text: st.t("Search") }
                    Card {
                        height: srCol.implicitHeight + 8
                        Column {
                            id: srCol; y: 4; width: parent.width
                            Row2 { label: st.t("Web search with")
                                Choice { options: [ { v: "google", t: "Google" }, { v: "ddg", t: "DuckDuckGo" }, { v: "brave", t: "Brave" }, { v: "yandex", t: "Yandex" }, { v: "youtube", t: "YouTube" } ]
                                         value: Cfg.data.searchEngine || "google"; onPicked: v => Cfg.set("searchEngine", v) } }
                            Row2 { label: st.t("Apps in the results"); sub: (Cfg.data.searchApps || 8) + ""
                                Slider { width: 260; from: 3; to: 15; step: 1; value: Cfg.data.searchApps || 8; onMoved: v => Cfg.set("searchApps", Math.round(v)) } }
                            Row2 { label: st.t("Files"); sub: st.t("Look through your home folder and /mnt")
                                Toggle { on: Cfg.data.searchFiles !== false; onToggled: Cfg.set("searchFiles", !(Cfg.data.searchFiles !== false)) } }
                            Row2 { label: st.t("Commands"); sub: st.t("lock, restart, settings, screenshot…")
                                Toggle { on: Cfg.data.searchCommands !== false; onToggled: Cfg.set("searchCommands", !(Cfg.data.searchCommands !== false)) } }
                            Row2 { label: st.t("Web search at the end")
                                Toggle { on: Cfg.data.searchWeb !== false; onToggled: Cfg.set("searchWeb", !(Cfg.data.searchWeb !== false)) } }
                            Row2 { label: st.t("Prefixes"); sub: st.t("> run a command · ? search the web · / files only · = calculator")
                                Toggle { on: Cfg.data.searchPrefixes !== false; onToggled: Cfg.set("searchPrefixes", !(Cfg.data.searchPrefixes !== false)) } }
                            Row2 { visible: Cfg.data.searchPrefixes !== false; label: st.t("Run commands in the terminal"); sub: st.t("For > : see the output in kitty")
                                Toggle { on: Cfg.data.searchShellTerm === true; onToggled: Cfg.set("searchShellTerm", !(Cfg.data.searchShellTerm === true)) } }
                        }
                    }
                    Row {
                        width: parent.width; spacing: 18
                        // ── live mock of the menu (same layout as shell.qml, real size 700 px), as large as fits:
                        // no wider than the room next to the palettes, no taller than the palettes column (no scrolling to drag)
                        Item {
                            id: mpv
                            readonly property var m: Cfg.data.menu
                            // fits the visible part of the page whole, so it can stay in view while you scroll
                            readonly property real k: Math.min(1, (parent.width - 18 - 280) / 700, Math.max(0.5, (content.height - 32) / Math.max(1, mock.height)))
                            width: 700 * k; height: mock.height * k
                            // sticky: once the page scrolls past its top it rides along (16 px from the top), until the end of the palettes column
                            readonly property real rowTop: pages.y + parent.parent.y + parent.y
                            transform: Translate {
                                y: Math.max(0, Math.min(mpv.parent.height - mpv.height, content.contentY + 16 - mpv.rowTop))
                            }
                            ClippingRectangle {
                                id: mock
                                width: 700; radius: 26; color: "#0f1119"; border.width: 1; border.color: st.cBorder
                                height: mockCol.implicitHeight + 20
                                scale: mpv.k; transformOrigin: Item.TopLeft
                                component MLabel: Text { color: st.cMuted; font.family: st.fUi; font.pixelSize: 11; font.weight: Font.Bold
                                                         font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2; leftPadding: 4 }
                                Column {
                                    id: mockCol; width: parent.width
                                    // header: the wallpaper fading into the glass, user, Settings + power, search
                                    Item {
                                        id: mHead
                                        width: parent.width; height: mpv.m.banner ? 168 : 128
                                        Item { id: mArt; anchors.fill: parent; visible: false; layer.enabled: mpv.m.banner
                                            WallThumb { anchors.fill: parent; visible: mpv.m.banner; file: st.wallpaper; size: 900 } }
                                        Rectangle { id: mFade; anchors.fill: parent; visible: false; layer.enabled: mpv.m.banner
                                            gradient: Gradient { GradientStop { position: 0; color: "#ffffffff" } GradientStop { position: 0.25; color: "#ffffffff" } GradientStop { position: 1; color: "#00ffffff" } } }
                                        MultiEffect { anchors.fill: parent; visible: mpv.m.banner; source: mArt; maskEnabled: true; maskSource: mFade; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                        Rectangle { visible: mpv.m.banner; width: parent.width; height: 76
                                            gradient: Gradient { GradientStop { position: 0; color: "#800f1119" } GradientStop { position: 1; color: "#000f1119" } } }
                                        Row { id: mWho; visible: mpv.m.user; x: 20; y: 18; spacing: 12
                                            Avatar { width: 40; height: 40; ringColor: st.cAccent }
                                            Column { anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                                Text { text: Quickshell.env("USER"); color: st.cFg; font.family: st.fUi; font.pixelSize: 15; font.weight: Font.Bold }
                                                Text { text: st.t("up") + " 1 " + st.t("h"); color: Qt.rgba(1, 1, 1, 0.62); font.family: st.fUi; font.pixelSize: 11 } } }
                                        // power buttons: drag to reorder, × to remove, add from the palette
                                        Rectangle {
                                            id: mPw
                                            anchors { right: parent.right; rightMargin: 20 } y: 16
                                            width: pwSlot.width + 8; height: 44; radius: 14; color: "#4d0f1119"; border.width: 1; border.color: st.cBorder
                                            DropSlot {
                                                id: pwSlot
                                                anchors.centerIn: parent
                                                hub: menuHub; spacing: 2; width: Math.max(rowWidth, 60); height: 36
                                                catalog: Cfg.powerCatalog; value: Cfg.list(mpv.m.powerList, []).filter(id => Cfg.powerCatalog.some(c => c.id === id))
                                                onChanged: v => Cfg.setMenu("powerList", v)
                                                chip: Component { Rectangle {
                                                    id: pwc
                                                    property string mid: ""; property var slot: null
                                                    width: 36; height: 36; radius: 11
                                                    color: pwa.containsMouse ? Cfg.acc(0.22) : "transparent"
                                                    opacity: menuHub.dragId === mid && menuHub.dragSlot === slot ? 0.25 : 1
                                                    Text { anchors.centerIn: parent; text: (Cfg.powerCatalog.find(x => x.id === pwc.mid) || { icon: "" }).icon
                                                           font.family: st.fIcon; font.pixelSize: 14; color: pwa.containsMouse ? st.cAccent : st.cFg }
                                                    DragArea { id: pwa; anchors.fill: parent; hub: menuHub; slot: pwc.slot; mid: pwc.mid }
                                                    ChipX { hub: menuHub; slot: pwc.slot; mid: pwc.mid; show: pwa.containsMouse; size: 24 }
                                                } }
                                            }
                                        }
                                        Rectangle { anchors { right: mPw.left; rightMargin: 8; verticalCenter: mPw.verticalCenter } width: 44; height: 44; radius: 14
                                            color: "#4d0f1119"; border.width: 1; border.color: st.cBorder
                                            Text { anchors.centerIn: parent; text: ""; font.family: st.fIcon; font.pixelSize: 16; color: st.cFg } }
                                        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 20; rightMargin: 20 } height: 46; radius: 14; color: "#99141720"; border.width: 1; border.color: st.cBorder
                                            Rectangle { anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter } width: 98; height: 32; radius: 10; color: Cfg.acc(0.12)
                                                Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: st.t("All apps"); color: st.cAccent; font.family: st.fUi; font.pixelSize: 12; font.weight: Font.DemiBold }
                                                Text { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } text: ""; color: st.cAccent; font.family: st.fIcon; font.pixelSize: 9 } }
                                            Text { anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter } text: "  " + st.t("Search apps, files, 2+2, 1000 jpy to usd…"); color: st.cMuted; font.family: st.fUi; font.pixelSize: 15 } }
                                    }
                                    Column {
                                        x: 20; width: parent.width - 40; spacing: 16; topPadding: 16
                                        MLabel { visible: mpv.m.pinned; text: st.t("Pinned") }
                                        Grid {
                                            visible: mpv.m.pinned; columns: 6; columnSpacing: 4; rowSpacing: 4
                                            Repeater {
                                                model: st.menuPins.map(id => DesktopEntries.byId(id)).filter(e => e).slice(0, 6 * (mpv.m.pinnedRows || 2))
                                                Column { required property var modelData; width: 106; height: 84; spacing: 7; topPadding: 15
                                                    IconImage { anchors.horizontalCenter: parent.horizontalCenter; implicitSize: 38; source: Quickshell.iconPath(modelData.icon, "application-x-executable") }
                                                    Text { anchors.horizontalCenter: parent.horizontalCenter; width: 92; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                                           text: modelData.name; color: st.cFg; font.family: st.fUi; font.pixelSize: 11 } }
                                            }
                                        }
                                        // volume + quick toggles: one card, like the menu
                                        Rectangle {
                                            visible: mpv.m.volume || mpv.m.toggles
                                            width: parent.width; height: mCtl.implicitHeight + 20; radius: 18; color: "#14ffffff"; border.width: 1; border.color: "#0affffff"
                                        Column {
                                            id: mCtl; x: 10; y: 10; width: parent.width - 20; spacing: 10
                                        Item { visible: mpv.m.volume; width: parent.width; height: 40
                                            Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: ""; font.family: st.fIcon; font.pixelSize: 17; color: st.cAccent }
                                            Rectangle { x: 46; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 146; height: 6; radius: 3; color: "#26ffffff"
                                                Rectangle { width: parent.width * 0.6; height: 6; radius: 3; color: st.cAccent }
                                                Rectangle { x: parent.width * 0.6 - 8; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: "#ffffff" } }
                                            Text { anchors { right: parent.right; rightMargin: 46; verticalCenter: parent.verticalCenter } text: "60%"
                                                   color: st.cFg; font.family: st.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                                            Text { anchors { right: parent.right; rightMargin: 11; verticalCenter: parent.verticalCenter } text: ""
                                                   font.family: st.fIcon; font.pixelSize: 15; color: st.cFg } }
                                        DropSlot {
                                            id: tgSlot
                                            visible: mpv.m.toggles; hub: menuHub; width: 640; spacing: 8; max: 6
                                            height: Math.max(implicitHeight, 64)
                                            catalog: Cfg.toggleCatalog; value: Cfg.list(mpv.m.toggleList, []).filter(id => Cfg.toggleCatalog.some(c => c.id === id && Cfg.available(c)))
                                            onChanged: v => Cfg.setMenu("toggleList", v.slice(0, 6))
                                            chip: Component { Rectangle {
                                                id: tgc
                                                property string mid: ""; property var slot: null
                                                readonly property var c: Cfg.toggleCatalog.find(x => x.id === mid) || { icon: "", name: mid }
                                                width: (640 - (tgSlot.value.length - 1) * 8) / Math.max(1, tgSlot.value.length); height: 64; radius: 14
                                                color: tga.containsMouse ? Cfg.acc(0.22) : "#0dffffff"
                                                opacity: menuHub.dragId === mid && menuHub.dragSlot === slot ? 0.25 : 1
                                                Column { anchors.centerIn: parent; spacing: 6
                                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tgc.c.icon; font.family: st.fIcon; font.pixelSize: 18; color: tga.containsMouse ? st.cAccent : st.cFg }
                                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: st.t(tgc.c.name); font.family: st.fUi; font.pixelSize: 11; color: st.cFg } }
                                                DragArea { id: tga; anchors.fill: parent; hub: menuHub; slot: tgc.slot; mid: tgc.mid }
                                                ChipX { hub: menuHub; slot: tgc.slot; mid: tgc.mid; show: tga.containsMouse; size: 28 }
                                            } }
                                        }
                                        }   // mCtl
                                        }   // controls card
                                        MLabel { visible: mpv.m.shortcuts && mpv.m.shortcutList.length > 0; text: st.t("Settings") }
                                        DropSlot {
                                            id: scSlot
                                            visible: mpv.m.shortcuts; hub: menuHub; width: 660; spacing: 8
                                            height: Math.max(implicitHeight, 42)
                                            catalog: Cfg.shortcutCatalog; value: Cfg.list(mpv.m.shortcutList, []).filter(id => Cfg.shortcutCatalog.some(c => c.id === id))
                                            onChanged: v => Cfg.setMenu("shortcutList", v)
                                            chip: Component { Rectangle {
                                                id: scc
                                                property string mid: ""; property var slot: null
                                                readonly property var c: Cfg.shortcutCatalog.find(x => x.id === mid) || { icon: "", name: mid }
                                                width: 214; height: 42; radius: 12
                                                color: sca.containsMouse ? Cfg.acc(0.22) : "#0dffffff"
                                                opacity: menuHub.dragId === mid && menuHub.dragSlot === slot ? 0.25 : 1
                                                Row { x: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                                    Rectangle { width: 30; height: 30; radius: 9; color: Cfg.acc(0.13)
                                                        Text { anchors.centerIn: parent; text: scc.c.icon; font.family: st.fIcon; font.pixelSize: 13; color: st.cAccent } }
                                                    Text { anchors.verticalCenter: parent.verticalCenter; width: 160; elide: Text.ElideRight
                                                           text: st.t(scc.c.name); font.family: st.fUi; font.pixelSize: 13; color: st.cFg } }
                                                DragArea { id: sca; anchors.fill: parent; hub: menuHub; slot: scc.slot; mid: scc.mid }
                                                ChipX { hub: menuHub; slot: scc.slot; mid: scc.mid; show: sca.containsMouse; size: 28 }
                                            } }
                                        }
                                        Rectangle { visible: mpv.m.media; width: parent.width; height: 64; radius: 18; color: "#14ffffff"; border.width: 1; border.color: "#0affffff"
                                            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "   " + st.t("Media player"); font.family: st.fUi; font.pixelSize: 13; color: st.cFg } }
                                    }
                                }
                            }
                        }
                        // ── controls
                        Column {
                            id: menuCtl
                            width: 280; spacing: 10
                            Heading { text: st.t("Quick toggles") }
                            ModPalette { width: parent.width; hub: menuHub; slots: [tgSlot] }
                            Heading { text: st.t("Settings shortcuts") }
                            ModPalette { width: parent.width; hub: menuHub; slots: [scSlot] }
                            Heading { text: st.t("Power buttons") }
                            ModPalette { width: parent.width; hub: menuHub; slots: [pwSlot] }
                            Heading { text: st.t("Sections") }
                            Card {
                                height: secCol.implicitHeight + 8
                                Column {
                                    id: secCol; y: 4; width: parent.width
                                    Repeater {
                                        model: [ { k: "banner", t: "Banner" }, { k: "pinned", t: "Pinned apps" }, { k: "volume", t: "Volume slider" },
                                                 { k: "toggles", t: "Quick toggles" }, { k: "shortcuts", t: "Settings shortcuts" }, { k: "media", t: "Media player" }, { k: "user", t: "User" } ]
                                        delegate: Item {
                                            required property var modelData
                                            width: secCol.width; height: 40
                                            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: st.t(modelData.t); color: st.cFg; font.family: st.fUi; font.pixelSize: 13 }
                                            Toggle { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                                     on: Cfg.data.menu[modelData.k] !== false; onToggled: Cfg.setMenu(modelData.k, !(Cfg.data.menu[modelData.k] !== false)) }
                                        }
                                    }
                                    Item {
                                        width: secCol.width; height: 44
                                        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: st.t("Rows of pinned apps"); color: st.cFg; font.family: st.fUi; font.pixelSize: 13 }
                                        Choice { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                                 options: [ { v: 1, t: "1" }, { v: 2, t: "2" }, { v: 3, t: "3" } ]; value: Cfg.data.menu.pinnedRows || 2
                                                 onPicked: v => Cfg.setMenu("pinnedRows", v) }
                                    }
                                }
                            }
                            Row { spacing: 8; topPadding: 6
                                Btn { primary: true; text: st.t("Open the menu"); onClicked: Quickshell.execDetached(["qs", "ipc", "call", "menu", "open"]) }
                                Btn { text: st.t("Reset"); onClicked: Cfg.set("menu", Cfg.defaults().menu) } }
                        }
                    }
                }

                // ── TASKBAR ─────────────────────────
                Column {
                    visible: st.page === "taskbar"; width: parent.width; spacing: 12
                    Title { text: st.t("Taskbar") }
                    Card {
                        height: tbCol.implicitHeight + 8
                        Column {
                            id: tbCol; y: 4; width: parent.width
                            Row2 { label: st.t("Bar position"); sub: st.t("At the bottom the bar splits into two pills next to the dock")
                                Choice { options: [ { v: "top", t: "Top" }, { v: "bottom", t: "Bottom" } ]; value: st.barpos
                                         onPicked: v => Quickshell.execDetached([st.scripts + "/barpos.sh", v]) } }
                            Row2 { label: st.t("24-hour clock")
                                Toggle { on: Cfg.data.clock24 !== false; onToggled: { Cfg.set("clock24", !(Cfg.data.clock24 !== false)); barRestart.restart(); } } }
                            Row2 { label: st.t("Show seconds")
                                Toggle { on: Cfg.data.seconds === true; onToggled: { Cfg.set("seconds", !(Cfg.data.seconds === true)); barRestart.restart(); } } }
                            Row2 { label: st.t("Tray icons"); sub: st.t("Choose which icons sit on the bar and which hide behind ^ (or right-click an icon)")
                                Btn { text: st.t("Change"); onClicked: Quickshell.execDetached(["qs", "ipc", "call", "tray", "edit"]) } }
                            Row2 { label: st.t("Wings")
                                Choice { options: [ { v: "hover", t: "On hover" }, { v: "always", t: "Always" } ]
                                         value: Cfg.barAlways ? "always" : "hover"; onPicked: v => Cfg.set("barMode", v) } }
                            Row2 { label: st.t("Notch at rest"); sub: st.t("Comet runs along the edge with the hour, tide fills up with the day, rings: day, week, month")
                                Choice { options: [ { v: "plain", t: "Plain" }, { v: "comet", t: "Comet" }, { v: "tide", t: "Tide" }, { v: "rings", t: "Rings" } ]
                                         value: Cfg.data.notchFace || "plain"; onPicked: v => Cfg.set("notchFace", v) } }
                            Row2 { label: st.t("Animation speed")
                                Choice { options: [ { v: 0.6, t: "Fast" }, { v: 1.0, t: "Normal" }, { v: 1.6, t: "Slow" } ]
                                         value: Cfg.anim; onPicked: v => Cfg.set("animSpeed", v) } }
                        }
                    }
                    Card {
                        height: 56
                        Row2 { anchors.verticalCenter: parent.verticalCenter; label: st.t("Mouse wheel on the bar")
                            Choice { options: [ { v: "volume", t: "Volume" }, { v: "workspace", t: "Workspaces" }, { v: "none", t: "Nothing" } ]
                                     value: Cfg.data.barWheel || "volume"; onPicked: v => Cfg.set("barWheel", v) } }
                    }
                    // live activities in the notch (Notch.qml): liveMusic, liveTrack, liveRec, liveTimer, liveShare, liveMic, liveReplay
                    Heading { text: st.t("Live activities") }
                    Card {
                        height: liveCol.implicitHeight + 8
                        Column {
                            id: liveCol; y: 4; width: parent.width
                            Repeater {
                                model: [ { k: "Music", t: "Music", s: "Cover and bars beside the clock" }, { k: "Track", t: "Track change", s: "Title and artist for a moment" },
                                         { k: "Rec", t: "Recording" }, { k: "Timer", t: "Timer and stopwatch" }, { k: "Share", t: "Screen sharing" },
                                         { k: "Mic", t: "Microphone in use", s: "Which app listens" }, { k: "Replay", t: "Instant Replay", s: "It runs all the time" } ]
                                Row2 {
                                    id: liveRow2
                                    required property var modelData
                                    readonly property bool on: modelData.k === "Replay" ? Cfg.data.liveReplay === true : Cfg.data["live" + modelData.k] !== false
                                    label: st.t(modelData.t); sub: modelData.s ? st.t(modelData.s) : ""
                                    Toggle { on: liveRow2.on; onToggled: Cfg.set("live" + liveRow2.modelData.k, !liveRow2.on) }
                                }
                            }
                        }
                    }
                    Heading { text: st.t("Window switcher") }
                    Card {
                        height: swCol.implicitHeight + 8
                        Column {
                            id: swCol; y: 4; width: parent.width
                            Row2 { label: st.t("Look"); sub: "Alt+Tab"
                                Choice { options: [ { v: "previews", t: "Previews" }, { v: "icons", t: "Icons only" } ]
                                         value: Cfg.data.swStyle || "previews"; onPicked: v => Cfg.set("swStyle", v) } }
                            Row2 { label: st.t("Only this monitor"); sub: st.t("Windows of the monitor you are on")
                                Toggle { on: Cfg.data.swThisMonitor === true; onToggled: Cfg.set("swThisMonitor", !(Cfg.data.swThisMonitor === true)) } }
                            Row2 { label: st.t("Minimized windows too")
                                Toggle { on: Cfg.data.swMinimized !== false; onToggled: Cfg.set("swMinimized", !(Cfg.data.swMinimized !== false)) } }
                            Row2 { label: st.t("Window titles")
                                Toggle { on: Cfg.data.swTitles !== false; onToggled: Cfg.set("swTitles", !(Cfg.data.swTitles !== false)) } }
                        }
                    }
                    Heading { text: st.t("Hot corners") }
                    Note { text: st.t("Push the mouse into a corner and hold it there for a moment. Off while a game is fullscreen.") }
                    Card {
                        id: hcCard
                        property string open: ""
                        readonly property var acts: [ { v: "none", t: "Nothing" }, { v: "menu", t: "Start menu" }, { v: "dashboard", t: "Dashboard" }, { v: "notifs", t: "Notifications" },
                                                      { v: "clipboard", t: "Clipboard" }, { v: "wallpaper", t: "Wallpaper" }, { v: "screenshot", t: "Screenshot" },
                                                      { v: "mixer", t: "Sound" }, { v: "notes", t: "Notes" }, { v: "lock", t: "Lock" }, { v: "settings", t: "Settings" },
                                                      { v: "convert", t: "File converter" } ]
                        height: hcCol.implicitHeight + 8
                        Column {
                            id: hcCol; y: 4; width: parent.width
                            Repeater {
                                model: [ { k: "tl", t: "Top left" }, { k: "tr", t: "Top right" }, { k: "bl", t: "Bottom left" }, { k: "br", t: "Bottom right" } ]
                                Column {
                                    required property var modelData
                                    width: hcCol.width
                                    readonly property string cur: (Cfg.data.corners || {})[modelData.k] || "none"
                                    Row2 { label: st.t(parent.modelData.t)
                                        Btn { text: st.t((hcCard.acts.find(a => a.v === parent.parent.parent.cur) || hcCard.acts[0]).t) + "  \u25be"
                                              primary: parent.parent.parent.cur !== "none"
                                              onClicked: hcCard.open = hcCard.open === parent.parent.parent.modelData.k ? "" : parent.parent.parent.modelData.k } }
                                    Flow {
                                        visible: hcCard.open === parent.modelData.k
                                        x: 18; width: parent.width - 36; spacing: 6; bottomPadding: 12
                                        Repeater {
                                            model: hcCard.acts
                                            Btn { required property var modelData; text: st.t(modelData.t); primary: parent.parent.cur === modelData.v
                                                  onClicked: { const c = Object.assign({}, Cfg.data.corners || {}); c[parent.parent.modelData.k] = modelData.v; Cfg.set("corners", c); hcCard.open = ""; } }
                                        }
                                    }
                                }
                            }
                            Note { visible: Object.values(Cfg.data.corners || {}).includes("convert"); x: 18; width: parent.width - 36
                                   text: st.t("File converter: drag files from Dolphin into that corner and drop them on a petal. The screen-edge catchers are off while a corner has it.") }
                            Row2 { label: st.t("Hold for"); sub: (Cfg.data.cornerDelay || 250) + " ms"
                                Slider { width: 260; from: 0; to: 800; step: 50; value: Cfg.data.cornerDelay || 250; onMoved: v => Cfg.set("cornerDelay", Math.round(v)) } }
                        }
                    }
                    Heading { text: st.t("Dock") }
                    Card {
                        height: dkCol.implicitHeight + 8
                        Column {
                            id: dkCol; y: 4; width: parent.width
                            Row2 { label: st.t("Icon size"); sub: (Cfg.data.dockIcon || 38) + " px"
                                Slider { width: 260; from: 28; to: 52; step: 1; value: Cfg.data.dockIcon || 38; onMoved: v => Cfg.set("dockIcon", Math.round(v)) } }
                            Row2 { label: st.t("Grow under the mouse"); sub: (typeof Cfg.data.dockMagnify === "number" ? Cfg.data.dockMagnify : 4) + " px"
                                Slider { width: 260; from: 0; to: 14; step: 1; value: typeof Cfg.data.dockMagnify === "number" ? Cfg.data.dockMagnify : 4; onMoved: v => Cfg.set("dockMagnify", Math.round(v)) } }
                            Row2 { label: st.t("Hide automatically"); sub: st.t("Slides into the bottom edge; comes back under the mouse")
                                Toggle { on: Cfg.data.dockAutoHide === true; onToggled: Cfg.set("dockAutoHide", !(Cfg.data.dockAutoHide === true)) } }
                            Row2 { label: st.t("Running apps marker")
                                Choice { options: [ { v: "line", t: "Line" }, { v: "dots", t: "Dots" }, { v: "none", t: "None" } ]
                                         value: Cfg.data.dockDots || "line"; onPicked: v => Cfg.set("dockDots", v) } }
                            Row2 { label: st.t("Notification badges"); sub: st.t("Number of unread notifications on the app icon")
                                Toggle { on: Cfg.data.dockBadges !== false; onToggled: Cfg.set("dockBadges", !(Cfg.data.dockBadges !== false)) } }
                        }
                    }
                    Heading { text: st.t("Corner island") }
                    Card {
                        height: ciCol.implicitHeight + 8
                        Column {
                            id: ciCol; y: 4; width: parent.width
                            Row2 { label: st.t("Corner island"); sub: st.t("Glass with indicators and buttons in a screen corner, tinted by the wallpaper")
                                Toggle { on: Cfg.data.islandOn !== false; onToggled: Cfg.set("islandOn", !(Cfg.data.islandOn !== false)) } }
                            Row2 { label: st.t("Corner"); visible: Cfg.data.islandOn !== false
                                Choice { options: [ { v: "tl", t: "Top left" }, { v: "tr", t: "Top right" }, { v: "bl", t: "Bottom left" }, { v: "br", t: "Bottom right" } ]
                                         value: Cfg.data.islandCorner || "tr"; onPicked: v => Cfg.set("islandCorner", v) } }
                            Row2 { label: st.t("Monitor"); visible: Cfg.data.islandOn !== false
                                Choice { options: [ { v: "main", t: "Main" }, { v: "second", t: "Second" }, { v: "both", t: "Both" } ]
                                         value: Cfg.data.islandScreen || "main"; onPicked: v => Cfg.set("islandScreen", v) } }
                            Row2 { label: st.t("Size"); visible: Cfg.data.islandOn !== false
                                Choice { options: [ { v: "s", t: "Small" }, { v: "m", t: "Medium" }, { v: "l", t: "Large" } ]
                                         value: Cfg.data.islandSize || "m"; onPicked: v => Cfg.set("islandSize", v) } }
                        }
                    }
                    Heading { text: st.t("Island modules"); visible: Cfg.data.islandOn !== false }
                    ModEditor { visible: Cfg.data.islandOn !== false; width: parent.width; kind: "island"; wallpaper: st.wallpaper }
                    Btn { visible: Cfg.data.islandOn !== false; text: st.t("Reset"); onClicked: Cfg.set("islandItems", Cfg.islandDefault) }
                    Heading { text: st.t("Bar") }
                    ModEditor { width: parent.width; kind: "bar"; wallpaper: st.wallpaper }
                    Btn { text: st.t("Reset"); onClicked: { Cfg.set("barLeft", Cfg.barLeftCatalog.map(c => c.id)); Cfg.set("barRight", Cfg.barRightCatalog.map(c => c.id)); } }
                }

                // ── INPUT ───────────────────────────
                Column {
                    visible: st.page === "input"; width: parent.width; spacing: 12
                    Title { text: st.t("Keyboard & Mouse"); z: 100; ModHub { id: kbHub } }
                    Heading { text: st.t("Keyboard") }
                    Card {
                        height: kbCol.implicitHeight + 8
                        Column {
                            id: kbCol; y: 4; width: parent.width
                            Row2 { label: st.t("Layouts")
                                Column {
                                    width: 420; spacing: 8
                                    DropSlot {
                                        id: kbSlot
                                        anchors.right: parent.right
                                        hub: kbHub; width: Math.min(420, Math.max(rowWidth, 60)); spacing: 6; min: 1; rtl: false
                                        catalog: [ { id: "us", name: "English (US)" }, { id: "gb", name: "English (UK)" }, { id: "ru", name: "Русский" }, { id: "ua", name: "Українська" },
                                                   { id: "by", name: "Беларуская" }, { id: "de", name: "Deutsch" }, { id: "fr", name: "Français" }, { id: "es", name: "Español" },
                                                   { id: "pl", name: "Polski" }, { id: "kz", name: "Қазақ" } ]
                                        value: String(st.cfg.kb_layout || "us").split(",").filter(x => x)
                                        onChanged: v => st.setCfg("kb_layout", (v.length ? v : ["us"]).join(","))
                                        chip: Component { Rectangle {
                                            id: kbc
                                            property string mid: ""; property var slot: null
                                            readonly property bool first: !!slot && slot.value[0] === mid
                                            width: kbt.implicitWidth + 28; height: 34; radius: 11
                                            color: first ? st.cAccent : (kba.containsMouse ? Cfg.acc(0.3) : Cfg.acc(0.16))
                                            opacity: kbHub.dragId === mid && kbHub.dragSlot === slot ? 0.25 : 1
                                            Text { id: kbt; anchors.centerIn: parent; text: kbc.slot ? kbc.slot.nameOf(kbc.mid) : kbc.mid
                                                   color: kbc.first ? st.cAccFg : st.cFg; font.family: st.fUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                                            DragArea { id: kba; anchors.fill: parent; hub: kbHub; slot: kbc.slot; mid: kbc.mid }
                                            ChipX { hub: kbHub; slot: kbc.slot; mid: kbc.mid; show: kba.containsMouse }
                                        } }
                                    }
                                    ModPalette { width: parent.width; hub: kbHub; slots: [kbSlot] }
                                }
                            }
                            Row2 {
                                label: st.t("Switch layout with")
                                Flow { width: 400; spacing: 6; layoutDirection: Qt.RightToLeft
                                    Repeater {
                                        model: [
                                            { v: "grp:alt_shift_toggle", t: "Alt + Shift" },
                                            { v: "grp:win_space_toggle", t: "Win + Space" },
                                            { v: "grp:caps_toggle",      t: "Caps Lock" },
                                            { v: "grp:ctrl_shift_toggle", t: "Ctrl + Shift" }
                                        ]
                                        delegate: Btn { required property var modelData; text: modelData.t; primary: st.cfg.kb_toggle === modelData.v
                                                        onClicked: st.setCfg("kb_toggle", modelData.v) }
                                    }
                                }
                            }
                            Row2 { label: st.t("Repeat delay"); sub: Math.round(st.cfg.repeat_delay || 600) + " ms"
                                Slider { width: 260; from: 150; to: 1000; step: 25; value: st.cfg.repeat_delay || 600; onMoved: v => st.setCfg("repeat_delay", Math.round(v)) } }
                            Row2 { label: st.t("Repeat rate"); sub: Math.round(st.cfg.repeat_rate || 25) + " / s"
                                Slider { width: 260; from: 10; to: 60; step: 1; value: st.cfg.repeat_rate || 25; onMoved: v => st.setCfg("repeat_rate", Math.round(v)) } }
                        }
                    }
                    Heading { text: st.t("Mouse") }
                    Card {
                        height: msCol.implicitHeight + 8
                        Column {
                            id: msCol; y: 4; width: parent.width
                            Row2 { label: st.t("Pointer speed"); sub: (st.cfg.sensitivity > 0 ? "+" : "") + st.cfg.sensitivity.toFixed(2) + "  (0 = default)"
                                Slider { width: 260; from: -1; to: 1; step: 0.05; value: st.cfg.sensitivity; onMoved: v => st.setCfg("sensitivity", v) } }
                            Row2 { label: st.t("Pointer acceleration"); sub: st.t("Off = raw 1:1 movement (good for games)")
                                Toggle { on: st.cfg.accel !== "flat"; onToggled: st.setCfg("accel", st.cfg.accel === "flat" ? "adaptive" : "flat") } }
                            Row2 { label: st.t("Natural scrolling"); sub: st.t("Content follows your fingers, like on a phone")
                                Toggle { on: st.cfg.natural_scroll === true; onToggled: st.setCfg("natural_scroll", !(st.cfg.natural_scroll === true)) } }
                        }
                    }
                    Btn { text: st.t("Show all keybinds"); onClicked: Quickshell.execDetached([st.home + "/.config/hypr/scripts/keybinds.sh"]) }
                }

                // ── TIME & LANGUAGE ─────────────────
                Column {
                    visible: st.page === "time"; width: parent.width; spacing: 12
                    Title { text: st.t("Time & Language") }
                    // live sample
                    Card {
                        height: 90
                        Column { anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter } spacing: 2
                            Text { text: Cfg.timeStr(Desk.now, Cfg.data.seconds === true); color: st.cFg; font.family: "Inter Display"; font.pixelSize: 32; font.weight: Font.Black }
                            Text { text: Cfg.dateLong(Desk.now) + "  ·  " + st.curTz + (Desk.weather ? "  ·  " + Desk.weather.city + " " + Cfg.temp(Desk.weather.current.temperature_2m) : "")
                                   color: st.cMuted; font.family: st.fUi; font.pixelSize: 13 } }
                    }
                    Heading { text: st.t("Language") }
                    Card {
                        height: lgC.implicitHeight + 8
                        Column {
                            id: lgC; y: 4; width: parent.width
                            Row2 { label: st.t("Language"); sub: st.t("Menus, widgets, dates and weather")
                                Choice { options: [ { v: "en", t: "English" }, { v: "ru", t: "Русский" } ]; value: Cfg.lang; onPicked: v => st.setLang(v) } }
                            Row2 { label: st.t("Apply to apps too (after re-login)"); sub: st.t("Sets LANG for every app; no root needed")
                                Toggle { on: Cfg.data.appsLang === true; onToggled: { Cfg.set("appsLang", !(Cfg.data.appsLang === true)); Quickshell.execDetached([st.scripts + "/sakura-locale.sh", Cfg.lang]); saveTimer.restart(); } } }
                        }
                    }
                    Heading { text: st.t("Time") }
                    Card {
                        height: tmC.implicitHeight + 8
                        Column {
                            id: tmC; y: 4; width: parent.width
                            Row2 { label: st.t("24-hour clock")
                                Toggle { on: Cfg.data.clock24 !== false; onToggled: { Cfg.set("clock24", !(Cfg.data.clock24 !== false)); barRestart.restart(); } } }
                            Row2 { label: st.t("Show seconds")
                                Toggle { on: Cfg.data.seconds === true; onToggled: { Cfg.set("seconds", !(Cfg.data.seconds === true)); barRestart.restart(); } } }
                            Row2 { label: st.t("First day of week")
                                Choice { options: [ { v: 1, t: "Monday" }, { v: 0, t: "Sunday" } ]; value: Cfg.data.weekStart === 0 ? 0 : 1; onPicked: v => Cfg.set("weekStart", v) } }
                            Row2 { label: st.t("Temperature")
                                Choice { options: [ { v: "c", t: "°C" }, { v: "f", t: "°F" } ]; value: Cfg.data.units === "f" ? "f" : "c"; onPicked: v => Cfg.set("units", v) } }
                            Row2 { label: st.t("Time zone"); sub: st.curTz + (st.tzSetting ? "  ·  " + st.t("asking for your password…") : "")
                                Field { width: 300; hint: st.t("Search…"); onTextChanged: st.tzQuery = text } }
                            Column {
                                visible: st.tzHits.length > 0; width: parent.width; leftPadding: 8; rightPadding: 8; bottomPadding: 6
                                Repeater { model: st.tzHits
                                    PickRow { required property string modelData; width: tmC.width - 16; text: modelData.replace(/_/g, " "); sel: modelData === st.curTz
                                           onClicked: st.setTz(modelData) } }
                            }
                            Row2 { visible: !!st.loc && !!Desk.weather && !!Desk.weather.timezone && Desk.weather.timezone !== st.curTz
                                   label: st.t("Use the location's time zone"); sub: Desk.weather ? Desk.weather.timezone : ""
                                Btn { text: st.t("Apply"); onClicked: st.setTz(Desk.weather.timezone) } }
                        }
                    }
                    Heading { text: st.t("Location") }
                    Card {
                        height: lcC.implicitHeight + 8
                        Column {
                            id: lcC; y: 4; width: parent.width
                            Row2 { label: st.loc ? st.loc.city : st.t("Detect automatically"); sub: st.t("Used for the weather")
                                Row { spacing: 8
                                    Field { id: geoF; width: 240; hint: st.t("Search city…"); onTextChanged: { st.geoQuery = text; geoT.restart(); } }
                                    Btn { text: ""; onClicked: st.detectLocation() } } }
                            Column {
                                visible: st.geo.length > 0; width: parent.width; leftPadding: 8; rightPadding: 8; bottomPadding: 6
                                Repeater { model: st.geo
                                    PickRow { required property var modelData; width: lcC.width - 16; text: modelData.name + (modelData.admin1 ? ", " + modelData.admin1 : "")
                                           sub: modelData.country || ""; onClicked: { st.setLocation(modelData); geoF.text = ""; } } }
                            }
                        }
                    }
                    Heading { text: st.t("Date") }
                    Card {
                        height: 56
                        Row2 { anchors.verticalCenter: parent.verticalCenter; label: st.t("Date style")
                            Choice { options: [ { v: "long", t: Cfg.cap(Cfg.locale.toString(Desk.now, "dddd, d MMMM")) }, { v: "short", t: Cfg.cap(Cfg.locale.toString(Desk.now, "ddd, d MMM")) },
                                                { v: "numeric", t: Cfg.locale.toString(Desk.now, Cfg.lang === "en" ? "MM/dd/yyyy" : "dd.MM.yyyy") } ]
                                     value: Cfg.data.dateStyle || "long"; onPicked: v => Cfg.set("dateStyle", v) } }
                    }
                    Heading { text: st.t("Weather") }
                    Card {
                        height: 56
                        Row2 { anchors.verticalCenter: parent.verticalCenter; label: st.t("Update every")
                            Choice { options: [10, 20, 30, 60].map(x => ({ v: x, t: x + " " + st.t("min") })); value: Cfg.data.weatherEvery || 20; onPicked: v => Cfg.set("weatherEvery", v) } }
                    }
                    Heading { text: st.t("World clock") }
                    Note { text: st.t("Cities for the World clock widget. Time zone like Europe/Paris or America/Los_Angeles.") }
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: Cfg.worldClocks
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: wcT.implicitWidth + 44; height: 32; radius: 10; color: "#14ffffff"
                                Text { id: wcT; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                       text: parent.modelData.name + "  ·  " + (Desk.timeIn(parent.modelData.tz) ? Cfg.timeStr(Desk.timeIn(parent.modelData.tz), false) : "…")
                                       font.family: st.fUi; font.pixelSize: 12; color: st.cFg }
                                Text { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "\uf00d"; font.family: st.fIcon; font.pixelSize: 10
                                       color: wcx.containsMouse ? st.cAccent : st.cMuted
                                       MouseArea { id: wcx; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                   onClicked: Cfg.set("worldClocks", Cfg.worldClocks.filter((c, i) => i !== parent.parent.index)) } }
                            }
                        }
                    }
                    Row {
                        spacing: 8
                        Field { id: wcTz; width: 240; hint: "Europe/Paris"; icon: "\uf0ac" }
                        Field { id: wcName; width: 160; hint: st.t("Name (optional)") }
                        Btn { text: st.t("Add"); onClicked: {
                            const tz = wcTz.text.trim(); if (!/^[A-Za-z_]+(\/[A-Za-z_\-+0-9]+)+$/.test(tz)) return;
                            const name = wcName.text.trim() || tz.split("/").pop().replace(/_/g, " ");
                            Cfg.set("worldClocks", Cfg.worldClocks.concat([{ tz: tz, name: name }])); wcTz.text = ""; wcName.text = "";
                        } }
                    }
                    Heading { text: st.t("Pomodoro") }
                    Card {
                        height: pmCol.implicitHeight + 8
                        Column {
                            id: pmCol; y: 4; width: parent.width
                            Row2 { label: st.t("Focus"); sub: (Cfg.data.pomoFocus || 25) + " " + st.t("min")
                                Slider { width: 260; from: 10; to: 90; step: 5; value: Cfg.data.pomoFocus || 25; onMoved: v => Cfg.set("pomoFocus", Math.round(v)) } }
                            Row2 { label: st.t("Short break"); sub: (Cfg.data.pomoBreak || 5) + " " + st.t("min")
                                Slider { width: 260; from: 1; to: 20; step: 1; value: Cfg.data.pomoBreak || 5; onMoved: v => Cfg.set("pomoBreak", Math.round(v)) } }
                            Row2 { label: st.t("Long break"); sub: (Cfg.data.pomoLong || 15) + " " + st.t("min")
                                Slider { width: 260; from: 5; to: 45; step: 5; value: Cfg.data.pomoLong || 15; onMoved: v => Cfg.set("pomoLong", Math.round(v)) } }
                            Row2 { label: st.t("Long break after"); sub: (Cfg.data.pomoCycles || 4) + " " + st.t("rounds")
                                Slider { width: 260; from: 2; to: 8; step: 1; value: Cfg.data.pomoCycles || 4; onMoved: v => Cfg.set("pomoCycles", Math.round(v)) } }
                            Row2 { label: Timers.pomo ? st.t(Timers.pomoPhase === "focus" ? "Focus" : "Break") + " · " + Timers.fmt(Timers.tRemain) : st.t("Not running")
                                sub: st.t("Shows in the Timer widget and the dashboard. Each phase starts the next one by itself.")
                                Btn { primary: !Timers.pomo; text: st.t(Timers.pomo ? "Stop" : "Start"); onClicked: { if (Timers.pomo) Timers.pomoStop(); else Timers.pomoStart(); } } }
                            Row2 { label: st.t("Alarm sound"); sub: st.t("Timers and alarms. Pomodoro phases use a shorter soft chime.")
                                Row { spacing: 10
                                    Choice { options: [ { v: "a", t: "Bubbles" }, { v: "b", t: "Deep bubbles" }, { v: "c", t: "Bubbling" } ]
                                             value: Cfg.data.alarmSound || "a"; onPicked: v => { Cfg.set("alarmSound", v); Timers.preview(v); } }
                                    Btn { text: "▶"; onClicked: Timers.preview(Cfg.data.alarmSound || "a") }
                                    Btn { text: "▶ " + st.t("Pomodoro"); onClicked: Timers.preview("pomo") } } }
                            // the picked variant is copied over notify.wav, so sfx.sh / volume / mute keep working unchanged
                            Row2 { label: st.t("Notification sound"); sub: st.t("Plays when a notification arrives. Volume and mute: Notifications > Sounds.")
                                Row { spacing: 10
                                    Choice { options: [ { v: "a", t: "Bup-bip" }, { v: "b", t: "Bubble" }, { v: "c", t: "Deep bubble" } ]
                                             value: Cfg.data.notifySound || "a"
                                             onPicked: v => { Cfg.set("notifySound", v); const d = Quickshell.env("HOME") + "/.local/share/sounds/sakura/";
                                                 Quickshell.execDetached(["sh", "-c", "cp -f \"$1\" \"$2\" && \"$3\" notify", "sh", d + "notify-" + v + ".wav", d + "notify.wav", st.scripts + "/sfx.sh"]); } }
                                    Btn { text: "▶"; onClicked: Quickshell.execDetached([st.scripts + "/sfx.sh", "notify"]) } } }
                        }
                    }
                }

                // ── NOTIFICATIONS ───────────────────
                Column {
                    visible: st.page === "notify"; width: parent.width; spacing: 12
                    Title { text: st.t("Notifications") }
                    Card {
                        height: nfCol.implicitHeight + 8
                        Column {
                            id: nfCol; y: 4; width: parent.width
                            Row2 { label: st.t("Do not disturb"); sub: st.t("Notifications stay silent and only collect in the panel")
                                Toggle { on: Notifs.dnd; onToggled: Notifs.toggleDnd() } }
                            Row2 { label: st.t("System sounds"); sub: st.t("Soft sounds for notifications, screenshots, clips, volume and login")
                                Toggle { on: st.cfg.sounds !== false; onToggled: st.setSounds(!(st.cfg.sounds !== false)) } }
                            Row2 { label: st.t("Notification panel")
                                Row { spacing: 8
                                    Btn { text: st.t("Open"); onClicked: { st.shown = false; Quickshell.execDetached(["qs", "ipc", "call", "notifs-center", "toggle"]); } }
                                    Btn { text: st.t("Clear all"); onClicked: Notifs.clearAll() } } }
                        }
                    }
                    Heading { text: st.t("Popups") }
                    Card {
                        height: npCol.implicitHeight + 8
                        Column {
                            id: npCol; y: 4; width: parent.width
                            Row2 { label: st.t("Show for"); sub: (Cfg.data.notifTimeout || 6) + " " + st.t("s")
                                Slider { width: 260; from: 2; to: 20; step: 1; value: Cfg.data.notifTimeout || 6; onMoved: v => Cfg.set("notifTimeout", Math.round(v)) } }
                            Row2 { label: st.t("Ignore the app's own time"); sub: st.t("Some apps ask to stay for minutes - use the time above for all")
                                Toggle { on: Cfg.data.ignoreAppTimeout === true; onToggled: Cfg.set("ignoreAppTimeout", !(Cfg.data.ignoreAppTimeout === true)) } }
                            Row2 { label: st.t("Urgent ones stay"); sub: st.t("Critical notifications wait until you close them")
                                Toggle { on: Cfg.data.criticalStay !== false; onToggled: Cfg.set("criticalStay", !(Cfg.data.criticalStay !== false)) } }
                            Row2 { label: st.t("Position")
                                Choice { options: [ { v: "top-right", t: "Top right" }, { v: "top-center", t: "Top" }, { v: "top-left", t: "Top left" }, { v: "bottom-right", t: "Bottom right" } ]
                                         value: Cfg.data.notifPos || "top-right"; onPicked: v => Cfg.set("notifPos", v) } }
                            Row2 { label: st.t("Test"); sub: ""
                                Btn { text: st.t("Send a test notification"); onClicked: Quickshell.execDetached(["notify-send", "-a", "Sakura", "Sakura", st.t("This is how notifications look")]) } }
                        }
                    }
                    Heading { text: st.t("Quiet hours") }
                    Card {
                        height: qhCol.implicitHeight + 8
                        Column {
                            id: qhCol; y: 4; width: parent.width
                            Row2 { label: st.t("Quiet hours"); sub: Notifs.quiet ? st.t("Quiet right now") : st.t("No popups or sounds at night")
                                Toggle { on: Cfg.data.quietHours === true; onToggled: Cfg.set("quietHours", !(Cfg.data.quietHours === true)) } }
                            Row2 { visible: Cfg.data.quietHours === true; label: st.t("From")
                                Choice { options: ["20:00", "21:00", "22:00", "23:00", "00:00"].map(x => ({ v: x, t: x })); value: Cfg.data.quietFrom || "22:00"; onPicked: v => Cfg.set("quietFrom", v) } }
                            Row2 { visible: Cfg.data.quietHours === true; label: st.t("To")
                                Choice { options: ["06:00", "07:00", "08:00", "09:00", "10:00"].map(x => ({ v: x, t: x })); value: Cfg.data.quietTo || "08:00"; onPicked: v => Cfg.set("quietTo", v) } }
                        }
                    }
                    Heading { text: st.t("Muted apps") }
                    Note { text: st.t("Their notifications don't pop up or play a sound, but still land in the panel. Apps appear here after they send something.") }
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: Array.from(new Set((Cfg.data.mutedApps || []).concat(Notifs.seenApps))).filter(x => x)
                            Rectangle {
                                required property string modelData
                                readonly property bool on: (Cfg.data.mutedApps || []).includes(modelData)
                                width: mt.implicitWidth + 40; height: 32; radius: 10
                                color: on ? Cfg.acc(0.22) : mm.containsMouse ? st.cHover : "#14ffffff"
                                Row { anchors.centerIn: parent; spacing: 7
                                    Text { text: parent.parent.on ? "\uf1f6" : "\uf0f3"; font.family: st.fIcon; font.pixelSize: 11; color: parent.parent.on ? st.cAccent : st.cMuted; anchors.verticalCenter: parent.verticalCenter }
                                    Text { id: mt; text: parent.parent.modelData; font.family: st.fUi; font.pixelSize: 12; color: st.cFg; anchors.verticalCenter: parent.verticalCenter } }
                                MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { const l = Cfg.data.mutedApps || []; Cfg.set("mutedApps", parent.on ? l.filter(x => x !== parent.modelData) : l.concat([parent.modelData])); } }
                            }
                        }
                    }
                    Heading { text: st.t("Sounds") }
                    Card {
                        height: sfCol.implicitHeight + 8
                        Column {
                            id: sfCol; y: 4; width: parent.width
                            Row2 { label: st.t("Volume of system sounds"); sub: Math.round((Cfg.data.sfxVolume !== undefined ? Cfg.data.sfxVolume : 0.6) * 100) + "%"
                                Row { spacing: 10
                                    Slider { width: 220; from: 0.1; to: 1.0; step: 0.05; value: Cfg.data.sfxVolume !== undefined ? Cfg.data.sfxVolume : 0.6; onMoved: v => Cfg.set("sfxVolume", Math.round(v * 100) / 100) }
                                    Btn { text: "\u25b6"; onClicked: Quickshell.execDetached([st.scripts + "/sfx.sh", "notify"]) } } }
                            Repeater {
                                model: [ { k: "notify", t: "Notifications" }, { k: "screenshot", t: "Screenshots" }, { k: "volume", t: "Volume change" },
                                         { k: "saved", t: "Saved clip" }, { k: "login", t: "Login" }, { k: "error", t: "Errors" } ]
                                Row2 {
                                    required property var modelData
                                    label: st.t(modelData.t)
                                    Row { spacing: 10
                                        Btn { text: "\u25b6"; onClicked: Quickshell.execDetached(["pw-play", Quickshell.env("HOME") + "/.local/share/sounds/sakura/" + parent.parent.parent.modelData.k + ".wav"]) }
                                        Toggle { anchors.verticalCenter: parent.verticalCenter; on: !(Cfg.data.sfxOff || []).includes(parent.parent.parent.modelData.k)
                                                 onToggled: { const l = Cfg.data.sfxOff || [], k = parent.parent.parent.modelData.k; Cfg.set("sfxOff", l.includes(k) ? l.filter(x => x !== k) : l.concat([k])); } } }
                                }
                            }
                        }
                    }
                    Heading { text: st.t("Volume & brightness popup") }
                    Card {
                        height: 56
                        Row2 { anchors.verticalCenter: parent.verticalCenter; label: st.t("Position")
                            Choice { options: [ { v: "top", t: "Top" }, { v: "center", t: "Center" }, { v: "bottom", t: "Bottom" } ]
                                     value: Cfg.data.osdPos || "bottom"; onPicked: v => { Cfg.set("osdPos", v); osdT.restart(); } } }
                    }
                    Timer { id: osdT; interval: 700; onTriggered: Quickshell.execDetached([st.scripts + "/osd.sh"]) }
                }

                // ── SCREENSHOTS & RECORDING ─────────
                Column {
                    visible: st.page === "capture"; width: parent.width; spacing: 12
                    Title { text: st.t("Screenshots & recording") }
                    Heading { text: st.t("Screenshots") }
                    Card {
                        height: shCol2.implicitHeight + 8
                        Column {
                            id: shCol2; y: 4; width: parent.width
                            Row2 { label: st.t("Folder")
                                Field { width: 260; text: Cfg.data.shotDir || "~/Pictures/Screenshots"; hint: "~/Pictures/Screenshots"; onAccepted: Cfg.set("shotDir", text.trim() || "~/Pictures/Screenshots") } }
                            Row2 { label: st.t("File name")
                                Choice { options: [ { v: "%Y-%m-%d_%H-%M-%S", t: "2026-11-10_09-41-05" }, { v: "Screenshot_%Y%m%d_%H%M%S", t: "Screenshot_20261110…" }, { v: "%s", t: "1794..." } ]
                                         value: Cfg.data.shotName || "%Y-%m-%d_%H-%M-%S"; onPicked: v => Cfg.set("shotName", v) } }
                            Row2 { label: st.t("Freeze the screen while selecting"); sub: st.t("Videos and games stop moving under the selection")
                                Toggle { on: Cfg.data.shotFreeze !== false; onToggled: Cfg.set("shotFreeze", !(Cfg.data.shotFreeze !== false)) } }
                            Row2 { label: st.t("Copy to the clipboard")
                                Toggle { on: Cfg.data.shotCopy !== false; onToggled: Cfg.set("shotCopy", !(Cfg.data.shotCopy !== false)) } }
                            Row2 { label: st.t("Notification")
                                Toggle { on: Cfg.data.shotNotify !== false; onToggled: Cfg.set("shotNotify", !(Cfg.data.shotNotify !== false)) } }
                            Row2 { label: st.t("Screenshot editor"); sub: st.t("Freeze, select, draw, then Enter copies · Ctrl+S saves (HolyScreen style)")
                                Toggle { on: Cfg.data.shotEditor !== false; onToggled: Cfg.set("shotEditor", !(Cfg.data.shotEditor !== false)) } }
                            Row2 { label: st.t("Draw on it right away"); sub: st.t("Without the screenshot editor: open satty after selecting")
                                Toggle { on: Cfg.data.shotEdit === true; onToggled: Cfg.set("shotEdit", !(Cfg.data.shotEdit === true)) } }
                            Row2 { label: ""
                                Row { spacing: 8
                                    Btn { text: st.t("Take one"); onClicked: { st.shown = false; Quickshell.execDetached(["sh", "-c", "sleep 0.5; " + st.scripts + "/screenshot.sh region"]); } }
                                    Btn { text: st.t("Open folder"); onClicked: Quickshell.execDetached(["xdg-open", (Cfg.data.shotDir || "~/Pictures/Screenshots").replace(/^~/, st.home)]) } } }
                        }
                    }
                    Heading { text: st.t("Recording & instant replay") }
                    Note { text: st.t("The same settings as the Alt+Z overlay. Replay restarts with the new settings.") }
                    Card {
                        height: rcCol.implicitHeight + 8
                        Column {
                            id: rcCol; y: 4; width: parent.width
                            Row2 { label: st.t("Folder")
                                Field { width: 260; text: st.capCfg.folder || "~/Videos/Clips"; hint: "~/Videos/Clips"; onAccepted: st.setCap("folder", text.trim() || "~/Videos/Clips") } }
                            Row2 { label: st.t("Frames per second")
                                Choice { options: [30, 60, 120, 144].map(x => ({ v: x, t: String(x) })); value: st.capCfg.fps || 60; onPicked: v => st.setCap("fps", v) } }
                            Row2 { label: st.t("Quality")
                                Choice { options: [ { v: "medium", t: "Medium" }, { v: "high", t: "High" }, { v: "very_high", t: "Very high" }, { v: "ultra", t: "Ultra" } ]
                                         value: st.capCfg.quality || "very_high"; onPicked: v => st.setCap("quality", v) } }
                            Row2 { label: st.t("Sound")
                                Choice { options: [ { v: "none", t: "None" }, { v: "desktop", t: "System" }, { v: "desktop+mic", t: "System + mic" } ]
                                         value: st.capCfg.audio || "desktop"; onPicked: v => st.setCap("audio", v) } }
                            Row2 { label: st.t("Replay length"); sub: Math.round((st.capCfg.replaySeconds || 60) / 60 * 10) / 10 + " " + st.t("min")
                                Slider { width: 260; from: 15; to: 600; step: 15; value: st.capCfg.replaySeconds || 60; onMoved: v => st.setCap("replaySeconds", Math.round(v)) } }
                            Row2 { label: st.t("Replay on at login")
                                Toggle { on: st.capCfg.replayAutostart === true; onToggled: st.setCap("replayAutostart", !(st.capCfg.replayAutostart === true)) } }
                            Row2 { label: ""
                                Btn { text: st.t("Open Capture (Alt+Z)"); onClicked: { st.shown = false; Quickshell.execDetached(["qs", "ipc", "call", "capture", "open"]); } } }
                        }
                    }
                    Heading { text: st.t("Clipboard") }
                    Card {
                        height: cbCol.implicitHeight + 8
                        Column {
                            id: cbCol; y: 4; width: parent.width
                            Row2 { label: st.t("Keep"); sub: st.t("entries in the history")
                                Choice { options: [100, 250, 750, 2000].map(x => ({ v: x, t: String(x) })); value: Cfg.data.clipMax || 750; onPicked: v => { Cfg.set("clipMax", v); clipApply.restart(); } } }
                            Row2 { label: st.t("Pictures too")
                                Toggle { on: Cfg.data.clipImages !== false; onToggled: { Cfg.set("clipImages", !(Cfg.data.clipImages !== false)); clipApply.restart(); } } }
                            Row2 { label: st.t("Skip passwords"); sub: st.t("Copies from password managers don't go into the history")
                                Toggle { on: Cfg.data.clipSkipSecret !== false; onToggled: { Cfg.set("clipSkipSecret", !(Cfg.data.clipSkipSecret !== false)); clipApply.restart(); } } }
                            Row2 { label: st.t("Start each session empty")
                                Toggle { on: Cfg.data.clipWipeLogin === true; onToggled: Cfg.set("clipWipeLogin", !(Cfg.data.clipWipeLogin === true)) } }
                            Row2 { label: ""
                                Row { spacing: 8
                                    Btn { text: st.t("Open (Super+V)"); onClicked: { st.shown = false; Quickshell.execDetached(["qs", "ipc", "call", "clipboard", "toggle"]); } }
                                    Btn { text: st.t("Clear history"); onClicked: Quickshell.execDetached([st.scripts + "/clip.sh", "wipe"]) } } }
                        }
                    }
                }

                // ── STORAGE ─────────────────────────
                Column {
                    visible: st.page === "storage"; width: parent.width; spacing: 12
                    Title { text: st.t("Storage") }
                    Repeater {
                        model: st.disks
                        delegate: Card {
                            required property var modelData
                            readonly property real frac: modelData.size > 0 ? modelData.used / modelData.size : 0
                            height: 92
                            Column {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 20 }
                                spacing: 8
                                Item { width: parent.width; height: 20
                                    Text { text: "  " + modelData.mount; color: st.cFg; font.family: st.fUi; font.pixelSize: 14; font.weight: Font.Bold }
                                    Text { anchors.right: parent.right; text: st.gb(modelData.free) + " " + st.t("free of") + " " + st.gb(modelData.size); color: st.cMuted; font.family: st.fUi; font.pixelSize: 12 } }
                                Rectangle { width: parent.width; height: 10; radius: 5; color: "#26ffffff"
                                    Rectangle { width: parent.width * parent.parent.parent.frac; height: 10; radius: 5; color: parent.parent.parent.frac > 0.9 ? "#ff8a8a" : st.cAccent } }
                                Text { text: modelData.dev + " · " + modelData.type + " · " + Math.round(parent.parent.frac * 100) + "% " + st.t("used"); color: st.cMuted; font.family: st.fUi; font.pixelSize: 11 }
                            }
                        }
                    }
                    Btn { text: st.t("Open file manager"); onClicked: Quickshell.execDetached(["xdg-open", st.home]) }
                }

                // ── DEFAULT APPS ────────────────────
                Column {
                    visible: st.page === "apps"; width: parent.width; spacing: 12
                    Title { text: st.t("Default apps") }
                    Note { text: st.t("Which app opens links and files of each kind.") }
                    Repeater {
                        model: [ { k: "browser", t: "Web browser", i: "" }, { k: "files", t: "File manager", i: "" }, { k: "text", t: "Text editor", i: "" },
                                 { k: "images", t: "Photos", i: "" }, { k: "video", t: "Video player", i: "" }, { k: "music", t: "Music player", i: "" },
                                 { k: "pdf", t: "PDF viewer", i: "" }, { k: "terminal", t: "Terminal", i: "" } ]
                        delegate: Card {
                            id: daC
                            required property var modelData
                            readonly property var info: st.defApps[modelData.k] || ({ current: null, options: [] })
                            readonly property var cur: info.options.find(o => o.id === info.current) || null
                            readonly property bool open: st.defOpen === modelData.k
                            height: daCol.implicitHeight + 8
                            Column {
                                id: daCol; y: 4; width: parent.width
                                Row2 { label: st.t(daC.modelData.t)
                                    Row { spacing: 10
                                        IconImage { visible: !!daC.cur; anchors.verticalCenter: parent.verticalCenter; implicitSize: 22
                                                    source: daC.cur ? Quickshell.iconPath(daC.cur.icon, "application-x-executable") : "" }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: daC.cur ? daC.cur.name : (daC.info.current || st.t("Not set"))
                                               color: daC.cur ? st.cFg : st.cMuted; font.family: st.fUi; font.pixelSize: 13 }
                                        Btn { text: daC.open ? st.t("Done") : st.t("Change"); onClicked: st.defOpen = daC.open ? "" : daC.modelData.k } } }
                                Column {
                                    visible: daC.open; width: parent.width; leftPadding: 8; rightPadding: 8; bottomPadding: 6
                                    Repeater { model: daC.open ? daC.info.options : []
                                        PickRow { required property var modelData; width: daCol.width - 16; text: modelData.name; icon: modelData.icon || ""
                                               sel: modelData.id === daC.info.current
                                               onClicked: { defSet.command = ["python3", "-I", st.scripts + "/default-apps.py", "set", daC.modelData.k, modelData.id]; defSet.running = true; } } }
                                }
                            }
                        }
                    }
                }

                // ── LIGHTING ────────────────────────
                Column {
                    visible: st.page === "lighting"; width: parent.width; spacing: 12
                    Title { text: st.t("Lighting") }
                    Note { text: st.t("RGB on the motherboard and other OpenRGB devices. Changes take a few seconds to reach the hardware.") }
                    Rectangle {
                        width: parent.width; height: 64; radius: 18
                        color: st.rgb.enabled ? "#" + st.rgb.color : "#14ffffff"
                        opacity: st.rgb.enabled ? (0.35 + 0.65 * st.rgb.brightness / 100) : 1
                        border.width: 1; border.color: st.cBorder
                        SequentialAnimation on opacity {
                            running: st.page === "lighting" && st.rgb.enabled && st.rgb.mode === "breathing"; loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 1500; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0;  duration: 1500; easing.type: Easing.InOutSine }
                        }
                        Text { anchors.centerIn: parent; text: st.rgb.enabled ? (st.rgb.mode === "rainbow" ? "Rainbow" : "#" + st.rgb.color.toUpperCase()) : st.t("Off")
                            color: st.rgb.enabled ? "#1a121a" : st.cMuted; font.family: st.fUi; font.pixelSize: 14; font.weight: Font.Bold }
                    }
                    Heading { text: st.t("Color") }
                    Row {
                        spacing: 10
                        Repeater {
                            model: [ { c: "f2b8d0", t: "Sakura" }, { c: "ff4fa3", t: "Hot pink" }, { c: "b9a6ff", t: "Lavender" },
                                     { c: "ffffff", t: "White" }, { c: "9fd8ff", t: "Ice" }, { c: "ffb37a", t: "Warm" } ]
                            delegate: Column {
                                required property var modelData
                                spacing: 4
                                Rectangle {
                                    width: 54; height: 54; radius: 16; color: "#" + modelData.c
                                    border.width: st.rgb.enabled && st.rgb.color === modelData.c ? 3 : 1
                                    border.color: st.rgb.enabled && st.rgb.color === modelData.c ? "#ffffff" : st.cBorder
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { const r = Object.assign({}, st.rgb); r.enabled = true; r.color = modelData.c; if (r.mode === "rainbow") r.mode = "static"; st.rgb = r; rgbTimer.restart(); } }
                                }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.t; color: st.cMuted; font.family: st.fUi; font.pixelSize: 11 }
                            }
                        }
                        Column {
                            spacing: 4
                            Rectangle {
                                width: 54; height: 54; radius: 16; color: "#14ffffff"
                                border.width: !st.rgb.enabled ? 3 : 1; border.color: !st.rgb.enabled ? "#ffffff" : st.cBorder
                                Text { anchors.centerIn: parent; text: ""; font.family: st.fIcon; color: st.cMuted; font.pixelSize: 18 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.setRgb("enabled", false) }
                            }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: st.t("Off"); color: st.cMuted; font.family: st.fUi; font.pixelSize: 11 }
                        }
                    }
                    Card {
                        height: lgCol.implicitHeight + 8
                        Column {
                            id: lgCol; y: 4; width: parent.width
                            Row2 {
                                label: st.t("Custom color")
                                Item {
                                    width: 300; height: 24
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 10; radius: 5
                                        gradient: Gradient { orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0;  color: "#ff8c8c" } GradientStop { position: 0.17; color: "#ffe08c" }
                                            GradientStop { position: 0.33; color: "#a8ff8c" } GradientStop { position: 0.5;  color: "#8cffe7" }
                                            GradientStop { position: 0.67; color: "#8cb4ff" } GradientStop { position: 0.83; color: "#e08cff" }
                                            GradientStop { position: 1.0;  color: "#ff8cb8" } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        function pick(mx) { const r = Object.assign({}, st.rgb); r.enabled = true; r.color = st.hueHex(Math.max(0, Math.min(0.999, mx / width)));
                                            if (r.mode === "rainbow") r.mode = "static"; st.rgb = r; rgbTimer.restart(); }
                                        onPressed: m => pick(m.x)
                                        onPositionChanged: m => { if (pressed) pick(m.x); }
                                    }
                                }
                            }
                            Row2 { label: st.t("Brightness"); sub: st.rgb.brightness + "%"
                                Slider { width: 300; from: 5; to: 100; step: 5; value: st.rgb.brightness; onMoved: v => st.setRgb("brightness", Math.round(v)) } }
                            Row2 {
                                label: st.t("Effect")
                                Choice { options: [ { v: "static", t: "Static" }, { v: "breathing", t: "Breathing" }, { v: "rainbow", t: "Rainbow" } ]
                                         value: st.rgb.enabled ? st.rgb.mode : ""
                                         onPicked: v => { const r = Object.assign({}, st.rgb); r.enabled = true; r.mode = v; st.rgb = r; rgbTimer.restart(); } }
                            }
                            Row2 { label: st.t("Apply at login"); sub: st.t("Restore these lights every time you log in")
                                Toggle { on: st.rgb.atLogin; onToggled: st.setRgb("atLogin", !st.rgb.atLogin) } }
                        }
                    }
                    Btn { text: st.t("Open OpenRGB (per-device control)"); onClicked: Quickshell.execDetached(["openrgb"]) }
                }

                // ── FLOATING LYRICS ─────────────────
                Column {
                    visible: st.page === "lyrics"; width: parent.width; spacing: 12
                    Title { text: st.t("Floating Lyrics") }
                    Note { text: st.t("While music plays, the words of the current line pop up one by one in liquid-glass pills. Hidden in fullscreen games and when nothing is playing.") }
                    Card {
                        height: lyCol.implicitHeight + 8
                        Column {
                            id: lyCol; y: 4; width: parent.width
                            Row2 { label: st.t("Show floating lyrics")
                                Toggle { on: st.lyr.enabled; onToggled: st.setLyr("enabled", !st.lyr.enabled) } }
                            Row2 { label: st.t("Layout")
                                Choice { options: [ { v: "scatter", t: "Scattered" }, { v: "row", t: "In a row" } ]; value: st.lyr.layout || "scatter"; onPicked: v => st.setLyr("layout", v) } }
                            Row2 { label: st.t("Animation")
                                Choice { options: [ { v: "pop", t: "Pop + blur" }, { v: "slide", t: "Slide up" }, { v: "wave", t: "Wave" }, { v: "fade", t: "Fade" } ]; value: st.lyr.style; onPicked: v => st.setLyr("style", v) } }
                            Row2 { label: st.t("Animation speed"); sub: st.lyr.speed.toFixed(2) + "x"
                                Slider { width: 280; from: 0.5; to: 2.0; step: 0.05; value: st.lyr.speed; onMoved: v => st.setLyr("speed", v) } }
                            Row2 { label: st.t("Size")
                                Choice { options: [ { v: "s", t: "Small" }, { v: "m", t: "Medium" }, { v: "l", t: "Large" } ]; value: st.lyr.size; onPicked: v => st.setLyr("size", v) } }
                            Row2 { label: st.t("Position")
                                Choice { options: [ { v: "top", t: "Top" }, { v: "bottom", t: "Bottom" } ]; value: st.lyr.position; onPicked: v => st.setLyr("position", v) } }
                            Row2 { label: st.t("Highlight the current word"); sub: st.t("Soft pink tint on the word being sung")
                                Toggle { on: st.lyr.highlight; onToggled: st.setLyr("highlight", !st.lyr.highlight) } }
                            Row2 { label: st.t("Timing offset"); sub: (st.lyr.offset >= 0 ? "+" : "") + st.lyr.offset.toFixed(2) + " s"
                                Slider { width: 280; from: -1.5; to: 1.5; step: 0.05; value: st.lyr.offset; onMoved: v => st.setLyr("offset", v) } }
                        }
                    }
                    Btn { primary: true; text: st.t("Preview"); onClicked: Quickshell.execDetached(["qs", "ipc", "call", "lyrics", "demo"]) }
                }

                // ── POWER & SLEEP ───────────────────
                Column {
                    visible: st.page === "power"; width: parent.width; spacing: 12
                    Title { text: st.t("Power & Sleep") }
                    Note { text: st.t("What happens when you leave the PC alone. Never = it stays on.") }
                    Card {
                        height: 56
                        Row2 { anchors.verticalCenter: parent.verticalCenter; label: st.t("Lock screen")
                            Row { spacing: 8
                                Choice { options: [ { v: "sakura", t: "Sakura" }, { v: "hyprlock", t: "hyprlock" } ]
                                         value: Cfg.data.lockScreen || "hyprlock"; onPicked: v => Cfg.set("lockScreen", v) }
                                Btn { text: st.t("Try it"); onClicked: { st.shown = false; Quickshell.execDetached(["qs", "ipc", "call", "lock", "lock"]); } } } }
                    }
                    Heading { text: st.t("Lock screen look") }
                    Card {
                        height: lkCol.implicitHeight + 8
                        Column {
                            id: lkCol; y: 4; width: parent.width
                            Row2 { label: st.t("Wallpaper blur"); sub: Math.round((typeof Cfg.data.lockBlur === "number" ? Cfg.data.lockBlur : 0.25) * 100) + "%"
                                Slider { width: 260; from: 0; to: 1; step: 0.05; value: typeof Cfg.data.lockBlur === "number" ? Cfg.data.lockBlur : 0.25; onMoved: v => Cfg.set("lockBlur", Math.round(v * 100) / 100) } }
                            Row2 { label: st.t("Darken"); sub: Math.round((typeof Cfg.data.lockDim === "number" ? Cfg.data.lockDim : 0.12) * 100) + "%"
                                Slider { width: 260; from: 0; to: 0.6; step: 0.02; value: typeof Cfg.data.lockDim === "number" ? Cfg.data.lockDim : 0.12; onMoved: v => Cfg.set("lockDim", Math.round(v * 100) / 100) } }
                            Row2 { label: st.t("Clock")
                                Choice { options: [ { v: "big", t: "Big" }, { v: "thin", t: "Thin" }, { v: "small", t: "Small" } ]; value: Cfg.data.lockClock || "big"; onPicked: v => Cfg.set("lockClock", v) } }
                            Row2 { label: st.t("Seconds")
                                Toggle { on: Cfg.data.lockSeconds === true; onToggled: Cfg.set("lockSeconds", !(Cfg.data.lockSeconds === true)) } }
                            Repeater {
                                model: [ { k: "lockWeather", t: "Weather" }, { k: "lockMedia", t: "What is playing" }, { k: "lockNotifs", t: "Notifications" }, { k: "lockPower", t: "Power buttons" } ]
                                Row2 { required property var modelData; label: st.t(modelData.t)
                                    Toggle { on: Cfg.data[parent.parent.modelData.k] !== false; onToggled: { const k = parent.parent.modelData.k; Cfg.set(k, !(Cfg.data[k] !== false)); } } }
                            }
                        }
                    }
                    Heading { text: st.t("Night light on a schedule") }
                    Card {
                        height: nlCol.implicitHeight + 8
                        Column {
                            id: nlCol; y: 4; width: parent.width
                            Row2 { label: st.t("Night light on a schedule"); sub: st.t("Warmer screen in the evening, back to normal in the morning")
                                Toggle { on: Cfg.data.nightAuto === true; onToggled: { Cfg.set("nightAuto", !(Cfg.data.nightAuto === true)); st.nightWas = -1; nightKick.restart(); } } }
                            Row2 { visible: Cfg.data.nightAuto === true; label: st.t("From")
                                Choice { options: ["19:00", "20:00", "21:00", "22:00", "23:00"].map(x => ({ v: x, t: x })); value: Cfg.data.nightFrom || "21:00"; onPicked: v => { Cfg.set("nightFrom", v); st.nightWas = -1; nightKick.restart(); } } }
                            Row2 { visible: Cfg.data.nightAuto === true; label: st.t("To")
                                Choice { options: ["05:00", "06:00", "07:00", "08:00", "09:00"].map(x => ({ v: x, t: x })); value: Cfg.data.nightTo || "07:00"; onPicked: v => { Cfg.set("nightTo", v); st.nightWas = -1; nightKick.restart(); } } }
                            Row2 { visible: Cfg.data.nightAuto === true; label: st.t("Warmth"); sub: Math.round((Cfg.data.nightStrength || 0.5) * 100) + "%"
                                Slider { width: 260; from: 0.15; to: 1; step: 0.05; value: Cfg.data.nightStrength || 0.5; onMoved: v => { Cfg.set("nightStrength", Math.round(v * 100) / 100); st.nightWas = -1; nightKick.restart(); } } }
                        }
                    }
                    Timer { id: nightKick; interval: 500; onTriggered: st.nightCheck() }
                    Card {
                        height: pwCol.implicitHeight + 8
                        Column {
                            id: pwCol; y: 4; width: parent.width
                            Repeater {
                                model: [
                                    { key: "screenOff",    label: "Turn off monitors after", opts: [0, 5, 10, 15, 30, 60] },
                                    { key: "lockAfter",    label: "Lock the screen after",   opts: [0, 5, 10, 15, 30, 60] },
                                    { key: "suspendAfter", label: "Sleep (suspend) after",   opts: [0, 30, 60, 120] }
                                ]
                                delegate: Row2 {
                                    required property var modelData
                                    label: st.t(modelData.label)
                                    Row {
                                        id: optRow
                                        spacing: 6
                                        property string optKey: modelData.key
                                        Repeater {
                                            model: modelData.opts
                                            delegate: Btn {
                                                required property int modelData
                                                property string key: optRow.optKey
                                                text: modelData === 0 ? st.t("Never") : (modelData >= 60 ? (modelData / 60) + " " + st.t("h") : modelData + " " + st.t("min"))
                                                primary: (st.cfg[key] || 0) === modelData
                                                onClicked: st.setPower(key, modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── ABOUT ───────────────────────────
                Column {
                    visible: st.page === "about"; width: parent.width; spacing: 12
                    Title { text: st.t("About") }
                    Card {
                        height: 120
                        Row {
                            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                            spacing: 18
                            ClippingRectangle {
                                width: 80; height: 80; radius: 40; color: st.cAccent
                                Avatar { anchors.fill: parent; ring: 3; ringColor: "transparent" }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text { text: Quickshell.env("USER") + "@" + Quickshell.env("HOSTNAME"); color: st.cFg; font.family: st.fUi; font.pixelSize: 20; font.weight: Font.Bold }
                                Text { text: "sakura mono rice"; color: st.cAccent; font.family: st.fUi; font.pixelSize: 13 }
                                Row { spacing: 8; topPadding: 4
                                    Btn { text: st.t("Change avatar"); onClicked: { avProc.command = [st.scripts + "/avatar.sh", "pick"]; avProc.running = true; } }
                                    Btn { text: st.t("Undo"); onClicked: { avProc.command = [st.scripts + "/avatar.sh", "reset"]; avProc.running = true; } } }
                            }
                        }
                    }
                    Card {
                        height: abCol.implicitHeight + 8
                        Column {
                            id: abCol; y: 4; width: parent.width
                            Repeater {
                                model: st.about
                                delegate: Row2 {
                                    required property var modelData
                                    label: st.t(modelData.k)
                                    Text { text: modelData.v; color: st.cMuted; font.family: st.fUi; font.pixelSize: 13 }
                                }
                            }
                        }
                    }
                    Heading { text: st.t("Backup") }
                    Card {
                        height: bkCol.implicitHeight + 8
                        Column {
                            id: bkCol; y: 4; width: parent.width
                            Row2 { label: st.t("Back up the rice"); sub: st.t("All configs and your own apps (new ones are found automatically), login theme, icons, sounds and wallpapers in one archive with an installer - to restore after a reinstall or to give to a friend")
                                Btn { primary: true; text: st.backingUp ? st.t("Packing…") : st.t("Make backup"); onClicked: if (!st.backingUp) st.makeBackup() } }
                            Row2 { label: st.t("Include my notes, drawings and location"); sub: st.t("Off = safe to share")
                                Toggle { on: st.backupPersonal; onToggled: st.backupPersonal = !st.backupPersonal } }
                            Row2 { label: st.lastBackup !== "" ? st.lastBackup.split("/").pop() : st.t("No backups yet"); sub: "~/sakura-backups · " + st.t("the 5 newest are kept")
                                Btn { text: st.t("Open folder"); onClicked: Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/sakura-backups\" && xdg-open \"$HOME/sakura-backups\""]) } }
                        }
                    }
                }
            }
        }
    }
    property bool dragging: false
    property bool tzSetting: tzSet.running
}
