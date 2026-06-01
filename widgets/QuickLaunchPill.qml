import QtQuick
import QtQuick.Layouts
import Quickshell

// =============================================================================
// QuickLaunchPill.qml — Quick launch row
// =============================================================================
//
// Purpose:
//   Horizontal row of icon buttons inside a pill that launch frequently used
//   applications (VSCodium, Firefox, Logseq, LM Studio).
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.glassHover, bar.pillBorder, bar.accent
//   - bar.quickLaunchIcon, bar.controlBorderWidth
//
// Dependencies:
//   - required property var bar (from shell.qml)
//
// Notes:
//   - Each icon has its own MouseArea for clicks while the outer area handles hover.
//   - Icon paths and launch commands are content and are left unchanged.
// =============================================================================

Rectangle {
    id: root

    // === Required Properties ===
    required property var bar

    // === Layout (for RowLayout participation in the bar) ===
    Layout.preferredWidth: appsRow.implicitWidth + 20
    Layout.preferredHeight: 36
    Layout.alignment: Qt.AlignVCenter

    // === Appearance via Theme ===
    radius: bar.pillRadius
    color: appsHover.containsMouse ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: appsHover.containsMouse ? bar.accent : bar.pillBorder

    // === Hover Area (covers the whole pill) ===
    MouseArea {
        id: appsHover
        anchors.fill: parent
        hoverEnabled: true
    }

    // === Content ===
    Row {
        id: appsRow
        anchors.centerIn: parent
        spacing: 10

        // VSCodium
        Item {
            width: bar.quickLaunchIcon
            height: bar.quickLaunchIcon

            Image {
                anchors.centerIn: parent
                width: bar.quickLaunchIcon
                height: bar.quickLaunchIcon
                source: "/home/crome/icons/vscodium.svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["gtk-launch", "vscodium"])
            }
        }

        // Firefox
        Item {
            width: bar.quickLaunchIcon
            height: bar.quickLaunchIcon

            Image {
                anchors.centerIn: parent
                width: bar.quickLaunchIcon
                height: bar.quickLaunchIcon
                source: "/home/crome/icons/firefox.svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["gtk-launch", "firefox"])
            }
        }

        // Logseq
        Item {
            width: bar.quickLaunchIcon
            height: bar.quickLaunchIcon

            Image {
                anchors.centerIn: parent
                width: bar.quickLaunchIcon
                height: bar.quickLaunchIcon
                source: "/home/crome/icons/logseq-a.svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["gtk-launch", "logseq"])
            }
        }

        // LM Studio
        Item {
            width: bar.quickLaunchIcon
            height: bar.quickLaunchIcon

            Image {
                anchors.centerIn: parent
                width: bar.quickLaunchIcon
                height: bar.quickLaunchIcon
                source: "/home/crome/icons/lmstudio-dark.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached([
                    "/home/crome/applications/LM-Studio-0.4.13-1-x64.AppImage"
                ])
            }
        }
    }
}
