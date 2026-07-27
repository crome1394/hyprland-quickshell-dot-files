import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io
import ".."

// =============================================================================
// RadarPill.qml — NWS radar viewer (bar pill + FloatingWindow)
// =============================================================================
//
// Data: scripts/radar-fetch.sh
//   - NOAA OpenGeo WMS radar (CREF / BREF)
//   - Esri World Topo basemap (scale-dependent city labels)
//   - Nominatim geocode for city/state & ZIP search
//
// Behavior:
//   - No background polling of radar frames
//   - Each fetch loads an *overscanned* region (Config.radarOverscan) so you can
//     pan a long way (e.g. Orrville → Chicago at regional zoom) without reloading
//   - Overscan is isotropic (same scale X/Y) so the buffer keeps the viewport
//     aspect ratio; QML Stretch then does not warp the map
//   - When pan/zoom settles, auto-refresh only if the viewport left the buffer
//     or zoom changed enough; otherwise keep the loaded image
//   - Manual Refresh always re-fetches
//   - Home restores Config default center/zoom
//
// IPC (shell.qml):
//   qs ipc call radar toggle | refresh | show | hide
//
// =============================================================================

Rectangle {
    id: root

    required property var bar

    Config { id: th }

    readonly property string fetchScript: Qt.resolvedUrl("../scripts/radar-fetch.sh").toString().replace("file://", "")
    readonly property real overscanRequest: th.radarOverscan || 3.0
    readonly property int settleMs: th.radarSettleMs || 420
    readonly property real zoomRefetchDelta: 0.28
    // Refetch when the viewport approaches this fraction of the loaded edge (0–0.5)
    readonly property real coverageEdgeMargin: 0.12

    property bool loading: false
    property bool searching: false
    property string errorMsg: ""
    property string statusMsg: ""
    property string imagePath: ""
    property int imageRev: 0  // cache-bust
    property string searchQuery: ""
    property string placeLabel: ""

    // Live view state (kept in sync from visual transform)
    property real centerLon: th.radarDefaultLon
    property real centerLat: th.radarDefaultLat
    property real zoom: th.radarDefaultZoom
    property string product: th.radarDefaultProduct || "cref"

    // Last successful fetch geography (defines the loaded image's geo extent)
    property real fetchedLon: th.radarDefaultLon
    property real fetchedLat: th.radarDefaultLat
    property real fetchedZoom: th.radarDefaultZoom
    property real viewWest: -89.3
    property real viewSouth: 37.2
    property real viewEast: -77.1
    property real viewNorth: 43.4
    // How many viewport-widths the loaded image spans (display size multiplier)
    property real coverageScale: 1.0
    property string radarTime: ""
    property string fetchedAt: ""

    // Visual offset of the frozen image while panning/zooming
    // Display size = mapSize * coverageScale * imageScale
    property real imageOffsetX: 0
    property real imageOffsetY: 0
    property real imageScale: 1.0

    /** Viewport moved/zoomed relative to the last fetch (may still be in buffer). */
    readonly property bool viewMoved: {
        const epsOff = 0.5
        return Math.abs(imageOffsetX) > epsOff
            || Math.abs(imageOffsetY) > epsOff
            || Math.abs(imageScale - 1.0) > 0.01
    }

    /** Needs a network reload (outside buffer or zoom change). */
    readonly property bool needsRefetch: {
        if (!imagePath)
            return true
        if (Math.abs(zoom - fetchedZoom) > zoomRefetchDelta)
            return true
        return !viewportInsideCoverage()
    }

    // Keep old name for UI (highlight Refresh when a reload will/would help)
    readonly property bool viewStale: viewMoved && needsRefetch

    readonly property string productLabel: product === "bref" ? "BREF" : "CREF"

    Layout.preferredWidth: Math.max(42, pillInner.implicitWidth + 16)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    radius: bar.pillRadius
    color: pillMouse.containsMouse || radarWindow.visible ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: (pillMouse.containsMouse || radarWindow.visible) ? bar.accent : bar.pillBorder

    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

    // ── Geometry: map pixel ↔ lon/lat using the *displayed* image transform ─
    //
    // Image is placed as:
    //   imgW = mapW * coverageScale * imageScale
    //   imgH = mapH * coverageScale * imageScale
    //   imgX = (mapW - imgW)/2 + imageOffsetX
    //   imgY = (mapH - imgH)/2 + imageOffsetY
    // coverageScale = overscan from last fetch (e.g. 3 → load 3× viewport).
    // imageScale = extra zoom since last fetch (1 = same zoom as fetch).
    // Image content maps to [viewWest..viewEast] × [viewNorth..viewSouth].

    function imageRect(mapW, mapH) {
        const s = Math.max(1e-6, coverageScale * imageScale)
        const imgW = mapW * s
        const imgH = mapH * s
        return {
            x: (mapW - imgW) / 2 + imageOffsetX,
            y: (mapH - imgH) / 2 + imageOffsetY,
            w: imgW,
            h: imgH
        }
    }

    function geoAtMapPixel(px, py, mapW, mapH) {
        const r = imageRect(mapW, mapH)
        if (r.w <= 0 || r.h <= 0)
            return { lon: centerLon, lat: centerLat }
        const u = (px - r.x) / r.w
        const v = (py - r.y) / r.h
        return {
            lon: viewWest + u * (viewEast - viewWest),
            lat: viewNorth - v * (viewNorth - viewSouth)
        }
    }

    /** Push centerLon/Lat/zoom from the current visual transform (map center). */
    function syncViewFromVisual() {
        const mapW = mapSurface.width
        const mapH = mapSurface.height
        if (mapW <= 1 || mapH <= 1)
            return
        const g = geoAtMapPixel(mapW / 2, mapH / 2, mapW, mapH)
        centerLon = Math.max(-180, Math.min(180, g.lon))
        centerLat = Math.max(-85, Math.min(85, g.lat))
        // imageScale is relative to last fetch zoom (coverageScale already baked into display)
        const z = fetchedZoom + Math.log(Math.max(1e-6, imageScale)) / Math.log(2)
        zoom = Math.max(3.0, Math.min(12.0, z))
    }

    /** True if the visible map rectangle stays inside the loaded image (with margin). */
    function viewportInsideCoverage() {
        const mapW = mapSurface.width
        const mapH = mapSurface.height
        if (mapW <= 1 || mapH <= 1 || !imagePath)
            return false
        const tl = geoAtMapPixel(0, 0, mapW, mapH)
        const br = geoAtMapPixel(mapW, mapH, mapW, mapH)
        const vWest = Math.min(tl.lon, br.lon)
        const vEast = Math.max(tl.lon, br.lon)
        const vNorth = Math.max(tl.lat, br.lat)
        const vSouth = Math.min(tl.lat, br.lat)
        const lonSpan = Math.max(1e-9, viewEast - viewWest)
        const latSpan = Math.max(1e-9, viewNorth - viewSouth)
        const mLon = coverageEdgeMargin * lonSpan
        const mLat = coverageEdgeMargin * latSpan
        return vWest >= viewWest + mLon
            && vEast <= viewEast - mLon
            && vSouth >= viewSouth + mLat
            && vNorth <= viewNorth - mLat
    }

    function scheduleSettleRefresh() {
        if (!radarWindow.visible || loading)
            return
        settleTimer.restart()
    }

    /** After pan/zoom settles: reload only if we left the buffer or zoomed. */
    function onViewSettled() {
        if (!radarWindow.visible || loading)
            return
        syncViewFromVisual()
        if (needsRefetch)
            refresh()
    }

    function toggle() {
        if (radarWindow.visible)
            hide()
        else
            show()
    }

    function show() {
        radarWindow.visible = true
        if (!imagePath)
            refresh()
    }

    function hide() {
        radarWindow.visible = false
    }

    function goHome() {
        centerLon = th.radarDefaultLon
        centerLat = th.radarDefaultLat
        zoom = th.radarDefaultZoom
        imageOffsetX = 0
        imageOffsetY = 0
        imageScale = 1.0
        placeLabel = ""
        // Align "fetched*" so sync doesn't fight Home before the image arrives
        fetchedLon = centerLon
        fetchedLat = centerLat
        fetchedZoom = zoom
        refresh()
    }

    function toggleProduct() {
        product = (product === "bref") ? "cref" : "bref"
        refresh()
    }

    function refresh() {
        settleTimer.stop()
        // Critical: derive center/zoom from what the user is *looking at*
        if (imagePath && viewMoved)
            syncViewFromVisual()

        if (fetchProcess.running)
            fetchProcess.running = false

        loading = true
        errorMsg = ""
        statusMsg = "Fetching…"

        const w = Math.max(320, Math.round(mapSurface.width || th.radarWidth - 28))
        const h = Math.max(240, Math.round(mapSurface.height || th.radarHeight - 120))

        fetchProcess.command = [
            fetchScript, "fetch",
            centerLon.toFixed(8),
            centerLat.toFixed(8),
            zoom.toFixed(6),
            String(w),
            String(h),
            String(product),
            overscanRequest.toFixed(3)
        ]
        fetchProcess.running = true
    }

    function panByPixels(dx, dy, mapW, mapH) {
        if (mapW <= 0 || mapH <= 0)
            return
        imageOffsetX += dx
        imageOffsetY += dy
        syncViewFromVisual()
    }

    function zoomAt(delta, mapW, mapH, anchorX, anchorY) {
        if (mapW <= 0 || mapH <= 0)
            return
        const oldScale = Math.max(1e-6, imageScale)
        const curZoom = fetchedZoom + Math.log(oldScale) / Math.log(2)
        const nextZoom = Math.max(3.0, Math.min(12.0, curZoom + delta))
        const nextScale = Math.pow(2, nextZoom - fetchedZoom)
        if (Math.abs(nextScale - oldScale) < 1e-6)
            return

        const g = geoAtMapPixel(anchorX, anchorY, mapW, mapH)

        imageScale = nextScale

        const u = (g.lon - viewWest) / Math.max(1e-12, (viewEast - viewWest))
        const v = (viewNorth - g.lat) / Math.max(1e-12, (viewNorth - viewSouth))
        const s = Math.max(1e-6, coverageScale * imageScale)
        const imgW = mapW * s
        const imgH = mapH * s
        const imgX = anchorX - u * imgW
        const imgY = anchorY - v * imgH
        imageOffsetX = imgX - (mapW - imgW) / 2
        imageOffsetY = imgY - (mapH - imgH) / 2

        syncViewFromVisual()
        scheduleSettleRefresh()
    }

    function centerOnPixelAndRefresh(px, py) {
        const mapW = mapSurface.width
        const mapH = mapSurface.height
        if (mapW <= 1 || mapH <= 1)
            return
        const g = geoAtMapPixel(px, py, mapW, mapH)
        syncViewFromVisual()
        centerLon = g.lon
        centerLat = g.lat
        imageOffsetX = 0
        imageOffsetY = 0
        imageScale = 1.0
        fetchedZoom = zoom
        fetchedLon = centerLon
        fetchedLat = centerLat
        refresh()
    }

    function applyFetchResult(j) {
        if (!j || j.ok === false) {
            errorMsg = (j && j.error) ? j.error : "fetch failed"
            statusMsg = ""
            loading = false
            return
        }
        imagePath = j.path || ""
        imageRev++
        fetchedLon = Number(j.center_lon)
        fetchedLat = Number(j.center_lat)
        fetchedZoom = Number(j.zoom)
        centerLon = fetchedLon
        centerLat = fetchedLat
        zoom = fetchedZoom
        viewWest = Number(j.west)
        viewSouth = Number(j.south)
        viewEast = Number(j.east)
        viewNorth = Number(j.north)
        coverageScale = Math.max(1.0, Number(j.overscan) || 1.0)
        product = j.product || product
        radarTime = j.radar_time || ""
        fetchedAt = j.fetched_at || ""
        imageOffsetX = 0
        imageOffsetY = 0
        imageScale = 1.0
        errorMsg = ""
        const cov = coverageScale.toFixed(1)
        statusMsg = (radarTime
            ? ("Radar " + radarTime.replace("T", " ").replace("Z", " UTC"))
            : ("Fetched " + (fetchedAt || "").replace("T", " ").replace("Z", " UTC")))
            + "  ·  " + cov + "× area"
        loading = false
    }

    function runSearch() {
        const q = (searchField.text || searchQuery || "").trim()
        if (!q) {
            errorMsg = "Enter a city, ST or ZIP"
            return
        }
        if (searchProcess.running)
            searchProcess.running = false
        searching = true
        errorMsg = ""
        statusMsg = "Searching…"
        searchQuery = q
        searchProcess.command = [fetchScript, "search", q]
        searchProcess.running = true
    }

    function applySearchResult(j) {
        searching = false
        if (!j || j.ok === false) {
            errorMsg = (j && j.error) ? j.error : "search failed"
            statusMsg = ""
            return
        }
        centerLon = Number(j.lon)
        centerLat = Number(j.lat)
        zoom = Number(j.zoom) || zoom
        placeLabel = j.display_name || j.query || ""
        imageOffsetX = 0
        imageOffsetY = 0
        imageScale = 1.0
        fetchedLon = centerLon
        fetchedLat = centerLat
        fetchedZoom = zoom
        statusMsg = placeLabel
        errorMsg = ""
        refresh()
    }

    // ── Pill face ───────────────────────────────────────────────────────────
    Row {
        id: pillInner
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰖐"
            color: bar.accent
            font.pixelSize: bar.iconSizePillLarge || 16
            font.family: bar.fontFamily
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Radar"
            color: bar.text
            font.pixelSize: bar.fontTiny || 11
            font.family: bar.fontMono
        }
    }

    MouseArea {
        id: pillMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
    }

    // Debounced auto-refresh after pan/zoom settles (only if outside buffer)
    Timer {
        id: settleTimer
        interval: root.settleMs
        repeat: false
        onTriggered: root.onViewSettled()
    }

    Io.Process {
        id: fetchProcess
        stdout: Io.StdioCollector {
            onStreamFinished: {
                const line = (text || "").trim()
                const lines = line.split("\n")
                let raw = ""
                for (let i = lines.length - 1; i >= 0; i--) {
                    if (lines[i].trim().startsWith("{")) {
                        raw = lines[i].trim()
                        break
                    }
                }
                if (!raw) {
                    root.errorMsg = "empty response from radar-fetch"
                    root.loading = false
                    return
                }
                try {
                    root.applyFetchResult(JSON.parse(raw))
                } catch (e) {
                    root.errorMsg = "bad JSON from radar-fetch"
                    root.loading = false
                }
            }
        }
        stderr: Io.StdioCollector { }
        onExited: (code) => {
            if (code !== 0 && root.loading) {
                if (!root.errorMsg)
                    root.errorMsg = "radar-fetch exited " + code
                root.loading = false
            }
        }
    }

    Io.Process {
        id: searchProcess
        stdout: Io.StdioCollector {
            onStreamFinished: {
                const line = (text || "").trim()
                const lines = line.split("\n")
                let raw = ""
                for (let i = lines.length - 1; i >= 0; i--) {
                    if (lines[i].trim().startsWith("{")) {
                        raw = lines[i].trim()
                        break
                    }
                }
                if (!raw) {
                    root.searching = false
                    root.errorMsg = "empty geocode response"
                    return
                }
                try {
                    root.applySearchResult(JSON.parse(raw))
                } catch (e) {
                    root.searching = false
                    root.errorMsg = "bad geocode JSON"
                }
            }
        }
        stderr: Io.StdioCollector { }
        onExited: (code) => {
            if (code !== 0 && root.searching) {
                if (!root.errorMsg)
                    root.errorMsg = "search failed (" + code + ")"
                root.searching = false
            }
        }
    }

    // ── Radar window ────────────────────────────────────────────────────────
    FloatingWindow {
        id: radarWindow
        visible: false
        title: "NWS Radar"
        color: "transparent"
        implicitWidth: th.radarWidth
        implicitHeight: th.radarHeight
        minimumSize: Qt.size(th.radarMinWidth, th.radarMinHeight)

        onClosed: root.hide()

        Shortcut {
            sequence: "Escape"
            enabled: radarWindow.visible && !searchField.activeFocus
            onActivated: root.hide()
        }
        Shortcut {
            sequence: "Ctrl+R"
            enabled: radarWindow.visible
            onActivated: root.refresh()
        }
        Shortcut {
            sequence: "R"
            enabled: radarWindow.visible && !searchField.activeFocus
            onActivated: root.refresh()
        }
        Shortcut {
            sequence: "H"
            enabled: radarWindow.visible && !searchField.activeFocus
            onActivated: root.goHome()
        }
        Shortcut {
            sequence: "P"
            enabled: radarWindow.visible && !searchField.activeFocus
            onActivated: root.toggleProduct()
        }
        Shortcut {
            sequence: "Ctrl+F"
            enabled: radarWindow.visible
            onActivated: searchField.forceActiveFocus()
        }
        Shortcut {
            sequence: "/"
            enabled: radarWindow.visible && !searchField.activeFocus
            onActivated: searchField.forceActiveFocus()
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: th.popupRadiusLarge || 12
            color: th.inspWindowBg || bar.glassPopupBg
            border.width: 1
            border.color: th.inspWindowBorder || bar.glassPopupBorder
            focus: radarWindow.visible

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight || 1
                color: th.inspWindowHighlight || bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "NWS Radar"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize || 16
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Rectangle {
                        radius: 6
                        color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.18)
                        border.width: 1
                        border.color: bar.accent
                        implicitHeight: 22
                        implicitWidth: productChipTxt.implicitWidth + 14
                        Text {
                            id: productChipTxt
                            anchors.centerIn: parent
                            text: root.productLabel
                            color: bar.accent
                            font.pixelSize: 11
                            font.family: bar.fontMono
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleProduct()
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Toggle CREF / BREF (P)"
                            ToolTip.delay: 400
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.loading || root.searching
                              ? (root.searching ? "Searching…" : "Loading…")
                              : (root.errorMsg || root.statusMsg)
                        color: root.errorMsg ? "#e06c75" : bar.subtext
                        font.pixelSize: 12
                        font.family: bar.fontMono
                        elide: Text.ElideRight
                        Layout.maximumWidth: 340
                    }

                    Rectangle {
                        radius: 6
                        implicitHeight: 28
                        implicitWidth: productBtnTxt.implicitWidth + 18
                        color: productBtnMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        Text {
                            id: productBtnTxt
                            anchors.centerIn: parent
                            text: "Product"
                            color: bar.text
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: productBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleProduct()
                        }
                    }

                    Rectangle {
                        radius: 6
                        implicitHeight: 28
                        implicitWidth: homeBtnTxt.implicitWidth + 18
                        color: homeBtnMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        Text {
                            id: homeBtnTxt
                            anchors.centerIn: parent
                            text: "Home"
                            color: bar.text
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: homeBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.goHome()
                        }
                    }

                    Rectangle {
                        radius: 6
                        implicitHeight: 28
                        implicitWidth: refreshBtnTxt.implicitWidth + 18
                        color: refreshBtnMa.containsMouse ? bar.iconHoverBg
                             : (root.viewStale ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.22) : "transparent")
                        border.width: 1
                        border.color: root.viewStale ? bar.accent : bar.pillBorder
                        Text {
                            id: refreshBtnTxt
                            anchors.centerIn: parent
                            text: root.loading ? "…" : "Refresh"
                            color: bar.text
                            font.pixelSize: 12
                            font.bold: root.viewStale
                        }
                        MouseArea {
                            id: refreshBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh()
                        }
                    }
                }

                // Search row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.22)
                        border.width: 1
                        border.color: searchField.activeFocus ? bar.accent : (bar.pillBorder || bar.divider)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: "⌕"
                                color: bar.subtext
                                font.pixelSize: 14
                            }
                            TextInput {
                                id: searchField
                                Layout.fillWidth: true
                                color: bar.text
                                font.pixelSize: 13
                                font.family: bar.fontFamily
                                clip: true
                                selectByMouse: true
                                selectedTextColor: bar.bg || "#111"
                                selectionColor: bar.accent
                                onAccepted: root.runSearch()
                                Keys.onEscapePressed: {
                                    focus = false
                                    event.accepted = true
                                }

                                Text {
                                    anchors.fill: parent
                                    visible: !searchField.text && !searchField.activeFocus
                                    text: "Search city, ST or ZIP…"
                                    color: bar.subtext
                                    font.pixelSize: 13
                                }
                            }
                        }
                    }

                    Rectangle {
                        radius: 6
                        implicitHeight: 32
                        implicitWidth: goBtnTxt.implicitWidth + 20
                        color: goBtnMa.containsMouse ? bar.iconHoverBg
                             : Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.2)
                        border.width: 1
                        border.color: bar.accent
                        Text {
                            id: goBtnTxt
                            anchors.centerIn: parent
                            text: root.searching ? "…" : "Go"
                            color: bar.text
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea {
                            id: goBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runSearch()
                        }
                    }
                }

                // Status / coords row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "Center  " + root.centerLat.toFixed(3) + ", " + root.centerLon.toFixed(3)
                              + "   ·   zoom " + root.zoom.toFixed(2)
                              + (root.placeLabel ? ("   ·   " + root.placeLabel) : "")
                        color: bar.subtext
                        font.pixelSize: 11
                        font.family: bar.fontMono
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: root.viewMoved && !root.loading
                        text: root.needsRefetch
                              ? "Leaving buffer — reloading…"
                              : ("Panning in " + root.coverageScale.toFixed(1) + "× buffer")
                        color: root.needsRefetch ? bar.accent : bar.subtext
                        font.pixelSize: 11
                        font.family: bar.fontMono
                    }

                    Text {
                        text: "drag · wheel · auto-reload at edge · / search · R force"
                        color: bar.subtext
                        font.pixelSize: 10
                        font.family: bar.fontMono
                        opacity: 0.75
                    }
                }

                // Map surface
                Rectangle {
                    id: mapSurface
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: "#1a1d21"
                    border.width: 1
                    border.color: bar.pillBorder || bar.divider
                    clip: true

                    Image {
                        id: radarImage
                        // coverageScale = isotropic overscan (same on X/Y from fetch).
                        // imageScale = extra zoom since last fetch. Stretch is safe
                        // because radar-fetch keeps image aspect == viewport aspect.
                        width: parent.width * root.coverageScale * root.imageScale
                        height: parent.height * root.coverageScale * root.imageScale
                        x: (parent.width - width) / 2 + root.imageOffsetX
                        y: (parent.height - height) / 2 + root.imageOffsetY
                        fillMode: Image.Stretch
                        asynchronous: true
                        cache: false
                        source: root.imagePath
                                 ? ("file://" + root.imagePath + "?r=" + root.imageRev)
                                 : ""
                        opacity: root.loading ? 0.55 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.imagePath && !root.loading
                        text: root.errorMsg || "Open and press Refresh"
                        color: bar.subtext
                        font.pixelSize: 13
                        font.family: bar.fontFamily
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: root.loading || root.searching
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.55)
                        implicitWidth: loadTxt.implicitWidth + 24
                        implicitHeight: loadTxt.implicitHeight + 14
                        Text {
                            id: loadTxt
                            anchors.centerIn: parent
                            text: root.searching ? "Searching…" : "Loading radar…"
                            color: bar.text
                            font.pixelSize: 13
                            font.family: bar.fontFamily
                        }
                    }

                    MouseArea {
                        id: mapMouse
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        hoverEnabled: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property real lastX: 0
                        property real lastY: 0

                        onPressed: function(mouse) {
                            lastX = mouse.x
                            lastY = mouse.y
                            searchField.focus = false
                            settleTimer.stop()
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed)
                                return
                            const dx = mouse.x - lastX
                            const dy = mouse.y - lastY
                            lastX = mouse.x
                            lastY = mouse.y
                            root.panByPixels(dx, dy, mapSurface.width, mapSurface.height)
                        }
                        onReleased: function(mouse) {
                            root.scheduleSettleRefresh()
                        }
                        onCanceled: root.scheduleSettleRefresh()
                        onDoubleClicked: function(mouse) {
                            settleTimer.stop()
                            root.centerOnPixelAndRefresh(mouse.x, mouse.y)
                        }
                        onWheel: function(wheel) {
                            const steps = wheel.angleDelta.y / 120.0
                            if (steps === 0)
                                return
                            root.zoomAt(steps * 0.35, mapSurface.width, mapSurface.height, wheel.x, wheel.y)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Radar © NWS / NOAA OpenGeo   ·   Basemap © Esri World Street Map   ·   Search © OSM Nominatim   ·   No auto-refresh"
                    color: bar.subtext
                    font.pixelSize: 10
                    font.family: bar.fontMono
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }
        }
    }

}
