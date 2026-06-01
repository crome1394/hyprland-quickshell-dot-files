import QtQuick
import "../Theme.qml" as ThemeModule

// =============================================================================
// VolumeBar.qml — Reusable clickable volume / progress bar
// =============================================================================
//
// Purpose:
//   Low-level clickable fill bar used for volume (speaker/mic) and progress.
//   Used inside AudioPill and audio popups.
//
// Theme Properties Consumed (with fallbacks):
//   - bar.sliderFill / Theme.sliderFill
//   - bar.sliderTrack / Theme.sliderTrack
//   - bar.sliderBarHeight / Theme.sliderBarHeight
//   - bar.sliderRadius / Theme.sliderRadius
//
// Dependencies:
//   - Optional: property var bar (preferred — carries aliases from shell.qml)
//   - Fallback: direct import of Theme.qml (for standalone use or when bar aliases are absent)
//
// Notes:
//   - Hybrid access pattern is intentional and preserved.
//   - All fallback defaults are kept in sync with Theme.qml.
//   - This component is used by AudioPill (single + dual views) and audio popups.
// =============================================================================

Item {
    id: root

    // === Properties ===
    property var bar
    property real value: 0.0
    property var onSet: function(v){}

    // === SLIDER STYLING FROM THEME (hybrid access) ===
    // Primary path: values from bar (preferred for consistency with the rest of the UI).
    // Fallback path: direct Theme.qml import (ensures the component remains usable
    // even if bar aliases are not present).
    readonly property QtObject t: ThemeModule.Theme

    property color fill:     (bar && bar.sliderFill)  ? bar.sliderFill  : (t ? t.sliderFill     : "#0095ff")
    property color track:    (bar && bar.sliderTrack) ? bar.sliderTrack : (t ? t.sliderTrack    : "#313244")
    property int  barHeight: (bar && bar.sliderBarHeight) ? bar.sliderBarHeight : (t ? t.sliderBarHeight : 6)

    readonly property int effectiveRadius: (bar && bar.sliderRadius !== undefined && bar.sliderRadius > 0)
        ? bar.sliderRadius
        : (t && t.sliderRadius !== undefined && t.sliderRadius > 0 ? t.sliderRadius : (barHeight / 2))

    implicitWidth: 110
    implicitHeight: barHeight + 4

    width: implicitWidth
    height: implicitHeight

    onValueChanged: {
        // Intentionally empty — presence of the handler forces observation for bindings.
    }

    readonly property real effectiveValue: Math.max(0, Math.min(1, value))

    // === Appearance ===
    // Track (background)
    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: root.barHeight
        radius: root.effectiveRadius
        color: root.track
    }

    // Fill layer — clipped container is the most reliable pattern for dynamic width.
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
