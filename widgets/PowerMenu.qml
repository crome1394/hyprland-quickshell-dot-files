import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

// =============================================================================
// PowerMenu.qml — Power / Session menu
// =============================================================================
//
// Purpose:
//   Power/session pill that opens a centered popup with Lock, Logout,
//   Reboot, Shutdown, and Enter BIOS options.
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.glassHover, bar.pillBorder, bar.accent
//   - bar.iconPower, bar.iconSizePillLarge, bar.fontFamily
//   - bar.popupRadiusLarge, bar.glassPopupBg, bar.glassPopupBorder,
//     bar.glassPopupHighlight, bar.popupHeaderHighlightHeight,
//     bar.popupSpacing, bar.popupTitleSize, bar.popupHintSize,
//     bar.controlBorderWidth, bar.buttonRadius,
//     bar.popupSectionSpacing, bar.dividerSubtle
//   - bar.popupPowerWidth, bar.popupPowerHeight
//   - bar.text, bar.subtext, bar.overlay
//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - required property Item barBg (for popup positioning)
//
// Notes:
//   - Power action commands are preserved exactly.
//   - Button styling inside the popup has been aligned to theme tokens
//     (including new state colors where applicable).
//   - Action buttons inside the Repeater still contain some hardcoded
//     values (radius, sizes, spacing, font sizes) — noted for possible
//     future micro-pass.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    // === Layout (for RowLayout participation in the bar) ===
    Layout.preferredWidth: 42
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    // === Appearance via Theme ===
    radius: bar.pillRadius
    color: powerMouse.containsMouse ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
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
        ToolTip.delay: bar.tooltipDelay

        onClicked: {
            if (powerPopup.visible) {
                powerPopup.visible = false
            } else {
                showPowerMenu()
            }
        }
    }

    // ===== Power / Session Menu Helpers =====
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
        powerPopup.anchor.rect.y = bar.popupAnchorY(powerPopup.implicitHeight);

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
        implicitWidth: bar.popupPowerWidth
        implicitHeight: bar.popupPowerHeight
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadiusLarge
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                spacing: bar.popupSectionSpacing

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Power Menu"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "ESC to close"
                        color: bar.overlay
                        font.pixelSize: bar.popupHintSize
                        font.family: bar.fontFamily
                    }

                    Rectangle {
                        width: 26
                        height: 26
                        radius: bar.buttonRadius
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
                    Layout.topMargin: bar.popupSectionSpacing
                    spacing: 10   // deliberate visual gap between large action cards

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
                            color: btnMa.containsMouse ? bar.popupButtonHoverBg : bar.popupButtonHoverBg
                            border.width: bar.controlBorderWidth
                            border.color: btnMa.containsMouse ? bar.accent : bar.dividerSubtle

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    font.pixelSize: 32
                                    font.family: bar.fontFamily
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
