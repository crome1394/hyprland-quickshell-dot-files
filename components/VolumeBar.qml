import QtQuick

// VolumeBar.qml
// Reusable clickable volume fill bar (used in audio popup and speaker/mic views).
// Extracted from the original monolithic shell.qml during incremental modularization.
//
// Properties (match the old inline Component exactly for drop-in replacement):
//   value     : 0.0 - 1.0 fill fraction
//   onSet(v)  : callback when user clicks to set a new volume
//   fill      : color of the filled portion (usually accent or muted)
//   track     : background track color
//   barHeight : thickness of the bar
//
// Pass `bar` (the root PanelWindow) so it can pick up theme colors as defaults.

Item {
    id: root

    property var bar   // theme source (accent, surface, muted)

    property real value: 0.0
    property var onSet: function(v){}
    property color fill: bar ? bar.accent : "#89b4fa"
    property color track: bar ? bar.surface : "#313244"
    property int barHeight: 6

    implicitWidth: 110
    implicitHeight: barHeight + 4

    // Force actual size from implicit when used with anchors.centerIn.
    // (anchors.fill from caller will take precedence)
    width: implicitWidth
    height: implicitHeight

    // This handler + computed property helps ensure external bindings
    // (especially from PopupWindow / complex layouts) properly drive updates.
    onValueChanged: {
        // Intentionally empty — presence of the handler forces observation.
    }

    readonly property real effectiveValue: Math.max(0, Math.min(1, value))

    // Track (background)
    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: root.barHeight
        radius: height / 2
        color: root.track
    }

    // Fill layer - use a clipped container for maximum reliability with dynamic width.
    // This pattern avoids most anchor + binding calculation problems.
    Item {
        id: fillContainer
        anchors.centerIn: parent
        width: parent.width
        height: root.barHeight
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: fillContainer.width * root.effectiveValue
            height: parent.height
            radius: height / 2
            color: root.fill || (root.bar ? root.bar.accent : "#89b4fa")
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => {
            var f = Math.max(0, Math.min(1, m.x / width));
            root.onSet(f);
        }
    }
}
