// Root of the player UI (used by shell.qml's window and by test.qml).
import QtQuick
import QtQuick.Effects
import Quickshell
import "pages"

Item {
    id: app
    focus: true
    clip: true

    // ── navigation ──────────────────────────────────────────────
    property var stack: [{ p: "home" }]
    readonly property var page: stack[stack.length - 1]
    function go(pg, root) {
        if (root) stack = [pg];
        else if (JSON.stringify(pg) !== JSON.stringify(page)) stack = stack.concat([pg]);
        nowPlaying = false;
    }
    function back() { if (nowPlaying) { nowPlaying = false; return; } if (stack.length > 1) stack = stack.slice(0, -1); }
    function openItem(it) {
        if (!it) return;
        if (it.type === "user") openArtist(it.id);
        else if (it.type === "playlist") go({ p: "playlist", pid: it.urn && it.system ? it.urn : it.id, title: it.title });
        else if (it.type === "track") Sound.playList([it], 0);
    }
    function openArtist(uid) { if (uid) go({ p: "artist", uid: uid }); }

    property alias pageItem: pageLoader.item
    property string searchQ: ""
    property string searchType: "tracks"
    property bool nowPlaying: false
    property string side: Theme.cfg.side || ""     // "" | queue | lyrics | <plugin tab>
    function toggleSide(s) { side = side === s ? "" : s; Theme.setCfg("side", side); }

    // ── things plugins add to (filled by Plugins.qml) ───────────
    property var pluginPages: []        // [{p, icon, label, component}]
    property var playerButtons: []      // [{icon, act, on}]
    property var nowBlocks: []          // [{component}]
    property var menuExtras: []         // [{icon, label, act(track)}]
    property var sideTabs: []           // [{id, icon, label, component}]
    property bool hasLyrics: sideTabs.some(t => t.id === "lyrics")
    property var api: null
    property var itemFilters: []
    function filterItems(items, kind) { let a = items; for (const f of itemFilters) { try { a = f(a, kind) || a; } catch (e) {} } return a; }
    property Component pluginManager: Component { PluginManager { host: plugins } }
    PluginHost { id: plugins; app: app }
    readonly property var navItems: [
        { p: "home", icon: "home", label: Theme.tr("Home") },
        { p: "search", icon: "search", label: Theme.tr("Search") },
        { p: "library", icon: "library", label: Theme.tr("Library") }
    ].concat(pluginPages.map(x => ({ p: x.p, icon: x.icon, label: x.label })))

    // ── comments for wave markers ───────────────────────────────
    property var comments: []
    Connections {
        target: Sound
        function onStarted(t) {
            app.comments = [];
            if (t && t.id) Sound.list("comments", t.id, r => { if (!r.err && Sound.track && Sound.track.id === t.id) app.comments = r.items; });
        }
    }

    // ── context menu ────────────────────────────────────────────
    function menuFor(it, p, queueIndex) {
        if (!it) return;
        let e = [];
        if (it.type === "track") {
            e.push({ icon: "play", label: Theme.tr("Play"), act: () => Sound.playList([it], 0) });
            e.push({ icon: "playNext", label: Theme.tr("Play next"), act: () => Sound.enqueue(it, true) });
            e.push({ icon: "plus", label: Theme.tr("Add to queue"), act: () => Sound.enqueue(it, false) });
            if (queueIndex !== undefined) e.push({ icon: "close", label: Theme.tr("Remove from queue"), act: () => Sound.remove(queueIndex) });
            e.push({ icon: Sound.isLiked(it.id) ? "heart" : "heartO", label: Theme.tr(Sound.isLiked(it.id) ? "Unlike" : "Like"), act: () => Sound.like(it) });
            e.push({ sep: true });
            e.push({ icon: "radio", label: Theme.tr("Start radio"), act: () => { Sound.playList([it], 0); Sound.radio(it.id); } });
            e.push({ icon: "users", label: Theme.tr("Related tracks"), act: () => go({ p: "list", kind: "related", arg: it.id, title: it.title }) });
            e.push({ icon: "user", label: Theme.tr("Go to artist"), act: () => openArtist(it.artistId) });
            for (const x of menuExtras) e.push({ icon: x.icon, label: x.label, act: () => x.act(it) });
        } else {
            e.push({ icon: "open", label: it.type === "user" ? Theme.tr("Go to artist") : Theme.tr("Playlist"), act: () => openItem(it) });
            if (it.type === "user") e.push({ icon: "user", label: Theme.tr(Sound.isFollowing(it.id) ? "Unfollow" : "Follow"), act: () => Sound.follow(it.id, undefined, it) });
        }
        e.push({ sep: true });
        e.push({ icon: "link", label: Theme.tr("Copy link"), act: () => Sound.copy(it.url) });
        e.push({ icon: "open", label: Theme.tr("Open in browser"), act: () => Sound.openUrl(it.url) });
        menu.open(e, p);
    }

    // popup above the player's right corner (plugin buttons)
    function popupAt(entries) { menu.open(entries, Qt.point(width - 250, height - Theme.playerH - 12 - (entries.length * 34 + 12))); }
    function popup(entries, p) { menu.open(entries, p); }

    // ── keys ────────────────────────────────────────────────────
    Keys.onPressed: ev => {
        const ctrl = ev.modifiers & Qt.ControlModifier;
        if (ctrl && ev.key === Qt.Key_F) { go({ p: "search" }, true); ev.accepted = true; }
        else if (ctrl && ev.key === Qt.Key_L) { go({ p: "library" }, true); ev.accepted = true; }
        else if (ctrl && ev.key === Qt.Key_Q) { toggleSide("queue"); ev.accepted = true; }
        else if (ev.key === Qt.Key_Space) { Sound.toggle(); ev.accepted = true; }
        else if (ev.key === Qt.Key_Right) { ctrl ? Sound.next() : Sound.seek(Math.min(Sound.dur, Sound.livePos + 5)); ev.accepted = true; }
        else if (ev.key === Qt.Key_Left) { ctrl ? Sound.prev() : Sound.seek(Math.max(0, Sound.livePos - 5)); ev.accepted = true; }
        else if (ev.key === Qt.Key_Up && ctrl) { Sound.setVolume(Math.min(100, Sound.vol + 5)); ev.accepted = true; }
        else if (ev.key === Qt.Key_Down && ctrl) { Sound.setVolume(Math.max(0, Sound.vol - 5)); ev.accepted = true; }
        else if (ev.key === Qt.Key_Escape || ev.key === Qt.Key_Back || (ev.key === Qt.Key_Backspace && (ev.modifiers & Qt.AltModifier))) { if (menu.visible) menu.close(); else back(); ev.accepted = true; }
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.BackButton; onClicked: app.back(); z: -1 }

    // ── background (theme: glass / blur / wallpaper / gradient) ─
    Item {
        id: bg
        anchors.fill: parent
        Image {
            id: bgSrc
            anchors.fill: parent
            visible: false
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: Theme.background === "wallpaper" ? 960 : 200
            source: Theme.background === "blur" || Theme.background === "gradient" ? (Sound.track ? Theme.small(Sound.track.art, 300) : "")
                  : Theme.background === "wallpaper" ? (Theme.sys.wallpaper && !/\.(mp4|webm|mkv|mov)$/i.test(Theme.sys.wallpaper) ? "file://" + Theme.sys.wallpaper : "") : ""
        }
        MultiEffect {
            anchors.fill: parent
            source: bgSrc
            visible: Theme.background !== "glass" && bgSrc.status === Image.Ready
            blurEnabled: Theme.bgBlur > 0.01
            blur: Theme.background === "gradient" ? 1.0 : Theme.bgBlur
            blurMax: Theme.background === "gradient" ? 64 : 48
            saturation: Theme.background === "gradient" ? 0.6 : 0
            opacity: (Theme.background === "wallpaper" ? 0.6 : 0.5) * (1 - Theme.bgDim * 0.6)
            SequentialAnimation on scale {
                running: Theme.bgMotion && Theme.background !== "glass"; loops: Animation.Infinite
                NumberAnimation { to: 1.12; duration: 19000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 19000; easing.type: Easing.InOutSine }
            }
        }
        Rectangle { anchors.fill: parent; color: Theme.background === "glass" ? "transparent" : Theme.a("#0f1119", Theme.bgDim) }
    }

    // ── layout ──────────────────────────────────────────────────
    Sidebar {
        id: sidebar
        visible: !app.covered
        app: app
        anchors.top: parent.top; anchors.bottom: player.top; anchors.left: parent.left
    }

    Item {
        id: sidePanel
        visible: !app.covered
        anchors.top: parent.top; anchors.bottom: player.top; anchors.right: parent.right
        width: app.side !== "" ? Theme.queueW : 0
        clip: true
        Behavior on width { NumberAnimation { duration: Theme.dur(220); easing.type: Easing.OutCubic } }
        QueuePanel { app: app; width: Theme.queueW; height: parent.height; visible: app.side === "queue" }
        Repeater {
            model: app.sideTabs
            Loader {
                required property var modelData
                width: Theme.queueW; height: sidePanel.height
                active: app.side === modelData.id
                visible: active
                sourceComponent: modelData.component
                onLoaded: if (item && item.hasOwnProperty("api")) item.api = app.api
            }
        }
    }

    Item {
        id: content
        visible: !app.covered
        anchors.top: parent.top; anchors.bottom: player.top
        anchors.left: sidebar.right; anchors.right: sidePanel.left

        Btn {
            z: 5
            visible: app.stack.length > 1
            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 14
            icon: "back"; size: 34
            onClicked: app.back()
        }

        Loader {
            id: pageLoader
            anchors.fill: parent
            property string key: JSON.stringify(app.page)
            onKeyChanged: { opacity = 0; reload.restart(); }
            Timer { id: reload; interval: 1; onTriggered: { pageLoader.sourceComponent = null; pageLoader.sourceComponent = pageLoader.pick(); pageLoader.opacity = 1; } }
            Component.onCompleted: sourceComponent = pick()
            Behavior on opacity { NumberAnimation { duration: Theme.dur(140) } }
            function pick() {
                const p = app.page.p;
                for (const x of app.pluginPages) if (x.p === p) return x.component;
                return ({ home: homeC, search: searchC, list: listC, library: libC, artist: artistC, playlist: plC, settings: setC })[p] || homeC;
            }
            onLoaded: {
                if (item.hasOwnProperty("app")) item.app = app;
                if (item.hasOwnProperty("page")) item.page = app.page;
                if (item.hasOwnProperty("api")) item.api = app.api;
            }
        }
        Component { id: homeC; HomePage {} }
        Component { id: searchC; SearchPage {} }
        Component { id: listC; ListPage { app: app } }
        Component { id: libC; LibraryPage {} }
        Component { id: artistC; ArtistPage {} }
        Component { id: plC; PlaylistPage {} }
        Component { id: setC; SettingsPage {} }
    }

    PlayerBar {
        id: player
        visible: !app.covered
        app: app
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    }

    NowPlaying { id: npView; anchors.fill: parent; app: app; shown: app.nowPlaying }
    // once Now playing fully covers the window, hide what is under it (no page shining through the glass)
    readonly property bool covered: npView.opacity > 0.99

    // toast for errors
    Rectangle {
        id: toast
        property string msg: ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: player.top; anchors.bottomMargin: 14
        width: Math.min(560, tT.implicitWidth + 32); height: 36; radius: 18
        color: Theme.pop; border.width: 1; border.color: Theme.line
        opacity: msg ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(180) } }
        Text { id: tT; anchors.centerIn: parent; width: Math.min(implicitWidth, 528); elide: Text.ElideRight; text: toast.msg; color: Theme.fg; font.family: Theme.fontUi; font.pixelSize: 12 }
        Timer { id: toastT; interval: 4000; onTriggered: toast.msg = "" }
        Connections { target: Sound; function onError(m) { toast.msg = m; toastT.restart(); } }
    }

    Menu { id: menu; z: 50 }

    Loader {
        // theme Overrides.qml: may restyle anything through `app`
        active: Theme.hasOverrides
        source: Theme.hasOverrides ? Theme.overridesUrl : ""
        onLoaded: if (item.hasOwnProperty("app")) item.app = app
    }
}
