// soft "creamy" key sounds while typing the password - the same wavs as the lock screen (hyprland.lua __setLockKeys).
// Loaded by Main.qml through a Loader: if QtMultimedia or audio isn't there, only the sounds are missing, the login still works.
import QtQuick 2.15
import QtMultimedia

Item {
    id: snd
    property real volume: 0.6
    property int n: 0
    SoundEffect { id: k1; source: "sounds/key1.wav"; volume: snd.volume }
    SoundEffect { id: k2; source: "sounds/key2.wav"; volume: snd.volume }
    SoundEffect { id: k3; source: "sounds/key3.wav"; volume: snd.volume }
    SoundEffect { id: kb; source: "sounds/key-back.wav"; volume: snd.volume }
    SoundEffect { id: ke; source: "sounds/key-enter.wav"; volume: snd.volume }
    function key() {
        // random, but never the same one twice in a row
        let i = Math.floor(Math.random() * 2); if (i >= n) i++; n = i;
        [k1, k2, k3][i].play();
    }
    function back() { kb.play(); }
    function enter() { ke.play(); }
}
