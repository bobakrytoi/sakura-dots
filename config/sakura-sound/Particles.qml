// Falling petals / snow / twinkling stars (theme `particles`). Runs only while visible.
// Each kind is its own particle system, rebuilt on change: switching properties of a live
// Emitter (e.g. velocity → null) crashes QtQuick.Particles.
import QtQuick
import QtQuick.Particles

Item {
    id: fx
    property string kind: Theme.particles
    readonly property bool on: kind !== "off" && visible && width > 0
    clip: true

    Loader {
        anchors.fill: parent
        active: fx.on
        sourceComponent: fx.kind === "stars" ? starsC : fallC
    }

    Component {
        id: fallC
        Item {
            readonly property bool petals: fx.kind === "petals"
            ParticleSystem { id: sys }
            Emitter {
                system: sys
                x: -fx.width * 0.1; y: -30; width: fx.width * 1.2; height: 1
                emitRate: petals ? 4 : 9
                lifeSpan: Math.max(6000, fx.height * 16); lifeSpanVariation: 1200
                size: petals ? 12 : 5; sizeVariation: petals ? 5 : 2
                velocity: AngleDirection { angle: 90; angleVariation: 22; magnitude: petals ? 52 : 38; magnitudeVariation: 18 }
            }
            Wander { system: sys; anchors.fill: parent; xVariance: petals ? 70 : 30; pace: petals ? 90 : 40 }
            ItemParticle {
                system: sys
                fade: true
                delegate: Rectangle {
                    width: fx.kind === "petals" ? 12 : 5
                    height: fx.kind === "petals" ? 8 : 5
                    radius: height * 0.9
                    antialiasing: true
                    color: fx.kind === "petals" ? Theme.a(Qt.lighter(Theme.accent, 1.15), 0.75) : "#e6ffffff"
                    rotation: Math.random() * 360
                }
            }
        }
    }

    Component {
        id: starsC
        Item {
            ParticleSystem { id: sys }
            Emitter {
                system: sys
                anchors.fill: parent
                emitRate: 6
                lifeSpan: 2600; lifeSpanVariation: 1000
                size: 4; sizeVariation: 2
                velocity: AngleDirection { magnitude: 0 }
            }
            ItemParticle {
                system: sys
                fade: true
                delegate: Rectangle {
                    width: 2 + Math.random() * 3; height: width; radius: width / 2
                    antialiasing: true
                    color: Theme.a(Theme.fg, 0.9)
                }
            }
        }
    }
}
