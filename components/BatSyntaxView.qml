import QtQuick
import QtQuick.Controls
import Quickshell.Io as Io

// Renders a file with syntax highlighting via the `bat` CLI (ANSI → HTML Text).
Item {
    id: root

    property string filePath: ""
    property string language: ""
    property string filterText: ""
    property int fontSize: 12
    property string fontFamily: "monospace"
    property color defaultColor: "#cdd6f4"
    property color accentColor: defaultColor

    property string _ansiText: ""
    property string _htmlText: ""
    property int displayLineCount: 1
    property int displayVersion: 0
    property real contentWidthEstimate: 320
    readonly property real charWidthPx: fontSize * 0.62
    readonly property real lineHeightPx: fontSize * 1.35
    readonly property real scrollContentHeight: Math.max(24, displayLineCount * lineHeightPx + 24)
    readonly property real contentSidePadding: 24
    property bool _loading: false
    property bool _loadHandled: false
    property bool _refreshPending: false
    property bool _needsRefresh: false
    property var onUnhandledKey: null

    function batLanguageForPath(path) {
        if (!path) return "Lua"
        if (path.endsWith(".lua")) return "Lua"
        if (path.endsWith(".conf")) {
            const name = path.substring(path.lastIndexOf("/") + 1)
            if (name === "hyprlock.conf") return "Java Properties"
            return "INI"
        }
        return ""
    }

    function resolvedLanguage() {
        if (language && language.length > 0) return language
        return batLanguageForPath(filePath)
    }

    function refresh() {
        if (!filePath || filePath.length === 0) {
            return
        }
        if (_loading) {
            _needsRefresh = true
            return
        }
        if (_refreshPending) {
            _needsRefresh = true
            return
        }
        _refreshPending = true
        Qt.callLater(runRefresh)
    }

    function runRefresh() {
        _refreshPending = false
        if (!filePath || filePath.length === 0) {
            return
        }
        if (_loading) {
            _needsRefresh = true
            return
        }
        _loading = true
        _loadHandled = false
        const cmd = [
            "bat",
            "--color", "always",
            "--decorations", "never",
            "--plain",
            "--paging=never"
        ]
        const lang = resolvedLanguage()
        if (lang.length > 0) {
            cmd.push("--language", lang)
        }
        cmd.push(filePath)
        batProcess.running = false
        batProcess.command = cmd
        batProcess.running = true
    }

    function escapeHtml(text) {
        return text
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
    }

    function colorToHex(color) {
        if (typeof color === "string") return color
        function hex(channel) {
            const value = Math.round(channel * 255).toString(16)
            return value.length === 1 ? "0" + value : value
        }
        return "#" + hex(color.r) + hex(color.g) + hex(color.b)
    }

    function rgbHex(r, g, b) {
        function hex(n) {
            const s = Math.round(n).toString(16)
            return s.length === 1 ? "0" + s : s
        }
        return "#" + hex(r) + hex(g) + hex(b)
    }

    function ansi16(code) {
        const palette = {
            30: "#1e1e2e", 31: "#f38ba8", 32: "#a6e3a1", 33: "#f9e2af",
            34: "#89b4fa", 35: "#cba6f7", 36: "#94e2de", 37: "#cdd6f4",
            90: "#6c7086", 91: "#f38ba8", 92: "#a6e3a1", 93: "#f9e2af",
            94: "#89b4fa", 95: "#cba6f7", 96: "#94e2de", 97: "#ffffff"
        }
        return palette[code] || null
    }

    function ansi256(code) {
        if (code < 16) return ansi16(code)
        if (code >= 232) {
            const gray = (code - 232) * 10 + 8
            return rgbHex(gray, gray, gray)
        }
        const cc = code - 16
        const r = Math.floor(cc / 36)
        const g = Math.floor(cc / 6) % 6
        const b = cc % 6
        const levels = [0, 95, 135, 175, 215, 255]
        return rgbHex(levels[r], levels[g], levels[b])
    }

    function applyAnsiCode(parts, state) {
        const next = {
            fg: state.fg,
            bold: state.bold
        }
        for (let i = 0; i < parts.length; i++) {
            const p = parts[i]
            if (p === 0 || p === "") {
                next.fg = colorToHex(defaultColor)
                next.bold = false
            } else if (p === 1) {
                next.bold = true
            } else if (p === 22) {
                next.bold = false
            } else if (p === 39) {
                next.fg = colorToHex(defaultColor)
            } else if (p >= 30 && p <= 37) {
                next.fg = ansi16(p)
            } else if (p >= 90 && p <= 97) {
                next.fg = ansi16(p)
            } else if (p === 38 && parts[i + 1] === 2 && i + 4 < parts.length) {
                next.fg = rgbHex(parts[i + 2], parts[i + 3], parts[i + 4])
                i += 4
            } else if (p === 38 && parts[i + 1] === 5 && i + 2 < parts.length) {
                next.fg = ansi256(parts[i + 2])
                i += 2
            }
        }
        return next
    }

    function ansiToHtml(text) {
        if (!text) return ""
        const defaultHex = colorToHex(defaultColor)
        const lines = text.split("\n")
        const htmlLines = []

        for (let li = 0; li < lines.length; li++) {
            const line = lines[li]
            let state = { fg: defaultHex, bold: false }
            let html = ""
            let i = 0

            while (i < line.length) {
                if (line.charCodeAt(i) === 27 && line[i + 1] === "[") {
                    let j = i + 2
                    while (j < line.length && line[j] !== "m") j++
                    const codes = line.substring(i + 2, j).split(";").map(function(v) {
                        const n = parseInt(v, 10)
                        return isNaN(n) ? v : n
                    })
                    state = applyAnsiCode(codes, state)
                    i = j + 1
                    continue
                }

                let j = i
                while (j < line.length) {
                    if (line.charCodeAt(j) === 27 && line[j + 1] === "[") break
                    j++
                }

                if (j > i) {
                    const chunk = escapeHtml(line.substring(i, j))
                    const weight = state.bold ? "font-weight:700;" : ""
                    html += '<span style="color:' + state.fg + ";" + weight + '">' + chunk + "</span>"
                }
                i = j
            }

            htmlLines.push(html.length ? html : "&nbsp;")
        }

        return '<pre style="margin:0;font-family:' + fontFamily + ";font-size:" + fontSize
            + "px;color:" + defaultHex + '">' + htmlLines.join("<br/>") + "</pre>"
    }

    function stripAnsi(text) {
        return text.replace(/\x1b\[[0-9;]*m/g, "")
    }

    function filteredAnsiSource() {
        if (!filterText || !filterText.trim()) {
            return _ansiText
        }
        const q = filterText.toLowerCase().trim()
        return _ansiText.split("\n").filter(function(line) {
            return stripAnsi(line).toLowerCase().indexOf(q) !== -1
        }).join("\n")
    }

    function plainText() {
        return stripAnsi(filteredAnsiSource())
    }

    function longestLineCharCount(text) {
        const lines = (text || "").split("\n")
        let maxLen = 0
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].length > maxLen) maxLen = lines[i].length
        }
        return maxLen
    }

    function estimatedContentWidth() {
        const chars = longestLineCharCount(stripAnsi(filteredAnsiSource()))
        return Math.max(320, Math.ceil(chars * charWidthPx) + contentSidePadding)
    }

    function rebuildDisplay() {
        const src = filteredAnsiSource()
        const plain = stripAnsi(src)
        displayLineCount = plain ? Math.max(1, plain.split("\n").length) : 1
        _htmlText = ansiToHtml(src)
        contentWidthEstimate = estimatedContentWidth()
        displayVersion++
    }

    function scrollFlickable() {
        return contentFlickable
    }

    function focusScroll() {
        contentFlickable.forceActiveFocus()
    }

    function resetScroll() {
        contentFlickable.contentX = 0
        contentFlickable.contentY = 0
    }

    function forceLayoutRefresh() {
        contentWidthEstimate = estimatedContentWidth()
        displayVersion++
        Qt.callLater(function() {
            resetScroll()
            contentFlickable.returnToBounds()
        })
    }

    function scrollableMaxY() {
        return Math.max(0, contentFlickable.contentHeight - contentFlickable.height)
    }

    function scrollableMaxX() {
        return Math.max(0, contentFlickable.contentWidth - contentFlickable.width)
    }

    function clampContentY(y) {
        return Math.max(0, Math.min(scrollableMaxY(), y))
    }

    function clampContentX(x) {
        return Math.max(0, Math.min(scrollableMaxX(), x))
    }

    function pageScroll(direction) {
        const maxY = scrollableMaxY()
        if (maxY <= 0) return
        const page = Math.max(80, contentFlickable.height * 0.85)
        contentFlickable.contentY = clampContentY(contentFlickable.contentY + direction * page)
    }

    function lineScroll(direction) {
        const maxY = scrollableMaxY()
        if (maxY <= 0) return
        const step = Math.max(lineHeightPx * 2, 24)
        contentFlickable.contentY = clampContentY(contentFlickable.contentY + direction * step)
    }

    function wheelScroll(deltaY) {
        const maxY = scrollableMaxY()
        if (maxY <= 0) return
        const step = Math.max(lineHeightPx * 3, 40)
        const ticks = deltaY / 120
        contentFlickable.contentY = clampContentY(contentFlickable.contentY - ticks * step)
    }

    function handleScrollKey(event) {
        if (event.key === Qt.Key_PageUp) {
            pageScroll(-1)
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_PageDown) {
            pageScroll(1)
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_Up) {
            lineScroll(-1)
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_Down) {
            lineScroll(1)
            event.accepted = true
            return true
        }
        return false
    }

    function finishBatLoad() {
        if (!_loading || _loadHandled) {
            return
        }
        _loadHandled = true
        _loading = false
        _ansiText = batStdout.text || ""
        rebuildDisplay()
        Qt.callLater(function() {
            forceLayoutRefresh()
            if (root.visible) focusScroll()
        })
        if (_needsRefresh) {
            _needsRefresh = false
            refresh()
        }
    }

    onFilePathChanged: {
        resetScroll()
        refresh()
    }
    onFilterTextChanged: rebuildDisplay()
    onDefaultColorChanged: rebuildDisplay()
    onVisibleChanged: {
        if (visible && _ansiText) Qt.callLater(forceLayoutRefresh)
    }
    onHeightChanged: {
        if (height > 0 && _ansiText.length > 0) Qt.callLater(contentFlickable.returnToBounds)
    }

    Io.Process {
        id: batProcess
        running: false
        stdout: Io.StdioCollector {
            id: batStdout
            onStreamFinished: root.finishBatLoad()
        }
        onExited: root.finishBatLoad()
    }

    Flickable {
        id: contentFlickable
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: true
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        focus: true
        activeFocusOnTab: true
        Keys.enabled: true

        property int _layoutTick: root.displayVersion

        contentWidth: Math.max(width, root.contentWidthEstimate)
        contentHeight: root.scrollContentHeight

        Keys.onPressed: function(event) {
            if (root.handleScrollKey(event)) return
            if (root.onUnhandledKey) root.onUnhandledKey(event)
        }

        WheelHandler {
            onWheel: function(event) {
                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                if (delta === 0) return
                root.wheelScroll(delta)
                event.accepted = true
            }
        }

        ScrollBar.vertical: ScrollBar {
            id: contentScrollBar
            policy: contentFlickable.contentHeight > contentFlickable.height + 1
                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: contentScrollBar.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
            }
        }

        ScrollBar.horizontal: ScrollBar {
            id: contentHScrollBar
            policy: contentFlickable.contentWidth > contentFlickable.width + 1
                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            contentItem: Rectangle {
                implicitHeight: 6
                radius: 3
                color: contentHScrollBar.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
            }
        }

        Item {
            id: scrollContent
            property int _layoutTick: root.displayVersion
            width: contentFlickable.contentWidth
            height: contentFlickable.contentHeight

            Text {
                id: syntaxText
                anchors.fill: parent
                anchors.margins: 12
                text: root._htmlText
                textFormat: Text.RichText
                color: root.defaultColor
                font.pixelSize: root.fontSize
                font.family: root.fontFamily
                wrapMode: Text.NoWrap
                lineHeight: 1.35
                lineHeightMode: Text.ProportionalHeight
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root._loading
        text: "Loading…"
        color: root.defaultColor
        font.pixelSize: root.fontSize
    }
}