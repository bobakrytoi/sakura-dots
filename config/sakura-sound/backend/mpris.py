"""MPRIS for Sakura Sound, served by the backend itself (instead of mpv-mpris).

mpv-mpris only knows mpv's own 1-2 entry playlist: its Next/Previous/Shuffle/Loop went to mpv and missed the
real queue. Here every control maps to the backend, so the notch, the Media card, the lock screen, media keys
and playerctl all drive the same queue. Bus name: org.mpris.MediaPlayer2.sakura_sound.
"""
import threading

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/><method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/><method name="Previous"/><method name="Pause"/><method name="PlayPause"/>
    <method name="Stop"/><method name="Play"/>
    <method name="Seek"><arg direction="in" type="x" name="Offset"/></method>
    <method name="SetPosition"><arg direction="in" type="o" name="TrackId"/><arg direction="in" type="x" name="Position"/></method>
    <method name="OpenUri"><arg direction="in" type="s" name="Uri"/></method>
    <signal name="Seeked"><arg type="x" name="Position"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""
ROOT, PLAYER, PATH = "org.mpris.MediaPlayer2", "org.mpris.MediaPlayer2.Player", "/org/mpris/MediaPlayer2"
LOOP_TO = {"off": "None", "all": "Playlist", "one": "Track"}
LOOP_FROM = {v: k for k, v in LOOP_TO.items()}


class Mpris:
    def __init__(self, backend, log=lambda *a: None):
        self.b = backend
        self.log = log
        self.conn = None
        self.meta = {}
        self.last = {}
        self.loop = GLib.MainLoop()
        threading.Thread(target=self._run, daemon=True).start()

    # ── bus ────────────────────────────────────────────────────
    def _run(self):
        node = Gio.DBusNodeInfo.new_for_xml(XML)

        def on_bus(conn, name):
            self.conn = conn
            for iface in node.interfaces:
                conn.register_object(PATH, iface, self._call, self._get, self._set)

        Gio.bus_own_name(Gio.BusType.SESSION, ROOT + ".sakura_sound", Gio.BusNameOwnerFlags.NONE,
                         on_bus, None, lambda *a: self.log("mpris: name lost"))
        self.loop.run()

    def _call(self, conn, sender, path, iface, method, params, inv):
        b = self.b
        try:
            if method == "Raise":
                import subprocess, os
                subprocess.Popen([os.path.expanduser("~/.local/bin/sakura-sound")], start_new_session=True)
            elif method == "PlayPause":
                b.pool.submit(b.handle, {"cmd": "toggle"})
            elif method == "Play":
                b.pool.submit(b.handle, {"cmd": "resume"})
            elif method in ("Pause", "Stop"):
                b.pool.submit(b.handle, {"cmd": "pause"})
            elif method == "Next":
                b.pool.submit(b.handle, {"cmd": "next"})
            elif method == "Previous":
                b.pool.submit(b.handle, {"cmd": "prev"})
            elif method == "Seek":
                b.pool.submit(b.handle, {"cmd": "seek", "t": max(0.0, b.pos + params.unpack()[0] / 1e6)})
            elif method == "SetPosition":
                b.pool.submit(b.handle, {"cmd": "seek", "t": max(0.0, params.unpack()[1] / 1e6)})
        except Exception as e:
            self.log("mpris call %s: %s" % (method, e))
        inv.return_value(None)

    def _props(self, iface):
        b = self.b
        if iface == ROOT:
            return {"CanQuit": GLib.Variant("b", False), "CanRaise": GLib.Variant("b", True),
                    "HasTrackList": GLib.Variant("b", False), "Identity": GLib.Variant("s", "Sakura Sound"),
                    "DesktopEntry": GLib.Variant("s", "sakura-sound"),
                    "SupportedUriSchemes": GLib.Variant("as", []), "SupportedMimeTypes": GLib.Variant("as", [])}
        has = b.cur() is not None
        return {
            # while a new track is still starting, say Paused: clients must not run the clock ahead of the audio
            "PlaybackStatus": GLib.Variant("s", "Playing" if b.playing and not b.starting else ("Paused" if has else "Stopped")),
            "LoopStatus": GLib.Variant("s", LOOP_TO.get(b.repeat, "None")),
            "Rate": GLib.Variant("d", 1.0), "MinimumRate": GLib.Variant("d", 1.0), "MaximumRate": GLib.Variant("d", 1.0),
            "Shuffle": GLib.Variant("b", bool(b.shuffle)),
            "Metadata": GLib.Variant("a{sv}", self.meta),
            "Volume": GLib.Variant("d", round(b.vol / 100.0, 3)),
            "Position": GLib.Variant("x", int(b.pos * 1e6)),
            "CanGoNext": GLib.Variant("b", has), "CanGoPrevious": GLib.Variant("b", has),
            "CanPlay": GLib.Variant("b", has), "CanPause": GLib.Variant("b", has),
            "CanSeek": GLib.Variant("b", has), "CanControl": GLib.Variant("b", True),
        }

    def _get(self, conn, sender, path, iface, prop):
        return self._props(iface).get(prop)

    def _set(self, conn, sender, path, iface, prop, value):
        b = self.b
        v = value.unpack()
        if prop == "Volume":
            b.pool.submit(b.handle, {"cmd": "volume", "v": max(0.0, min(1.3, float(v))) * 100})
        elif prop == "Shuffle":
            b.pool.submit(b.handle, {"cmd": "shuffle", "on": bool(v)})
        elif prop == "LoopStatus" and v in LOOP_FROM:
            b.pool.submit(b.handle, {"cmd": "repeat", "mode": LOOP_FROM[v]})
        return True

    # ── updates from the backend (any thread) ─────────────────
    def set_track(self, t, cover="", title="", artist=""):
        if not t:
            self.meta = {}
        else:
            m = {"mpris:trackid": GLib.Variant("o", "/org/sakura/sound/track/%s" % t.get("id", 0)),
                 "mpris:length": GLib.Variant("x", int((t.get("dur") or 0) * 1e6)),
                 "xesam:title": GLib.Variant("s", title or ""),
                 "xesam:artist": GLib.Variant("as", [artist] if artist else []),
                 "xesam:url": GLib.Variant("s", t.get("url") or "")}
            if cover:
                m["mpris:artUrl"] = GLib.Variant("s", "file://" + cover)
            elif t.get("art"):
                m["mpris:artUrl"] = GLib.Variant("s", t["art"])
            self.meta = m
        GLib.idle_add(self._emit, PLAYER, ["Metadata", "CanGoNext", "CanGoPrevious", "CanPlay", "CanPause", "CanSeek", "PlaybackStatus"])

    def changed(self):
        """Call after state changes; only properties that really changed are announced."""
        GLib.idle_add(self._emit_diff)

    def seeked(self, pos):
        def go():
            if self.conn:
                self.conn.emit_signal(None, PATH, PLAYER, "Seeked", GLib.Variant("(x)", (int(pos * 1e6),)))
            return False
        GLib.idle_add(go)

    def _emit_diff(self):
        p = self._props(PLAYER)
        keys = [k for k in ("PlaybackStatus", "LoopStatus", "Shuffle", "Volume")
                if self.last.get(k) is None or self.last[k] != p[k].unpack()]
        if keys:
            self._emit(PLAYER, keys, p)
        return False

    def _emit(self, iface, keys, p=None):
        if not self.conn:
            return False
        p = p or self._props(iface)
        for k in keys:
            self.last[k] = p[k].unpack()
        self.conn.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                              GLib.Variant("(sa{sv}as)", (iface, {k: p[k] for k in keys}, [])))
        return False
