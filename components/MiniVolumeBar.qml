import QtQuick
import "../Theme.qml" as ThemeModule

// MiniVolumeBar.qml
// Compact version used inside the dual (speaker+mic) view of the audio pill.
//
// Now fully driven by the central Theme singleton (via bar.sliderMini* aliases).
// The old hardcoded fill "#89b4fa" and radius 2 are gone — everything is in Theme.qml.

Item {
    id: root

    property var bar   // carries the new slider* properties from Theme

    property real value: 0.0
    property var onSet: function(v){}

    // === THEME-DRIVEN DEFAULTS (the centralization fix) ===
    // Direct import of Theme.qml so the slider styling properties are always available
    // inside the component (the original request).
    readonly property QtObject t: ThemeModule.Theme

    // `fill` is usually overridden by the parent for mute state logic.
    property color fill:     (bar && bar.sliderFill) ? bar.sliderFill : (t ? t.sliderFill : "#0095ff")
    property color track:    (bar && bar.sliderTrack) ? bar.sliderTrack : (t ? t.sliderTrack : "#313244")
    property int  barHeight: (bar && bar.sliderMiniHeight) ? bar.sliderMiniHeight : (t ? t.sliderMiniHeight : 5)

    readonly property int effectiveRadius: (bar && bar.sliderRadius !== undefined && bar.sliderRadius > 0)
        ? bar.sliderRadius
        : (t && t.sliderRadius !== undefined && t.sliderRadius > 0 ? t.sliderRadius : (barHeight / 2))

    implicitWidth: 48
    implicitHeight: barHeight

    width: implicitWidth
    height: implicitHeight

    onValueChanged: {
        // Intentionally empty — forces binding observation
    }

    readonly property real effectiveValue: Math.max(0, Math.min(1, value))

    // Track
    Rectangle {
        anchors.fill: parent
        radius: root.effectiveRadius
        color: root.track
    }

    // Fill layer (clipped container = reliable dynamic width)
    Item {
        id: fillContainer
        anchors.fill: parent
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: fillContainer.width * root.effectiveValue
            height: parent.height
            radius: root.effectiveRadius
            color: root.fill
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
