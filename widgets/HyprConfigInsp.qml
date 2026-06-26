import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io as Io

// =============================================================================
// HyprConfigInsp.qml — Hyprland Config Inspector
// =============================================================================
//
// Floating overlay for browsing and editing split Hyprland configuration.
//
// Features:
//   - Parsed tabs: Key Bindings, Environment, Runtime Options (hyprctl getoption)
//   - Bat-syntax tabs for ~/.config/hypr/config/*.lua and hypr*.conf files
//   - System info (fastfetch + clickable copy-to-clipboard values + logo)
//   - Edit (kitty nano) and Reload per config file tab
//   - Header: Hyprland version + distro; Refresh All; wrapping tab bar
//   - Global search, tab scrollbar, PgUp/PgDown content scroll
//   - Resizable FloatingWindow (title: "Hyprland Config Inspector")
// =============================================================================

import ".."
import "../components"

Item {
    id: root

    required property var bar

    Theme { id: th }

    readonly property color glassPopupBg: th.glassPopupBg
    readonly property color glassPopupBorder: th.glassPopupBorder
    readonly property color glassPopupHighlight: th.glassPopupHighlight
    readonly property color text: th.text
    readonly property color subtext: th.subtext
    readonly property color overlay: th.overlay
    readonly property color accent: th.accent
    readonly property color surface: th.surface

    readonly property int popupRadiusLarge: th.popupRadiusLarge || 16
    readonly property int popupHelpWidth: th.popupHelpWidth || 1060
    readonly property int popupHelpHeight: th.popupHelpHeight || 720
    readonly property int tabBarMaxHeight: 102

    readonly property string configDir: "/home/crome/.config/hypr/config"
    readonly property string hyprDir: "/home/crome/.config/hypr"

    readonly property var tabs: [
        { label: "Key Bindings", id: "keybindings", file: "keybindings.lua", view: "binds" },
        { label: "Environment", id: "environment", file: "environment-variables.lua", view: "env" },
        { label: "Runtime Options", id: "runtime-options", file: "", view: "runtime" },
        { label: "Monitors", id: "monitors", file: "monitors.lua", view: "raw" },
        { label: "My Programs", id: "my-programs", file: "my-programs.lua", view: "raw" },
        { label: "Autostarts", id: "autostarts", file: "autostarts.lua", view: "raw" },
        { label: "Permissions", id: "permissions", file: "permissions.lua", view: "raw" },
        { label: "Look & Feel", id: "look-and-feel", file: "look-and-feel.lua", view: "raw" },
        { label: "Misc", id: "misc", file: "misc.lua", view: "raw" },
        { label: "Input", id: "input", file: "input.lua", view: "raw" },
        { label: "Window & Layer Rules", id: "windows-and-workspaces", file: "windows-and-workspaces.lua", view: "raw" },
        { label: "Hypridle", id: "hypridle", file: "hypridle.conf", view: "raw", dir: "/home/crome/.config/hypr", batLanguage: "INI" },
        { label: "Hyprlock", id: "hyprlock", file: "hyprlock.conf", view: "raw", dir: "/home/crome/.config/hypr", batLanguage: "Java Properties" },
        { label: "Hyprpaper", id: "hyprpaper", file: "hyprpaper.conf", view: "raw", dir: "/home/crome/.config/hypr", batLanguage: "INI" },
        { label: "System Info", id: "system", file: "", view: "system" }
    ]

    readonly property var currentTabInfo: (currentTab >= 0 && currentTab < tabs.length) ? tabs[currentTab] : tabs[0]
    readonly property bool hasConfigFile: currentTabInfo.file && currentTabInfo.file.length > 0
    property string rawSource: ""
    property string batFilePath: ""
    property string batLanguage: ""

    function syncRawSource() {
        const id = currentTabInfo.id
        rawSource = (id && fileContents[id]) ? fileContents[id] : ""
    }

    property int inspectorWidth: popupHelpWidth || 1060
    property int inspectorHeight: popupHelpHeight || 720

    property bool open: inspectorWindow.visible
    signal opened()
    signal closed()

    function toggle() {
        if (inspectorWindow.visible) hide()
        else show()
    }

    property int currentTab: 0
    onCurrentTabChanged: syncRawSource()
    property string globalFilter: ""

    property var fileContents: ({})
    property int fileContentsVersion: 0
    property var fileMtimes: ({})
    property int fileMtimesVersion: 0
    property string _pendingMtimeId: ""
    property var _parsedBinds: []
    property var _parsedEnv: []

    property string systemOutput: ""
    property bool systemDirty: true
    property var systemEntries: []
    property string copiedValue: ""

    property string wmDistroLabel: ""

    property bool _loading: false
    property bool _loadHandled: false
    property bool _singleLoadPending: false
    property string _pendingFileId: ""
    property string _pendingFileView: ""

    function tabPath(tab) {
        if (!tab || !tab.file) return ""
        const base = tab.dir || configDir
        return base + "/" + tab.file
    }

    function setFileContent(id, text) {
        const copy = Object.assign({}, fileContents)
        copy[id] = text
        fileContents = copy
        fileContentsVersion++
    }

    function setFileMtime(id, epoch) {
        const copy = Object.assign({}, fileMtimes)
        copy[id] = epoch
        fileMtimes = copy
        fileMtimesVersion++
    }

    function formatFileMtime(id) {
        const epoch = fileMtimes[id]
        if (!epoch) return ""
        const seconds = parseInt(epoch, 10)
        if (!seconds || isNaN(seconds)) return ""
        const d = new Date(seconds * 1000)
        if (isNaN(d.getTime())) return ""
        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        const pad = function(n) { return n < 10 ? "0" + n : "" + n }
        return "modified " + months[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
            + " " + pad(d.getHours()) + ":" + pad(d.getMinutes())
    }

    function mtimeSuffix(tab) {
        const formatted = formatFileMtime(tab.id)
        return formatted ? "  ·  " + formatted : ""
    }

    function refreshFileMtime(tab) {
        if (!tab || !tab.file) return
        _pendingMtimeId = tab.id
        statProcess.running = false
        statProcess.command = ["stat", "-c", "%Y", tabPath(tab)]
        statProcess.running = true
    }

    function applyLoadedFile(id, view, text) {
        const body = text || ""
        setFileContent(id, body)
        if (view === "binds") _parsedBinds = parseKeybinds(body)
        else if (view === "env") _parsedEnv = parseEnvVars(body)
        if (currentTabInfo.id === id) syncRawSource()
    }

    function parseAllFileOutput(text) {
        if (!text) return
        let searchFrom = 0
        while (searchFrom < text.length) {
            const fileAt = text.indexOf("@@FILE:", searchFrom)
            const mtimeAt = text.indexOf("@@MTIME:", searchFrom)
            if (fileAt === -1 && mtimeAt === -1) break

            let marker = "@@FILE:"
            let markerAt = fileAt
            if (mtimeAt !== -1 && (fileAt === -1 || mtimeAt < fileAt)) {
                marker = "@@MTIME:"
                markerAt = mtimeAt
            }

            const idStart = markerAt + marker.length
            const idEnd = text.indexOf("@@", idStart)
            if (idEnd === -1) break
            const id = text.substring(idStart, idEnd)
            let bodyStart = idEnd + 2
            if (text[bodyStart] === "\n") bodyStart++

            const nextFile = text.indexOf("@@FILE:", bodyStart)
            const nextMtime = text.indexOf("@@MTIME:", bodyStart)
            let bodyEnd = text.length
            if (nextFile !== -1) bodyEnd = Math.min(bodyEnd, nextFile)
            if (nextMtime !== -1) bodyEnd = Math.min(bodyEnd, nextMtime)

            const body = text.substring(bodyStart, bodyEnd)
            if (marker === "@@MTIME:") {
                setFileMtime(id, body.trim())
            } else {
                const tab = tabs.find(function(t) { return t.id === id })
                if (tab) applyLoadedFile(id, tab.view, body)
            }
            searchFrom = bodyEnd
        }
    }

    function finishFileLoad() {
        if (!_loading || _loadHandled) return
        _loadHandled = true
        const body = fileStdout.text || ""
        if (_singleLoadPending && _pendingFileId) {
            applyLoadedFile(_pendingFileId, _pendingFileView, body)
        } else {
            parseAllFileOutput(body)
        }
        _loading = false
        _singleLoadPending = false
        _pendingFileId = ""
        _pendingFileView = ""
        syncRawSource()
    }

    function startFileLoad(command, single, fileId, fileView) {
        _loading = true
        _loadHandled = false
        _singleLoadPending = single
        _pendingFileId = fileId || ""
        _pendingFileView = fileView || ""
        fileCat.running = false
        fileCat.command = command
        fileCat.running = true
    }

    function refreshAllFiles() {
        const parts = []
        for (let i = 0; i < tabs.length; i++) {
            const tab = tabs[i]
            if (tab.view === "system") continue
            const path = tabPath(tab)
            const escaped = path.replace(/'/g, "'\\''")
            parts.push("printf '@@MTIME:" + tab.id + "@@\\n'")
            parts.push("stat -c '%Y' '" + escaped + "' 2>/dev/null || echo 0")
            parts.push("printf '@@FILE:" + tab.id + "@@\\n'")
            parts.push("cat '" + escaped + "'")
        }
        if (!parts.length) return
        startFileLoad(["sh", "-c", parts.join(" && ")], false, "", "")
    }

    function parseHeaderInfo(text) {
        if (!text) return ""
        const marker = "---OS---"
        const splitAt = text.indexOf(marker)
        const hyprLine = (splitAt === -1 ? text : text.substring(0, splitAt)).trim().split("\n")[0] || ""
        const osBlock = splitAt === -1 ? "" : text.substring(splitAt + marker.length)

        let wm = "Hyprland"
        const wmMatch = hyprLine.match(/Hyprland\s+([\d.]+)/i)
        if (wmMatch) wm = "Hyprland " + wmMatch[1]

        let distro = ""
        const prettyMatch = osBlock.match(/PRETTY_NAME="?([^"\n]+)"?/)
        if (prettyMatch) distro = prettyMatch[1]
        else {
            const nameMatch = osBlock.match(/NAME="?([^"\n]+)"?/)
            if (nameMatch) distro = nameMatch[1].replace(/ Linux$/i, "")
        }

        if (wm && distro) return wm + " \u2022 " + distro
        return wm || distro || ""
    }

    function refreshHeaderInfo() {
        headerProcess.running = false
        headerProcess.running = true
    }

    function refreshAll() {
        refreshHeaderInfo()
        refreshAllFiles()
        const tab = currentTabInfo
        if (tab && tab.view === "raw" && tab.file) {
            batViewer.refresh()
        }
        if (tab && tab.view === "system") {
            refreshSystemInfo()
        } else {
            systemDirty = true
        }
        if (tab && tab.view === "runtime") {
            runtimeViewer.refresh()
        }
    }

    function refreshCurrentTab() {
        const tab = currentTabInfo
        if (!tab) return
        if (tab.view === "system") {
            refreshSystemInfo()
            return
        }
        if (tab.view === "runtime") {
            runtimeViewer.refresh()
            return
        }
        refreshFileMtime(tab)
        if (tab.view === "raw") {
            batViewer.refresh()
            startFileLoad(["cat", tabPath(tab)], true, tab.id, tab.view)
            return
        }
        startFileLoad(["cat", tabPath(tab)], true, tab.id, tab.view)
    }

    function editCurrentConfigFile() {
        const tab = currentTabInfo
        if (!tab || !tab.file) return
        Quickshell.execDetached(["kitty", "-e", "nano", tabPath(tab)])
    }

    function statusText() {
        const tab = currentTabInfo
        if (!tab) return ""
        const modified = mtimeSuffix(tab)
        const filterNote = (globalFilter && globalFilter.trim()) ? "  ·  filtered" : ""
        if (tab.view === "binds") return filteredBinds().length + " bindings  ·  " + tab.file + modified + filterNote
        if (tab.view === "env") return filteredEnv().length + " environment variables  ·  " + tab.file + modified + filterNote
        if (tab.view === "raw") {
            const body = rawSource || fileContents[tab.id] || ""
            const lines = body.length ? body.split("\n").length : 0
            const chars = body.length
            return lines + " lines (" + chars + " chars)  ·  " + tab.file + "  ·  bat" + modified + filterNote
        }
        if (tab.view === "system") return filteredSystemEntries().length + " entries  ·  system info" + filterNote
        if (tab.view === "runtime") {
            const cat = runtimeViewer.currentCategory()
            const name = cat ? cat.label : "category"
            return runtimeViewer.filteredOptions().length + " options  ·  " + name + "  ·  live" + filterNote
        }
        return ""
    }

    function scrollTabIntoView() {
        if (!tabFlickable || !tabFlow || currentTab < 0 || currentTab >= tabs.length) return
        if (currentTab >= tabFlow.children.length) return
        const chip = tabFlow.children[currentTab]
        if (!chip || chip.y === undefined) return
        const top = chip.y
        const bottom = top + chip.height
        if (top < tabFlickable.contentY) {
            tabFlickable.contentY = top
        } else if (bottom > tabFlickable.contentY + tabFlickable.height) {
            tabFlickable.contentY = Math.max(0, bottom - tabFlickable.height)
        }
    }

    function activateTab(index) {
        if (index < 0 || index >= tabs.length) return
        currentTab = index
        const tab = tabs[index]
        batLanguage = (tab.view === "raw" && tab.batLanguage) ? tab.batLanguage : ""
        batFilePath = (tab.view === "raw" && tab.file) ? tabPath(tab) : ""
        syncRawSource()
        if (tab.view === "system" && systemDirty) {
            refreshSystemInfo()
        } else if (tab.view === "runtime") {
            runtimeViewer.ensureLoaded()
        } else if (tab.file && !fileContents[tab.id]) {
            refreshCurrentTab()
        }
        scrollTabIntoView()
        Qt.callLater(function() { contentPanel.forceActiveFocus() })
    }

    function nextTab() {
        activateTab((currentTab + 1) % tabs.length)
    }

    function prevTab() {
        activateTab((currentTab - 1 + tabs.length) % tabs.length)
    }

    function show() {
        inspectorWindow.visible = true
        const tab = currentTabInfo
        batLanguage = (tab.view === "raw" && tab.batLanguage) ? tab.batLanguage : ""
        batFilePath = (tab.view === "raw" && tab.file) ? tabPath(tab) : ""
        if (!wmDistroLabel) refreshHeaderInfo()
        if (tab.view === "system" && systemDirty) refreshSystemInfo()
        else if (tab.view === "runtime") runtimeViewer.ensureLoaded()
        Qt.callLater(function() {
            scrollTabIntoView()
            contentPanel.forceActiveFocus()
        })
    }

    function hide() {
        inspectorWindow.visible = false
    }

    Io.Process {
        id: fileCat
        running: false
        stdout: Io.StdioCollector {
            id: fileStdout
            onStreamFinished: finishFileLoad()
        }
        onExited: finishFileLoad()
    }

    Io.Process {
        id: statProcess
        running: false
        stdout: Io.StdioCollector {
            id: statStdout
            onStreamFinished: {
                if (root._pendingMtimeId) {
                    root.setFileMtime(root._pendingMtimeId, (statStdout.text || "").trim())
                    root._pendingMtimeId = ""
                }
            }
        }
        onExited: {
            if (root._pendingMtimeId) {
                root.setFileMtime(root._pendingMtimeId, (statStdout.text || "").trim())
                root._pendingMtimeId = ""
            }
        }
    }

    Component.onCompleted: {
        refreshHeaderInfo()
        refreshAllFiles()
        syncRawSource()
    }

    Io.Process {
        id: headerProcess
        command: ["sh", "-c", "hyprctl version 2>/dev/null | head -1; printf '\\n---OS---\\n'; rg '^PRETTY_NAME=' /etc/os-release 2>/dev/null || grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null || true"]
        running: false
        stdout: Io.StdioCollector {
            id: headerStdout
            onStreamFinished: {
                const label = root.parseHeaderInfo(headerStdout.text || "")
                if (label) root.wmDistroLabel = label
            }
        }
        onExited: {
            const label = root.parseHeaderInfo(headerStdout.text || "")
            if (label) root.wmDistroLabel = label
        }
    }

    function parseKeybinds(text) {
        if (!text) return []
        const lines = text.split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const originalLine = lines[i]
            let line = originalLine.trim()
            if (!line.includes("hl.bind(")) continue
            if (line.startsWith("--hl.bind") || line.startsWith("----hl.bind")) continue
            if (!originalLine.includes("--#")) continue

            const bindIdx = line.indexOf("hl.bind(")
            if (bindIdx === -1) continue
            const afterOpen = line.substring(bindIdx + 8)
            let depth = 0
            let keyEnd = -1
            for (let j = 0; j < afterOpen.length; j++) {
                const ch = afterOpen[j]
                if (ch === '(' || ch === '{' || ch === '[') depth++
                else if (ch === ')' || ch === '}' || ch === ']') depth--
                else if (ch === ',' && depth === 0) {
                    keyEnd = j
                    break
                }
            }
            if (keyEnd === -1) continue
            let keyExpr = afterOpen.substring(0, keyEnd).trim()
            keyExpr = keyExpr.replace(/mainMod\s*\.\.\s*/g, "SUPER + ")
            keyExpr = keyExpr.replace(/["']/g, "")
            keyExpr = keyExpr.replace(/\s*\+\s*/g, " + ")
            keyExpr = keyExpr.replace(/\+\s*\+\s*/g, "+ ")
            keyExpr = keyExpr.replace(/\s+/g, " ").trim()

            let description = ""
            const descMatch = originalLine.match(/--#\s*(.+)$/)
            if (descMatch) description = descMatch[1].trim()

            out.push({ key: keyExpr, action: description, comment: "" })
        }
        return out
    }

    function parseEnvVars(text) {
        if (!text) return []
        const lines = text.split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const originalLine = lines[i]
            let line = originalLine.trim()
            if (!line.includes("hl.env(")) continue
            if (line.startsWith("--hl.env") || line.startsWith("----hl.env")) continue
            const m = line.match(/^hl\.env\(\s*["']([^"']+)["']\s*,\s*(.+?)\s*\)/)
            if (!m) continue
            let value = m[2].trim()
            const quoted = value.match(/^["']([^"']*)["']$/)
            if (quoted) value = quoted[1]
            let comment = ""
            const hashMatch = originalLine.match(/--#\s*(.+)$/)
            if (hashMatch) comment = hashMatch[1].trim()
            else {
                const oldMatch = originalLine.match(/--\s*(.+)$/)
                if (oldMatch) comment = oldMatch[1].trim()
            }
            out.push({ key: m[1], value: value, comment: comment })
        }
        return out
    }

    function parseFastfetchOutput(raw) {
        if (!raw) return []
        const lines = raw.split("\n")
        const entries = []
        for (let line of lines) {
            line = line.trim()
            if (!line) continue
            if (line.includes("@") && !line.includes(":")) continue
            if (line.match(/^[-=]+$/)) continue
            const idx = line.indexOf(":")
            if (idx > 0) {
                const label = line.substring(0, idx).trim()
                let value = line.substring(idx + 1).trim()
                const lower = label.toLowerCase()
                if (lower === "terminal" || lower.includes("font")) continue
                if (value) entries.push({ label: label, value: value })
            }
        }
        return entries
    }

    function keyPillColor(key) {
        const k = (key || "").toUpperCase().trim()
        if (k.includes("SUPER") || k.includes("WIN") || k.includes("META")) return "#89b4fa"
        if (k.includes("SHIFT")) return "#fab387"
        if (k.includes("CTRL") || k.includes("CONTROL")) return "#cba6f7"
        if (k.includes("ALT")) return "#94e2d5"
        return "#6c7086"
    }

    function keyPillTextColor(key) {
        return keyPillColor(key) === "#6c7086" ? "#ffffff" : "#000000"
    }

    function refreshSystemInfo() {
        systemProcess.running = false
        systemProcess.running = true
        systemDirty = false
        copiedValue = ""
    }

    function copyToClipboard(text) {
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy',
            "wl-copy",
            text
        ])
        copiedValue = text
        Qt.callLater(function() {
            if (copiedValue === text) copiedValue = ""
        }, 1200)
    }

    Io.Process {
        id: systemProcess
        command: ["fastfetch", "--logo", "none"]
        running: false
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => { systemOutput += line + "\n" }
        }
        onStarted: systemOutput = ""
        onExited: (code) => {
            if (code !== 0 && systemOutput.trim() === "") {
                systemOutput = "Failed to collect system information (exit code " + code + ")"
            } else {
                systemEntries = parseFastfetchOutput(systemOutput)
            }
        }
    }

    function filterQuery() {
        return (globalFilter && globalFilter.trim()) ? globalFilter.toLowerCase().trim() : ""
    }

    function filteredBinds() {
        const q = filterQuery()
        if (!q) return _parsedBinds
        return _parsedBinds.filter(function(b) {
            return (b.key && b.key.toLowerCase().indexOf(q) !== -1) ||
                   (b.action && b.action.toLowerCase().indexOf(q) !== -1) ||
                   (b.comment && b.comment.toLowerCase().indexOf(q) !== -1)
        })
    }

    function filteredEnv() {
        const q = filterQuery()
        if (!q) return _parsedEnv
        return _parsedEnv.filter(function(e) {
            return (e.key && e.key.toLowerCase().indexOf(q) !== -1) ||
                   (e.value && e.value.toLowerCase().indexOf(q) !== -1) ||
                   (e.comment && e.comment.toLowerCase().indexOf(q) !== -1)
        })
    }

    function filteredSystemEntries() {
        const q = filterQuery()
        if (!q) return systemEntries
        return systemEntries.filter(function(e) {
            return (e.label && e.label.toLowerCase().indexOf(q) !== -1) ||
                   (e.value && e.value.toLowerCase().indexOf(q) !== -1)
        })
    }

    function scrollFlickablePage(flickable, direction) {
        if (!flickable || flickable.contentHeight <= flickable.height) return
        const page = Math.max(80, flickable.height * 0.85)
        const maxY = Math.max(0, flickable.contentHeight - flickable.height)
        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY + direction * page))
    }

    function pageContentScroll(direction) {
        const tab = currentTabInfo
        if (!tab) return
        if (tab.view === "binds") scrollFlickablePage(bindsFlickable, direction)
        else if (tab.view === "env") scrollFlickablePage(envFlickable, direction)
        else if (tab.view === "raw") batViewer.pageScroll(direction)
        else if (tab.view === "runtime") runtimeViewer.pageScroll(direction)
        else if (tab.view === "system") scrollFlickablePage(systemFlickable, direction)
    }

    FloatingWindow {
        id: inspectorWindow
        visible: false
        title: "Hyprland Config Inspector"
        color: "transparent"
        implicitWidth: root.inspectorWidth
        implicitHeight: root.inspectorHeight
        minimumSize: Qt.size(560, 400)

        Shortcut {
            sequence: "Escape"
            enabled: inspectorWindow.visible
            onActivated: root.hide()
        }

        Shortcut {
            sequence: "Tab"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.nextTab()
        }

        Shortcut {
            sequence: "Shift+Tab"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.prevTab()
        }

        Shortcut {
            sequence: "PgUp"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.pageContentScroll(-1)
        }

        Shortcut {
            sequence: "PgDown"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.pageContentScroll(1)
        }

        Rectangle {
            id: contentPanel
            anchors.fill: parent
            radius: root.popupRadiusLarge || 16
            color: root.glassPopupBg
            border.width: 1
            border.color: root.glassPopupBorder
            focus: inspectorWindow.visible

            Keys.onPressed: (event) => {
                if (globalFilterField.activeFocus) return
                if (event.key === Qt.Key_PageUp) {
                    root.pageContentScroll(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageDown) {
                    root.pageContentScroll(1)
                    event.accepted = true
                }
            }

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: root.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Item {
                    id: titleBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: titleColumn.implicitHeight

                    ColumnLayout {
                        id: titleColumn
                        anchors.fill: parent
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text { text: "Hyprland Config Inspector"; color: root.text; font.pixelSize: 18; font.bold: true }
                            Item { Layout.fillWidth: true }

                            Rectangle {
                                width: 78
                                height: 28
                                radius: 6
                                color: refreshAllMa.containsMouse ? root.surface : "transparent"
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.1)
                                Text { anchors.centerIn: parent; text: "Refresh All"; color: root.accent; font.pixelSize: 11 }
                                MouseArea {
                                    id: refreshAllMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.refreshAll()
                                }
                            }

                            Rectangle {
                                width: 28
                                height: 28
                                radius: 6
                                color: closeMa.containsMouse ? root.surface : "transparent"
                                Text { anchors.centerIn: parent; text: "✕"; color: root.text; font.pixelSize: 14 }
                                MouseArea {
                                    id: closeMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.hide()
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: root.wmDistroLabel || "Hyprland"
                                color: root.accent
                                font.pixelSize: 12
                                font.bold: true
                            }

                            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 14; color: Qt.rgba(1, 1, 1, 0.12) }

                            Text {
                                text: "SUPER + ?  ·  Tab / Shift+Tab  ·  PgUp / PgDown"
                                color: root.overlay
                                font.pixelSize: 12
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        cursorShape: Qt.SizeAllCursor
                        onPressed: inspectorWindow.startSystemMove()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Flickable {
                        id: tabFlickable
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(Math.max(34, tabFlow.implicitHeight), root.tabBarMaxHeight)
                        contentWidth: width
                        contentHeight: tabFlow.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick

                        ScrollBar.vertical: ScrollBar {
                            id: tabBarScrollBar
                            policy: tabFlickable.contentHeight > tabFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: tabBarScrollBar.pressed ? root.accent : Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        Flow {
                            id: tabFlow
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: root.tabs
                                delegate: Rectangle {
                                    required property int index
                                    required property var modelData

                                    height: 30
                                    width: tabLabel.implicitWidth + 28
                                    radius: 7
                                    color: (root.currentTab === index) ? Qt.rgba(0.55, 0.70, 0.96, 0.18) : (tma.containsMouse ? root.surface : "transparent")
                                    border.width: (root.currentTab === index) ? 1 : 0
                                    border.color: root.accent

                                    Text {
                                        id: tabLabel
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: (root.currentTab === index) ? root.accent : root.text
                                        font.pixelSize: 12
                                        font.bold: (root.currentTab === index)
                                    }

                                    MouseArea {
                                        id: tma
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activateTab(index)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 28
                        radius: 6
                        color: root.surface
                        border.width: 1
                        border.color: Qt.rgba(1,1,1,0.08)

                        TextField {
                            id: globalFilterField
                            anchors.fill: parent
                            anchors.margins: 4
                            z: 2
                            focusPolicy: Qt.StrongFocus
                            activeFocusOnPress: true
                            selectByMouse: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.text
                            font.pixelSize: 13
                            selectionColor: Qt.rgba(0.55, 0.70, 0.96, 0.35)
                            selectedTextColor: root.text
                            placeholderText: "Search all tabs..."
                            placeholderTextColor: root.overlay
                            onTextChanged: root.globalFilter = text
                            Keys.onTabPressed: (event) => {
                                event.accepted = true
                                root.nextTab()
                            }
                            Keys.onBacktabPressed: (event) => {
                                event.accepted = true
                                root.prevTab()
                            }
                            background: Rectangle {
                                color: "transparent"
                                border.width: 0
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"

                    // Key Bindings
                    Flickable {
                        id: bindsFlickable
                        visible: root.currentTabInfo.view === "binds"
                        anchors.fill: parent
                        contentHeight: bindsGrid.implicitHeight + 20
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            id: bindsScrollBar
                            policy: bindsFlickable.contentHeight > bindsFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: bindsScrollBar.pressed ? root.accent : Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        GridLayout {
                            id: bindsGrid
                            width: parent.width
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 2

                            Repeater {
                                model: root.filteredBinds()
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    radius: 4
                                    color: rma.containsMouse ? Qt.rgba(1,1,1,0.03) : "transparent"

                                    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Row {
                                            spacing: 4
                                            Repeater {
                                                model: modelData.key.split(/\s*\+\s*/)
                                                delegate: Rectangle {
                                                    height: 20
                                                    width: keyText.implicitWidth + 12
                                                    radius: 5
                                                    color: keyPillColor(modelData)

                                                    Text {
                                                        id: keyText
                                                        anchors.centerIn: parent
                                                        text: modelData
                                                        color: keyPillTextColor(modelData)
                                                        font.pixelSize: 10
                                                        font.family: "monospace"
                                                        font.bold: true
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.action
                                            color: root.text
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RuntimeOptionsView {
                        id: runtimeViewer
                        visible: root.currentTabInfo.view === "runtime"
                        anchors.fill: parent
                        globalFilter: root.globalFilter
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                    }

                    // Environment
                    Flickable {
                        id: envFlickable
                        visible: root.currentTabInfo.view === "env"
                        anchors.fill: parent
                        contentHeight: envCol.implicitHeight + 20
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            id: envScrollBar
                            policy: envFlickable.contentHeight > envFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: envScrollBar.pressed ? root.accent : Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        Column {
                            id: envCol
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: root.filteredEnv()
                                delegate: Rectangle {
                                    width: envCol.width
                                    height: 24
                                    radius: 4
                                    color: ema.containsMouse ? Qt.rgba(1,1,1,0.03) : "transparent"

                                    MouseArea { id: ema; anchors.fill: parent; hoverEnabled: true }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 12

                                        Text {
                                            Layout.preferredWidth: 290
                                            text: modelData.key
                                            color: root.accent
                                            font.pixelSize: 12
                                            font.family: "monospace"
                                        }
                                        Text {
                                            Layout.preferredWidth: 380
                                            text: modelData.value
                                            color: root.accent
                                            font.pixelSize: 12
                                            font.family: "monospace"
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: modelData.comment
                                            text: modelData.comment
                                            color: root.text
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Raw config file viewer — syntax highlighting via `bat`
                    BatSyntaxView {
                        id: batViewer
                        visible: root.currentTabInfo.view === "raw"
                        anchors.fill: parent
                        filePath: root.batFilePath
                        language: root.batLanguage
                        filterText: root.globalFilter
                        defaultColor: root.text
                        accentColor: root.accent
                    }

                    // System Info
                    Item {
                        visible: root.currentTabInfo.view === "system"
                        anchors.fill: parent
                        anchors.margins: 10

                        RowLayout {
                            anchors.fill: parent
                            spacing: 20

                            Image {
                                source: "/home/crome/.config/quickshell/cachyos-linux.svg"
                                Layout.preferredWidth: 180
                                Layout.preferredHeight: 180
                                fillMode: Image.PreserveAspectFit
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 4

                                Text {
                                    text: "crome@crome-dt"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: root.accent
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: root.glassPopupBorder
                                    opacity: 0.5
                                }

                                Flickable {
                                    id: systemFlickable
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    contentHeight: sysList.implicitHeight
                                    boundsBehavior: Flickable.StopAtBounds

                                    ScrollBar.vertical: ScrollBar {
                                        id: systemScrollBar
                                        policy: systemFlickable.contentHeight > systemFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                        contentItem: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: systemScrollBar.pressed ? root.accent : Qt.rgba(1, 1, 1, 0.2)
                                        }
                                    }

                                    Column {
                                        id: sysList
                                        width: parent.width
                                        spacing: 2

                                        Repeater {
                                            model: root.filteredSystemEntries()
                                            delegate: Rectangle {
                                                width: parent.width
                                                height: 24
                                                color: valueMa.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent"

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 4
                                                    anchors.rightMargin: 8
                                                    spacing: 12

                                                    Text {
                                                        Layout.preferredWidth: 210
                                                        text: modelData.label + ":"
                                                        color: root.accent
                                                        font.pixelSize: 12
                                                        font.family: "monospace"
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.value
                                                        color: root.text
                                                        font.pixelSize: 12
                                                        font.family: "monospace"

                                                        MouseArea {
                                                            id: valueMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: root.copyToClipboard(modelData.value)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: root.statusText()
                        color: root.overlay
                        font.pixelSize: 11
                        property int _mtimeTick: root.fileMtimesVersion
                        property string _filterTick: root.globalFilter
                        property int _fileTick: root.fileContentsVersion
                        property int _runtimeTick: runtimeViewer.optionsVersion
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: root.currentTabInfo.view === "system" || root.currentTabInfo.view === "runtime"
                        width: 68
                        height: 22
                        radius: 5
                        color: refSysMa.containsMouse ? root.surface : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1,1,1,0.1)
                        Text { anchors.centerIn: parent; text: "Refresh"; color: root.accent; font.pixelSize: 11 }
                        MouseArea {
                            id: refSysMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.currentTabInfo.view === "runtime") runtimeViewer.refreshCategory()
                                else root.refreshSystemInfo()
                            }
                        }
                    }

                    Rectangle {
                        visible: root.hasConfigFile
                        width: 40
                        height: 22
                        radius: 5
                        color: editLuaMa.containsMouse ? root.surface : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1,1,1,0.1)
                        Text { anchors.centerIn: parent; text: "Edit"; color: root.accent; font.pixelSize: 11 }
                        MouseArea {
                            id: editLuaMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.editCurrentConfigFile()
                        }
                    }

                    Rectangle {
                        visible: root.hasConfigFile
                        Layout.leftMargin: 6
                        width: 68
                        height: 22
                        radius: 5
                        color: refLuaMa.containsMouse ? root.surface : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1,1,1,0.1)
                        Text { anchors.centerIn: parent; text: "Reload"; color: root.accent; font.pixelSize: 11 }
                        MouseArea {
                            id: refLuaMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshCurrentTab()
                        }
                    }
                }
            }

            // Bottom-right resize grip — updates implicitWidth/Height directly
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 4
                width: 22
                height: 22
                radius: 3
                z: 201
                color: resizeMa.containsMouse || resizeMa.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "◢"
                    color: root.overlay
                    font.pixelSize: 9
                }

                MouseArea {
                    id: resizeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.SizeFDiagCursor

                    property real startWidth: 0
                    property real startHeight: 0
                    property real pressSceneX: 0
                    property real pressSceneY: 0

                    onPressed: (mouse) => {
                        startWidth = root.inspectorWidth
                        startHeight = root.inspectorHeight
                        pressSceneX = mouse.scenePosition.x
                        pressSceneY = mouse.scenePosition.y
                    }

                    onPositionChanged: (mouse) => {
                        if (!pressed) return
                        const dx = mouse.scenePosition.x - pressSceneX
                        const dy = mouse.scenePosition.y - pressSceneY
                        root.inspectorWidth = Math.max(560, Math.round(startWidth + dx))
                        root.inspectorHeight = Math.max(400, Math.round(startHeight + dy))
                    }
                }
            }
        }
    }
}