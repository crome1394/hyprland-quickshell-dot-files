import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

import "../components"

// AudioPill.qml
// The full audio/volume widget: cycling speaker/mic/dual pill + its two popups.
// Uses the reusable VolumeBar/MiniVolumeBar components we extracted earlier.
// Extracted from the original monolithic shell.qml.

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
            // Keep the direct PipeWire stream list fresh (used in media popup).
            // Complements the MPRIS path.
            // (media is still in main file for now)
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

    // Popups and show functions would go here in the full extraction.
    // For this step, the core pill + state is moved.
}
