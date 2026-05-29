import QtQuick
import Quickshell

// QuickLaunchPill.qml
// Encapsulated quick launch icons pill (VSCodium, Firefox, Logseq, LM Studio, etc.)
// Extracted from the original monolithic shell.qml.

Rectangle {
    id: root

    required property var bar   // theme + style source

    Layout.preferredWidth: appsRow.implicitWidth + 20
    Layout.preferredHeight: 36
    radius: bar.pillRadius
    color: appsHover.containsMouse ? bar.glassHover : bar.pillBg
    border.width: 1
    border.color: appsHover.containsMouse ? bar.accent : bar.pillBorder

    MouseArea {
        id: appsHover
        anchors.fill: parent
        hoverEnabled: true
    }

    Row {
        id: appsRow
        anchors.centerIn: parent
        spacing: 10

        // VSCodium
        Item {
            width: 20; height: 20
            Image {
                anchors.centerIn: parent
                width: 20; height: 20
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
            width: 20; height: 20
            Image {
                anchors.centerIn: parent
                width: 20; height: 20
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
            width: 20; height: 20
            Image {
                anchors.centerIn: parent
                width: 20; height: 20
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
            width: 20; height: 20
            Image {
                anchors.centerIn: parent
                width: 20; height: 20
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
