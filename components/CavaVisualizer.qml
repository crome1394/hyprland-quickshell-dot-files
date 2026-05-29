import QtQuick

// CavaVisualizer.qml
// Pure-QML animated "cava-like" waveform bars used as background in the
// centered media pill. No external binary required.
//
// Extracted from the original monolithic shell.qml during the split.
//
// Properties:
//   active          : bool — when true, taller + brighter bars + faster animation
//   barColor        : base (inactive) color
//   barColorActive  : color when active / playing
//
// The component computes its own bar widths dynamically from its width so it
// always spans the parent pill nicely.

Item {
    id: root

    required property var bar   // for future theme-driven colors if desired

    property bool active: false
    property color barColor: Qt.rgba(1, 1, 1, 0.18)
    property color barColorActive: Qt.rgba(0.55, 0.71, 0.98, 0.35)

    readonly property int barCount: 40
    readonly property int barGap: 1

    // Bar width computed dynamically so the waveform always spans the full available width.
    readonly property int barWidth: {
        const avail = root.width > 20 ? root.width : 580;
        const gaps = (barCount - 1) * barGap;
        return Math.max(1, Math.floor((avail - gaps) / barCount));
    }

    // Efficiency trick: slow the animation way down when nothing is playing.
    readonly property int animationInterval: root.active ? 95 : 420

    implicitHeight: 22

    // Animation driver
    property real phase: 0
    Timer {
        running: root.visible && root.barCount > 0
        interval: root.animationInterval
        repeat: true
        onTriggered: root.phase = (root.phase + 0.28) % (Math.PI * 2)
    }

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
