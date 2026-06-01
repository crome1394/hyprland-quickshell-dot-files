import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

// =============================================================================
// PowerMenu.qml — Power / Session menu
// =============================================================================
//
// Simple power menu with Lock, Logout, Suspend, Reboot, Shutdown, and BIOS entry.
// Opens as a centered popup on click.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    Layout.preferredWidth: 42
    Layout.preferredHeight: 36
    radius: bar.pillRadius
    color: powerMouse.containsMouse ? bar.glassHover : bar.pillBg
    border.width: 1
    border.color: powerMouse.containsMouse ? bar.accent : bar.pillBorder

    Text {
        id: powerIcon
        anchors.centerIn: parent
        text: bar.iconPower
        font.pixelSize: bar.iconSizePillLarge
        font.family: bar.fontFamily
        color: powerMouse.containsMouse ? bar.accent : bar.subtext
    }

    MouseArea {
        id: powerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        ToolTip.text: "Power / Session"
        ToolTip.visible: containsMouse
        ToolTip.delay: 1750

        onClicked: {
            if (powerPopup.visible) {
                powerPopup.visible = false
            } else {
                showPowerMenu()
            }
        }
    }

    // ===== POWER / SESSION MENU HELPERS =====
    function showPowerMenu() {
        if (powerPopup.visible) {
            hidePowerMenu();
            return;
        }

        var pos = root.mapToItem(barBg, root.width / 2, root.height);
        var popupW = powerPopup.implicitWidth;
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;

        var targetX = bar.sideMargin + pos.x - (popupW / 2) + 60;

        var minX = 12;
        var maxX = screenW - popupW - 12;
        powerPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX));
        powerPopup.anchor.rect.y = bar.implicitHeight + 4;

        powerPopup.visible = true;
    }

    function hidePowerMenu() {
        powerPopup.visible = false;
    }

    function powerAction(cmd) {
        Quickshell.execDetached(cmd);
        hidePowerMenu();
    }

    function powerLock()     { powerAction(["hyprlock"]); }
    function powerBios()     { powerAction(["systemctl", "reboot", "--firmware-setup"]); }

    function powerLogout() {
        Quickshell.execDetached([
            "sh", "-c",
            "systemctl --user stop psd.service & pkill -f 'steam|discord|flameshot|espanso|google-chrome-stable' & sleep 1 & command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"
        ]);
        hidePowerMenu();
    }

    function powerReboot() {
        Quickshell.execDetached([
            "sh", "-c",
            "systemctl --user stop psd.service & pkill -f \"steam|discord|flameshot|espanso|google-chrome-stable\" & sleep 1 & reboot"
        ]);
        hidePowerMenu();
    }

    function powerShutdown() {
        Quickshell.execDetached([
            "sh", "-c",
            "systemctl --user stop psd.service & pkill -f \"steam|discord|flameshot|espanso|google-chrome-stable\" & sleep 1 & shutdown now"
        ]);
        hidePowerMenu();
    }

    // ===== POWER MENU POPUP =====
    PopupWindow {
        id: powerPopup
        anchor.window: bar
        implicitWidth: 560
        implicitHeight: 192
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadiusLarge
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Power Menu"
                        color: bar.text
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "ESC to close"
                        color: bar.overlay
                        font.pixelSize: 11
                    }

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 6
                        color: powerCloseMa.containsMouse ? bar.glassHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: bar.subtext
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: powerCloseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: hidePowerMenu()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 10

                    Repeater {
                        model: [
                            { icon: "󰌾", label: "Lock",     action: "lock" },
                            { icon: "󰍃", label: "Logout",   action: "logout" },
                            { icon: "󰑓", label: "Reboot",   action: "reboot" },
                            { icon: "󰐥", label: "Shutdown", action: "shutdown" },
                            { icon: "󰛳", label: "Enter BIOS", action: "bios" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 92
                            radius: 10
                            color: btnMa.containsMouse ? bar.glassHover : Qt.rgba(0.10, 0.10, 0.12, 0.55)
                            border.width: 1
                            border.color: btnMa.containsMouse ? bar.accent : Qt.rgba(1, 1, 1, 0.06)

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    font.pixelSize: 32
                                    font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                                    color: btnMa.containsMouse ? bar.accent : bar.text
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: btnMa.containsMouse ? bar.text : bar.subtext
                                }
                            }

                            MouseArea {
                                id: btnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    switch (modelData.action) {
                                        case "lock":     powerLock(); break;
                                        case "logout":   powerLogout(); break;
                                        case "reboot":   powerReboot(); break;
                                        case "shutdown": powerShutdown(); break;
                                        case "bios":     powerBios(); break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: hidePowerMenu()
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: hidePowerMenu()
        }
    }
}
