import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

import "../components"

// MediaPill.qml
// Centered media player pill (MPRIS + PipeWire visualizer) + rich popup.
// Extracted from the original monolithic shell.qml.

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    anchors.centerIn: barBg
    z: 5
    visible: media.title !== ""
    width: 600
    implicitHeight: 36
    radius: bar.pillRadius
    color: mediaHover.containsMouse ? bar.glassHover : bar.glassPillBg
    border.width: 1
    border.color: mediaHover.containsMouse ? bar.accent : bar.glassBorder

    // ===== MEDIA STATE (moved from main file) =====
    QtObject {
        id: media

        readonly property var allPlayers: (Mpris.players && Mpris.players.values) ? Mpris.players.values : []

        property var players: []
        property int currentIndex: 0
        readonly property var currentPlayer: (players.length > 0 && currentIndex >= 0 && currentIndex < players.length)
            ? players[currentIndex] : null

        property var firstSeen: ({})

        property var browserAudioNodes: []

        readonly property string title: currentPlayer ? (currentPlayer.trackTitle || (currentPlayer.metadata ? currentPlayer.metadata["xesam:title"] || "" : "")) : ""
        readonly property string artist: {
            if (!currentPlayer) return "";
            const md = currentPlayer.metadata || {};
            const a = md["xesam:artist"];
            if (Array.isArray(a)) return a.join(", ");
            if (typeof a === "string") return a;
            return currentPlayer.identity || "";
        }
        readonly property string album: currentPlayer ? ((currentPlayer.metadata || {})["xesam:album"] || "") : ""
        readonly property string artUrl: currentPlayer ? ((currentPlayer.metadata || {})["mpris:artUrl"] || "") : ""
        readonly property string appName: currentPlayer ? (currentPlayer.identity || currentPlayer.desktopEntry || "Media") : ""
        readonly property bool isPlaying: currentPlayer ? !!currentPlayer.isPlaying : false
        readonly property bool canToggle: currentPlayer ? !!currentPlayer.canTogglePlaying : false
        readonly property bool canNext: currentPlayer ? !!currentPlayer.canGoNext : false
        readonly property bool canPrev: currentPlayer ? !!currentPlayer.canGoPrevious : false
        readonly property bool canSeek: currentPlayer ? !!currentPlayer.canSeek : false
        readonly property real position: currentPlayer ? currentPlayer.position : 0
        readonly property real length: currentPlayer ? currentPlayer.length : 0
        readonly property bool lengthSupported: currentPlayer ? !!currentPlayer.lengthSupported : false

        function refreshPlayers() {
            Qt.callLater(media._actuallyRefreshPlayers);
        }

        function _actuallyRefreshPlayers() {
            const raw = (Mpris.players && Mpris.players.values) ? Mpris.players.values : [];
            let candidates = [];
            let currentKeys = new Set();

            for (let i = 0; i < raw.length; i++) {
                const p = raw[i];
                if (!p) continue;
                const t = p.trackTitle || (p.metadata ? p.metadata["xesam:title"] : "") || "";
                if (!t) continue;
                if (!p.isPlaying) continue;

                candidates.push(p);

                const key = p.dbusName || ("id:" + p.uniqueId);
                if (key) {
                    currentKeys.add(key);
                    if (media.firstSeen[key] === undefined) {
                        media.firstSeen[key] = Date.now();
                    }
                }
            }

            for (let k in media.firstSeen) {
                if (!currentKeys.has(k)) {
                    delete media.firstSeen[k];
                }
            }

            if (candidates.length === 0) {
                media.players = [];
                media.currentIndex = 0;
                return;
            }

            let newIdx = 0;

            if (media.currentPlayer && candidates.length > 0) {
                let found = -1;
                for (let i = 0; i < candidates.length; i++) {
                    if (candidates[i] === media.currentPlayer) { found = i; break; }
                }
                if (found !== -1) {
                    newIdx = found;
                } else {
                    newIdx = 0;
                }
            }

            media.players = candidates;
            if (newIdx >= candidates.length) newIdx = 0;
            media.currentIndex = newIdx;
        }

        function cycleNext() {
            if (players.length < 2) return;
            currentIndex = (currentIndex + 1) % players.length;
        }
        function cyclePrev() {
            if (players.length < 2) return;
            currentIndex = (currentIndex - 1 + players.length) % players.length;
        }
        function selectPlayer(idx) {
            if (idx >= 0 && idx < players.length) currentIndex = idx;
        }

        function forceRescan() {
            console.log("Media: user requested force rescan of MPRIS players");
            firstSeen = ({});
            _actuallyRefreshPlayers();
            refreshBrowserAudioNodes();
        }

        function refreshBrowserAudioNodes() {
            const vals = (Pipewire.nodes && Pipewire.nodes.values) ? Pipewire.nodes.values : [];
            let result = [];

            const browserHints = ["brave", "firefox", "chrome", "chromium", "audacious", "mpv", "vlc", "spotify", "deadbeef", "rhythmbox", "clementine"];

            for (let i = 0; i < vals.length; i++) {
                const n = vals[i];
                if (!n || !n.audio) continue;

                const props = n.properties || {};
                const appName = props["application.name"] || n.name || "";
                const lower = appName.toLowerCase();

                let isBrowser = false;
                for (let b = 0; b < browserHints.length; b++) {
                    if (lower.indexOf(browserHints[b]) !== -1) {
                        isBrowser = true;
                        break;
                    }
                }
                if (!isBrowser) continue;

                const mediaName = props["media.name"] || "";
                const nodeName = n.name || "";
                const role = props["media.role"] || "";
                const mediaClass = props["media.class"] || "";

                result.push({
                    app: appName,
                    mediaName: mediaName,
                    nodeName: nodeName,
                    role: role,
                    mediaClass: mediaClass,
                    isOutput: !!n.isStream || !n.isSink,
                    volume: (n.audio.volume !== undefined) ? n.audio.volume : 0,
                    muted: !!n.audio.muted
                });
            }

            media.browserAudioNodes = result;
        }

        function toggleCurrent() {
            if (currentPlayer && currentPlayer.canTogglePlaying) {
                currentPlayer.togglePlaying();
            } else if (currentPlayer && currentPlayer.canPause && currentPlayer.isPlaying) {
                currentPlayer.pause();
            } else if (currentPlayer && currentPlayer.canPlay) {
                currentPlayer.play();
            }
        }

        function nextTrack() {
            if (currentPlayer && currentPlayer.canGoNext) currentPlayer.next();
        }
        function prevTrack() {
            if (currentPlayer && currentPlayer.canGoPrevious) currentPlayer.previous();
        }

        function seekTo(ms) {
            if (!currentPlayer || !currentPlayer.canSeek) return;
            const clamped = Math.max(0, Math.min(ms, currentPlayer.length || ms));
            if (currentPlayer.setPosition) {
                currentPlayer.setPosition(clamped);
            } else if (currentPlayer.seek) {
                currentPlayer.seek(clamped - (currentPlayer.position || 0));
            }
        }

        function seekRelative(deltaMs) {
            if (!currentPlayer || !currentPlayer.canSeek) return;
            seekTo((currentPlayer.position || 0) + deltaMs);
        }
    }

    Connections {
        target: Mpris.players
        function onValuesChanged() { media.refreshPlayers(); }
    }

    // ===== THE PILL UI =====
    // Subtle top highlight
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: bar.glassHighlight
        radius: parent.radius
    }

    // Cava visualizer background
    CavaVisualizer {
        anchors.fill: parent
        anchors.margins: 4
        bar: bar
        active: Qt.binding(function(){ return media.isPlaying; })
    }

    Row {
        id: mediaRow
        anchors.centerIn: parent
        spacing: 8
        z: 1

        // Play/pause indicator
        Text {
            text: media.isPlaying ? "▶" : "⏸"
            font.pixelSize: 14
            font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
            color: media.isPlaying ? bar.accent : bar.subtext
            anchors.verticalCenter: parent.verticalCenter
        }

        // Title
        Text {
            text: media.title || "No media"
            color: bar.text
            font.pixelSize: 15
            font.bold: true
            font.family: "JetBrains Mono Nerd Font, monospace"
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mediaHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (event.angleDelta.y > 0) {
                    media.cyclePrev();
                } else {
                    media.cycleNext();
                }
            }
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                media.toggleCurrent();
            } else if (mouse.button === Qt.RightButton) {
                showMediaPopup();
            }
        }
    }

    // Popups and helpers will be moved here in the full extraction.
    // For now, this is the core pill + state.
}
