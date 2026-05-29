import QtQuick

// Sparkline.qml
// Compact filled history graph for dashboard sparklines.
// Expects an array of numbers (0-100 range recommended).
//
// Properties:
//   history    : array, most recent value should be at the end
//   maxPoints  : how many points to display
//   lineColor / fillColor

Item {
    id: root

    property var history: []
    property int maxPoints: 42
    property color lineColor: "#89b4fa"
    property color fillColor: Qt.rgba(0.53, 0.71, 0.98, 0.18)
    property real lineWidth: 1.5

    implicitWidth: 120
    implicitHeight: 36

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const w = width
            const h = height
            const data = root.history

            if (!data || data.length < 2) {
                // faint placeholder
                ctx.beginPath()
                ctx.moveTo(0, h * 0.65)
                ctx.lineTo(w, h * 0.65)
                ctx.lineWidth = 1
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08)
                ctx.stroke()
                return
            }

            const n = Math.min(data.length, root.maxPoints)
            const stepX = w / (n - 1)

            // Compute visible range
            let minV = 100, maxV = 0
            for (let i = 0; i < n; i++) {
                const v = Math.max(0, Math.min(100, data[i]))
                if (v < minV) minV = v
                if (v > maxV) maxV = v
            }
            const range = Math.max(1, maxV - minV)

            // Main line path
            ctx.beginPath()
            for (let i = 0; i < n; i++) {
                const v = Math.max(0, Math.min(100, data[i]))
                const x = i * stepX
                const y = h - ((v - minV) / range) * (h - 4) - 2
                if (i === 0) ctx.moveTo(x, y)
                else ctx.lineTo(x, y)
            }

            ctx.lineWidth = root.lineWidth
            ctx.strokeStyle = root.lineColor
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.stroke()

            // Fill under line
            ctx.lineTo(w, h)
            ctx.lineTo(0, h)
            ctx.closePath()
            ctx.fillStyle = root.fillColor
            ctx.fill()

            // Redraw crisp line on top
            ctx.beginPath()
            for (let i = 0; i < n; i++) {
                const v = Math.max(0, Math.min(100, data[i]))
                const x = i * stepX
                const y = h - ((v - minV) / range) * (h - 4) - 2
                if (i === 0) ctx.moveTo(x, y)
                else ctx.lineTo(x, y)
            }
            ctx.lineWidth = root.lineWidth
            ctx.strokeStyle = root.lineColor
            ctx.stroke()
        }
    }

    onHistoryChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()
}
