pragma Singleton
// Colours, fonts and look. Colour *roles* only; "auto" = follow the shell
// (~/.config/sakura/settings.json → accent, glass, font, animSpeed, lang).
// A theme (~/.config/sakura-sound/themes/<name>/theme.json) may shift a role
// (hue/lightness/alpha) or, only if the user really wants, pin a hex.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: th

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/.config/sakura-sound"

    // ── shell settings (same maths as quickshell/Cfg.qml) ────────
    property var sys: ({})
    FileView {
        path: th.home + "/.config/sakura/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { th.sys = JSON.parse(text()); } catch (e) {} }
    }
    readonly property color sysAccent: /^#[0-9a-fA-F]{6}$/.test(sys.accent || "") ? sys.accent : "#f2b8d0"
    readonly property real glassAlpha: typeof sys.glass === "number" ? Math.max(0.15, Math.min(0.95, sys.glass)) : 0.55
    readonly property color sysGlass: Qt.rgba(15 / 255, 17 / 255, 25 / 255, glassAlpha)
    readonly property string fontUi: sys.font || "Inter"
    readonly property real anim: typeof sys.animSpeed === "number" ? sys.animSpeed : 1.0
    readonly property string lang: sys.lang || "en"

    // ── player settings + active theme ───────────────────────────
    property var cfg: ({})
    FileView {
        id: cfgFile
        path: th.dir + "/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { th.cfg = JSON.parse(text()); } catch (e) { th.cfg = {}; } }
        onLoadFailed: th.cfg = {}
    }
    function setCfg(k, v) {
        const c = Object.assign({}, cfg); c[k] = v; cfg = c;
        cfgFile.setText(JSON.stringify(c, null, 2));
    }
    readonly property string themeName: cfg.theme || "sakura"
    property var t: ({})          // theme.json of the active theme
    property var preview: null    // live preview from the editor (overrides t)
    readonly property var tt: preview || t
    FileView {
        path: th.dir + "/themes/" + th.themeName + "/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { th.t = JSON.parse(text()); } catch (e) { th.t = {}; } }
        onLoadFailed: th.t = {}
    }
    readonly property bool hasOverrides: tt.overrides === true
    readonly property url overridesUrl: "file://" + th.dir + "/themes/" + th.themeName + "/Overrides.qml"

    // role resolver: "auto" | "#hex" | {hue: deg, light: ±, sat: ±, alpha: 0..1}
    function role(spec, base) {
        if (spec === undefined || spec === null || spec === "auto") return base;
        if (typeof spec === "string" && /^#[0-9a-fA-F]{6,8}$/.test(spec)) return spec;
        if (typeof spec === "object") {
            let h = base.hslHue, s = base.hslSaturation, l = base.hslLightness, a = base.a;
            if (h < 0) h = 0;
            if (spec.hue) h = ((h * 360 + spec.hue) % 360 + 360) % 360 / 360;
            if (spec.sat) s = Math.max(0, Math.min(1, s + spec.sat));
            if (spec.light) l = Math.max(0, Math.min(1, l + spec.light));
            if (spec.alpha !== undefined) a = spec.alpha;
            return Qt.hsla(h, s, l, a);
        }
        return base;
    }
    readonly property var cc: tt.colors || ({})
    // "cover" = dynamic accent from the current artwork (backend → Sound.coverColor)
    readonly property bool accentFromCover: cc.accent === "cover"
    readonly property color accent: accentFromCover ? (Sound.coverColor || sysAccent) : role(cc.accent, sysAccent)
    readonly property color glass: role(cc.glass, sysGlass)
    readonly property color fg: role(cc.fg, "#e6e8ef")
    readonly property color muted: role(cc.muted, "#8b90a0")
    readonly property color faint: Qt.rgba(muted.r, muted.g, muted.b, 0.65)
    readonly property color card: role(cc.card, "#14ffffff")
    readonly property color cardHi: Qt.rgba(card.r, card.g, card.b, Math.min(1, card.a * 1.6 + 0.02))
    readonly property color hover: "#0fffffff"
    readonly property color line: "#12ffffff"
    readonly property color side: "#1f05060a"
    // popups (menus, toasts, tooltips): the window's glass, denser, with a breath of the accent
    readonly property color pop: Qt.tint(Qt.rgba(glass.r, glass.g, glass.b, Math.max(0.9, glass.a + 0.35)), Qt.rgba(accent.r, accent.g, accent.b, 0.07))
    readonly property color popLine: Qt.rgba(accent.r, accent.g, accent.b, 0.16)
    readonly property color accFg: (0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b) > 0.55 ? "#1a121a" : "#ffffff"
    function a(c, al) { const k = Qt.darker(c, 1.0); return Qt.rgba(k.r, k.g, k.b, al); }

    // ── look knobs ──────────────────────────────────────────────
    readonly property string cover: tt.cover || "rounded"          // square rounded circle vinyl spin cd
    readonly property string background: tt.background || "glass"  // glass blur wallpaper gradient
    readonly property string density: tt.density || "normal"       // compact normal comfy
    readonly property string player: tt.player || "big"            // compact big
    readonly property string waveStyle: tt.wave || "bars"           // bars line mirror off
    readonly property bool visualizer: tt.visualizer !== false && vizStyle !== "off"
    // effects
    readonly property string vizStyle: tt.visualizer === false ? "off" : (tt.vizStyle || "bars")   // bars mirror circle off
    readonly property string particles: tt.particles || "off"      // off petals snow stars
    readonly property bool glow: tt.glow === true                  // coloured glow behind covers
    readonly property bool pulse: tt.pulse === true                // cover breathes with the bass
    readonly property string npLayout: tt.npLayout || "side"       // side center
    readonly property bool bgMotion: tt.bgMotion === true          // slow drift of the blurred background
    readonly property real bgBlur: typeof tt.bgBlur === "number" ? tt.bgBlur : 0.8
    readonly property real bgDim: typeof tt.bgDim === "number" ? tt.bgDim : 0.35
    readonly property bool marquee: tt.marquee !== false            // long titles scroll on hover
    readonly property string fontHead: tt.fontHead || fontUi
    readonly property int sideW: tt.sideW || 208
    readonly property int queueW: tt.queueW || 320
    readonly property int radius: tt.radius || 22
    readonly property int rowH: density === "compact" ? 44 : density === "comfy" ? 64 : 54
    readonly property int playerH: player === "compact" ? 72 : 92
    function dur(ms) { return Math.round(ms * anim); }

    readonly property string fIcon: "Symbols Nerd Font"
    readonly property string fMono: "JetBrainsMono Nerd Font"

    function coverRadius(w) {
        switch (cover) {
        case "square": return 4;
        case "circle": case "vinyl": case "spin": case "cd": return w / 2;
        default: return Math.max(6, Math.round(w * 0.12));
        }
    }

    // ── helpers ─────────────────────────────────────────────────
    function time(s) {
        if (!(s > 0)) return "0:00";
        s = Math.floor(s);
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), ss = s % 60;
        return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (ss < 10 ? "0" : "") + ss;
    }
    function num(n) {
        if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M";
        if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "K";
        return "" + (n || 0);
    }
    function small(url, px) {
        // SoundCloud artwork sizes: t67x67 t300x300 t500x500
        if (!url) return "";
        return px <= 80 ? url.replace("-t500x500.", "-t67x67.") : px <= 300 ? url.replace("-t500x500.", "-t300x300.") : url;
    }

    function tr(s) { return lang === "ru" && ru[s] !== undefined ? ru[s] : s; }
    readonly property var ru: ({
        "Home": "Главная", "Search": "Поиск", "Library": "Библиотека", "Queue": "Очередь", "Lyrics": "Текст",
        "Now playing": "Сейчас играет", "Up next": "Дальше", "Clear": "Очистить", "Tracks": "Треки",
        "Artists": "Артисты", "Playlists": "Плейлисты", "Albums": "Альбомы", "Likes": "Лайки",
        "History": "История", "Following": "Подписки", "Feed": "Лента", "Liked tracks": "Понравившиеся",
        "Recently played": "Недавнее", "From people you follow": "От тех, на кого подписан",
        "Continue": "Продолжить", "Search SoundCloud": "Поиск в SoundCloud", "Nothing found": "Ничего не нашлось",
        "Play": "Играть", "Shuffle": "Перемешать", "Play next": "Играть следующим", "Add to queue": "В очередь",
        "Go to artist": "К артисту", "Start radio": "Радио по треку", "Copy link": "Копировать ссылку",
        "Open in browser": "Открыть в браузере", "Remove from queue": "Убрать из очереди",
        "Popular": "Популярное", "Reposts": "Репосты", "Related tracks": "Похожие", "followers": "подписчиков",
        "tracks": "треков", "plays": "прослушиваний", "Guest": "Гость", "Sign in to SoundCloud in Brave": "Войди в SoundCloud в Brave",
        "Preview": "Превью", "Queue is empty": "Очередь пуста", "Settings": "Настройки", "Themes": "Темы",
        "Plugins": "Плагины", "Loading…": "Загрузка…", "Back": "Назад", "Good morning": "Доброе утро",
        "Good afternoon": "Добрый день", "Good evening": "Добрый вечер", "Good night": "Доброй ночи",
        "Album": "Альбом", "Playlist": "Плейлист", "Reposted by": "Репост", "Station": "Станция",
        "Appearance": "Вид", "Cover": "Обложка", "Background": "Фон", "Density": "Плотность", "Player": "Плеер",
        "Wave": "Волна", "Visualizer": "Визуализатор", "Heading font": "Шрифт заголовков", "Sidebar width": "Ширина колонки",
        "Queue width": "Ширина очереди", "Corner radius": "Скругление", "Accent": "Акцент", "Glass": "Стекло",
        "Text": "Текст", "Muted": "Приглушённый", "Card": "Карточки", "Follow system": "Как в системе",
        "Square": "Квадрат", "Rounded": "Скруглённая", "Circle": "Круг", "Vinyl": "Винил", "Spinning": "Крутится",
        "CD": "CD", "Blurred cover": "Размытая обложка", "Wallpaper": "Обои", "Cover gradient": "Градиент обложки",
        "Compact": "Компактно", "Normal": "Обычно", "Comfy": "Просторно", "Big": "Большой", "Bars": "Полоски",
        "Line": "Линия", "Mirror": "Зеркало", "Off": "Выкл", "On": "Вкл", "Save as new theme": "Сохранить как новую",
        "Save": "Сохранить", "Import": "Импорт", "Export": "Экспорт", "Delete": "Удалить", "Reload": "Перезагрузить",
        "Hue shift": "Сдвиг оттенка", "Account": "Аккаунт", "Cookies from": "Cookies из", "Signed in as": "Вход как",
        "Not signed in": "Вход не выполнен", "Check again": "Проверить снова", "Theme name": "Имя темы",
        "Version": "Версия", "Enabled": "Включён", "Statistics": "Статистика", "This week": "За неделю",
        "Top artists": "Топ артистов", "Top tracks": "Топ треков", "minutes listened": "минут прослушано",
        "Comments": "Комментарии", "Show more": "Показать ещё", "Show all": "Все", "Your playlists": "Твои плейлисты",
        "Liked playlists": "Лайкнутые плейлисты", "Made for you": "Для тебя", "Couldn't load": "Не удалось загрузить",
        "Retry": "Повторить", "Mini player": "Мини-плеер", "Open Sakura Sound": "Открыть Sakura Sound",
        "Unknown": "Неизвестно", "Repeat": "Повтор", "Behaviour": "Поведение", "Track change notice": "Notice при смене трека",
        "No lyrics found": "Текст не найден", "Like": "Нравится", "Checking…": "Проверяю…", "Couldn't read cookies from": "Не получилось прочитать cookies из", "Sign in to SoundCloud in": "Войди в SoundCloud в", "From your artists": "От твоих артистов", "Now playing layout": "Раскладка «Сейчас играет»", "Side by side": "Рядом", "Centered": "По центру",
        "Particles": "Частицы", "Petals": "Лепестки", "Snow": "Снег", "Stars": "Звёзды", "Cover glow": "Свечение обложки",
        "Pulse to the beat": "Пульс в такт", "Moving background": "Движущийся фон", "Background blur": "Размытие фона",
        "Background dim": "Затемнение фона", "Scrolling titles": "Бегущие названия", "Accent from cover": "Акцент из обложки", "Unlike": "Убрать лайк", "Follow": "Подписаться", "Subscribed": "Вы подписаны", "Unfollow": "Отписаться", "End of track": "После трека", "End of queue": "После очереди",
        "Equalizer": "Эквалайзер", "Normalization": "Нормализация", "Dynamic": "Динамическая", "Loudness": "По громкости",
        "Offset": "Сдвиг", "Text size": "Размер текста", "Line in Now playing": "Строка в «Сейчас играет»",
        "Synced lyrics from LRCLIB in the right panel and in Now playing": "Синхронный текст из LRCLIB справа и в «Сейчас играет»",
        "Sleep timer": "Таймер сна", "Pause after N minutes, at the end of the track or of the queue": "Пауза через N минут, после трека или очереди",
        "Fade out over the last 30 s": "Затухание последние 30 с",
        "10-band equalizer with presets and loudness normalization (mpv filters)": "10 полос, пресеты и нормализация громкости (фильтры mpv)",
        "Crossfade & gapless": "Кроссфейд и gapless", "Soft fade between tracks and gapless playback": "Мягкий переход между треками и воспроизведение без пауз", "The next track follows without a pause": "Следующий трек начинается без паузы",
        "Fade": "Переход", "Gapless": "Без пауз", "Strict": "Строго",
        "Last.fm scrobbler": "Скробблер Last.fm", "Now playing + scrobbles to your Last.fm account": "«Сейчас играет» и скробблы в твой Last.fm",
        "API key": "API-ключ", "Shared secret": "Секрет", "Connect": "Подключить", "Done": "Готово",
        "After allowing in the browser": "После разрешения в браузере", "Status": "Статус",
        "Discord Rich Presence": "Статус в Discord", "\"Listening to …\" with the cover in your Discord status": "«Слушает …» с обложкой в статусе Discord",
        "Application ID": "ID приложения", "Hide on pause": "Скрывать на паузе", "Button \"Open on SoundCloud\"": "Кнопка «Открыть в SoundCloud»",
        "Track radio": "Радио по треку", "Endless queue: when the last track starts, related tracks are added": "Бесконечная очередь: на последнем треке добавляются похожие",
        "Keep the queue going": "Продолжать очередь",
        "Feed filters": "Фильтры ленты", "Skip reposts and short previews": "Пропуск репостов и коротких превью",
        "Hide reposts in the feed": "Скрывать репосты в ленте", "Hide 30 s previews in lists": "Скрывать 30-секундные превью",
        "Skip previews while playing": "Пропускать превью при игре", "Hide tracks shorter than": "Скрывать треки короче",
        "Small glass player on top of all windows, drag it anywhere": "Маленький стеклянный плеер поверх окон, можно перетаскивать",
        "Monitor": "Монитор", "Main": "Главный", "Second": "Второй",
        "Your own page: what you listened to, top artists and tracks (local history)": "Своя страница: что слушал, топ артистов и треков (локальная история)"
    })
}
