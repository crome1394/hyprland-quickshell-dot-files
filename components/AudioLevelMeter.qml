import QtQuick
import "../Config.qml" as ConfigModule

// =============================================================================
// AudioLevelMeter.qml — Compact VU-style peak / level meter
// =============================================================================
//
// Purpose:
//   Pure visual real-time level meter for the AudioPill popup.  Driven by an
//   external 0..1 `level` property (typically PwNodePeakMonitor.peak).
//   Includes a decaying peak-hold marker for classic VU readability.
//
// Theme Properties Consumed (with fallbacks):
//   - bar.sliderTrack / Theme.sliderTrack  (track background)
//   - bar.muted / Theme.muted              (when muted)
//
// Dependencies:
//   - Optional: property var bar (theme carrier)
//   - Does NOT talk to PipeWire itself — parent supplies `level` / `muted`.
//
// Notes:
//   - Safe to keep mounted when idle: zero level draws an empty track only.
//   - Peak-hold decay is local UI state and never writes audio parameters.
// =============================================================================

Item {
    id: root

    // === Properties ===
    property var bar
    property real level: 0.0          // Instantaneous level, 0..1
    property bool muted: false
    property int barHeight: 8
    // How long (ms) the peak tick lingers before decaying
    property int peakHoldMs: 600
    property real peakDecayPerTick: 0.04

    readonly property QtObject t: ConfigModule.Config

    property color track: (bar && bar.sliderTrack) ? bar.sliderTrack
                        : (t ? t.sliderTrack : "#1a1c1f")
    property color mutedColor: (bar && bar.muted) ? bar.muted
                             : (t ? t.muted : "#5c5c60")

    // Local peak-hold (UI only)
    property real peakHold: 0.0

    implicitWidth: 120
    implicitHeight: barHeight + 2
    width: implicitWidth
    height: implicitHeight

    readonly property real clampedLevel: Math.max(0, Math.min(1, level))

    // Colour ramp: green → yellow → orange → red (matches AudioPill volume tiers)
    function levelColor(v) {
        if (root.muted)
            return root.mutedColor
        var p = Math.max(0, Math.min(1, v))
        if (p < 0.60)
            return "#10B981"   // green
        if (p < 0.80)
            return "#F59E0B"   // amber
        if (p < 0.92)
            return "#F97316"   // orange
        return "#EF4444"       // red (near clip)
    }

    onClampedLevelChanged: {
        if (clampedLevel > peakHold)
            peakHold = clampedLevel
    }

    // Peak-hold decay timer — only runs while the meter is visible
    Timer {
        interval: 50
        repeat: true
        running: root.visible
        onTriggered: {
            if (root.peakHold > root.clampedLevel) {
                root.peakHold = Math.max(root.clampedLevel, root.peakHold - root.peakDecayPerTick)
            }
        }
    }

    // Track
    Rectangle {
        id: trackRect
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.barHeight
        radius: Math.max(1, root.barHeight / 2)
        color: root.track
        clip: true

        // Level fill
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * root.clampedLevel
            height: parent.height
            radius: parent.radius
            color: root.levelColor(root.clampedLevel)

            Behavior on width {
                NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
            }
        }

        // Peak-hold tick (thin vertical marker)
        Rectangle {
            visible: root.peakHold > 0.02
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(parent.width - width, parent.width * root.peakHold - width / 2))
            width: 2
            height: parent.height
            radius: 1
            color: root.muted ? root.mutedColor : "#FFFFFF"
            opacity: 0.85
        }
    }
}
