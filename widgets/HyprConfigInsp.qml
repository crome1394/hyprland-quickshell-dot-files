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
//   - Parsed tabs: Key Bindings, Environment, Runtime Options (hyprctl getoption), CPU/GPU (sysmon)
//   - Config Files tab (dropdown + bat) for ~/.config/hypr/config/*.lua and hypr*.conf
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

    SysMonService {
        id: sysMonService
        autoPoll: inspectorWindow.visible
    }

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

    readonly property var configFileEntries: [
        { id: "monitors", label: "Monitors", file: "monitors.lua" },
        { id: "my-programs", label: "My Programs", file: "my-programs.lua" },
        { id: "autostarts", label: "Autostarts", file: "autostarts.lua" },
        { id: "permissions", label: "Permissions", file: "permissions.lua" },
        { id: "look-and-feel", label: "Look & Feel", file: "look-and-feel.lua" },
        { id: "misc", label: "Misc", file: "misc.lua" },
        { id: "input", label: "Input", file: "input.lua" },
        { id: "windows-and-workspaces", label: "Window & Layer Rules", file: "windows-and-workspaces.lua" },
        { id: "hyprland", label: "Main Config", file: "hyprland.lua", dir: hyprDir },
        { id: "keybindings", label: "Key Bindings", file: "keybindings.lua" },
        { id: "environment", label: "Environment", file: "environment-variables.lua" },
        { id: "hypridle", label: "Hypridle", file: "hypridle.conf", dir: hyprDir, batLanguage: "INI" },
        { id: "hyprlock", label: "Hyprlock", file: "hyprlock.conf", dir: hyprDir, batLanguage: "Java Properties" },
        { id: "hyprpaper", label: "Hyprpaper", file: "hyprpaper.conf", dir: hyprDir, batLanguage: "INI" }
    ]

    readonly property var tabs: [
        { label: "Key Bindings", id: "keybindings", file: "keybindings.lua", view: "binds" },
        { label: "Environment", id: "environment", file: "environment-variables.lua", view: "env" },
        { label: "Runtime Options", id: "runtime-options", file: "", view: "runtime" },
        { label: "Config Files", id: "config-files", file: "", view: "configfiles" },
        { label: "CPU", id: "cpu", file: "", view: "cpu" },
        { label: "GPU", id: "gpu", file: "", view: "gpu" },
        { label: "System Info", id: "system", file: "", view: "system" }
    ]

    readonly property var currentTabInfo: (currentTab >= 0 && currentTab < tabs.length) ? tabs[currentTab] : tabs[0]
    readonly property bool hasConfigFile: {
        const tab = currentTabInfo
        if (tab.view === "configfiles") return true
        return tab.file && tab.file.length > 0
    }
    property string rawSource: ""
    property string batFilePath: ""
    property string batLanguage: ""

    function fileEntryById(id) {
        if (!id) return null
        for (let i = 0; i < configFileEntries.length; i++) {
            if (configFileEntries[i].id === id) return configFileEntries[i]
        }
        return null
    }

    function syncRawSource() {
        let id = currentTabInfo.id
        if (currentTabInfo.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            id = entry ? entry.id : ""
        }
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

    function mtimeSuffix(entry) {
        if (!entry || !entry.id) return ""
        const formatted = formatFileMtime(entry.id)
        return formatted ? "  ·  " + formatted : ""
    }

    function fileBackedEntries() {
        const entries = []
        for (let i = 0; i < tabs.length; i++) {
            const tab = tabs[i]
            if (tab.view === "system" || tab.view === "runtime" || tab.view === "configfiles" || tab.view === "cpu" || tab.view === "gpu") continue
            if (tab.file) entries.push(tab)
        }
        for (let j = 0; j < configFileEntries.length; j++) {
            entries.push(configFileEntries[j])
        }
        return entries
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
        if (currentTabInfo.id === id || (currentTabInfo.view === "configfiles" && configFilesViewer.selectedFileId === id)) {
            syncRawSource()
        }
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
                const tab = tabs.find(function(t) { return t.id === id }) ||
                    fileEntryById(id)
                if (tab) applyLoadedFile(id, tab.view || "raw", body)
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
        const entries = fileBackedEntries()
        for (let i = 0; i < entries.length; i++) {
            const tab = entries[i]
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

    function refreshConfigFileEntry(entry) {
        if (!entry || !entry.file) return
        refreshFileMtime(entry)
        configFilesViewer.refreshBat()
        startFileLoad(["cat", tabPath(entry)], true, entry.id, "raw")
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
        if (tab && tab.view === "configfiles") {
            configFilesViewer.refreshBat()
        }
        if (tab && tab.view === "system") {
            refreshSystemInfo()
        } else {
            systemDirty = true
        }
        if (tab && tab.view === "runtime") {
            runtimeViewer.refresh()
        }
        if (tab && (tab.view === "cpu" || tab.view === "gpu")) {
            sysMonService.refresh()
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
        if (tab.view === "cpu" || tab.view === "gpu") {
            sysMonService.refresh()
            return
        }
        if (tab.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            if (entry) refreshConfigFileEntry(entry)
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
        if (!tab) return
        if (tab.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            if (entry) Quickshell.execDetached(["kitty", "-e", "nano", tabPath(entry)])
            return
        }
        if (!tab.file) return
        Quickshell.execDetached(["kitty", "-e", "nano", tabPath(tab)])
    }

    function statusText() {
        if (copiedValue) return "Copied to clipboard"
        const tab = currentTabInfo
        if (!tab) return ""
        const filterNote = (globalFilter && globalFilter.trim()) ? "  ·  filtered" : ""
        if (tab.view === "binds") return filteredBinds().length + " bindings  ·  " + tab.file + mtimeSuffix(tab) + filterNote
        if (tab.view === "env") return filteredEnv().length + " environment variables  ·  " + tab.file + mtimeSuffix(tab) + filterNote
        if (tab.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            const file = entry ? entry.file : ""
            const id = entry ? entry.id : ""
            const body = rawSource || (id && fileContents[id]) || ""
            const lines = body.length ? body.split("\n").length : 0
            const chars = body.length
            return lines + " lines (" + chars + " chars)  ·  " + file + "  ·  bat" + mtimeSuffix(entry) + filterNote
        }
        if (tab.view === "raw") {
            const body = rawSource || fileContents[tab.id] || ""
            const lines = body.length ? body.split("\n").length : 0
            const chars = body.length
            return lines + " lines (" + chars + " chars)  ·  " + tab.file + "  ·  bat" + mtimeSuffix(tab) + filterNote
        }
        if (tab.view === "system") return filteredSystemEntries().length + " entries  ·  system info" + filterNote
        if (tab.view === "cpu") {
            const util = sysMonService.data.cpu ? (sysMonService.data.cpu.util || 0).toFixed(0) : "0"
            const cores = sysMonService.data.cpu_info && sysMonService.data.cpu_info.cores ? sysMonService.data.cpu_info.cores : "?"
            return util + "% CPU  ·  " + cores + " cores  ·  live (" + (sysMonService.pollInterval / 1000).toFixed(1) + "s)" + filterNote
        }
        if (tab.view === "gpu") {
            const util = sysMonService.data.gpu ? (sysMonService.data.gpu.util || 0).toFixed(0) : "0"
            const vramUsed = sysMonService.data.gpu ? Math.round((sysMonService.data.gpu.vram_used || 0) / 1024) : 0
            const vramTotal = sysMonService.data.gpu ? Math.round((sysMonService.data.gpu.vram_total || 0) / 1024) : 0
            const name = sysMonService.data.gpu_info && sysMonService.data.gpu_info.name ? sysMonService.data.gpu_info.name : "GPU"
            return util + "% GPU  ·  " + vramUsed + "/" + vramTotal + " GB VRAM  ·  " + name + filterNote
        }
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

    function focusActiveTabContent() {
        const tab = currentTabInfo
        if (tab.view === "runtime") runtimeViewer.focusScroll()
        else if (tab.view === "configfiles") configFilesViewer.focusScroll()
        else contentPanel.forceActiveFocus()
    }

    function resetTabScroll(tab) {
        if (!tab) return
        if (tab.view === "binds") bindsFlickable.contentY = 0
        else if (tab.view === "env") envFlickable.contentY = 0
        else if (tab.view === "system") systemFlickable.contentY = 0
        else if (tab.view === "cpu") cpuViewer.resetScroll()
        else if (tab.view === "gpu") gpuViewer.resetScroll()
        else if (tab.view === "runtime") runtimeViewer.resetScroll()
        else if (tab.view === "configfiles") configFilesViewer.resetScroll()
        else if (tab.view === "raw") batViewer.resetScroll()
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
        } else if (tab.view === "cpu" || tab.view === "gpu") {
            sysMonService.refresh()
        } else if (tab.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            if (entry && !fileContents[entry.id]) refreshConfigFileEntry(entry)
            else configFilesViewer.refreshBat()
        } else if (tab.file && !fileContents[tab.id]) {
            refreshCurrentTab()
        }
        scrollTabIntoView()
        Qt.callLater(function() {
            root.focusActiveTabContent()
            root.resetTabScroll(tab)
        })
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
        else if (tab.view === "cpu" || tab.view === "gpu") sysMonService.refresh()
        else if (tab.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            if (entry && !fileContents[entry.id]) refreshConfigFileEntry(entry)
            else configFilesViewer.refreshBat()
        }
        Qt.callLater(function() {
            scrollTabIntoView()
            root.focusActiveTabContent()
            root.resetTabScroll(tab)
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

    function envKeyIsHighlight(key) {
        const k = (key || "").toUpperCase()
        if (!k) return false
        const prefixes = [
            "__GL", "__NV", "__VK", "GBM_", "NVD_", "LIBVA_", "AQ_", "GDK_", "QT_",
            "SDL_", "XDG_", "MOZ_", "ELECTRON_", "CLUTTER_", "HYPRCURSOR", "XCURSOR"
        ]
        for (let i = 0; i < prefixes.length; i++) {
            if (k.indexOf(prefixes[i]) === 0) return true
        }
        return k.indexOf("WAYLAND") !== -1
    }

    function envKeyColor(key) {
        return envKeyIsHighlight(key) ? "#94e2d5" : accent
    }

    function envValueColor(key, value) {
        const v = (value || "").trim()
        const lower = v.toLowerCase()
        const k = (key || "").toUpperCase()

        if (lower === "1" || lower === "true" || lower === "enabled") return "#a6e3a1"
        if (lower === "0" || lower === "false" || lower === "disabled") return "#fab387"

        if (envKeyIsHighlight(key) || lower.indexOf("nvidia") !== -1 || lower.indexOf("wayland") !== -1
                || lower.indexOf("opengl") !== -1 || lower === "direct" || lower.indexOf("nvidia_only") !== -1) {
            return "#89dceb"
        }

        if (v.indexOf("/") === 0 || v.indexOf("~") === 0 || v.indexOf("/dev/") !== -1) {
            return "#a6adc8"
        }

        if (k.indexOf("THEME") !== -1 || k.indexOf("PLATFORMTHEME") !== -1
                || lower.indexOf("bibata") !== -1 || lower === "qt6ct" || lower === "auto"
                || lower === "arch-") {
            return "#cba6f7"
        }

        if (k === "TERMINAL" || lower.indexOf("hyprland") !== -1) return "#89b4fa"

        return text
    }

    readonly property int envTableSideMargin: 10
    readonly property int envTableColSpacing: 12

    function envTableContentWidth(totalWidth) {
        return Math.max(0, totalWidth - envTableSideMargin * 2)
    }

    function envVariableColumnWidth(totalWidth) {
        const usable = envTableContentWidth(totalWidth) - envTableColSpacing
        const target = Math.round(usable * 0.34)
        return Math.max(200, Math.min(target, 300))
    }

    function envValueColumnWidth(totalWidth) {
        const usable = envTableContentWidth(totalWidth) - envTableColSpacing
        const remaining = usable - envVariableColumnWidth(totalWidth)
        return Math.max(220, remaining)
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

    readonly property bool canCopyTab: {
        const view = currentTabInfo.view
        return view === "raw" || view === "runtime" || view === "configfiles"
    }

    function copyCurrentTabContent() {
        const tab = currentTabInfo
        if (!tab) return
        if (tab.view === "raw") {
            const text = batViewer.plainText()
            if (text) copyToClipboard(text)
            return
        }
        if (tab.view === "configfiles") {
            const text = configFilesViewer.plainText()
            if (text) copyToClipboard(text)
            return
        }
        if (tab.view === "runtime") {
            const text = runtimeViewer.exportText()
            if (text) copyToClipboard(text)
        }
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

    function flickableMaxY(flickable) {
        if (!flickable) return 0
        return Math.max(0, flickable.contentHeight - flickable.height)
    }

    function scrollFlickablePage(flickable, direction) {
        const maxY = flickableMaxY(flickable)
        if (maxY <= 0) return
        const page = Math.max(80, flickable.height * 0.85)
        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY + direction * page))
    }

    function scrollFlickableLine(flickable, direction, step) {
        const maxY = flickableMaxY(flickable)
        if (maxY <= 0) return
        const lineStep = step || 28
        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY + direction * lineStep))
    }

    function flickableWheelScroll(flickable, deltaY, step) {
        const maxY = flickableMaxY(flickable)
        if (maxY <= 0) return
        const lineStep = step || 42
        const ticks = deltaY / 120
        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY - ticks * lineStep))
    }

    function pageContentScroll(direction) {
        const tab = currentTabInfo
        if (!tab) return
        if (tab.view === "binds") scrollFlickablePage(bindsFlickable, direction)
        else if (tab.view === "env") scrollFlickablePage(envFlickable, direction)
        else if (tab.view === "raw") batViewer.pageScroll(direction)
        else if (tab.view === "configfiles") configFilesViewer.pageScroll(direction)
        else if (tab.view === "runtime") runtimeViewer.pageScroll(direction)
        else if (tab.view === "cpu") cpuViewer.pageScroll(direction)
        else if (tab.view === "gpu") gpuViewer.pageScroll(direction)
        else if (tab.view === "system") scrollFlickablePage(systemFlickable, direction)
    }

    function lineContentScroll(direction) {
        const tab = currentTabInfo
        if (!tab) return
        if (tab.view === "binds") scrollFlickableLine(bindsFlickable, direction)
        else if (tab.view === "env") scrollFlickableLine(envFlickable, direction)
        else if (tab.view === "raw") batViewer.lineScroll(direction)
        else if (tab.view === "configfiles") configFilesViewer.lineScroll(direction)
        else if (tab.view === "runtime") runtimeViewer.lineScroll(direction)
        else if (tab.view === "cpu") cpuViewer.lineScroll(direction)
        else if (tab.view === "gpu") gpuViewer.lineScroll(direction)
        else if (tab.view === "system") scrollFlickableLine(systemFlickable, direction)
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

        Shortcut {
            sequence: "Up"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.lineContentScroll(-1)
        }

        Shortcut {
            sequence: "Down"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.lineContentScroll(1)
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
                const tab = root.currentTabInfo
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                    if (tab.view === "runtime" && runtimeViewer.handleNavKey(event)) {
                        runtimeViewer.focusScroll()
                        return
                    }
                    if (tab.view === "configfiles" && configFilesViewer.handleNavKey(event)) {
                        configFilesViewer.focusScroll()
                        return
                    }
                }
                if (event.key === Qt.Key_PageUp) {
                    root.pageContentScroll(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageDown) {
                    root.pageContentScroll(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    root.lineContentScroll(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    root.lineContentScroll(1)
                    event.accepted = true
                } else if (tab.view === "runtime" && runtimeViewer.handleNavKey(event)) {
                    runtimeViewer.focusScroll()
                } else if (tab.view === "configfiles" && configFilesViewer.handleNavKey(event)) {
                    configFilesViewer.focusScroll()
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
                                text: "SUPER + ?  ·  Tab / Shift+Tab  ·  PgUp / PgDown / ↑ / ↓"
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
                        property int _bindsTick: root.fileContentsVersion
                        property string _filterTick: root.globalFilter
                        contentHeight: Math.max(bindsGrid.implicitHeight + 20, 1)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: true

                        WheelHandler {
                            onWheel: function(event) {
                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                                if (delta === 0) return
                                root.flickableWheelScroll(bindsFlickable, delta)
                                event.accepted = true
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            id: bindsScrollBar
                            policy: bindsFlickable.contentHeight > bindsFlickable.height + 1
                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
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
                        onCopyRequested: (text) => root.copyToClipboard(text)
                    }

                    ConfigFilesView {
                        id: configFilesViewer
                        visible: root.currentTabInfo.view === "configfiles"
                        anchors.fill: parent
                        anchors.margins: 10
                        files: root.configFileEntries
                        configDir: root.configDir
                        globalFilter: root.globalFilter
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        onSelectedFileIdChanged: {
                            root.syncRawSource()
                            const entry = configFilesViewer.currentEntry()
                            if (entry && !root.fileContents[entry.id]) {
                                root.refreshConfigFileEntry(entry)
                            } else {
                                configFilesViewer.refreshBat()
                            }
                        }
                    }

                    // Environment
                    Flickable {
                        id: envFlickable
                        visible: root.currentTabInfo.view === "env"
                        anchors.fill: parent
                        anchors.margins: 10
                        property int _envTick: root.fileContentsVersion
                        property string _filterTick: root.globalFilter
                        contentHeight: Math.max(envCol.implicitHeight, 1)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: true

                        WheelHandler {
                            onWheel: function(event) {
                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                                if (delta === 0) return
                                root.flickableWheelScroll(envFlickable, delta)
                                event.accepted = true
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            id: envScrollBar
                            policy: envFlickable.contentHeight > envFlickable.height + 1
                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: envScrollBar.pressed ? root.accent : Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        Column {
                            id: envCol
                            width: parent.width
                            spacing: 8

                            Rectangle {
                                width: parent.width
                                height: 28
                                radius: 4
                                color: Qt.rgba(1, 1, 1, 0.03)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: root.envTableSideMargin
                                    anchors.rightMargin: root.envTableSideMargin
                                    spacing: root.envTableColSpacing

                                    Text {
                                        Layout.preferredWidth: root.envVariableColumnWidth(parent.width)
                                        Layout.minimumWidth: root.envVariableColumnWidth(parent.width)
                                        Layout.maximumWidth: root.envVariableColumnWidth(parent.width)
                                        text: "Variable"
                                        color: root.accent
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.family: "monospace"
                                    }
                                    Text {
                                        Layout.preferredWidth: root.envValueColumnWidth(parent.width)
                                        Layout.minimumWidth: root.envValueColumnWidth(parent.width)
                                        Layout.maximumWidth: root.envValueColumnWidth(parent.width)
                                        text: "Value"
                                        color: root.accent
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.family: "monospace"
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: root.filteredEnv()
                                    delegate: Rectangle {
                                        width: envCol.width
                                        height: Math.max(28, envComment.visible ? 40 : 28)
                                        radius: 4
                                        color: keyMa.containsMouse || valueMa.containsMouse
                                            ? Qt.rgba(1, 1, 1, 0.03) : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: root.envTableSideMargin
                                            anchors.rightMargin: root.envTableSideMargin
                                            spacing: root.envTableColSpacing

                                            ColumnLayout {
                                                Layout.preferredWidth: root.envVariableColumnWidth(envCol.width)
                                                Layout.minimumWidth: root.envVariableColumnWidth(envCol.width)
                                                Layout.maximumWidth: root.envVariableColumnWidth(envCol.width)
                                                spacing: 0

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.key
                                                    color: root.envKeyColor(modelData.key)
                                                    font.pixelSize: 12
                                                    font.family: "monospace"
                                                    font.bold: root.envKeyIsHighlight(modelData.key)
                                                    elide: Text.ElideRight

                                                    MouseArea {
                                                        id: keyMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.copyToClipboard(modelData.key)
                                                    }
                                                }

                                                Text {
                                                    id: envComment
                                                    visible: modelData.comment && modelData.comment.length > 0
                                                    text: modelData.comment
                                                    color: root.overlay
                                                    font.pixelSize: 10
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            Item {
                                                Layout.preferredWidth: root.envValueColumnWidth(envCol.width)
                                                Layout.minimumWidth: root.envValueColumnWidth(envCol.width)
                                                Layout.maximumWidth: root.envValueColumnWidth(envCol.width)
                                                Layout.preferredHeight: envComment.visible ? 40 : 28
                                                clip: true

                                                Text {
                                                    anchors.fill: parent
                                                    text: modelData.value
                                                    color: root.envValueColor(modelData.key, modelData.value)
                                                    font.pixelSize: 12
                                                    font.family: "monospace"
                                                    verticalAlignment: Text.AlignVCenter
                                                    horizontalAlignment: Text.AlignRight
                                                    elide: Text.ElideLeft
                                                }

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

                    CpuMonitorView {
                        id: cpuViewer
                        visible: root.currentTabInfo.view === "cpu"
                        anchors.fill: parent
                        anchors.margins: 10
                        service: sysMonService
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                    }

                    GpuMonitorView {
                        id: gpuViewer
                        visible: root.currentTabInfo.view === "gpu"
                        anchors.fill: parent
                        anchors.margins: 10
                        service: sysMonService
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        gaugeLowColor: th.gaugeLow
                        gaugeMidColor: th.gaugeMid
                        gaugeHighColor: th.gaugeHigh
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
                                    Layout.minimumHeight: 0
                                    clip: true
                                    property int _sysTick: root.systemEntries.length
                                    property string _filterTick: root.globalFilter
                                    contentHeight: Math.max(sysList.implicitHeight, 1)
                                    boundsBehavior: Flickable.StopAtBounds
                                    interactive: true

                                    WheelHandler {
                                        onWheel: function(event) {
                                            const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                                            if (delta === 0) return
                                            root.flickableWheelScroll(systemFlickable, delta)
                                            event.accepted = true
                                        }
                                    }

                                    ScrollBar.vertical: ScrollBar {
                                        id: systemScrollBar
                                        policy: systemFlickable.contentHeight > systemFlickable.height + 1
                                            ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
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
                        property string _configFileTick: configFilesViewer.selectedFileId
                        property int _cpuTick: sysMonService.cpuHistory.length
                        property int _gpuTick: sysMonService.gpuHistory.length
                        property var _cpuData: sysMonService.data
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: root.canCopyTab
                        width: 44
                        height: 22
                        radius: 5
                        color: copyTabMa.containsMouse ? root.surface : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1,1,1,0.1)
                        Text { anchors.centerIn: parent; text: "Copy"; color: root.accent; font.pixelSize: 11 }
                        MouseArea {
                            id: copyTabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.copyCurrentTabContent()
                        }
                    }

                    Rectangle {
                        visible: root.currentTabInfo.view === "system" || root.currentTabInfo.view === "runtime" || root.currentTabInfo.view === "cpu" || root.currentTabInfo.view === "gpu"
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
                                else if (root.currentTabInfo.view === "cpu" || root.currentTabInfo.view === "gpu") sysMonService.refresh()
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