import QtQuick

// MiniVolumeBar.qml
// Compact version used inside the dual (speaker+mic) view of the audio pill.
// Extracted from the original monolithic shell.qml.
//
// Slightly different proportions and fixed small radius (2) to match the
// previous "mini" visual exactly.

Item {
    id: root

    required property var bar

    property real value: 0.0
    property var onSet: function(v){}
    property color fill: bar ? bar.accent : "#89b4fa"
    property color track: bar ? bar.surface : "#313244"

    implicitWidth: 48
    implicitHeight: 5

    Rectangle {
        anchors.fill: parent
        radius: 2
        color: root.track
    }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(parent.width, parent.width * root.value))
        height: parent.height
        radius: 2
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
