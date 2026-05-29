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

    property var bar   // theme source (accent, surface, muted) - supplied by Loader onLoaded for now

    property real value: 0.0
    property var onSet: function(v){}
    property color fill: bar ? bar.accent : "#89b4fa"
    property color track: bar ? bar.surface : "#313244"
    property int barHeight: 6

    implicitWidth: 110
    implicitHeight: barHeight + 4

    // Track
    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: root.barHeight
        radius: height / 2
        color: root.track
    }

    // Fill
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(parent.width, parent.width * root.value))
        height: root.barHeight
        radius: height / 2
        color: root.fill
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
