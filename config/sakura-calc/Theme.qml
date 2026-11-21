pragma Singleton
// Look of sakura-calc: follows the shell (~/.config/sakura/settings.json → accent, glass, font, animSpeed, lang).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: th
    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/.config/sakura-calc"

    property var sys: ({})
    FileView {
        path: th.home + "/.config/sakura/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { th.sys = JSON.parse(text()); } catch (e) {} }
    }

    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(sys.accent || "") ? sys.accent : "#f2b8d0"
    readonly property real glassAlpha: typeof sys.glass === "number" ? Math.max(0.15, Math.min(0.95, sys.glass)) : 0.55
    readonly property color glass: Qt.rgba(15 / 255, 17 / 255, 25 / 255, glassAlpha)
    readonly property color pop: Qt.tint(Qt.rgba(16 / 255, 18 / 255, 27 / 255, Math.max(0.9, glassAlpha + 0.35)), Qt.rgba(accent.r, accent.g, accent.b, 0.06))
    readonly property color accFg: (0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b) > 0.55 ? "#141620" : "#ffffff"
    readonly property real anim: typeof sys.animSpeed === "number" && sys.animSpeed > 0 ? sys.animSpeed : 1.0
    readonly property string lang: sys.lang || "en"

    readonly property color fg: "#eef0f7"
    function a(c, al) { return Qt.rgba(c.r, c.g, c.b, al); }
    readonly property color dim: a(fg, 0.5)
    readonly property color faint: a(fg, 0.3)

    readonly property string fUi: sys.font || "Inter"
    readonly property string fDisplay: "Inter Display"
    readonly property string fIcon: "Symbols Nerd Font"

    function ms(d) { return Math.round(d / anim); }

    readonly property var ru: ({
        "Basic": "Обычный", "Scientific": "Научный", "Convert": "Конвертер", "History": "История",
        "Length": "Длина", "Mass": "Масса", "Temperature": "Температура", "Volume": "Объём", "Area": "Площадь",
        "Speed": "Скорость", "Data": "Данные", "Time": "Время", "Currency": "Валюта"
    })
    function tr(s) { return lang === "ru" && ru[s] ? ru[s] : s; }
}
