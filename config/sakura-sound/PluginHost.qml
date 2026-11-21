// Loads local plugins from ~/.config/sakura-sound/plugins/<id>/ (manifest.json + Plugin.qml).
// Nothing is downloaded. Enabled state + settings live in settings.json → plugins.<id>.
import QtQuick

Item {
    id: host
    property var app: null
    property var list: []
    property var reg: ({})
    property int rev: 0
    readonly property var pcfg: Theme.cfg.plugins || ({})
    visible: false

    function manifest(pid) { return list.find(m => m.id === pid) || null; }
    function dirOf(pid) { const m = manifest(pid); return m ? m.dir : ""; }
    function enabled(pid) {
        const c = pcfg[pid];
        if (c && c.enabled !== undefined) return c.enabled;
        const m = manifest(pid);
        return !!(m && m.enabled !== false);
    }
    function configOf(pid) {
        const m = manifest(pid), out = {};
        for (const s of (m && m.settings) || []) if (s.key) out[s.key] = s.default;
        return Object.assign(out, (pcfg[pid] || {}).config || {});
    }
    function setPlugin(pid, patch) {
        const all = Object.assign({}, pcfg);
        all[pid] = Object.assign({}, all[pid] || {}, patch);
        Theme.setCfg("plugins", all);
        rev += 1;
    }
    function setEnabled(pid, on) { setPlugin(pid, { enabled: on }); }
    function setConfig(pid, key, v) {
        const c = Object.assign({}, (pcfg[pid] || {}).config || {}); c[key] = v;
        setPlugin(pid, { config: c });
    }

    function register(pid, kind, o) {
        const r = Object.assign({}, reg);
        r[pid] = Object.assign({ pages: [], buttons: [], menu: [], blocks: [], tabs: [], filters: [] }, r[pid] || {});
        r[pid][kind] = r[pid][kind].concat([o]);
        reg = r;
        publish();
    }
    function unregister(pid) { const r = Object.assign({}, reg); delete r[pid]; reg = r; publish(); }
    function all(kind) { let a = []; for (const pid in reg) a = a.concat(reg[pid][kind] || []); return a; }
    function publish() {
        if (!app) return;
        app.pluginPages = all("pages");
        app.playerButtons = all("buttons");
        app.menuExtras = all("menu");
        app.nowBlocks = all("blocks");
        app.sideTabs = all("tabs");
        app.itemFilters = all("filters");
    }

    function reload() {
        const keep = list;
        list = [];
        reg = ({});
        publish();
        Sound.send("plugins", {}, r => { host.list = r.plugins || []; host.rev += 1; });
    }
    Component.onCompleted: Qt.callLater(reload)

    Component { id: apiC; SoundApi {} }

    Repeater {
        model: host.list.length
        Loader {
            id: pl
            required property int index
            readonly property var m: host.list[index]
            readonly property string pid: m ? m.id : ""
            property var api: null
            active: !!m && (host.rev, host.enabled(pid))
            // same URL scheme as the config root, so plugins share Theme/Sound singletons
            source: m ? Qt.resolvedUrl("plugins/" + m.id + "/" + (m.entry || "Plugin.qml")) : ""
            onLoaded: {
                api = apiC.createObject(host, { pid: pid, host: host });
                if (item.hasOwnProperty("api")) item.api = api;
            }
            onActiveChanged: if (!active) { host.unregister(pid); if (api) { api.destroy(); api = null; } }
            onStatusChanged: if (status === Loader.Error) console.log("[sound] plugin " + pid + " failed to load")
            function action(key) { if (item && typeof item.action === "function") item.action(key); }
        }
    }
    function action(pid, key) {
        for (let i = 0; i < children.length; i++) { const c = children[i]; if (c.pid === pid && c.action) { c.action(key); return; } }
    }
}
