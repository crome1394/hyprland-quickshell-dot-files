import QtQuick

// =============================================================================
// CavaVisualizer.qml — Pure-QML animated waveform (MediaPill background)
// =============================================================================
//
// Purpose:
//   Animated “cava-like” waveform bars used as a live visual background
//   inside the centered MediaPill. No external binary required.
//
// Theme Properties Consumed (with fallbacks):
//   - bar.cavaInactive / fallback
//   - bar.cavaActive / fallback
//   - bar.cavaBarCount / fallback
//   - bar.cavaBarGap / fallback
//   - bar.cavaAnimFast / fallback
//   - bar.cavaAnimSlow / fallback
//
// Dependencies:
//   - Optional: property var bar (for theme-driven values)
//   - Falls back to reasonable defaults if bar is not provided
//
// Notes:
//   - The wave mathematics, phase logic, amplitude scaling, and Repeater
//     structure are artistic/effect choices and are intentionally left untouched.
//   - Only the color and timing values that already have Theme tokens have been
//     cleaned up for consistency.
// =============================================================================

Item {
    id: root

    // === Properties ===
    property var bar
    property bool active: false

    // === THEME-DRIVEN VALUES (hybrid access) ===
    property color barColor: (bar && bar.cavaInactive) ? bar.cavaInactive : Qt.rgba(1, 1, 1, 0.18)
    property color barColorActive: (bar && bar.cavaActive) ? bar.cavaActive : Qt.rgba(0.55, 0.71, 0.98, 0.35)

    readonly property int barCount: (bar && bar.cavaBarCount) ? bar.cavaBarCount : 40
    readonly property int barGap: (bar && bar.cavaBarGap !== undefined) ? bar.cavaBarGap : 1

    // Dynamic bar width so the waveform always fills the available space
    readonly property int barWidth: {
        const avail = root.width > 20 ? root.width : 580;
        const gaps = (barCount - 1) * barGap;
        return Math.max(1, Math.floor((avail - gaps) / barCount));
    }

    // Smart animation speed: fast when media is playing, slow when idle
    readonly property int animationInterval: root.active
        ? ((bar && bar.cavaAnimFast) ? bar.cavaAnimFast : 95)
        : ((bar && bar.cavaAnimSlow) ? bar.cavaAnimSlow : 420)

    implicitHeight: 22

    // === Animation Driver ===
    property real phase: 0
    Timer {
        running: root.visible && root.barCount > 0
        interval: root.animationInterval
        repeat: true
        onTriggered: root.phase = (root.phase + 0.28) % (Math.PI * 2)
    }

    // === Visual Waveform ===
    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.barGap

        Repeater {
            model: root.barCount
            Rectangle {
                width: root.barWidth
                radius: 1
                color: root.active ? root.barColorActive : root.barColor

                property real offset: (index * 0.9) + (index % 3) * 0.7

                property real h: {
                    const t = root.phase + offset;
                    const base = root.active ? 5 : 3;
                    const amp = root.active ? 17 : 11;
                    const s = Math.sin(t) * 0.6 + Math.sin(t * 1.7) * 0.4;
                    return Math.max(2, base + s * amp);
                }

                height: h
                anchors.verticalCenter: parent.verticalCenter

                Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            }
        }
    }
}
