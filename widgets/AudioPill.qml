import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io as Io

import "../components"

// =============================================================================
// AudioPill.qml — Audio control pill (speaker + mic + device menus)
// =============================================================================
//
// Purpose:
//   Multi-view audio pill (speaker only / mic only / dual compact) with full
//   device selection popup, volume controls, mute, and wheel support.
//
// Popup extras (right-click — do not affect the compact bar pill):
//   - L/R channel volume sliders for stereo playback and recording devices
//   - Real-time VU peak meters via PwNodePeakMonitor (enabled only while open)
//   - Card profile dropdowns (PipeWire/Pulse profiles via audio-control.sh)
//
// Theme Properties Consumed:
//   - bar.audioViewContentWidth, bar.audioViewSidePadding
//   - bar.pillRadius, bar.pillBg, bar.pillBorder, bar.accent
//   - bar.iconHoverBg, bar.workspaceRadius  (content hover; Config.qml)
//   - bar.audioSpeakerTier1–4, bar.audioMicTier1–4, bar.audioUtilThreshold1–3
//   - bar.audioSpeakerUtilColor(), bar.audioMicUtilColor()
//   - bar.audioSpeakerIcon, bar.audioMicIcon, bar.audioSpeakerIconMuted, bar.audioMicIconMuted
//   - bar.pillHPadding
//   - bar.iconSpeaker*, bar.iconMic*, bar.iconSizeTray, bar.iconSizePopup
//   - bar.fontFamily, bar.fontPillLabel, bar.fontPopupTitle, bar.fontSection,
//     bar.fontBody, bar.fontSmall
//   - bar.muted, bar.text, bar.subtext, bar.overlay, bar.bg, bar.surface
//   - bar.sliderPopupHeight, bar.controlBorderWidth, bar.buttonRadius,
//     bar.smallButtonRadius
//   - bar.popupRadius, bar.glassPopupBg, bar.glassPopupBorder,
//     bar.glassPopupHighlight, bar.popupHeaderHighlightHeight,
//     bar.popupSpacing, bar.popupTitleSize, bar.popupSectionSize,
//     bar.popupHintSize, bar.popupButtonHoverBg, bar.dividerStrong
//   - bar.popupAudioWidth, bar.popupAudioHeight
//   - bar.tooltipDelay
//
// Dependencies:
//   - required property var bar
//   - required property Item barBg (for popup positioning)
//   - Quickshell.Services.Pipewire (volume, channels, PwNodePeakMonitor)
//   - scripts/audio-control.sh (card profile list/set; L/R pactl fallback)
//
// Notes:
//   - Bar pill views (speaker / mic / dual) are intentionally unchanged.
//   - Peak monitors are disabled when the popup is closed (CPU / PipeWire load).
//   - L/R and profile rows hide gracefully for mono / profile-less devices.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    // === Layout ===
    Layout.preferredWidth: bar.audioViewContentWidth + bar.pillHPadding
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    // === Appearance via Theme ===
    radius: bar.pillRadius
    color: bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: bar.pillBorder

    // ===== AUDIO STATE (logic preserved exactly) =====
    PwObjectTracker {
        id: audioTracker
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(function(n){ return !!n; })
    }

    // Path to the shared pactl helper (profiles + optional channel-volume fallback).
    readonly property string audioControlScript: "/home/crome/.config/quickshell/scripts/audio-control.sh"

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

        // --- Profile list state (playback + recording card profiles) ---
        // Populated asynchronously via list-card-profiles; empty when unavailable.
        property string speakerCard: ""
        property string micCard: ""
        property string speakerProfileActive: ""
        property string micProfileActive: ""
        property var speakerProfiles: []   // [{name, description, available, sinks, sources, priority}]
        property var micProfiles: []
        property bool profileListForSink: true
        property string profileListCard: ""
        property var profileListItems: []

        // ---- Master volume (unchanged behaviour + wpctl BT workaround) ----
        function setVolume(node, v) {
            if (node && node.audio) node.audio.volume = Math.max(0.0, Math.min(1.0, v));
            // Workaround for Quickshell#807: on many Bluetooth (bluez) sinks, the device route
            // lacks a "volumeStep" param, so direct PwNodeAudio.volume writes only update local
            // QML state and do not reach the PipeWire backend. wpctl uses the reliable control
            // path (works for BT + all other devices, and is what pavucontrol/wpctl users rely on).
            if (node && node.id !== undefined) {
                var pct = Math.round(v * 100);
                Quickshell.execDetached(["wpctl", "set-volume", String(node.id), pct + "%"]);
            }
        }
        function stepVolume(node, delta) {
            if (!node || !node.audio) return;
            var nv = Math.max(0.0, Math.min(1.0, node.audio.volume + delta));
            node.audio.volume = nv;
            if (node.id !== undefined) {
                // Use absolute target for the wpctl call. This way:
                // - Good devices: local .volume= already applied the delta; wpctl sets the *same* target (harmless)
                // - Bluetooth (buggy in Quickshell): local is ignored by backend, wpctl applies the correct target
                var pct = Math.round(nv * 100);
                Quickshell.execDetached(["wpctl", "set-volume", String(node.id), pct + "%"]);
            }
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

        // ---- L/R channel helpers (stereo devices only) ----
        //
        // Uses PwNodeAudio.channels + .volumes (native Quickshell PipeWire API).
        // Indices prefer FrontLeft/FrontRight; fall back to 0/1 for plain stereo.
        // Mono / missing channel data → hasStereoChannels() is false and UI hides.

        function _channels(node) {
            return (node && node.audio && node.audio.channels) ? node.audio.channels : [];
        }
        function _volumes(node) {
            return (node && node.audio && node.audio.volumes) ? node.audio.volumes : [];
        }

        function hasStereoChannels(node) {
            return _channels(node).length >= 2 && _volumes(node).length >= 2;
        }

        function _findChannelIndex(node, preferEnum, fallbackIndex) {
            var chs = _channels(node);
            for (var i = 0; i < chs.length; i++) {
                if (chs[i] === preferEnum)
                    return i;
            }
            return fallbackIndex;
        }

        function leftChannelIndex(node) {
            return _findChannelIndex(node, PwAudioChannel.FrontLeft, 0);
        }
        function rightChannelIndex(node) {
            return _findChannelIndex(node, PwAudioChannel.FrontRight, 1);
        }

        function channelVolume(node, isLeft) {
            if (!node || !node.audio) return 0.0;
            var vols = _volumes(node);
            if (vols.length === 0) return 0.0;
            var idx = isLeft ? leftChannelIndex(node) : rightChannelIndex(node);
            if (idx < 0 || idx >= vols.length) return vols[0] || 0.0;
            return vols[idx] || 0.0;
        }

        // Bindings touch .volumes / .channels directly so QML re-evaluates on
        // volumesChanged / channelsChanged (function-only bindings often miss notifies).
        readonly property real speakerLeftVolume: {
            var _ = speaker && speaker.audio ? speaker.audio.volumes : null
            var __ = speaker && speaker.audio ? speaker.audio.channels : null
            return channelVolume(speaker, true)
        }
        readonly property real speakerRightVolume: {
            var _ = speaker && speaker.audio ? speaker.audio.volumes : null
            var __ = speaker && speaker.audio ? speaker.audio.channels : null
            return channelVolume(speaker, false)
        }
        readonly property real micLeftVolume: {
            var _ = mic && mic.audio ? mic.audio.volumes : null
            var __ = mic && mic.audio ? mic.audio.channels : null
            return channelVolume(mic, true)
        }
        readonly property real micRightVolume: {
            var _ = mic && mic.audio ? mic.audio.volumes : null
            var __ = mic && mic.audio ? mic.audio.channels : null
            return channelVolume(mic, false)
        }
        readonly property bool speakerHasStereo: {
            var _ = speaker && speaker.audio ? speaker.audio.volumes : null
            var __ = speaker && speaker.audio ? speaker.audio.channels : null
            return hasStereoChannels(speaker)
        }
        readonly property bool micHasStereo: {
            var _ = mic && mic.audio ? mic.audio.volumes : null
            var __ = mic && mic.audio ? mic.audio.channels : null
            return hasStereoChannels(mic)
        }

        // Set one channel (L or R) while preserving the other.
        // Writes native volumes + pactl multi-channel set for backend reliability
        // (same class of issue as the master-volume wpctl workaround).
        function setChannelVolume(node, isLeft, v, isSink) {
            if (!node || !node.audio) return;
            if (!hasStereoChannels(node)) return;

            var clamped = Math.max(0.0, Math.min(1.0, v));
            var li = leftChannelIndex(node);
            var ri = rightChannelIndex(node);
            // Snapshot peer channel before write so we can send a full L/R pair.
            var leftVol = isLeft ? clamped : channelVolume(node, true);
            var rightVol = isLeft ? channelVolume(node, false) : clamped;

            var vols = _volumes(node);
            var next = [];
            for (var i = 0; i < vols.length; i++)
                next.push(vols[i]);
            if (li >= 0 && li < next.length) next[li] = leftVol;
            if (ri >= 0 && ri < next.length) next[ri] = rightVol;

            // Native Quickshell write (updates UI-bound state immediately).
            try {
                node.audio.volumes = next;
            } catch (e) {
                // Some nodes reject partial channel writes; fall through to pactl.
            }

            // Backend write via pactl (L% R%) — reliable across ALSA/BT/USB.
            if (node.name) {
                var lPct = Math.round(leftVol * 100);
                var rPct = Math.round(rightVol * 100);
                var kind = isSink ? "sink" : "source";
                Quickshell.execDetached([
                    root.audioControlScript, "set-channel-volume",
                    kind, String(node.name), String(lPct), String(rPct)
                ]);
            }
        }

        // ---- Card / profile helpers ----
        //
        // PipeWire nodes expose the owning card as properties["device.name"]
        // (e.g. "alsa_card.usb-..."). Bluetooth / virtual devices may omit it;
        // the profile row simply stays hidden in that case.

        function cardNameForNode(node) {
            if (!node) return "";
            var p = node.properties || {};
            // Prefer an explicit card id when present (Pulse-compat props).
            if (p["device.name"] && String(p["device.name"]).indexOf("alsa_card.") === 0)
                return String(p["device.name"]);

            // Derive from ALSA node name:
            //   alsa_output.<card-id>.<profile>  →  alsa_card.<card-id>
            //   alsa_input.<card-id>.<profile>   →  alsa_card.<card-id>
            // Profile is the final dotted segment (e.g. analog-stereo, hdmi-stereo).
            var nm = node.name || "";
            if (nm.indexOf("alsa_output.") === 0 || nm.indexOf("alsa_input.") === 0) {
                var rest = nm.replace(/^alsa_(output|input)\./, "");
                var lastDot = rest.lastIndexOf(".");
                if (lastDot > 0)
                    return "alsa_card." + rest.substring(0, lastDot);
            }
            // Bluetooth / virtual nodes: no stable alsa_card id — hide profile row.
            return "";
        }

        function getProfileLabel(isSink) {
            var active = isSink ? speakerProfileActive : micProfileActive;
            var list = isSink ? speakerProfiles : micProfiles;
            if (!active || active.length === 0)
                return "No profile";
            for (var i = 0; i < list.length; i++) {
                if (list[i].name === active)
                    return list[i].description || active;
            }
            return active;
        }

        // Profiles relevant to a section: playback wants sinks>0, recording sources>0.
        // Always keep the currently active profile visible (even if filtered).
        function filteredProfiles(isSink) {
            var list = isSink ? speakerProfiles : micProfiles;
            var active = isSink ? speakerProfileActive : micProfileActive;
            var out = [];
            for (var i = 0; i < list.length; i++) {
                var p = list[i];
                if (!p || !p.name) continue;
                // Hide the "Off" profile unless it is already active (avoids accidents).
                if (p.name === "off" && p.name !== active)
                    continue;
                var isActive = (p.name === active);
                var hasRole = isSink
                    ? (p.sinks === undefined || Number(p.sinks) > 0)
                    : (p.sources === undefined || Number(p.sources) > 0);
                if (isActive || hasRole)
                    out.push(p);
            }
            return out;
        }

        function applyProfilePayload(isSink, data) {
            if (!data) return;
            var profiles = data.profiles || [];
            if (isSink) {
                speakerCard = data.card || "";
                speakerProfileActive = data.active || "";
                speakerProfiles = profiles;
            } else {
                micCard = data.card || "";
                micProfileActive = data.active || "";
                micProfiles = profiles;
            }
        }
    }

    // Real-time peak meters (PipeWire). Enabled ONLY while the audio popup is
    // open so we never sample peaks for a closed UI (cheap + less wire load).
    PwNodePeakMonitor {
        id: speakerPeakMon
        node: audio.speaker
        enabled: audioPopup.visible && !!audio.speaker
    }
    PwNodePeakMonitor {
        id: micPeakMon
        node: audio.mic
        enabled: audioPopup.visible && !!audio.mic
    }

    // Async profile fetch — separate processes for sink/source so stdout never
    // interleaves and either side can refresh independently.
    function _parseProfileJson(text) {
        var t = (text || "").trim();
        if (!t.length) return null;
        // Prefer the last non-empty line in case a collector retained prior output.
        var lines = t.split("\n");
        var last = "";
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line.length) last = line;
        }
        try {
            return JSON.parse(last);
        } catch (e) {
            return null;
        }
    }

    Io.Process {
        id: speakerProfileProcess
        running: false
        stdout: Io.StdioCollector { id: speakerProfileStdout }
        onExited: (code) => {
            if (code !== 0) return;
            var data = root._parseProfileJson(speakerProfileStdout.text);
            if (data)
                audio.applyProfilePayload(true, data);
        }
    }

    Io.Process {
        id: micProfileProcess
        running: false
        stdout: Io.StdioCollector { id: micProfileStdout }
        onExited: (code) => {
            if (code !== 0) return;
            var data = root._parseProfileJson(micProfileStdout.text);
            if (data)
                audio.applyProfilePayload(false, data);
        }
    }

    Io.Process {
        id: profileSetProcess
        running: false
        // Fire-and-forget; refresh profiles after exit so the label updates.
        onExited: (code) => {
            if (code === 0)
                root.refreshProfiles();
        }
    }

    function _startProfileFetch(isSink) {
        var node = isSink ? audio.speaker : audio.mic;
        var card = audio.cardNameForNode(node);
        if (!card || card.length === 0) {
            audio.applyProfilePayload(isSink, { card: "", active: "", profiles: [] });
            return;
        }
        var proc = isSink ? speakerProfileProcess : micProfileProcess;
        if (proc.running)
            proc.running = false;
        proc.command = [root.audioControlScript, "list-card-profiles", card];
        proc.running = true;
    }

    // Refresh both profile lists. Safe to call often (popup open / after set).
    function refreshProfiles() {
        root._startProfileFetch(true);
        root._startProfileFetch(false);
    }

    function setCardProfile(card, profileName) {
        if (!card || !profileName) return;
        if (profileSetProcess.running)
            profileSetProcess.running = false;
        profileSetProcess.command = [
            root.audioControlScript, "set-card-profile", card, profileName
        ];
        profileSetProcess.running = true;
    }

    // =========================================================================
    // Echo cancel (sticky system AEC — permanent preference, reversible Off)
    // =========================================================================
    // Preference: ~/.config/quickshell/echo-cancel.pref  (preferred true/false)
    // Login: systemd user unit quickshell-echo-cancel.service → echo-cancel-apply
    // Backup: Component.onCompleted also runs apply (covers service races).
    //
    // On  → qs_ec_* defaults + preferred=true  (survives reboot)
    // Off → hardware restored + preferred=false (stays off until turned On)
    // Nuclear: audio-control.sh echo-cancel-force-off
    //          systemctl --user disable --now quickshell-echo-cancel.service
    // =========================================================================
    property bool echoCancelEnabled: false
    property bool echoCancelPreferred: false
    property bool echoCancelBusy: false
    property string echoCancelError: ""
    property string echoCancelHint: ""
    property bool echoCancelApplyTried: false

    function applyEchoCancelStatus(data) {
        if (!data) return;
        echoCancelEnabled = !!data.enabled;
        echoCancelPreferred = !!data.preferred;
        echoCancelError = data.error || "";
        if (echoCancelEnabled) {
            echoCancelHint = "On (permanent) · cleaned mic/speakers · Off undoes until you re-enable";
        } else if (echoCancelPreferred && !echoCancelEnabled) {
            echoCancelHint = "Preferred on · applying… (or run echo-cancel-apply if stuck)";
        } else if (echoCancelError.length) {
            echoCancelHint = echoCancelError;
        } else {
            echoCancelHint = "Off · hardware path · turn On to make permanent again";
        }
    }

    function refreshEchoCancelStatus() {
        if (echoCancelStatusProcess.running)
            echoCancelStatusProcess.running = false;
        echoCancelStatusProcess.command = [root.audioControlScript, "echo-cancel-status"];
        echoCancelStatusProcess.running = true;
    }

    // Apply sticky preference at shell start (idempotent; no-op if preferred=false).
    function applyEchoCancelPreference() {
        if (echoCancelBusy) return;
        if (echoCancelApplyProcess.running)
            echoCancelApplyProcess.running = false;
        echoCancelApplyProcess.command = [root.audioControlScript, "echo-cancel-apply"];
        echoCancelApplyProcess.running = true;
    }

    function setEchoCancel(wantOn) {
        if (echoCancelBusy) return;
        echoCancelBusy = true;
        echoCancelError = "";
        if (echoCancelToggleProcess.running)
            echoCancelToggleProcess.running = false;
        // On → preferred=true; Off → preferred=false + restore hardware.
        echoCancelToggleProcess.command = [
            root.audioControlScript,
            wantOn ? "echo-cancel-on" : "echo-cancel-off"
        ];
        echoCancelToggleProcess.running = true;
    }

    // --- Public API (popup toggle + qs ipc call audioPill …) ---
    function setEchoCancelEnabled(enabled) {
        root.setEchoCancel(!!enabled);
    }
    function enableEchoCancel() {
        root.setEchoCancel(true);
    }
    function disableEchoCancel() {
        root.setEchoCancel(false);
    }
    function toggleEchoCancel() {
        root.setEchoCancel(!root.echoCancelEnabled);
    }

    Io.Process {
        id: echoCancelStatusProcess
        running: false
        stdout: Io.StdioCollector { id: echoCancelStatusStdout }
        onExited: (code) => {
            var data = root._parseProfileJson(echoCancelStatusStdout.text);
            if (data)
                root.applyEchoCancelStatus(data);
        }
    }

    Io.Process {
        id: echoCancelToggleProcess
        running: false
        stdout: Io.StdioCollector { id: echoCancelToggleStdout }
        onExited: (code) => {
            root.echoCancelBusy = false;
            var data = root._parseProfileJson(echoCancelToggleStdout.text);
            if (data) {
                root.applyEchoCancelStatus(data);
            } else {
                root.echoCancelError = code === 0 ? "" : "Echo cancel command failed";
                root.refreshEchoCancelStatus();
            }
            // Virtual devices appeared/disappeared — refresh lists + profiles.
            audio.refreshDevices();
            root.refreshProfiles();
        }
    }

    Io.Process {
        id: echoCancelApplyProcess
        running: false
        stdout: Io.StdioCollector { id: echoCancelApplyStdout }
        onExited: (code) => {
            var data = root._parseProfileJson(echoCancelApplyStdout.text);
            if (data)
                root.applyEchoCancelStatus(data);
            else
                root.refreshEchoCancelStatus();
            if (root.echoCancelEnabled)
                audio.refreshDevices();
        }
    }

    // After the bar is up, apply sticky preference once (covers late PipeWire).
    Timer {
        id: echoCancelApplyTimer
        interval: 2500
        repeat: false
        onTriggered: {
            if (!root.echoCancelApplyTried) {
                root.echoCancelApplyTried = true;
                root.applyEchoCancelPreference();
            }
        }
    }

    Component.onCompleted: {
        echoCancelApplyTimer.start();
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() {
            audio.refreshDevices();
        }
    }

    // When the default sink/source changes (device switch or profile change),
    // refresh card profiles if the popup is open so labels stay accurate.
    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() {
            if (audioPopup.visible)
                root._startProfileFetch(true);
        }
        function onDefaultAudioSourceChanged() {
            if (audioPopup.visible)
                root._startProfileFetch(false);
        }
    }

    // Content chip: per-item hover (same token as QuickLaunch / SysStats)
    // MouseArea stays on the chip so padding outside does not light the whole pill.
    Rectangle {
        id: audioContent
        anchors.centerIn: parent
        width: bar.audioViewContentWidth
        height: parent.height - 8
        radius: bar.workspaceRadius
        color: audioHover.containsMouse ? bar.iconHoverBg : "transparent"
        implicitWidth: width
        implicitHeight: height

        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

        MouseArea {
            id: audioHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            // Let volume sliders / wheel handlers receive input; clicks still bubble
            // for empty areas. VolumeBar has its own drag handling.
            z: -1

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

        // SPEAKER VIEW
        Row {
            visible: audio.viewMode === 0
            anchors.centerIn: parent
            spacing: 6

            Item {
                width: bar.iconSizeTray
                height: bar.iconSizeTray
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: audio.speakerMuted ? bar.iconSpeakerMuted : bar.iconSpeaker
                    font.pixelSize: bar.iconSizeTray
                    font.family: bar.fontFamily
                    color: audio.speakerMuted ? bar.audioSpeakerIconMuted : bar.audioSpeakerIcon
                }
            }

            Item {
                width: 110; height: 18
                anchors.verticalCenter: parent.verticalCenter

                VolumeBar {
                    id: spkBar
                    anchors.centerIn: parent
                    bar: bar
                    onSet: function(v){ audio.setVolume(audio.speaker, v); }
                }
                Binding {
                    target: spkBar
                    property: "fill"
                    value: audio.speakerMuted ? bar.sliderFillMuted : bar.audioSpeakerUtilColor(audio.speakerPercent)
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
                font.pixelSize: bar.fontPillLabel
                font.bold: true
                color: audio.speakerMuted ? bar.muted : bar.audioSpeakerUtilColor(audio.speakerPercent)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // MIC VIEW
        Row {
            visible: audio.viewMode === 1
            anchors.centerIn: parent
            spacing: 6

            Item {
                width: bar.iconSizeTray
                height: bar.iconSizeTray
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: audio.micMuted ? bar.iconMicMuted : bar.iconMic
                    font.pixelSize: bar.iconSizeTray
                    font.family: bar.fontFamily
                    color: audio.micMuted ? bar.audioMicIconMuted : bar.audioMicIcon
                }
            }

            Item {
                width: 110; height: 18
                anchors.verticalCenter: parent.verticalCenter

                VolumeBar {
                    id: micBar
                    anchors.centerIn: parent
                    bar: bar
                    onSet: function(v){ audio.setVolume(audio.mic, v); }
                }
                Binding {
                    target: micBar
                    property: "fill"
                    value: audio.micMuted ? bar.sliderFillMuted : bar.audioMicUtilColor(audio.micPercent)
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
                font.pixelSize: bar.fontPillLabel
                font.bold: true
                color: audio.micMuted ? bar.muted : bar.audioMicUtilColor(audio.micPercent)
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

                Item {
                    width: bar.iconSizeTray
                    height: bar.iconSizeTray
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: audio.speakerMuted ? bar.iconSpeakerMuted : bar.iconSpeaker
                        font.pixelSize: bar.iconSizeTray
                        font.family: bar.fontFamily
                        color: audio.speakerMuted ? bar.audioSpeakerIconMuted : bar.audioSpeakerIcon
                    }
                }
                Item {
                    width: 58; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    MiniVolumeBar {
                        id: spkMiniBar
                        anchors.centerIn: parent
                        bar: bar
                        onSet: function(v){ audio.setVolume(audio.speaker, v); }
                    }
                    Binding {
                        target: spkMiniBar
                        property: "fill"
                        value: audio.speakerMuted ? bar.sliderFillMuted : bar.audioSpeakerUtilColor(audio.speakerPercent)
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

                Item {
                    width: bar.iconSizeTray
                    height: bar.iconSizeTray
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: audio.micMuted ? bar.iconMicMuted : bar.iconMic
                        font.pixelSize: bar.iconSizeTray
                        font.family: bar.fontFamily
                        color: audio.micMuted ? bar.audioMicIconMuted : bar.audioMicIcon
                    }
                }
                Item {
                    width: 58; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    MiniVolumeBar {
                        id: micMiniBar
                        anchors.centerIn: parent
                        bar: bar
                        onSet: function(v){ audio.setVolume(audio.mic, v); }
                    }
                    Binding {
                        target: micMiniBar
                        property: "fill"
                        value: audio.micMuted ? bar.sliderFillMuted : bar.audioMicUtilColor(audio.micPercent)
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

    // ===== AUDIO POPUP (device selectors + full sliders) =====
    PopupWindow {
        id: audioPopup
        anchor.window: bar
        implicitWidth: bar.popupAudioWidth
        implicitHeight: bar.popupAudioHeight
        visible: false
        color: "transparent"

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
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                spacing: 16

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Audio Controls"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "right-click pill or outside to close"
                        color: bar.overlay
                        font.pixelSize: bar.popupHintSize
                        font.family: bar.fontFamily
                    }
                }

                // OUTPUT section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Playback"
                        color: bar.accent
                        font.pixelSize: bar.popupSectionSize
                        font.bold: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: bar.buttonRadius
                        color: outDevMouse.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

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

                    // Playback card profile dropdown (hidden when card/profiles unavailable)
                    Rectangle {
                        visible: audio.speakerCard.length > 0 && audio.speakerProfiles.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        radius: bar.buttonRadius
                        color: outProfMouse.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                text: "Profile"
                                color: bar.subtext
                                font.pixelSize: 11
                                font.family: bar.fontFamily
                            }
                            Text {
                                Layout.fillWidth: true
                                text: audio.getProfileLabel(true)
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
                            id: outProfMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: openAudioProfileList(true)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: audio.speakerMuted ? bar.iconSpeakerMuted : bar.iconSpeaker
                            font.pixelSize: bar.iconSizePopup
                            font.family: bar.fontFamily
                            color: audio.speakerMuted ? bar.audioSpeakerIconMuted : bar.audioSpeakerIcon
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
                                barHeight: bar ? bar.sliderPopupHeight : 8
                            }
                            Binding {
                                target: popupSpkBar
                                property: "fill"
                                value: audio.speakerMuted ? bar.sliderFillMuted : bar.audioSpeakerUtilColor(audio.speakerPercent)
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
                            color: audio.speakerMuted ? bar.muted : bar.audioSpeakerUtilColor(audio.speakerPercent)
                            font.pixelSize: 13
                            font.bold: true
                            Layout.preferredWidth: 42
                        }

                        Rectangle {
                            width: 52; height: 22; radius: bar.smallButtonRadius
                            color: muteOutMa.containsMouse ? (audio.speakerMuted ? bar.muted : bar.accent) : bar.surface
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

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

                    // L / R channel volume (stereo playback only)
                    RowLayout {
                        visible: audio.speakerHasStereo
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "L"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.bold: true
                            Layout.preferredWidth: 12
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 14
                            VolumeBar {
                                id: popupSpkLBar
                                anchors.fill: parent
                                bar: bar
                                barHeight: 5
                                onSet: function(v) { audio.setChannelVolume(audio.speaker, true, v, true); }
                            }
                            Binding {
                                target: popupSpkLBar
                                property: "fill"
                                value: audio.speakerMuted ? bar.sliderFillMuted : bar.audioSpeakerUtilColor(Math.round(audio.speakerLeftVolume * 100))
                            }
                            Binding {
                                target: popupSpkLBar
                                property: "value"
                                value: audio.speakerLeftVolume
                            }
                        }
                        Text {
                            text: Math.round(audio.speakerLeftVolume * 100) + "%"
                            color: bar.subtext
                            font.pixelSize: 11
                            Layout.preferredWidth: 32
                        }

                        Text {
                            text: "R"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.bold: true
                            Layout.preferredWidth: 12
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 14
                            VolumeBar {
                                id: popupSpkRBar
                                anchors.fill: parent
                                bar: bar
                                barHeight: 5
                                onSet: function(v) { audio.setChannelVolume(audio.speaker, false, v, true); }
                            }
                            Binding {
                                target: popupSpkRBar
                                property: "fill"
                                value: audio.speakerMuted ? bar.sliderFillMuted : bar.audioSpeakerUtilColor(Math.round(audio.speakerRightVolume * 100))
                            }
                            Binding {
                                target: popupSpkRBar
                                property: "value"
                                value: audio.speakerRightVolume
                            }
                        }
                        Text {
                            text: Math.round(audio.speakerRightVolume * 100) + "%"
                            color: bar.subtext
                            font.pixelSize: 11
                            Layout.preferredWidth: 32
                        }
                    }

                    // Playback VU / peak meter
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Level"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            Layout.preferredWidth: 36
                        }
                        AudioLevelMeter {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            bar: bar
                            barHeight: 8
                            muted: audio.speakerMuted
                            // Peak is 0..1 from PwNodePeakMonitor; force 0 when muted/closed
                            level: (audioPopup.visible && !audio.speakerMuted) ? speakerPeakMon.peak : 0
                        }
                    }
                }

                // INPUT section (identical pattern applied)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Recording"
                        color: bar.accent
                        font.pixelSize: bar.popupSectionSize
                        font.bold: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: bar.buttonRadius
                        color: inDevMouse.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

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

                    // Recording card profile dropdown (hidden when card/profiles unavailable)
                    Rectangle {
                        visible: audio.micCard.length > 0 && audio.micProfiles.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        radius: bar.buttonRadius
                        color: inProfMouse.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                text: "Profile"
                                color: bar.subtext
                                font.pixelSize: 11
                                font.family: bar.fontFamily
                            }
                            Text {
                                Layout.fillWidth: true
                                text: audio.getProfileLabel(false)
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
                            id: inProfMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: openAudioProfileList(false)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: audio.micMuted ? bar.iconMicMuted : bar.iconMic
                            font.pixelSize: bar.iconSizePopup
                            font.family: bar.fontFamily
                            color: audio.micMuted ? bar.audioMicIconMuted : bar.audioMicIcon
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
                                barHeight: bar ? bar.sliderPopupHeight : 8
                            }
                            Binding {
                                target: popupMicBar
                                property: "fill"
                                value: audio.micMuted ? bar.sliderFillMuted : bar.audioMicUtilColor(audio.micPercent)
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
                            color: audio.micMuted ? bar.muted : bar.audioMicUtilColor(audio.micPercent)
                            font.pixelSize: 13
                            font.bold: true
                            Layout.preferredWidth: 42
                        }

                        Rectangle {
                            width: 52; height: 22; radius: bar.smallButtonRadius
                            color: muteInMa.containsMouse ? (audio.micMuted ? bar.muted : bar.accent) : bar.surface
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

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

                    // L / R channel volume (stereo recording only)
                    RowLayout {
                        visible: audio.micHasStereo
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "L"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.bold: true
                            Layout.preferredWidth: 12
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 14
                            VolumeBar {
                                id: popupMicLBar
                                anchors.fill: parent
                                bar: bar
                                barHeight: 5
                                onSet: function(v) { audio.setChannelVolume(audio.mic, true, v, false); }
                            }
                            Binding {
                                target: popupMicLBar
                                property: "fill"
                                value: audio.micMuted ? bar.sliderFillMuted : bar.audioMicUtilColor(Math.round(audio.micLeftVolume * 100))
                            }
                            Binding {
                                target: popupMicLBar
                                property: "value"
                                value: audio.micLeftVolume
                            }
                        }
                        Text {
                            text: Math.round(audio.micLeftVolume * 100) + "%"
                            color: bar.subtext
                            font.pixelSize: 11
                            Layout.preferredWidth: 32
                        }

                        Text {
                            text: "R"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.bold: true
                            Layout.preferredWidth: 12
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 14
                            VolumeBar {
                                id: popupMicRBar
                                anchors.fill: parent
                                bar: bar
                                barHeight: 5
                                onSet: function(v) { audio.setChannelVolume(audio.mic, false, v, false); }
                            }
                            Binding {
                                target: popupMicRBar
                                property: "fill"
                                value: audio.micMuted ? bar.sliderFillMuted : bar.audioMicUtilColor(Math.round(audio.micRightVolume * 100))
                            }
                            Binding {
                                target: popupMicRBar
                                property: "value"
                                value: audio.micRightVolume
                            }
                        }
                        Text {
                            text: Math.round(audio.micRightVolume * 100) + "%"
                            color: bar.subtext
                            font.pixelSize: 11
                            Layout.preferredWidth: 32
                        }
                    }

                    // Recording VU / peak meter
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Level"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            Layout.preferredWidth: 36
                        }
                        AudioLevelMeter {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            bar: bar
                            barHeight: 8
                            muted: audio.micMuted
                            level: (audioPopup.visible && !audio.micMuted) ? micPeakMon.peak : 0
                        }
                    }

                    // ---------------------------------------------------------
                    // Echo cancel toggle (system AEC for speaker→mic bleed)
                    // Fully reversible: Off restores prior hardware defaults.
                    // Does not edit PipeWire conf; safe alongside Meet/Discord.
                    // ---------------------------------------------------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Echo cancel"
                                color: bar.text
                                font.pixelSize: 12
                                font.family: bar.fontFamily
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }

                            // Toggle button — label always shows the action / state clearly
                            Rectangle {
                                width: 72
                                height: 24
                                radius: bar.smallButtonRadius
                                opacity: root.echoCancelBusy ? 0.6 : 1.0
                                color: {
                                    if (echoCancelToggleMa.containsMouse)
                                        return root.echoCancelEnabled ? bar.muted : bar.accent;
                                    return root.echoCancelEnabled ? bar.accent : bar.surface;
                                }
                                border.width: bar.controlBorderWidth
                                border.color: bar.dividerStrong

                                Text {
                                    anchors.centerIn: parent
                                    text: root.echoCancelBusy
                                          ? "…"
                                          : (root.echoCancelEnabled ? "On" : "Off")
                                    color: {
                                        if (echoCancelToggleMa.containsMouse)
                                            return bar.bg;
                                        return root.echoCancelEnabled ? bar.bg : bar.text;
                                    }
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }

                                MouseArea {
                                    id: echoCancelToggleMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: root.echoCancelBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                                    enabled: !root.echoCancelBusy
                                    onClicked: root.setEchoCancel(!root.echoCancelEnabled)
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.echoCancelHint.length
                                  ? root.echoCancelHint
                                  : "Sticky preference · survives reboot when On"
                            color: root.echoCancelError.length ? bar.muted : bar.subtext
                            font.pixelSize: 10
                            font.family: bar.fontFamily
                            wrapMode: Text.WordWrap
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
                audioProfileListPopup.visible = false
            }
        }
    }

    // Device list popup (shared) — same centralization pattern applied
    PopupWindow {
        id: audioDeviceListPopup
        anchor.window: bar
        implicitWidth: 320
        implicitHeight: Math.min(420, Math.max(100, (audio.deviceListForSink ? audio.sinks.length : audio.sources.length) * 39 + 90))
        visible: false
        color: "transparent"

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
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                spacing: 4

                Text {
                    text: audio.deviceListForSink ? "Select Playback Device" : "Select Recording Device"
                    color: bar.text
                    font.pixelSize: bar.popupSectionSize
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
                            radius: bar.buttonRadius
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

    // Card profile list popup (shared by Playback + Recording profile rows)
    PopupWindow {
        id: audioProfileListPopup
        anchor.window: bar
        implicitWidth: 340
        implicitHeight: Math.min(420, Math.max(100, audio.profileListItems.length * 32 + 70))
        visible: false
        color: "transparent"

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
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                spacing: 4

                Text {
                    text: audio.profileListForSink ? "Playback Profile" : "Recording Profile"
                    color: bar.text
                    font.pixelSize: bar.popupSectionSize
                    font.bold: true
                }

                Item { Layout.preferredHeight: 4 }

                // Scrollable-ish list: ColumnLayout + Repeater (same pattern as devices)
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: profileCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: profileCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: audio.profileListItems
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: bar.buttonRadius
                                color: rowProfMa.containsMouse ? bar.surface : "transparent"
                                opacity: (modelData.available === false) ? 0.45 : 1.0

                                required property var modelData

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.description || modelData.name
                                        color: bar.text
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: modelData.name === (audio.profileListForSink
                                            ? audio.speakerProfileActive
                                            : audio.micProfileActive)
                                        text: "✓"
                                        color: bar.accent
                                        font.pixelSize: 13
                                    }
                                }

                                MouseArea {
                                    id: rowProfMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // Allow selecting unavailable profiles only if already active
                                    // (user may need to leave a dead profile); otherwise require available.
                                    onClicked: {
                                        if (modelData.available === false
                                            && modelData.name !== (audio.profileListForSink
                                                ? audio.speakerProfileActive
                                                : audio.micProfileActive)) {
                                            return
                                        }
                                        var card = audio.profileListCard
                                        if (card && modelData.name) {
                                            root.setCardProfile(card, modelData.name)
                                        }
                                        audioProfileListPopup.visible = false
                                    }
                                }
                            }
                        }

                        Text {
                            visible: audio.profileListItems.length === 0
                            text: "(no profiles)"
                            color: bar.overlay
                            font.pixelSize: 11
                            font.italic: true
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: audioProfileListPopup.visible = false
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
        // Close sibling flyouts so only one secondary popup is open.
        audioProfileListPopup.visible = false
        var popupW = audioDeviceListPopup.implicitWidth
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920

        var p = root.mapToItem(barBg, 0, root.height)
        var baseX = bar.sideMargin + p.x
        audioDeviceListPopup.anchor.rect.x = Math.min(baseX, screenW - popupW - 12)
        audioDeviceListPopup.anchor.rect.y = bar.popupAnchorY(audioDeviceListPopup.implicitHeight, 46)
        audioDeviceListPopup.visible = true
    }

    function openAudioProfileList(forSink) {
        audio.profileListForSink = forSink
        audio.profileListCard = forSink ? audio.speakerCard : audio.micCard
        audio.profileListItems = audio.filteredProfiles(forSink)
        audioDeviceListPopup.visible = false

        if (!audio.profileListCard || audio.profileListItems.length === 0)
            return

        var popupW = audioProfileListPopup.implicitWidth
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
        var p = root.mapToItem(barBg, 0, root.height)
        var baseX = bar.sideMargin + p.x
        audioProfileListPopup.anchor.rect.x = Math.min(baseX, screenW - popupW - 12)
        audioProfileListPopup.anchor.rect.y = bar.popupAnchorY(audioProfileListPopup.implicitHeight, 46)
        audioProfileListPopup.visible = true
    }

    function showAudioPopup() {
        if (audioPopup.visible) {
            audioPopup.visible = false
            audioDeviceListPopup.visible = false
            audioProfileListPopup.visible = false
            return
        }

        var pos = root.mapToItem(barBg, root.width / 2, root.height)
        var popupW = audioPopup.implicitWidth
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920

        var targetX = bar.sideMargin + pos.x - (popupW / 2) + 60

        var minX = 12
        var maxX = screenW - popupW - 12
        audioPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
        audioPopup.anchor.rect.y = bar.popupAnchorY(audioPopup.implicitHeight)

        // Load card profiles + echo-cancel status (async, non-blocking).
        root.refreshProfiles()
        root.refreshEchoCancelStatus()
        audioPopup.visible = true
    }
}
