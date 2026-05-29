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

    // Force actual size from implicit when the component is centered
    // via anchors.centerIn (common in the bar pill). Anchors.fill cases
    // from the caller will override this.
    width: implicitWidth
    height: implicitHeight

    // Track
    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: root.barHeight
        radius: height / 2
        color: root.track
    }

    // Fill - use root.width explicitly for more reliable binding
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.width * root.value
        height: root.barHeight
        radius: height / 2
        color: root.fill
        visible: root.value > 0
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
