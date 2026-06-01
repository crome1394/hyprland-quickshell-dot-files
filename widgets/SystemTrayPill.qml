import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// =============================================================================
// SystemTrayPill.qml — System tray with styled menus
// =============================================================================
//
// Purpose:
//   System tray pill showing icons. Right-click opens a custom glassmorphic
//   menu supporting submenus, check items, radio items, and separators.
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.glassHover, bar.pillBorder, bar.accent
//   - bar.iconSizeTray, bar.controlBorderWidth
//   - bar.popupRadius, bar.glassPopupBg, bar.glassPopupBorder,
//     bar.glassPopupHighlight, bar.popupHeaderHighlightHeight,
//     bar.popupSpacing, bar.popupHintSize, bar.buttonRadius
//   - bar.menuBtnNone, bar.menuBtnCheck, bar.menuBtnRadio
//   - bar.text, bar.subtext, bar.overlay, bar.accent, bar.glassHover
//   - bar.dividerStrong
//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - required property Item barBg (for popup positioning)
//   - Quickshell.Services.SystemTray
//   - Quickshell.Widgets (IconImage)
//
// Notes:
//   - All menu logic (menuStack, QsMenuOpener, submenus, check/radio/separator handling) is preserved exactly.
//   - Menu delegate styling has been aligned to theme tokens where safe.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    visible: SystemTray.items.values.length > 0
    Layout.preferredWidth: visible ? (trayContent.implicitWidth + 14) : 0
    Layout.preferredHeight: bar.pillHeight
    radius: bar.pillRadius
    color: trayHover.containsMouse ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: trayHover.containsMouse ? bar.accent : bar.pillBorder

    MouseArea {
        id: trayHover
        anchors.fill: parent
        hoverEnabled: true
    }

    Item {
        id: trayContent
        anchors.centerIn: parent
        implicitWidth: trayIconsRow.implicitWidth
        implicitHeight: trayIconsRow.implicitHeight

        Row {
            id: trayIconsRow
            spacing: 8
            anchors.centerIn: parent

            Repeater {
                model: SystemTray.items.values
                delegate: Item {
                    id: trayIconItem
                    required property var modelData
                    width: bar.iconSizeTray + 2
                    height: bar.iconSizeTray + 2

                    IconImage {
                        anchors.centerIn: parent
                        width: bar.iconSizeTray
                        height: bar.iconSizeTray
                        source: modelData ? modelData.icon : ""
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (!modelData) return;
                            if (mouse.button === Qt.LeftButton) {
                                modelData.activate();
                            } else if (mouse.button === Qt.RightButton) {
                                if (modelData.hasMenu) {
                                    showTrayMenu(modelData, trayIconItem);
                                } else {
                                    modelData.activate();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ===== TRAY MENU HELPERS =====
    function showTrayMenu(trayItem, sourceItem) {
        if (!trayItem || !trayItem.hasMenu) return;
        trayMenuPopup.currentItem = trayItem;
        trayMenuPopup.menuHandle = trayItem.menu;
        trayMenuPopup.menuStack = [];
        trayMenuPopup.itemTitle = trayItem.title || trayItem.id || "Menu";

        var p = sourceItem.mapToItem(barBg, sourceItem.width / 2, sourceItem.height);
        var popupW = trayMenuPopup.implicitWidth || 220;
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;

        var targetX = bar.sideMargin + p.x - (popupW / 2);
        var minX = 12;
        var maxX = screenW - popupW - 12;
        trayMenuPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX));
        trayMenuPopup.anchor.rect.y = bar.implicitHeight + 4;

        trayMenuPopup.visible = true;
    }

    function closeTrayMenu() {
        trayMenuPopup.visible = false;
        trayMenuPopup.menuStack = [];
        trayMenuPopup.menuHandle = null;
        trayMenuPopup.currentItem = null;
    }

    // ===== STYLED SYSTEM TRAY MENU POPUP =====
    PopupWindow {
        id: trayMenuPopup
        anchor.window: bar
        implicitWidth: Math.max(200, menuContent.implicitWidth + 24)
        implicitHeight: Math.min(520, Math.max(80, menuContent.implicitHeight + 28))
        visible: false
        color: "transparent"

        property var currentItem: null
        property var menuHandle: null
        property var menuStack: []
        property string itemTitle: ""

        QsMenuOpener {
            id: trayMenuOpener
            menu: trayMenuPopup.menuHandle
        }

        function pushSubMenu(handle) {
            if (!handle) return;
            trayMenuPopup.menuStack.push(trayMenuPopup.menuHandle);
            trayMenuPopup.menuHandle = handle;
        }

        function popSubMenu() {
            if (trayMenuPopup.menuStack.length > 0) {
                trayMenuPopup.menuHandle = trayMenuPopup.menuStack.pop();
            } else {
                closeTrayMenu();
            }
        }

        function activateEntry(entry) {
            if (!entry) return;
            if (entry.hasChildren) {
                pushSubMenu(entry);
            } else {
                entry.triggered();
                closeTrayMenu();
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
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
                id: menuContent
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                spacing: 2

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4

                    Text {
                        Layout.fillWidth: true
                        text: trayMenuPopup.itemTitle
                        color: bar.text
                        font.pixelSize: bar.popupHintSize
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: trayMenuPopup.menuStack.length > 0
                        width: 22; height: 22; radius: bar.buttonRadius
                        color: backMa.containsMouse ? bar.surface : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "←"
                            color: bar.accent
                            font.pixelSize: 14
                            font.bold: true
                        }
                        MouseArea {
                            id: backMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: trayMenuPopup.popSubMenu()
                        }
                    }

                    Rectangle {
                        width: 22; height: 22; radius: bar.buttonRadius
                        color: closeMa.containsMouse ? bar.surface : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: bar.subtext
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: closeTrayMenu()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    height: 1
                    color: bar.dividerStrong
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 4
                    spacing: 1

                    Repeater {
                        model: trayMenuOpener.children
                        delegate: Rectangle {
                            id: entryRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: modelData && modelData.isSeparator ? 6 : 28
                            radius: bar.buttonRadius
                            color: entryMouse.containsMouse && !modelData.isSeparator ? bar.glassHover : "transparent"
                            visible: modelData && modelData.enabled !== false

                            MouseArea {
                                id: entryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: modelData && !modelData.isSeparator
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData) trayMenuPopup.activateEntry(modelData);
                                }
                            }

                            Rectangle {
                                visible: modelData && modelData.isSeparator
                                anchors.centerIn: parent
                                width: parent.width - 16
                                height: 1
                                color: bar.dividerStrong
                            }

                            RowLayout {
                                visible: modelData && !modelData.isSeparator
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                Item {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: modelData && modelData.buttonType !== bar.menuBtnNone || (modelData && modelData.checkState !== undefined && modelData.checkState !== 0)

                                    Text {
                                        anchors.centerIn: parent
                                        text: {
                                            if (!modelData) return "";
                                            if (modelData.buttonType === bar.menuBtnRadio) return modelData.checkState === Qt.Checked ? "●" : "○";
                                            if (modelData.buttonType === bar.menuBtnCheck) return modelData.checkState === Qt.Checked ? "✓" : (modelData.checkState === Qt.PartiallyChecked ? "◐" : "");
                                            return "";
                                        }
                                        color: bar.accent
                                        font.pixelSize: bar.popupHintSize
                                        font.bold: true
                                    }
                                }

                                IconImage {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: modelData && modelData.icon && modelData.icon.length > 0
                                    source: (modelData && modelData.icon) ? modelData.icon : ""
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData ? (modelData.text || "") : ""
                                    color: entryMouse.containsMouse ? bar.text : bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: modelData && modelData.hasChildren
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "▸"
                                    color: bar.accent
                                    font.pixelSize: bar.popupHintSize
                                }
                            }
                        }
                    }

                    Text {
                        visible: (!trayMenuOpener.children || trayMenuOpener.children.length === 0) && !trayMenuPopup.menuHandle
                        Layout.alignment: Qt.AlignHCenter
                        text: "(no menu)"
                        color: bar.overlay
                        font.pixelSize: bar.popupHintSize
                        font.italic: true
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: closeTrayMenu()
        }
    }
}
