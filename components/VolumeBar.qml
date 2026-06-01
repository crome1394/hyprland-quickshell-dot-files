import QtQuick
import "../Theme.qml" as ThemeModule

// VolumeBar.qml
// Reusable clickable volume fill bar (used in audio popup and speaker/mic views).
//
// This component now pulls its defaults from the central Theme singleton
// (via the aliases that shell.qml exposes on `bar`, or by direct import).
// All slider styling is therefore controlled from one place.
//
// Properties:
//   value     : 0.0 - 1.0 fill fraction
//   onSet(v)  : callback when user clicks to set a new volume
//   fill      : color of the filled portion (falls back to Theme.sliderFill / sliderFillMuted)
//   track     : background track color (falls back to Theme.sliderTrack)
//   barHeight : thickness of the bar (falls back to Theme.sliderBarHeight / sliderPopupHeight)
//
// Pass `bar` (the root PanelWindow) — it now carries all the new slider* aliases.

Item {
    id: root

    // Theme source. When present, we read slider* properties from it.
    // This is the standard Quickshell pattern (everything flows through the bar object).
    property var bar

    property real value: 0.0
    property var onSet: function(v){}

    // === SLIDER STYLING FROM THEME (the key centralization) ===
    // The component prefers values passed via `bar` (for per-instance control and backward compat),
    // but falls back to the central Theme.qml directly so the slider styling is always recognized
    // even if `bar` aliases are not present.
    readonly property QtObject t: ThemeModule.Theme

    // `fill` is usually overridden by the parent (AudioPill) to handle muted vs normal state using accent/muted.
    // The default below is for standalone use or when no override is given.
    property color fill:     (bar && bar.sliderFill)  ? bar.sliderFill  : (t ? t.sliderFill     : "#0095ff")
    property color track:    (bar && bar.sliderTrack) ? bar.sliderTrack : (t ? t.sliderTrack    : "#313244")
    property int  barHeight: (bar && bar.sliderBarHeight) ? bar.sliderBarHeight : (t ? t.sliderBarHeight : 6)

    // Optional explicit radius from theme (0 = auto pill shape)
    readonly property int effectiveRadius: (bar && bar.sliderRadius !== undefined && bar.sliderRadius > 0)
        ? bar.sliderRadius
        : (t && t.sliderRadius !== undefined && t.sliderRadius > 0 ? t.sliderRadius : (barHeight / 2))

    implicitWidth: 110
    implicitHeight: barHeight + 4

    // Force actual size from implicit when used with anchors.centerIn.
    width: implicitWidth
    height: implicitHeight

    onValueChanged: {
        // Intentionally empty — presence of the handler forces observation for bindings.
    }

    readonly property real effectiveValue: Math.max(0, Math.min(1, value))

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

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => {
            var f = Math.max(0, Math.min(1, m.x / width));
            root.onSet(f);
        }
    }
}
