import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import Quickshell.Io as Io

import "components"

PanelWindow {
    id: bar

    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: 54   // Increased for ultrawide readability (was 46)
    color: "transparent"

    // ===== Theme (centralized — see Theme.qml) =====
    // Single source of truth. All values (including glassmorphic tokens,
    // workspace colors, pill metrics, and audio widget sizing) live in Theme.qml.
    // The aliases below provide 100% backward compatibility so the other 3300+
    // lines of this file (and any code using bar.accent, bar.pillRadius, etc.)
    // continue to work with zero other changes during the split.
    Theme { id: theme }

    property alias bg: theme.bg
    property alias surface: theme.surface
    property alias text: theme.text
    property alias subtext: theme.subtext
    property alias overlay: theme.overlay
    property alias accent: theme.accent
    property alias todayBg: theme.todayBg
    property alias weekday: theme.weekday
    property alias clock: theme.clock
    property alias muted: theme.muted
    property alias barRadius: theme.barRadius
    property alias sideMargin: theme.sideMargin

    readonly property alias glassBg: theme.glassBg
    readonly property alias glassBorder: theme.glassBorder
    readonly property alias glassHighlight: theme.glassHighlight
    readonly property alias glassPillBg: theme.glassPillBg
    readonly property alias glassHover: theme.glassHover
    readonly property alias glassPopupBg: theme.glassPopupBg
    readonly property alias glassPopupBorder: theme.glassPopupBorder
    readonly property alias glassPopupHighlight: theme.glassPopupHighlight

    readonly property alias menuBtnNone: theme.menuBtnNone
    readonly property alias menuBtnCheck: theme.menuBtnCheck
    readonly property alias menuBtnRadio: theme.menuBtnRadio

    readonly property alias wsHoverYellow: theme.wsHoverYellow
    readonly property alias wsActiveBg: theme.wsActiveBg
    readonly property alias wsText: theme.wsText
    readonly property alias wsActiveText: theme.wsActiveText

    readonly property alias pillBg: theme.pillBg
    readonly property alias pillBorder: theme.pillBorder
    readonly property alias pillRadius: theme.pillRadius

    readonly property alias audioViewContentWidth: theme.audioViewContentWidth
    readonly property alias audioViewSidePadding: theme.audioViewSidePadding

    function getWsIcon(id) {
        switch (id) {
            case 1: return "";     // code
            case 2: return "🦁";    // Brave Browser
            case 3: return "";     // chats
            case 4: return "";     // Google Chrome
            case 5: return "🕹";    // game
            case 6: return "";     // Misc
            case 7: return "󰈹";     // Firefox
            case 8: return "";     // term
            case 9: return "󰨞";     // vscode
            case 10: return "";    // Misc
            default: return "󰈸";
        }
    }

    property var shownWorkspaces: []

    function updateShownWorkspaces() {
        if (!Hyprland.workspaces || !Hyprland.workspaces.values) {
            bar.shownWorkspaces = [];
            return;
        }
        const filtered = Hyprland.workspaces.values.filter(function(w) {
            if (!w || w.id <= 0) return false;
            let hasWindows = false;
            if (w.toplevels) {
                if (typeof w.toplevels.count === "number") hasWindows = w.toplevels.count > 0;
                else if (w.toplevels.values && typeof w.toplevels.values.length === "number") hasWindows = w.toplevels.values.length > 0;
            }
            return hasWindows || w.active || w.focused;
        });
        filtered.sort(function(a, b) { return a.id - b.id; });
        bar.shownWorkspaces = filtered;
    }

    // ===== NOTIFICATIONS (swaync-backed bell widget) =====
    // Uses swaync-client -s (subscribe) for live count + DND state.
    // This is purely event-driven (no polling timers). The client process
    // only emits when swaync has changes. Keeps resource use minimal.
    QtObject {
        id: notif
        property int count: 0
        property bool dnd: false
        property bool inhibited: false
        // icon computed from state (using common nerd font bell glyphs)
        readonly property string icon: {
            if (dnd) return notif.count > 0 ? "󰂠" : "󰪓";  // dnd variants
            return notif.count > 0 ? "󱅫" : "󰂜";            // normal bell
        }
    }

    function switchToRelative(delta) {
        if (!bar.shownWorkspaces || bar.shownWorkspaces.length === 0) return;
        const activeId = (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id) ? Hyprland.focusedWorkspace.id : 1;
        let idx = -1;
        for (let i = 0; i < bar.shownWorkspaces.length; i++) {
            if (bar.shownWorkspaces[i].id === activeId) { idx = i; break; }
        }
        if (idx < 0) idx = 0;
        let newIdx = idx + delta;
        if (newIdx < 0) newIdx = 0;
        if (newIdx >= bar.shownWorkspaces.length) newIdx = bar.shownWorkspaces.length - 1;
        const target = bar.shownWorkspaces[newIdx];
        if (target && target.activate) target.activate();
    }

    Component.onCompleted: {
        bar.updateShownWorkspaces();
        audio.refreshDevices();
        wsColdStartPoller.start();   // cold-start burst to catch full workspace state on qs launch
        // Ensure we pick up any MPRIS players that were already registered before the
        // Connections below became active (e.g. Audacious, Spotify, etc. left running).
        Qt.callLater(media.refreshPlayers);
        media.refreshBrowserAudioNodes();

        // Kick the CPU/GPU stats pill poller immediately so the centered widget appears fast
        Qt.callLater(function() {
            if (!statsPoller.running) statsPoller.running = true
        })
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { bar.updateShownWorkspaces(); }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { bar.updateShownWorkspaces(); }
    }
    // Note: toplevel open/close is reflected via workspaces.values updates in practice (Hyprland IPC pushes changes).
    // If some windows don't appear/disappear immediately, a manual refresh button or extra Hyprland.toplevels connection can be added.

    // Cold-start workspace polling (fixes "only shows current workspace on qs launch after cold boot/reboot")
    // When quickshell starts while Hyprland is already running with windows on other workspaces,
    // the Hyprland IPC model (especially per-workspace toplevel counts) is often incomplete for the
    // first 200-900ms. A short burst of forced refreshes ensures occupied workspaces appear immediately.
    property int _wsColdPollCount: 0
    Timer {
        id: wsColdStartPoller
        interval: 130
        repeat: true
        onTriggered: {
            bar.updateShownWorkspaces();
            bar._wsColdPollCount += 1;
            if (bar._wsColdPollCount >= 7) {   // ~910ms of coverage (130*7) — enough to catch delayed IPC state
                stop();
                bar._wsColdPollCount = 0;
            }
        }
    }

    // Lightweight periodic rescan for MPRIS.
    // Many native players (Audacious, mpv, some VLC configs, etc.) register a single
    // MPRIS object once and then mutate Metadata + PlaybackStatus in place when you
    // press play or change tracks. This does *not* emit valuesChanged on the players list.
    // Browser media often spawns fresh MPRIS objects, which is why the "streams like
    // in the browser" path felt more reliable before.
    // A cheap 1.5s poll guarantees we notice title/playback changes quickly without
    // noticeable CPU cost (the actual work is a tiny loop over < 10 objects).
    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: media.refreshPlayers()
    }

    // ===== AUDIO WIDGET (Pipewire) =====
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
            media.refreshBrowserAudioNodes();
        }
    }

    // ===== MEDIA PLAYER (MPRIS) =====
    // Centered pill in top bar. Shows ONLY when at least one stream is *actively playing*.
    // As soon as playback stops/pauses or the player disappears, the pill is hidden.
    // This prevents the previous problem of a stuck pill after "nothing is playing".
    // Scroll cycles between simultaneous playing streams. Right-click opens the rich popup
    // (with art, controls, and the independent PipeWire audio sources list).
    // Visualizer is pure QML (no external cava). Updates are cheap + coalesced.
    QtObject {
        id: media

        // All players reported by MPRIS (reacts to players changing)
        readonly property var allPlayers: (Mpris.players && Mpris.players.values) ? Mpris.players.values : []

        // Currently playing players (with a title). The pill is only visible when this list is non-empty.
        // When multiple streams are playing simultaneously we pick the one seen first for stability.
        // Paused/stopped players are intentionally excluded (prevents stuck pills after playback ends).
        property var players: []
        property int currentIndex: 0
        readonly property var currentPlayer: (players.length > 0 && currentIndex >= 0 && currentIndex < players.length)
            ? players[currentIndex] : null

        // Track first observation time for each player (by stable dbusName) so we can honor
        // "show whichever stream was started first" when several are active simultaneously.
        property var firstSeen: ({})

        // Supplementary "direct" view from PipeWire (independent of MPRIS).
        // Shows whatever is *actually* producing audio right now (browsers + native players
        // like Audacious, mpv, etc). This is what powers the lower section of the media popup.
        // Use the Rescan button (or just open the popup) after starting playback if you want
        // the freshest picture of raw audio nodes.
        property var browserAudioNodes: []

        // Convenience getters (safe when no player)
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

        // Rebuild filtered players list whenever Mpris reports changes.
        //
        // New simplified policy (after user feedback):
        // - The centered pill ONLY shows when there is at least one *currently playing* stream
        //   with a title. As soon as everything is paused, stopped, or the player goes away,
        //   the pill disappears. This prevents the "stuck after nothing is playing" problem.
        // - When multiple things are playing at once we still pick the one that was seen first
        //   (stable ordering across rapid tab/media changes).
        // - Paused players are deliberately excluded from the pill (and from the main players list).
        //   They can still be inspected via the "Audio sources from PipeWire" section in the popup
        //   or by re-opening the player itself.
        //
        // The 1.5s poller + onValuesChanged + forceRescan now reliably drive both appearance
        // and disappearance.
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
                if (!t) continue;           // must have a title
                if (!p.isPlaying) continue; // only currently playing streams make it into the pill

                candidates.push(p);

                const key = p.dbusName || ("id:" + p.uniqueId);
                if (key) {
                    currentKeys.add(key);
                    if (media.firstSeen[key] === undefined) {
                        media.firstSeen[key] = Date.now();
                    }
                }
            }

            // Drop firstSeen entries for players that have gone away (prevents unbounded growth).
            for (let k in media.firstSeen) {
                if (!currentKeys.has(k)) {
                    delete media.firstSeen[k];
                }
            }

            function startedFirst(a, b) {
                const ka = a.dbusName || ("id:" + a.uniqueId);
                const kb = b.dbusName || ("id:" + b.uniqueId);
                const ta = media.firstSeen[ka] || Number.MAX_SAFE_INTEGER;
                const tb = media.firstSeen[kb] || Number.MAX_SAFE_INTEGER;
                return ta - tb;
            }
            candidates.sort(startedFirst);

            // Hard clear when nothing is actively playing. This is the key change that
            // makes the pill reliably disappear instead of getting stuck on a paused ghost.
            if (candidates.length === 0) {
                media.players = [];
                media.currentIndex = 0;
                return;
            }

            // We have one or more currently playing streams.
            let newIdx = 0;

            if (media.currentPlayer && candidates.length > 0) {
                let found = -1;
                for (let i = 0; i < candidates.length; i++) {
                    if (candidates[i] === media.currentPlayer) { found = i; break; }
                }
                if (found !== -1) {
                    newIdx = found;   // keep user's choice while it is still playing
                } else {
                    newIdx = 0;       // previous one vanished → reset to first (earliest seen)
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

        // Manual rescan requested by the user (via Refresh button in popup).
        // Clears the "started first" memory and forces a full rebuild of the players list
        // from the current MPRIS state. This is the closest we can get to "query browsers
        // manually" without additional browser-side setup (remote debugging or extensions).
        //
        // In the future this could be extended to also talk to Chromium remote debugging
        // (if you launch Brave with --remote-debugging-port=9222) or a custom extension.
        function forceRescan() {
            console.log("Media: user requested force rescan of MPRIS players");
            firstSeen = ({});           // forget previous start times / ordering
            _actuallyRefreshPlayers();  // run full rebuild immediately
            refreshBrowserAudioNodes(); // direct query of PipeWire audio nodes
        }

        // Scans PipeWire nodes for known media-producing apps (browsers + Audacious,
        // mpv, etc.) and extracts useful info about active audio streams.
        // Completely independent of MPRIS. This is the "what is *really* making sound"
        // view, similar to pavucontrol sink inputs. Shown in the media popup.
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

        // Seek by absolute position (ms). Many players are picky; we try setPosition first.
        function seekTo(ms) {
            if (!currentPlayer || !currentPlayer.canSeek) return;
            const clamped = Math.max(0, Math.min(ms, currentPlayer.length || ms));
            if (currentPlayer.setPosition) {
                currentPlayer.setPosition(clamped);
            } else if (currentPlayer.seek) {
                // fallback: relative seek from current
                currentPlayer.seek(clamped - (currentPlayer.position || 0));
            }
        }

        // Relative seek (for clicking on the bar)
        function seekRelative(deltaMs) {
            if (!currentPlayer || !currentPlayer.canSeek) return;
            seekTo((currentPlayer.position || 0) + deltaMs);
        }
    }

    // Mpris list changes (add/remove + metadata updates on existing players) can arrive
    // in bursts. We let Qt.callLater coalesce them into a single rebuild.
    Connections {
        target: Mpris.players
        function onValuesChanged() { media.refreshPlayers(); }
    }

    // ===== CENTERED CPU+GPU STATS (lightweight poller for top bar pill) =====
    // Polls a minimal ~80ms script every 1.6s. Provides live util + temp for the
    // AMD 9950X3D (k10temp) and NVIDIA RTX 5080. Used exclusively by the centered
    // sysPill when no media is playing.
    property real cpuUtil: 0
    property int  cpuTemp: 0
    property real gpuUtil: 0
    property int  gpuTemp: 0
    property bool sysStatsReady: false

    function updateSysStats(d) {
        if (d.cpu) {
            cpuUtil = Number(d.cpu.util) || 0
            cpuTemp = Math.round(Number(d.cpu.temp) || 0)
        }
        if (d.gpu) {
            gpuUtil = Number(d.gpu.util) || 0
            gpuTemp = Math.round(Number(d.gpu.temp) || 0)
        }
        sysStatsReady = true
    }

    Io.Process {
        id: statsPoller
        command: ["/home/crome/.config/quickshell/scripts/bar-stats.sh"]
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                const trimmed = line.trim()
                if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return
                try {
                    const d = JSON.parse(trimmed)
                    bar.updateSysStats(d)
                } catch (e) {}
            }
        }
        onExited: (code) => {
            // ready for next timer kick
        }
    }

    Timer {
        id: statsTimer
        interval: 1600
        running: true
        repeat: true
        onTriggered: {
            if (!statsPoller.running) statsPoller.running = true
        }
    }

    // ===== Bar Content =====
    // Glassmorphic styling throughout bar + all popups (frosted acrylic style)
    // (Easy to revert - the glass* properties control most of it)
    Rectangle {
        id: barBg
        anchors.fill: parent
        anchors.leftMargin: bar.sideMargin
        anchors.rightMargin: bar.sideMargin
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: bar.barRadius
        color: bar.glassBg
        border.width: 1
        border.color: bar.glassBorder

        // Stronger top light edge for classic glassmorphism
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1.5
            color: bar.glassHighlight
            radius: parent.radius
        }

        // Very subtle bottom inner shadow for depth
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(0, 0, 0, 0.25)
            radius: parent.radius
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20   // Slightly more breathing room for ultrawide
            anchors.rightMargin: 20
            spacing: 14

            // Left side - Workspaces (from eww migration: icons+num, only active/occupied,

            Rectangle {
                id: launcherPill
                Layout.preferredWidth: 42
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: launcherMouse.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: launcherMouse.containsMouse ? bar.accent : bar.pillBorder

                Text {
                    anchors.centerIn: parent
                    text: "󰀻"   // Change this icon if you want (see note below)
                    font.pixelSize: 18
                    font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                    color: launcherMouse.containsMouse ? bar.accent : bar.subtext
                }

                MouseArea {
                    id: launcherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["sh", "-c", "~/.local/bin/rofi-app-drawer"])
                    }
                }

                ToolTip.text: "App Launcher"
                ToolTip.visible: launcherMouse.containsMouse
                ToolTip.delay: 500
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }


            // reactive via Quickshell.Hyprland (no polling), yellow hover, active highlight,
            // scroll wheel, click to focus)
            // Encapsulated in a pill (matching eww module pill style: #1a1a1a bg, rounded, subtle border)
            Rectangle {
                id: workspacesPill
                color: bar.glassPillBg
                radius: bar.pillRadius
                border.width: 1
                border.color: bar.glassBorder

                Layout.preferredWidth: wsRow.implicitWidth + 16
                Layout.preferredHeight: 40   // Taller pill for ultrawide readability
                Layout.alignment: Qt.AlignVCenter

                // Mouse wheel: up advances "next" in the shown list (per requirements)
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const delta = (event.angleDelta.y > 0) ? 1 : -1;
                        bar.switchToRelative(delta);
                    }
                }

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: bar.shownWorkspaces
                        delegate: Rectangle {
                            id: wsBtn
                            required property var modelData // HyprlandWorkspace
                            required property int index
                            property bool isActive: modelData && (modelData.active || modelData.focused)
                            property bool isHovered: wsMouse.containsMouse

                            width: 42   // Slightly wider for bigger text
                            height: 32
                            radius: 8
                            color: isActive ? Qt.rgba(0.53, 0.69, 0.96, 0.22) :   // Glassy accent tint when active
                                   (isHovered ? bar.wsHoverYellow : "transparent")
                            border.width: isActive ? 1 : 0
                            border.color: isActive ? Qt.rgba(0.53, 0.69, 0.96, 0.6) : "#45475a"

                            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

                            MouseArea {
                                id: wsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData) modelData.activate();
                                }
                            }

                            // Icon + number (matching eww mapping)
                            // Text is white + bold like the date/time clock, slightly larger
                            Row {
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: bar.getWsIcon(modelData ? modelData.id : 0)
                                    font.pixelSize: 17   // Increased for ultrawide readability
                                    color: isActive ? "#e0e7ff" :
                                           (isHovered ? "#111111" : bar.clock)
                                    font.family: "JetBrains Mono Nerd Font, Symbols Nerd Font, monospace"
                                    font.bold: true
                                }
                                Text {
                                    text: modelData ? modelData.id : ""
                                    font.pixelSize: 15   // Increased for ultrawide readability
                                    font.bold: true
                                    color: isActive ? "#e0e7ff" :
                                           (isHovered ? "#111111" : bar.clock)
                                }
                            }
                        }
                    }
                }
            }  // closes workspacesPill Rectangle

            Item { Layout.fillWidth: true }

            // ===== QUICK LAUNCH APPS (encapsulated pill, left of system tray) =====
            Rectangle {
                id: appsPill
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



            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== SYSTEM TRAY (right side, left of volume widget, pill style, comfortable spacing, efficient reactive) =====
            Rectangle {
                id: trayPill
                visible: SystemTray.items.values.length > 0
                Layout.preferredWidth: visible ? (trayContent.implicitWidth + 14) : 0
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: trayHover.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
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
                        spacing: 8   // comfortable width between icons
                        anchors.centerIn: parent

                        Repeater {
                            model: SystemTray.items.values
                            delegate: Item {
                                id: trayIconItem
                                required property var modelData
                                width: 20
                                height: 20

                                IconImage {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
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
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== AUDIO / VOLUME WIDGET (cycle speaker <-> mic <-> dual, popup on right-click) =====
            Rectangle {
                id: audioPill
                Layout.preferredWidth: bar.audioViewContentWidth + 18
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: audioHover.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: audioHover.containsMouse ? bar.accent : bar.pillBorder

                // Main interaction area (left-click cycle, middle mute, right popup)
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
                            // Middle: mute the "primary" for current view
                            if (audio.viewMode === 0) audio.toggleMute(audio.speaker);
                            else if (audio.viewMode === 1) audio.toggleMute(audio.mic);
                            else audio.toggleMute(audio.speaker);  // dual: speaker
                        } else if (mouse.button === Qt.RightButton) {
                            showAudioPopup();
                        }
                    }
                }

                // Content switches on viewMode. Fixed outer width so pill never resizes on cycle.
                // Speaker/mic stay centered (balanced look, stable x-position because width fixed).
                // Dual left+right anchored + sidePadding so speaker icon lines up exactly and it spans full width.
                // Bar host Items widened to fully contain their bars (no overflow/overlap with pill borders).
                Item {
                    id: audioContent
                    anchors.centerIn: parent
                    width: bar.audioViewContentWidth
                    implicitWidth: width
                    implicitHeight: 22

                    // ========== SPEAKER VIEW ==========
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

                        // Clickable slider + wheel for speaker (host sized to contain bar fully)
                        Item {
                            width: 110; height: 18
                            anchors.verticalCenter: parent.verticalCenter

                            // ========== DIAGNOSTIC TEST (temporary) ==========
                            // Hard-coding value + obvious color to determine if the
                            // problem is (A) the value binding not reaching the component,
                            // or (B) the width calculation inside VolumeBar still failing.
                            VolumeBar {
                                anchors.centerIn: parent
                                bar: bar
                                value: 0.75                    // hard-coded 75% for test
                                onSet: function(v){ audio.setVolume(audio.speaker, v); }
                                fill: "#ff00ff"                // bright magenta - impossible to miss
                            }
                            // ==================================================

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

                    // ========== MIC VIEW ==========
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

                            // ========== DIAGNOSTIC TEST (temporary) ==========
                            VolumeBar {
                                anchors.centerIn: parent
                                bar: bar
                                value: 0.75
                                onSet: function(v){ audio.setVolume(audio.mic, v); }
                                fill: "#ff00ff"
                            }
                            // ==================================================

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

                    // ========== DUAL VIEW ==========
                    // Spans complete inner width (left + right anchored). Speaker icon lines up via sidePadding + 16px size.
                    Item {
                        visible: audio.viewMode === 2
                        anchors.fill: parent

                        // Speaker mini - left side (matches speaker view icon x-position)
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
                                    anchors.centerIn: parent
                                    bar: bar
                                    value: Qt.binding(function(){ return audio.speakerVolume; })
                                    onSet: function(v){ audio.setVolume(audio.speaker, v); }
                                    fill: Qt.binding(function(){ return audio.speakerMuted ? bar.muted : bar.accent; })
                                }
                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.speaker, d); }
                                }
                            }
                        }

                        // Mic mini - right side (symmetric, full span)
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
                                    anchors.centerIn: parent
                                    bar: bar
                                    value: Qt.binding(function(){ return audio.micVolume; })
                                    onSet: function(v){ audio.setVolume(audio.mic, v); }
                                    fill: Qt.binding(function(){ return audio.micMuted ? bar.muted : bar.accent; })
                                }
                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.mic, d); }
                                }
                            }
                        }
                    }
                }
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== CLOCK (clickable) - encapsulated in pill (matching eww .clock style + workspaces pill) =====
            Rectangle {
                id: clockButton
                Layout.preferredWidth: clockLabel.implicitWidth + 28
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: clockArea.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: clockArea.containsMouse ? bar.accent : bar.pillBorder

                Text {
                    id: clockLabel
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(new Date(), "dddd, MM·dd·yyyy | HH:mm:ss")
                    color: bar.clock
                    font.pixelSize: 15   // Increased for ultrawide readability (was 13)
                    font.family: "monospace"
                    font.bold: true
                }

                MouseArea {
                    id: clockArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (calendarPopup.visible) {
                            calendarPopup.visible = false
                        } else {
                            showCalendarPopup()
                        }
                    }
                }

                // Live updating clock
                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: {
                        clockLabel.text = Qt.formatDateTime(new Date(), "dddd, MM·dd·yyyy | HH:mm:ss")
                    }
                }
            }

            // ===== NOTIFICATION BELL (right of clock, swaync backed) =====
            // Pill style to match clock + tray + audio widgets. Icon + live count badge.
            // Left click: toggle swaync control center (your full rich history + actions + replies)
            // Right click: toggle DND (icon changes to crossed bell, state synced live)
            Rectangle {
                id: notifBell
                Layout.preferredWidth: bellRow.implicitWidth + 18
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: bellMouse.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: bellMouse.containsMouse ? bar.accent : bar.pillBorder

                Row {
                    id: bellRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        id: bellIcon
                        text: notif.icon
                        font.pixelSize: 16
                        font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                        color: notif.dnd ? bar.muted : (notif.count > 0 ? bar.accent : bar.subtext)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Counter badge (only when > 0). Compact pill or circle-ish.
                    Rectangle {
                        visible: notif.count > 0
                        width: Math.max(18, countLabel.implicitWidth + 8)
                        height: 18
                        radius: 9
                        color: notif.dnd ? Qt.rgba(0.6, 0.2, 0.2, 0.9) : bar.accent
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            id: countLabel
                            anchors.centerIn: parent
                            text: notif.count > 99 ? "99+" : notif.count
                            color: "#111111"
                            font.pixelSize: 11
                            font.bold: true
                            font.family: "monospace"
                        }
                    }
                }

                MouseArea {
                    id: bellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    // Attached ToolTip (works because QtQuick.Controls is imported)
                    ToolTip.text: {
                        if (notif.dnd) return notif.count + " notifications (DND enabled)";
                        if (notif.count > 0) return notif.count + " notifications";
                        return "No notifications";
                    }
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 650

                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            toggleDnd()
                        } else if (mouse.button === Qt.LeftButton) {
                            toggleNotifPanel()
                        }
                    }
                }
            }

            // Subtle modern vertical divider (between notifications and power menu)
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== POWER / SESSION MENU (right of notification bell) =====
            // Icon-only pill; click opens centered power actions popup (logout, lock, reboot, shutdown, BIOS)
            Rectangle {
                id: powerPill
                Layout.preferredWidth: 42
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: powerMouse.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: powerMouse.containsMouse ? bar.accent : bar.pillBorder

                Text {
                    id: powerIcon
                    anchors.centerIn: parent
                    text: "󰐥"
                    font.pixelSize: 18
                    font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                    color: powerMouse.containsMouse ? bar.accent : bar.subtext
                }

                MouseArea {
                    id: powerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    ToolTip.text: "Power / Session"
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 650

                    onClicked: {
                        if (powerPopup.visible) {
                            powerPopup.visible = false
                        } else {
                            showPowerMenu()
                        }
                    }
                }
            }
        }
    }

    // ===== MEDIA PILL (centered on the bar) =====
    // Overlay inside barBg so it is perfectly centered regardless of left/right content width.
    // Only visible when we have at least one stream with a title.
    // Background = animated cava-style bars. Foreground = prominent title.
    // Left click = toggle, Right click = rich popup, Wheel = cycle streams.
    Rectangle {
        id: mediaPill
        anchors.centerIn: barBg
        z: 5
        visible: media.title !== ""
        width: 600
        implicitHeight: 36
        radius: bar.pillRadius
        color: mediaHover.containsMouse ? bar.glassHover : bar.glassPillBg
        border.width: 1
        border.color: mediaHover.containsMouse ? bar.accent : bar.glassBorder

        // Subtle top highlight (glassmorphic)
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: bar.glassHighlight
            radius: parent.radius
        }

        // The cava-like visualizer as background layer (spans full pill width via dynamic bars)
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

            // Small play/pause indicator (left of title)
            Text {
                text: media.isPlaying ? "" : ""
                font.pixelSize: 13
                font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                color: media.isPlaying ? bar.accent : bar.subtext
                anchors.verticalCenter: parent.verticalCenter
            }

            // Prominent title (the star of the show) — more room before eliding at 600px
            Text {
                text: media.title
                font.pixelSize: 14
                font.bold: true
                color: bar.text
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                maximumLineCount: 1
            }
        }

        MouseArea {
            id: mediaHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton) {
                    media.toggleCurrent();
                } else if (mouse.button === Qt.RightButton) {
                    showMediaPopup();
                } else if (mouse.button === Qt.MiddleButton) {
                    // Middle click could raise the player window if supported
                    if (media.currentPlayer && media.currentPlayer.canRaise) {
                        media.currentPlayer.raise();
                    }
                }
            }
        }

        // Scroll wheel cycles between active streams (the key feature for multiple browser tabs)
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (event.angleDelta.y > 0) media.cycleNext();
                else media.cyclePrev();
            }
        }
    }

    // ===== CPU + GPU MONITOR PILL (centered, glassmorphic, mutually exclusive with media pill) =====
    // Shows a compact dual visual bar + temperature display.
    // - Horizontal progress bars for utilization (color: green/yellow/red by load)
    // - Temperatures to the right of each bar (color: yellow/red by temp severity)
    // - Entire pill is centered exactly like the media pill using anchors.centerIn
    // - Right-click on CPU half launches kitty + btop
    // - Right-click on GPU half launches kitty + nvtop
    // - Only visible when no MPRIS media is actively playing (keeps center clean and purposeful)
    Rectangle {
        id: sysPill
        anchors.centerIn: barBg
        z: 5
        visible: media.title === "" && bar.sysStatsReady
        width: 385
        implicitHeight: 40
        radius: bar.pillRadius
        color: sysHover.containsMouse ? bar.glassHover : bar.glassPillBg
        border.width: 1
        border.color: sysHover.containsMouse ? bar.accent : bar.glassBorder

        // Subtle top glass highlight
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: bar.glassHighlight
            radius: parent.radius
        }

        MouseArea {
            id: sysHover
            anchors.fill: parent
            hoverEnabled: true
            // Whole pill hover only; clicks are handled by the two child areas below
        }

        Row {
            anchors.centerIn: parent
            spacing: 17

            // ----- CPU HALF -----
            Item {
                width: 162
                height: 26
                MouseArea {
                    id: cpuClick
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            Quickshell.execDetached(["kitty", "-e", "btop"])
                        }
                    }
                    ToolTip.text: "Right-click to launch btop"
                    ToolTip.visible: cpuClick.containsMouse
                    ToolTip.delay: 650
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 7

                    Text {
                        text: "CPU"
                        font.pixelSize: 13
                        font.bold: true
                        font.family: "JetBrains Mono Nerd Font, monospace"
                        color: cpuClick.containsMouse ? bar.accent : bar.subtext
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Visual utilization bar (compact, animated)
                    Item {
                        width: 73
                        height: 8
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.09)
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(2, Math.min(parent.width, parent.width * (bar.cpuUtil / 100)))
                            height: 8
                            radius: 4
                            color: bar.cpuUtil > 85 ? "#f38ba8" :
                                   (bar.cpuUtil > 65 ? "#f9e2af" : bar.accent)
                            Behavior on width {
                                NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                            }
                        }
                    }

                    // Temp (always shown, color coded)
                    Text {
                        text: bar.cpuTemp + "°"
                        font.pixelSize: 13
                        font.bold: true
                        color: bar.cpuTemp > 85 ? "#f38ba8" :
                               (bar.cpuTemp > 70 ? "#f9e2af" : bar.text)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Thin vertical divider between CPU and GPU sections
            Rectangle {
                width: 1
                height: 17
                color: Qt.rgba(1, 1, 1, 0.13)
                anchors.verticalCenter: parent.verticalCenter
            }

            // ----- GPU HALF -----
            Item {
                width: 162
                height: 26
                MouseArea {
                    id: gpuClick
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            Quickshell.execDetached(["kitty", "-e", "nvtop"])
                        }
                    }
                    ToolTip.text: "Right-click to launch nvtop"
                    ToolTip.visible: gpuClick.containsMouse
                    ToolTip.delay: 650
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 7

                    Text {
                        text: "GPU"
                        font.pixelSize: 13
                        font.bold: true
                        font.family: "JetBrains Mono Nerd Font, monospace"
                        color: gpuClick.containsMouse ? bar.accent : bar.subtext
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Visual utilization bar (compact, animated)
                    Item {
                        width: 73
                        height: 8
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.09)
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(2, Math.min(parent.width, parent.width * (bar.gpuUtil / 100)))
                            height: 8
                            radius: 4
                            color: bar.gpuUtil > 85 ? "#f38ba8" :
                                   (bar.gpuUtil > 65 ? "#f9e2af" : bar.accent)
                            Behavior on width {
                                NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                            }
                        }
                    }

                    // Temp (always shown, color coded)
                    Text {
                        text: bar.gpuTemp + "°"
                        font.pixelSize: 13
                        font.bold: true
                        color: bar.gpuTemp > 85 ? "#f38ba8" :
                               (bar.gpuTemp > 70 ? "#f9e2af" : bar.text)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // ===== Calendar Logic =====
    QtObject {
        id: calendar
        property int viewedMonth: new Date().getMonth()
        property int viewedYear: new Date().getFullYear()

        function goToToday() {
            var now = new Date()
            viewedMonth = now.getMonth()
            viewedYear = now.getFullYear()
        }

        function changeMonth(delta) {
            viewedMonth += delta
            while (viewedMonth < 0) {
                viewedMonth += 12
                viewedYear -= 1
            }
            while (viewedMonth > 11) {
                viewedMonth -= 12
                viewedYear += 1
            }
        }
    }

    // ===== CALENDAR POPUP =====
    PopupWindow {
        id: calendarPopup
        anchor.window: bar
        implicitWidth: 310
        implicitHeight: 280   // Reduced ~50% from tall version (calendar-specific; other popups untouched)
        visible: false
        color: "transparent"

        // Glassmorphic popup background
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
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
                anchors.margins: 14
                spacing: 10

                // Header: Month + Year + Navigation
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: Qt.formatDateTime(new Date(calendar.viewedYear, calendar.viewedMonth, 1), "MMMM yyyy")
                        color: bar.text
                        font.pixelSize: 17
                        font.bold: true
                        horizontalAlignment: Text.AlignLeft
                    }

                    // Nav buttons: year-, month-, today, month+, year+
                    Repeater {
                        model: [
                            { sym: "«", delta: -12, tip: "Previous year" },
                            { sym: "‹", delta: -1,  tip: "Previous month" },
                            { sym: "›", delta:  1,  tip: "Next month" },
                            { sym: "»", delta: 12,  tip: "Next year" }
                        ]
                        delegate: Rectangle {
                            width: 26
                            height: 26
                            radius: 6
                            color: navMa.containsMouse ? bar.surface : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.sym
                                color: bar.accent
                                font.pixelSize: 15
                                font.bold: true
                            }

                            MouseArea {
                                id: navMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: calendar.changeMonth(modelData.delta)
                            }
                        }
                    }

                    // Today button
                    Rectangle {
                        width: 52
                        height: 24
                        radius: 6
                        color: todayBtnMa.containsMouse ? bar.accent : bar.surface

                        Text {
                            anchors.centerIn: parent
                            text: "Today"
                            color: todayBtnMa.containsMouse ? bar.bg : bar.text
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: todayBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: calendar.goToToday()
                        }
                    }
                }

                // Weekday headers (Monday first)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]
                        delegate: Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: bar.weekday
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }

                // Calendar grid (42 cells)
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    rowSpacing: 3
                    columnSpacing: 3

                    Repeater {
                        model: 42
                        delegate: Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 22

                            // ===== Day calculation =====
                            property int firstDay: new Date(calendar.viewedYear, calendar.viewedMonth, 1).getDay() // 0=Sun
                            property int leadingEmpty: (firstDay === 0) ? 6 : (firstDay - 1)
                            property int daysInMonth: new Date(calendar.viewedYear, calendar.viewedMonth + 1, 0).getDate()
                            property int dayNum: index - leadingEmpty + 1

                            property bool isCurrentMonth: dayNum >= 1 && dayNum <= daysInMonth
                            property int displayNum: {
                                if (isCurrentMonth) return dayNum
                                if (dayNum < 1) {
                                    // previous month
                                    var prevDays = new Date(calendar.viewedYear, calendar.viewedMonth, 0).getDate()
                                    return prevDays + dayNum
                                }
                                // next month
                                return dayNum - daysInMonth
                            }

                            property bool isToday: {
                                var now = new Date()
                                return isCurrentMonth &&
                                       calendar.viewedYear === now.getFullYear() &&
                                       calendar.viewedMonth === now.getMonth() &&
                                       dayNum === now.getDate()
                            }

                            // Today highlight circle
                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                color: bar.todayBg
                                visible: isToday
                            }

                            // Day number
                            Text {
                                anchors.centerIn: parent
                                text: displayNum > 0 ? displayNum : ""
                                color: isToday ? bar.bg :
                                       (isCurrentMonth ? bar.text : bar.overlay)
                                font.pixelSize: isToday ? 13 : 12
                                font.bold: isToday || isCurrentMonth
                            }
                        }
                    }
                }

                // Footer
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4

                    Text {
                        Layout.fillWidth: true
                        text: "Current day is highlighted"
                        color: bar.overlay
                        font.pixelSize: 10
                    }

                    Text {
                        text: "click clock to close"
                        color: bar.overlay
                        font.pixelSize: 10
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
        implicitHeight: 260   // Reduced ~50% from tall version (sound widget popup only; others untouched)
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
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

                // Header
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

                    // Device selector (click to open list)
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

                    // Slider row
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
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                bar: bar
                                value: Qt.binding(function(){ return audio.speakerVolume; })
                                onSet: function(v){ audio.setVolume(audio.speaker, v); }
                                barHeight: 8
                                fill: Qt.binding(function(){ return audio.speakerMuted ? bar.muted : bar.accent; })
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

                        // Mute toggle button
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
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                bar: bar
                                value: Qt.binding(function(){ return audio.micVolume; })
                                onSet: function(v){ audio.setVolume(audio.mic, v); }
                                barHeight: 8
                                fill: Qt.binding(function(){ return audio.micMuted ? bar.muted : bar.accent; })
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

        // Close on click outside content (simple: whole popup mouse)
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: audioPopup.visible = false
        }
    }

    // Device list popup (shared for output/input)
    PopupWindow {
        id: audioDeviceListPopup
        anchor.window: bar
        implicitWidth: 320
        implicitHeight: Math.min(420, Math.max(100, (audio.deviceListForSink ? audio.sinks.length : audio.sources.length) * 39 + 90))  // ~50% taller
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
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

                // Device rows
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
                                    var node = modelData.node;
                                    if (audio.deviceListForSink) {
                                        Pipewire.preferredDefaultAudioSink = node;
                                    } else {
                                        Pipewire.preferredDefaultAudioSource = node;
                                    }
                                    audioDeviceListPopup.visible = false;
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
        if (!dev || !dev.node) return false;
        var def = audio.deviceListForSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource;
        if (!def) return false;
        return (def.name === dev.node.name) || (def.description === dev.node.description);
    }

    function openAudioDeviceList(forSink, targetItem) {
        audio.deviceListForSink = forSink;
        var popupW = audioDeviceListPopup.implicitWidth;
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;

        // Better position using mapToItem (relative to barBg like calendar)
        var p = (audioPill && barBg) ? audioPill.mapToItem(barBg, 0, audioPill.height) : {x: 200, y: 0};
        var baseX = bar.sideMargin + p.x;
        audioDeviceListPopup.anchor.rect.x = Math.min(baseX, screenW - popupW - 12);
        audioDeviceListPopup.anchor.rect.y = bar.implicitHeight + 46;
        audioDeviceListPopup.visible = true;
    }

    function showAudioPopup() {
        if (audioPopup.visible) {
            audioPopup.visible = false;
            audioDeviceListPopup.visible = false;
            return;
        }
        var pos = audioPill.mapToItem(barBg, audioPill.width / 2, audioPill.height);
        var popupW = audioPopup.implicitWidth;
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;

        var targetX = bar.sideMargin + pos.x - (popupW / 2);
        var minX = 12;
        var maxX = screenW - popupW - 12;
        audioPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX));
        audioPopup.anchor.rect.y = bar.implicitHeight + 2;

        audioPopup.visible = true;
        audioDeviceListPopup.visible = false;
    }

    // Helper to position + show popup nicely under the clock
    function showCalendarPopup() {
        // Map relative to the visual bar background (reliable QQuickItem target)
        var pos = clockButton.mapToItem(barBg, clockButton.width / 2, clockButton.height)
        var popupWidth = calendarPopup.implicitWidth

        // The barBg has leftMargin, so add the bar's side margin for correct window-relative x
        var targetX = bar.sideMargin + pos.x - (popupWidth / 2)

        // Clamp to screen edges using the screen the bar is on
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
        var minX = 12
        var maxX = screenW - popupWidth - 12
        calendarPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
        calendarPopup.anchor.rect.y = bar.implicitHeight + 2

        calendarPopup.visible = true
    }

    // ===== NOTIFICATION ACTION HELPERS (swaync-client one-shots, fire-and-forget) =====
    function toggleNotifPanel() {
        Quickshell.execDetached(["swaync-client", "-t", "-sw"])
    }

    function toggleDnd() {
        Quickshell.execDetached(["swaync-client", "-d", "-sw"])
    }

    function clearAllNotifications() {
        Quickshell.execDetached(["swaync-client", "-C", "-sw"])
    }

    // ===== MEDIA POPUP HELPERS =====
    function showMediaPopup() {
        if (mediaPopup.visible) {
            mediaPopup.visible = false;
            return;
        }
        if (!mediaPill.visible || !media.currentPlayer) return;

        // Position under the bar, centered on the media pill (like audio/calendar/power)
        var pos = mediaPill.mapToItem(barBg, mediaPill.width / 2, mediaPill.height);
        var popupW = mediaPopup.implicitWidth;
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;

        var targetX = bar.sideMargin + pos.x - (popupW / 2);
        var minX = 12;
        var maxX = screenW - popupW - 12;
        mediaPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX));
        mediaPopup.anchor.rect.y = bar.implicitHeight + 4;

        // Give the user fresh PipeWire browser audio data when they open the popup.
        // They can still hit the big Rescan button for a full MPRIS + PipeWire refresh.
        media.refreshBrowserAudioNodes();

        mediaPopup.visible = true;
    }

    function hideMediaPopup() {
        mediaPopup.visible = false;
    }

    // ===== MEDIA POPUP (rich controls, art, seek, player selector) =====
    // Large glassmorphic card shown on right-click of the media pill.
    // Contains album art, full metadata, transport, seek bar (when supported), and
    // a horizontal list to switch between multiple active streams.
    PopupWindow {
        id: mediaPopup
        anchor.window: bar
        implicitWidth: 520
        implicitHeight: 470   // extra room for PipeWire audio sources section
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
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
                spacing: 12

                // Header row: app name + manual rescan + close hint
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: media.appName
                        color: bar.accent
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }

                    // Manual "query browsers" / rescan button.
                    // Because Chromium MPRIS is unreliable, this lets the user force
                    // a fresh read of whatever players are currently advertised.
                    Rectangle {
                        Layout.preferredWidth: 68
                        Layout.preferredHeight: 20
                        radius: 4
                        color: rescanMa.containsMouse ? bar.glassHover : bar.surface
                        border.width: 1
                        border.color: bar.glassBorder

                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "⟳"
                                font.pixelSize: 12
                                color: bar.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Rescan"
                                font.pixelSize: 10
                                color: bar.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: rescanMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: media.forceRescan()
                        }
                    }

                    Text {
                        text: "click outside to close"
                        color: bar.overlay
                        font.pixelSize: 11
                        Layout.leftMargin: 8
                    }
                }

                // Art + metadata block
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    // Album art (large, with fallback)
                    Rectangle {
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 110
                        radius: 8
                        color: bar.surface
                        border.width: 1
                        border.color: "#45475a"

                        ClippingRectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 6
                            color: "transparent"

                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                source: media.artUrl
                                visible: media.artUrl !== ""
                            }
                        }

                        // Fallback icon when no art
                        Text {
                            anchors.centerIn: parent
                            visible: media.artUrl === ""
                            text: "󰝚"
                            font.pixelSize: 42
                            color: bar.overlay
                        }
                    }

                    // Title / Artist / Album
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: media.title || "(no title)"
                            color: bar.text
                            font.pixelSize: 18
                            font.bold: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: media.artist !== ""
                            text: media.artist
                            color: bar.subtext
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: media.album !== ""
                            text: media.album
                            color: bar.overlay
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                }

                // Transport row
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 24
                    Layout.topMargin: 6

                    // Previous
                    Rectangle {
                        width: 42; height: 42; radius: 21
                        color: prevMa.containsMouse ? bar.glassHover : "transparent"
                        border.width: 1
                        border.color: media.canPrev ? bar.glassBorder : "#333"
                        opacity: media.canPrev ? 1.0 : 0.4

                        Text {
                            anchors.centerIn: parent
                            text: "󰒮"
                            font.pixelSize: 20
                            color: bar.text
                        }
                        MouseArea {
                            id: prevMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: media.canPrev
                            onClicked: media.prevTrack()
                        }
                    }

                    // Play / Pause (larger)
                    Rectangle {
                        width: 58; height: 58; radius: 29
                        color: playMa.containsMouse ? bar.accent : bar.glassHover
                        border.width: 1
                        border.color: bar.accent

                        Text {
                            anchors.centerIn: parent
                            text: media.isPlaying ? "󰏤" : "󰐊"
                            font.pixelSize: 26
                            color: playMa.containsMouse ? bar.bg : bar.text
                        }
                        MouseArea {
                            id: playMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: media.toggleCurrent()
                        }
                    }

                    // Next
                    Rectangle {
                        width: 42; height: 42; radius: 21
                        color: nextMa.containsMouse ? bar.glassHover : "transparent"
                        border.width: 1
                        border.color: media.canNext ? bar.glassBorder : "#333"
                        opacity: media.canNext ? 1.0 : 0.4

                        Text {
                            anchors.centerIn: parent
                            text: "󰒭"
                            font.pixelSize: 20
                            color: bar.text
                        }
                        MouseArea {
                            id: nextMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: media.canNext
                            onClicked: media.nextTrack()
                        }
                    }
                }

                // Seek bar (only when supported)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: media.canSeek && media.lengthSupported && media.length > 0
                    spacing: 4

                    // Progress bar
                    Rectangle {
                        id: seekTrack
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: bar.surface

                        Rectangle {
                            width: Math.max(0, Math.min(parent.width, (media.position / media.length) * parent.width))
                            height: parent.height
                            radius: 3
                            color: bar.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (m) => {
                                if (media.length > 0) {
                                    const frac = m.x / width;
                                    media.seekTo(frac * media.length);
                                }
                            }
                        }
                    }

                    // Time labels
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: Qt.formatTime(new Date(media.position), "mm:ss")
                            color: bar.overlay
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Qt.formatTime(new Date(media.length), "mm:ss")
                            color: bar.overlay
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                    }
                }

                // Player / stream selector (only when multiple streams are playing)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: media.players.length > 1
                    spacing: 4

                    Text {
                        text: "Active streams"
                        color: bar.accent
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 58
                        contentWidth: playerRow.implicitWidth
                        clip: true

                        Row {
                            id: playerRow
                            spacing: 6

                            Repeater {
                                model: media.players
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    width: 170
                                    height: 52
                                    radius: 6
                                    color: index === media.currentIndex ? Qt.rgba(0.55, 0.71, 0.98, 0.18) : bar.surface
                                    border.width: index === media.currentIndex ? 1 : 0
                                    border.color: bar.accent

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 5
                                        spacing: 1

                                        Row {
                                            width: parent.width
                                            spacing: 4
                                            Text {
                                                text: modelData.identity || modelData.desktopEntry || "Player"
                                                color: bar.text
                                                font.pixelSize: 11
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Text {
                                            text: (modelData.trackTitle || "").substring(0, 26)
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                        // Helpful for distinguishing multiple players from the same browser
                                        Text {
                                            visible: modelData.dbusName
                                            text: (modelData.dbusName || "").replace("org.mpris.MediaPlayer2.", "")
                                            color: bar.overlay
                                            font.pixelSize: 8
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            media.selectPlayer(index);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // === PipeWire audio view (independent of MPRIS) ===
                // Direct snapshot of actual audio-producing nodes right now.
                // Includes browsers *and* native players (Audacious etc.) thanks to the
                // expanded hints. This is the ground truth of "what is emitting sound"
                // even if the app has no/broken MPRIS. Refreshes live + on popup open.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: media.browserAudioNodes.length > 0
                    spacing: 4
                    Layout.topMargin: 8

                    Text {
                        text: "Audio sources from PipeWire"
                        color: bar.accent
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            model: media.browserAudioNodes
                            delegate: Text {
                                required property var modelData

                                readonly property string volInfo: modelData.muted ? " (muted)" :
                                    (modelData.volume > 0 ? " • vol " + Math.round(modelData.volume * 100) + "%" : "")

                                text: modelData.app +
                                      (modelData.mediaName ? " — " + modelData.mediaName : "") +
                                      (modelData.role ? " [" + modelData.role + "]" : "") +
                                      volInfo

                                color: bar.subtext
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                    }

                    Text {
                        text: "Direct PipeWire nodes (browsers + Audacious, mpv, etc). Independent of MPRIS."
                        color: bar.overlay
                        font.pixelSize: 9
                        font.italic: true
                    }
                }
            }
        }

        // Click outside the card to close
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: mediaPopup.visible = false
        }
    }

    // ===== POWER / SESSION MENU HELPERS =====
    // logout / reboot / shutdown replicate the cleanup from hyprland.lua
    // (psd stop + targeted pkill + sleep 1 before the final action)
    function showPowerMenu() {
        if (powerPopup.visible) {
            hidePowerMenu();
            return;
        }

        // Position under the bar, centered on the power pill (naturally right-side because pill is rightmost)
        // Matches the pattern used by calendarPopup, audioPopup, tray menus, etc.
        var pos = powerPill.mapToItem(barBg, powerPill.width / 2, powerPill.height);
        var popupW = powerPopup.implicitWidth;
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;

        // Slight right bias so the wide popup sits more toward the top-right of the screen
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

    // Destructive session actions below replicate the exact cleanup logic from
    // the corresponding binds in ~/.config/hypr/hyprland.lua (stop psd + kill
    // common apps before the actual logout/reboot/shutdown).
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

    // ===== TRAY MENU HELPERS (styled, efficient, no polling) =====
    function showTrayMenu(trayItem, sourceItem) {
        if (!trayItem || !trayItem.hasMenu) return;
        trayMenuPopup.currentItem = trayItem;
        trayMenuPopup.menuHandle = trayItem.menu;
        trayMenuPopup.menuStack = [];
        trayMenuPopup.itemTitle = trayItem.title || trayItem.id || "Menu";

        // Position popup near the icon, under the bar
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

    // ===== STYLED SYSTEM TRAY MENU POPUP (matches bar theme, supports submenus, checks, separators; efficient via QsMenuOpener) =====
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

        // Reactive menu opener - children update when menuHandle changes
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
            radius: 10
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                id: menuContent
                anchors.fill: parent
                anchors.margins: 6
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
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    // Back button for submenus
                    Rectangle {
                        visible: trayMenuPopup.menuStack.length > 0
                        width: 22; height: 22; radius: 4
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

                    // Close X
                    Rectangle {
                        width: 22; height: 22; radius: 4
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
                    color: "#45475a"
                }

                // Menu entries
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
                            radius: 4
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

                            // Separator
                            Rectangle {
                                visible: modelData && modelData.isSeparator
                                anchors.centerIn: parent
                                width: parent.width - 16
                                height: 1
                                color: "#45475a"
                            }

                            // Regular entry content
                            RowLayout {
                                visible: modelData && !modelData.isSeparator
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                // Checkbox / radio indicator
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
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                // Icon if present
                                IconImage {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: modelData && modelData.icon && modelData.icon.length > 0
                                    source: (modelData && modelData.icon) ? modelData.icon : ""
                                }

                                // Label
                                Text {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData ? (modelData.text || "") : ""
                                    color: entryMouse.containsMouse ? bar.text : bar.subtext
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }

                                // Submenu arrow
                                Text {
                                    visible: modelData && modelData.hasChildren
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "▸"
                                    color: bar.accent
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    Text {
                        visible: (!trayMenuOpener.children || trayMenuOpener.children.length === 0) && !trayMenuPopup.menuHandle
                        Layout.alignment: Qt.AlignHCenter
                        text: "(no menu)"
                        color: bar.overlay
                        font.pixelSize: 11
                        font.italic: true
                    }
                }
            }
        }

        // Click outside to close
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: closeTrayMenu()
        }
    }

    // ===== POWER MENU POPUP (drops under bar near power pill on the right, glassmorphic, 5 actions incl. BIOS) =====
    PopupWindow {
        id: powerPopup
        anchor.window: bar
        implicitWidth: 560
        implicitHeight: 192
        visible: false
        color: "transparent"

        // Glassmorphic card background
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
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

                // Header row with title + hint + close X
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
                        text: "Esc or click outside to close"
                        color: bar.overlay
                        font.pixelSize: 10
                    }

                    // Small close button
                    Rectangle {
                        width: 22; height: 22
                        radius: 4
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

                // Horizontal action buttons (icon + label)
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

        // Click on popup background (outside the visual card content) closes it
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: hidePowerMenu()
        }

        // Keyboard escape support (works when the popup receives focus)
        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: hidePowerMenu()
        }
    }

    // ===== SWAYNC SUBSCRIBE (event-driven state for bell) =====
    // Long-lived process. swaync-client pushes a JSON line only on relevant changes
    // (new notif, close, dnd toggle, etc.). No timers, no polling, very cheap.
    // Parses simple output from `swaync-client -s -sw`:
    //   { "count": N, "dnd": bool, "visible": bool, "inhibited": bool }
    Io.Process {
        id: swayncSub
        running: true
        command: ["swaync-client", "-s", "-sw"]

        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                // SplitParser emits one chunk per splitMarker (we still trim + guard for safety)
                const line = data.trim();
                if (!line) return;
                try {
                    const j = JSON.parse(line);
                    if (typeof j.count === 'number') {
                        notif.count = j.count;
                    }
                    if (typeof j.dnd === 'boolean') {
                        notif.dnd = j.dnd;
                    }
                    if (typeof j.inhibited === 'boolean') {
                        notif.inhibited = j.inhibited;
                    }
                } catch (e) {
                    // ignore malformed lines (initial handshake or noise)
                }
            }
        }

        onExited: (code) => {
            // If swaync isn't running or client dies, keep trying (Quickshell will restart component on reload)
            // For robustness you could add a short restart Timer here if desired.
            console.log("swaync subscribe exited with code", code);
        }
    }
}
