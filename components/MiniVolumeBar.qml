import QtQuick
import "../Theme.qml" as ThemeModule

// =============================================================================
// MiniVolumeBar.qml — Compact volume bar for dual (speaker + mic) view
// =============================================================================
//
// Purpose:
//   Very small version of VolumeBar used exclusively inside the dual-view
//   layout of AudioPill.qml.
//
// Theme Properties Consumed (with fallbacks):
//   - bar.sliderFill / Theme.sliderFill
//   - bar.sliderTrack / Theme.sliderTrack
//   - bar.sliderMiniHeight / Theme.sliderMiniHeight
//   - bar.sliderRadius / Theme.sliderRadius
//
// Dependencies:
//   - Optional: property var bar (preferred)
//   - Fallback: direct import of Theme.qml
//
// Notes:
//   - This is the most space-constrained slider in the entire configuration.
//   - Hybrid access pattern is intentional and preserved exactly.
//   - All fallback defaults are kept in sync with Theme.qml.
// =============================================================================

Item {
    id: root

    // === Properties ===
    property var bar
    property real value: 0.0
    property var onSet: function(v){}

    // === THEME-DRIVEN DEFAULTS (hybrid access) ===
    readonly property QtObject t: ThemeModule.Theme

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

    // === Appearance ===
    // Track
    Rectangle {
        anchors.fill: parent
        radius: root.effectiveRadius
        color: root.track
    }

    // Fill layer (clipped)
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

    // === Behavior ===
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => {
            var f = Math.max(0, Math.min(1, m.x / width));
            root.onSet(f);
        }
    }
}
