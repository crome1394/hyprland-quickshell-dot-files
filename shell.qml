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
import "widgets"

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



    Component.onCompleted: {
        audio.refreshDevices();
        // Ensure we pick up any MPRIS players that were already registered before the
        // Connections below became active (e.g. Audacious, Spotify, etc. left running).
        Qt.callLater(media.refreshPlayers);
        media.refreshBrowserAudioNodes();


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



    // Note: media state now lives inside MediaPill component.
    // The following is a minimal stub left over during extraction.
    QtObject {
        id: media
        // Temporary compatibility stub
        readonly property string title: ""
    }

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


            WorkspacesPill {
                bar: bar
            }

            Item { Layout.fillWidth: true }

            // ===== QUICK LAUNCH APPS (encapsulated pill, left of system tray) =====
            QuickLaunchPill {
                bar: bar
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== SYSTEM TRAY (right side, left of volume widget, pill style, comfortable spacing, efficient reactive) =====
            SystemTrayPill {
                bar: bar
                barBg: barBg
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            AudioPill {
                bar: bar
                barBg: barBg
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== CLOCK + CALENDAR (coupled pair) =====
            ClockPill {
                bar: bar
                barBg: barBg
            }

            // ===== NOTIFICATION BELL (right of clock, swaync backed) =====
            NotificationBell {
                bar: bar
                notif: notif
            }

            // Subtle modern vertical divider (between notifications and power menu)
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== POWER / SESSION MENU (right of notification bell) =====
            PowerMenu {
                bar: bar
                barBg: barBg
            }
        }
    }

    MediaPill {
        id: mediaPill
        bar: bar
        barBg: barBg
    }

    SysStatsPill {
        bar: bar
        barBg: barBg
        mediaActive: mediaPill.hasMedia
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
