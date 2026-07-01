import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

// =============================================================================
// QuickLaunchPill.qml — Quick launch row
// =============================================================================
//
// Purpose:
//   Horizontal row of icon buttons inside a pill. Apps and icons are defined in
//   Config.qml (search QUICK LAUNCH — quickLaunchApps).
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.glassHover, bar.pillBorder, bar.accent
//   - bar.quickLaunchIcon, bar.quickLaunchSpacing, bar.quickLaunchPaddingH
//   - bar.quickLaunchApps, bar.fontFamily, bar.controlBorderWidth, bar.tooltipDelay
// =============================================================================

Rectangle {
    id: root

    required property var bar

    Layout.preferredWidth: appsRow.implicitWidth + bar.quickLaunchPaddingH * 2
    Layout.preferredHeight: 36
    Layout.alignment: Qt.AlignVCenter

    radius: bar.pillRadius
    color: appsHover.containsMouse ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: appsHover.containsMouse ? bar.accent : bar.pillBorder

    function launchEntry(entry) {
        if (!entry || entry.command === undefined || entry.command === null)
            return
        if (Array.isArray(entry.command)) {
            if (entry.command.length > 0)
                Quickshell.execDetached(entry.command)
            return
        }
        if (typeof entry.command === "string" && entry.command.length > 0)
            Quickshell.execDetached(["sh", "-c", entry.command])
    }

    function entryUsesGlyph(entry) {
        return entry && (!entry.icon || entry.icon.length === 0) && entry.glyph && entry.glyph.length > 0
    }

    MouseArea {
        id: appsHover
        anchors.fill: parent
        hoverEnabled: true
    }

    Row {
        id: appsRow
        anchors.centerIn: parent
        spacing: bar.quickLaunchSpacing

        Repeater {
            model: bar.quickLaunchApps

            Item {
                required property var modelData
                required property int index

                width: bar.quickLaunchIcon
                height: bar.quickLaunchIcon

                Image {
                    visible: !root.entryUsesGlyph(modelData)
                    anchors.centerIn: parent
                    width: bar.quickLaunchIcon
                    height: bar.quickLaunchIcon
                    source: modelData.icon || ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                Text {
                    visible: root.entryUsesGlyph(modelData)
                    anchors.centerIn: parent
                    text: modelData.glyph || ""
                    font.pixelSize: bar.quickLaunchIcon
                    font.family: bar.fontFamily
                    color: launchClick.containsMouse ? bar.accent : bar.subtext
                }

                MouseArea {
                    id: launchClick
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launchEntry(modelData)

                    ToolTip.text: modelData.tooltip || ""
                    ToolTip.visible: containsMouse && (modelData.tooltip || "").length > 0
                    ToolTip.delay: bar.tooltipDelay
                }
            }
        }
    }
}