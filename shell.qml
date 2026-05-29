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



    // (Media logic has been moved into widgets/MediaPill.qml)



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
