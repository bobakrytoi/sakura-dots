// The Sakura Sound mark: a five-petal blossom with notched petal tips, drawn (not a font glyph).
import QtQuick
import QtQuick.Shapes

Item {
    id: mk
    property color color: Theme.accent
    property color core: Theme.a("#0f1119", 0.9)
    property bool spin: false
    implicitWidth: 24; implicitHeight: 24
    readonly property real k: width / 200      // design space 200×200, centre 100,100

    Item {
        id: rot
        anchors.fill: parent
        RotationAnimation on rotation { running: mk.spin && mk.visible; from: 0; to: 360; duration: 12000; loops: Animation.Infinite
                                        onRunningChanged: if (!running) rot.rotation = 0 }
        Repeater {
            model: 5
            Shape {
                required property int index
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                transform: Rotation { origin.x: mk.width / 2; origin.y: mk.height / 2; angle: index * 72 }
                ShapePath {

                    fillColor: mk.color
                    strokeColor: "transparent"
                    startX: 100 * mk.k; startY: 92 * mk.k
                    PathCubic { x: 82 * mk.k; y: 8 * mk.k;   control1X: 66 * mk.k; control1Y: 74 * mk.k;  control2X: 58 * mk.k; control2Y: 30 * mk.k }
                    PathLine  { x: 100 * mk.k; y: 22 * mk.k }
                    PathLine  { x: 118 * mk.k; y: 8 * mk.k }
                    PathCubic { x: 100 * mk.k; y: 92 * mk.k; control1X: 142 * mk.k; control1Y: 30 * mk.k; control2X: 134 * mk.k; control2Y: 74 * mk.k }
                }
            }
        }
        Rectangle { anchors.centerIn: parent; width: mk.width * 0.16; height: width; radius: width / 2; color: mk.core }
    }
}
