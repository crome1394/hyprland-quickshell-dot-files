import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

import "../components"

// =============================================================================
// AudioPill.qml — Audio control pill (speaker + mic + device menus)
// =============================================================================
//
// Three view modes cycled with left click:
//   0 = Speaker volume
//   1 = Microphone volume
//   2 = Both (compact)
//
// Right click opens the full audio popup with device lists.
// Middle click mutes the current view's device.
// Wheel on the bars changes volume.
//
// All PipeWire logic lives in the private `audio` QtObject.
// Reuses VolumeBar and MiniVolumeBar from ../components.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    Layout.preferredWidth: bar.audioViewContentWidth + 18
    Layout.preferredHeight: 36
    radius: bar.pillRadius
    color: audioHover.containsMouse ? bar.glassHover : bar.pillBg
    border.width: 1
    border.color: audioHover.containsMouse ? bar.accent : bar.pillBorder

    // ===== AUDIO STATE (moved from main file) =====
    PwObjectTracker {
        id: audioTracker
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(function(n){ return !!n; })
    }

    QtObject {
        id: audio
        property int viewMode: 0  // 0=speaker, 1=mic, 2=dual

        property var sinks: []
        property var sources: []

        readonly property var speaker: Pipewire.defaultAudioSink
        readonly property var mic: Pipewire.defaultAudioSource

        readonly property real speakerVolume: (speaker && speaker.audio) ? speaker.audio.volume : 0.0
        readonly property bool speakerMuted: (speaker && speaker.audio) ? speaker.audio.muted : false
        readonly property real micVolume: (mic && mic.audio) ? mic.audio.volume : 0.0
        readonly property bool micMuted: (mic && mic.audio) ? mic.audio.muted : false

        readonly property int speakerPercent: Math.round(speakerVolume * 100)
        readonly property int micPercent: Math.round(micVolume * 100)

        property bool deviceListForSink: true

        function setVolume(node, v) {
            if (node && node.audio) node.audio.volume = Math.max(0.0, Math.min(1.0, v));
        }
        function stepVolume(node, delta) {
            if (!node || !node.audio) return;
            var nv = Math.max(0.0, Math.min(1.0, node.audio.volume + delta));
            node.audio.volume = nv;
        }
        function toggleMute(node) {
            if (node && node.audio) node.audio.muted = !node.audio.muted;
        }
        function cycleView() { viewMode = (viewMode + 1) % 3; }

        function refreshDevices() {
            var s = [], r = [];
            var vals = (Pipewire.nodes && Pipewire.nodes.values) ? Pipewire.nodes.values : [];
            for (var i = 0; i < vals.length; i++) {
                var n = vals[i];
                if (!n || !n.audio) continue;
                var nm = n.description || n.name || n.nickname || "Device";
                if (n.isSink && !n.isStream) s.push({node: n, name: nm});
                else if (!n.isSink && !n.isStream) r.push({node: n, name: nm});
            }
            var cmp = function(a,b){ return a.name.localeCompare(b.name); };
            s.sort(cmp); r.sort(cmp);
            audio.sinks = s;
            audio.sources = r;
        }

        function getCurrentDeviceName(isSink) {
            var def = isSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource;
            if (!def) return "Default";
            return def.description || def.name || def.nickname || "Device";
        }
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() {
            audio.refreshDevices();
            // Keep the direct PipeWire stream list fresh (used in the media popup's PipeWire sources section).
            // Complements the MPRIS path.
        }
    }

    // ===== THE PILL UI =====
    MouseArea {
        id: audioHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                audio.cycleView();
            } else if (mouse.button === Qt.MiddleButton) {
                if (audio.viewMode === 0) audio.toggleMute(audio.speaker);
                else if (audio.viewMode === 1) audio.toggleMute(audio.mic);
                else audio.toggleMute(audio.speaker);
            } else if (mouse.button === Qt.RightButton) {
                showAudioPopup();
            }
        }
    }

    Item {
        id: audioContent
        anchors.centerIn: parent
        width: bar.audioViewContentWidth
        implicitWidth: width
        implicitHeight: 22

        // SPEAKER VIEW
        Row {
            visible: audio.viewMode === 0
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: audio.speakerMuted ? "" : ""
                font.pixelSize: 16
                font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                color: audio.speakerMuted ? bar.muted : bar.accent
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: 110; height: 18
                anchors.verticalCenter: parent.verticalCenter

                VolumeBar {
                    id: spkBar
                    anchors.centerIn: parent
                    bar: bar
                    onSet: function(v){ audio.setVolume(audio.speaker, v); }
                    fill: Qt.binding(function(){ return audio.speakerMuted ? bar.muted : bar.accent; })
                }
                Binding {
                    target: spkBar
                    property: "value"
                    value: audio.speakerVolume
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (e) => {
                        const d = (e.angleDelta.y > 0) ? 0.05 : -0.05;
                        audio.stepVolume(audio.speaker, d);
                    }
                }
            }

            Text {
                text: audio.speakerPercent + "%"
                font.pixelSize: 12
                font.bold: true
                color: audio.speakerMuted ? bar.muted : bar.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // MIC VIEW
        Row {
            visible: audio.viewMode === 1
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: audio.micMuted ? "󰍭" : "󰍬"
                font.pixelSize: 16
                font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                color: audio.micMuted ? bar.muted : bar.accent
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: 110; height: 18
                anchors.verticalCenter: parent.verticalCenter

                VolumeBar {
                    id: micBar
                    anchors.centerIn: parent
                    bar: bar
                    onSet: function(v){ audio.setVolume(audio.mic, v); }
                    fill: Qt.binding(function(){ return audio.micMuted ? bar.muted : bar.accent; })
                }
                Binding {
                    target: micBar
                    property: "value"
                    value: audio.micVolume
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (e) => {
                        const d = (e.angleDelta.y > 0) ? 0.05 : -0.05;
                        audio.stepVolume(audio.mic, d);
                    }
                }
            }

            Text {
                text: audio.micPercent + "%"
                font.pixelSize: 12
                font.bold: true
                color: audio.micMuted ? bar.muted : bar.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // DUAL VIEW
        Item {
            visible: audio.viewMode === 2
            anchors.fill: parent

            Row {
                anchors.left: parent.left
                anchors.leftMargin: bar.audioViewSidePadding
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    text: audio.speakerMuted ? "" : ""
                    font.pixelSize: 16
                    font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                    color: audio.speakerMuted ? bar.muted : bar.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    width: 58; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    MiniVolumeBar {
                        id: spkMiniBar
                        anchors.centerIn: parent
                        bar: bar
                        onSet: function(v){ audio.setVolume(audio.speaker, v); }
                        fill: Qt.binding(function(){ return audio.speakerMuted ? bar.muted : bar.accent; })
                    }
                    Binding {
                        target: spkMiniBar
                        property: "value"
                        value: audio.speakerVolume
                    }
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.speaker, d); }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: bar.audioViewSidePadding
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    text: audio.micMuted ? "󰍭" : "󰍬"
                    font.pixelSize: 14
                    font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                    color: audio.micMuted ? bar.muted : bar.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    width: 58; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    MiniVolumeBar {
                        id: micMiniBar
                        anchors.centerIn: parent
                        bar: bar
                        onSet: function(v){ audio.setVolume(audio.mic, v); }
                        fill: Qt.binding(function(){ return audio.micMuted ? bar.muted : bar.accent; })
                    }
                    Binding {
                        target: micMiniBar
                        property: "value"
                        value: audio.micVolume
                    }
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.mic, d); }
                    }
                }
            }
        }
    }

    // ===== AUDIO POPUP (device selectors + full sliders + mutes) =====
    PopupWindow {
        id: audioPopup
        anchor.window: bar
        implicitWidth: 420
        implicitHeight: 260
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 12
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
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Audio Controls"
                        color: bar.text
                        font.pixelSize: 16
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "right-click pill or outside to close"
                        color: bar.overlay
                        font.pixelSize: 11
                    }
                }

                // OUTPUT section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Playback"
                        color: bar.accent
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 6
                        color: outDevMouse.containsMouse ? bar.glassHover : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: 1
                        border.color: "#45475a"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: audio.getCurrentDeviceName(true)
                                color: bar.text
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "▼"
                                color: bar.subtext
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: outDevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: openAudioDeviceList(true, outDevMouse)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: audio.speakerMuted ? "" : ""
                            font.pixelSize: 17
                            font.family: "Symbols Nerd Font"
                            color: audio.speakerMuted ? bar.muted : bar.accent
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18
                            VolumeBar {
                                id: popupSpkBar
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                bar: bar
                                onSet: function(v){ audio.setVolume(audio.speaker, v); }
                                barHeight: 8
                                fill: Qt.binding(function(){ return audio.speakerMuted ? bar.muted : bar.accent; })
                            }
                            Binding {
                                target: popupSpkBar
                                property: "value"
                                value: audio.speakerVolume
                            }
                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.speaker, d); }
                            }
                        }

                        Text {
                            text: audio.speakerPercent + "%"
                            color: audio.speakerMuted ? bar.muted : bar.text
                            font.pixelSize: 13
                            font.bold: true
                            Layout.preferredWidth: 42
                        }

                        Rectangle {
                            width: 52; height: 22; radius: 5
                            color: muteOutMa.containsMouse ? (audio.speakerMuted ? bar.muted : bar.accent) : bar.surface
                            border.width: 1
                            border.color: "#45475a"

                            Text {
                                anchors.centerIn: parent
                                text: audio.speakerMuted ? "Unmute" : "Mute"
                                color: muteOutMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                            }
                            MouseArea {
                                id: muteOutMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: audio.toggleMute(audio.speaker)
                            }
                        }
                    }
                }

                // INPUT section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Recording"
                        color: bar.accent
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 6
                        color: inDevMouse.containsMouse ? bar.glassHover : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: 1
                        border.color: "#45475a"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: audio.getCurrentDeviceName(false)
                                color: bar.text
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "▼"
                                color: bar.subtext
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: inDevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: openAudioDeviceList(false, inDevMouse)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: audio.micMuted ? "󰍭" : "󰍬"
                            font.pixelSize: 17
                            font.family: "Symbols Nerd Font"
                            color: audio.micMuted ? bar.muted : bar.accent
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18
                            VolumeBar {
                                id: popupMicBar
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                bar: bar
                                onSet: function(v){ audio.setVolume(audio.mic, v); }
                                barHeight: 8
                                fill: Qt.binding(function(){ return audio.micMuted ? bar.muted : bar.accent; })
                            }
                            Binding {
                                target: popupMicBar
                                property: "value"
                                value: audio.micVolume
                            }
                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.mic, d); }
                            }
                        }

                        Text {
                            text: audio.micPercent + "%"
                            color: audio.micMuted ? bar.muted : bar.text
                            font.pixelSize: 13
                            font.bold: true
                            Layout.preferredWidth: 42
                        }

                        Rectangle {
                            width: 52; height: 22; radius: 5
                            color: muteInMa.containsMouse ? (audio.micMuted ? bar.muted : bar.accent) : bar.surface
                            border.width: 1
                            border.color: "#45475a"

                            Text {
                                anchors.centerIn: parent
                                text: audio.micMuted ? "Unmute" : "Mute"
                                color: muteInMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                            }
                            MouseArea {
                                id: muteInMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: audio.toggleMute(audio.mic)
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: {
                audioPopup.visible = false
                audioDeviceListPopup.visible = false
            }
        }
    }

    // Device list popup (shared for output/input)
    PopupWindow {
        id: audioDeviceListPopup
        anchor.window: bar
        implicitWidth: 320
        implicitHeight: Math.min(420, Math.max(100, (audio.deviceListForSink ? audio.sinks.length : audio.sources.length) * 39 + 90))
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 10
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
                anchors.margins: 10
                spacing: 4

                Text {
                    text: audio.deviceListForSink ? "Select Playback Device" : "Select Recording Device"
                    color: bar.text
                    font.pixelSize: 13
                    font.bold: true
                }

                Item { Layout.preferredHeight: 4 }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: audio.deviceListForSink ? audio.sinks : audio.sources
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            radius: 4
                            color: rowDevMa.containsMouse ? bar.surface : "transparent"

                            required property var modelData

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: bar.text
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: isCurrentDevice(modelData)
                                    text: "✓"
                                    color: bar.accent
                                    font.pixelSize: 13
                                }
                            }

                            MouseArea {
                                id: rowDevMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var node = modelData.node
                                    if (audio.deviceListForSink) {
                                        Pipewire.preferredDefaultAudioSink = node
                                    } else {
                                        Pipewire.preferredDefaultAudioSource = node
                                    }
                                    audioDeviceListPopup.visible = false
                                }
                            }
                        }
                    }

                    Text {
                        visible: (audio.deviceListForSink ? audio.sinks.length : audio.sources.length) === 0
                        text: "(no devices)"
                        color: bar.overlay
                        font.pixelSize: 11
                        font.italic: true
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: audioDeviceListPopup.visible = false
        }
    }

    function isCurrentDevice(dev) {
        if (!dev || !dev.node) return false
        var def = audio.deviceListForSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
        if (!def) return false
        return (def.name === dev.node.name) || (def.description === dev.node.description)
    }

    function openAudioDeviceList(forSink, targetItem) {
        audio.deviceListForSink = forSink
        var popupW = audioDeviceListPopup.implicitWidth
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920

        var p = root.mapToItem(barBg, 0, root.height)
        var baseX = bar.sideMargin + p.x
        audioDeviceListPopup.anchor.rect.x = Math.min(baseX, screenW - popupW - 12)
        audioDeviceListPopup.anchor.rect.y = bar.implicitHeight + 46
        audioDeviceListPopup.visible = true
    }

    function showAudioPopup() {
        if (audioPopup.visible) {
            audioPopup.visible = false
            audioDeviceListPopup.visible = false
            return
        }
        var pos = root.mapToItem(barBg, root.width / 2, root.height)
        var popupW = audioPopup.implicitWidth
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920

        var targetX = bar.sideMargin + pos.x - (popupW / 2)
        var minX = 12
        var maxX = screenW - popupW - 12
        audioPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
        audioPopup.anchor.rect.y = bar.implicitHeight + 2

        audioPopup.visible = true
        audioDeviceListPopup.visible = false
    }
}

