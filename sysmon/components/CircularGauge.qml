import QtQuick

// CircularGauge.qml
// Dashboard-style circular gauge with threshold-based coloring.
// Designed for CPU/GPU/Memory style metrics (0-100).
//
// Properties:
//   value      : 0-100
//   label      : center label (e.g. "CPU")
//   subValue   : small text below (e.g. "62°C")
//   size       : diameter in pixels
//   strokeWidth
//
// The gauge uses a 270° arc (bottom-open style) and colors:
//   green (<65) → yellow (65-85) → red (>85)

Item {
    id: root

    property real value: 0
    property string label: ""
    property string subValue: ""
    property int size: 92
    property int strokeWidth: 9

    // Dashboard palette (matches Catppuccin + your main bar)
    property color bgColor: Qt.rgba(1, 1, 1, 0.07)
    property color lowColor: "#a6e3a1"     // green
    property color midColor: "#f9e2af"     // yellow
    property color highColor: "#f38ba8"    // red

    readonly property real clamped: Math.max(0, Math.min(100, value))
    readonly property color gaugeColor: clamped > 85 ? highColor : (clamped > 65 ? midColor : lowColor)

    implicitWidth: size
    implicitHeight: size

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const w = width
            const h = height
            const cx = w / 2
            const cy = h / 2
            const radius = (Math.min(w, h) / 2) - (root.strokeWidth / 2) - 1

            const startAngle = -Math.PI * 0.75
            const endAngle = Math.PI * 0.75
            const fullSweep = endAngle - startAngle
            const progress = root.clamped / 100
            const currentAngle = startAngle + fullSweep * progress

            // Background track
            ctx.beginPath()
            ctx.arc(cx, cy, radius, startAngle, endAngle, false)
            ctx.lineWidth = root.strokeWidth
            ctx.strokeStyle = root.bgColor
            ctx.lineCap = "round"
            ctx.stroke()

            // Progress arc
            if (progress > 0.005) {
                ctx.beginPath()
                ctx.arc(cx, cy, radius, startAngle, currentAngle, false)
                ctx.lineWidth = root.strokeWidth
                ctx.strokeStyle = root.gaugeColor
                ctx.lineCap = "round"
                ctx.stroke()
            }

            // Subtle inner highlight ring
            ctx.beginPath()
            ctx.arc(cx, cy, radius - root.strokeWidth * 0.55, startAngle, endAngle, false)
            ctx.lineWidth = 1.5
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.05)
            ctx.stroke()
        }
    }

    // Center text block
    Column {
        anchors.centerIn: parent
        spacing: -1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.clamped.toFixed(0) + "%"
            font.pixelSize: root.size * 0.30
            font.bold: true
            color: root.gaugeColor
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font.pixelSize: root.size * 0.14
            color: "#cdd6f4"
            opacity: 0.9
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.subValue !== ""
            text: root.subValue
            font.pixelSize: root.size * 0.12
            color: "#a6adc8"
        }
    }

    onValueChanged: canvas.requestPaint()
    onGaugeColorChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()
}
