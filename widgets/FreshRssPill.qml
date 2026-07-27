import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io
import ".."

// =============================================================================
// FreshRssPill.qml — FreshRSS reader (bar pill + FloatingWindow)
// =============================================================================
//
// Data: scripts/freshrss-api.sh
//   - Google Reader per-feed streams (All/Read) — parallel, auth-cached
//   - Fever unread/starred id lists
//   - Anonymous public RSS fallback without API password
//
// Perf notes:
//   - Categories start collapsed → ListView only paints ~N feed headers
//   - listRows skips date/item expansion for collapsed feeds
//   - Search scans metadata/summary only (not full HTML)
//   - API trims HTML/text before JSON hits QML
//
// IPC (shell.qml):
//   qs ipc call freshRss toggle | refresh | show | hide
//
// =============================================================================

Rectangle {
    id: root

    required property var bar

    Config { id: th }

    readonly property string apiScript: Qt.resolvedUrl("../scripts/freshrss-api.sh").toString().replace("file://", "")

    property string mode: "rss"       // rss | fever
    property bool writable: false
    property bool loading: false
    property string statusMsg: ""
    property string errorMsg: ""
    property var items: []
    property int selectedIndex: -1
    // note: unreadCount / loadedCount declared with filter defaults below
    property string filterMode: "all" // all | video  (content type)
    // Defaults: All (read + unread) with all dates, categories start collapsed.
    // "Today" is available as a date chip when you want a tighter view.
    property string readScope: "all"  // unread | all | read | saved
    property string dateFilter: "all" // all | today | week
    property string searchQuery: ""

    // How many articles to pull (adjustable in the window UI)
    // - perFeedLimit: All/Read scopes (per channel)
    // - itemLimit: Unread/Starred scopes (total ids)
    property int perFeedLimit: th.freshRssPerFeedLimit || 12
    property int itemLimit: th.freshRssItemLimit || 80
    readonly property var perFeedChoices: [5, 8, 10, 12, 15, 20, 25, 30]
    readonly property var itemLimitChoices: [20, 40, 50, 80, 100, 150, 200]

    // Collapsed category titles → true. Reassign whole object + bump version so listRows rebinds.
    property var collapsedCategories: ({})
    property int collapseVersion: 0
    // After each successful fetch, re-collapse categories (fresh session start behavior).
    property bool autoCollapseOnLoad: true

    // Unread badge + per-feed maps from FreshRSS (GReader unread-count)
    property int unreadCount: 0
    property int loadedCount: 0
    property var feedUnreadById: ({})    // "16" → 10
    property var feedUnreadByTitle: ({}) // "Alex Jones Live" → 10
    property int countsVersion: 0        // bump when maps change (listRows rebind)

    function serverUnreadForCategory(cat, feedId) {
        const _ = countsVersion
        const titles = feedUnreadByTitle || ({})
        if (cat && titles[cat] !== undefined && titles[cat] !== null)
            return Math.max(0, Number(titles[cat]) || 0)
        const ids = feedUnreadById || ({})
        if (feedId !== undefined && feedId !== null && feedId !== "") {
            const k = String(feedId)
            if (ids[k] !== undefined && ids[k] !== null)
                return Math.max(0, Number(ids[k]) || 0)
        }
        return -1  // unknown (not from server)
    }

    /** Unread among currently loaded+filtered items for a category (fallback / date rows). */
    function loadedUnreadInList(itemList) {
        let n = 0
        for (let i = 0; i < itemList.length; i++) {
            if (Number(itemList[i].is_read) !== 1)
                n++
        }
        return n
    }

    readonly property string viewStatusText: {
        const shown = filteredItems.length
        const loaded = loadedCount || items.length
        let loadedUnread = 0
        let loadedRead = 0
        for (let i = 0; i < filteredItems.length; i++) {
            if (Number(filteredItems[i].is_read) === 1)
                loadedRead++
            else
                loadedUnread++
        }
        const parts = []
        parts.push(readScope)
        parts.push(dateFilter === "today" ? "today" : (dateFilter === "week" ? "7d" : "all dates"))
        // FreshRSS-accurate global unread first
        parts.push(unreadCount + " unread")
        // What's visible in the current filter
        parts.push(shown + " shown")
        if (shown > 0)
            parts.push(loadedUnread + "u/" + loadedRead + "r in view")
        if (loaded !== shown)
            parts.push(loaded + " loaded")
        if (readScope === "all" || readScope === "read")
            parts.push(perFeedLimit + "/feed")
        else
            parts.push("max " + itemLimit)
        return parts.join(" · ")
    }

    readonly property var selectedItem: {
        if (selectedIndex < 0 || selectedIndex >= items.length)
            return null
        return items[selectedIndex]
    }

    // Flat article list after search / date / video filters, newest first.
    // Keep this cheap: items may be hundreds; avoid scanning full HTML bodies.
    readonly property var filteredItems: {
        const q = (searchQuery || "").trim().toLowerCase()
        const wantVideo = filterMode === "video"
        const df = dateFilter
        let startToday = 0
        let startWeek = 0
        if (df === "today" || df === "week") {
            const now = new Date()
            startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000
            if (df === "week")
                startWeek = startToday - 6 * 86400
        }

        const src = items
        const n = src.length
        const list = []
        for (let i = 0; i < n; i++) {
            const it = src[i]
            if (wantVideo) {
                // Prefer precomputed flag from the API; fall back for older payloads.
                if (Number(it.is_video) !== 1 && !itemIsVideo(it))
                    continue
            }
            if (df === "today") {
                if (Number(it.created_on_time || 0) < startToday)
                    continue
            } else if (df === "week") {
                if (Number(it.created_on_time || 0) < startWeek)
                    continue
            }
            if (q.length > 0) {
                // Metadata only (not full body text) — much cheaper for large lists
                const blob = (
                    String(it.title || "") + "\n" +
                    String(it.author || "") + "\n" +
                    String(it.feed_title || "") + "\n" +
                    String(it.group_title || "") + "\n" +
                    String(it.category || "") + "\n" +
                    String(it.summary || "")
                ).toLowerCase()
                if (blob.indexOf(q) < 0)
                    continue
            }
            list.push(it)
        }
        list.sort((a, b) => Number(b.created_on_time || 0) - Number(a.created_on_time || 0))
        return list
    }

    // Date sub-group collapse: key = "category\x1fYYYY-MM-DD" → true when collapsed
    property var collapsedDates: ({})

    function dateKeyForEpoch(epoch) {
        const e = Number(epoch || 0)
        if (e <= 0)
            return "unknown"
        const d = new Date(e * 1000)
        const y = d.getFullYear()
        const m = String(d.getMonth() + 1).padStart(2, "0")
        const day = String(d.getDate()).padStart(2, "0")
        return y + "-" + m + "-" + day
    }

    function dateLabelForKey(key, epoch) {
        if (!key || key === "unknown")
            return "Unknown date"
        const now = new Date()
        const todayKey = dateKeyForEpoch(Math.floor(now.getTime() / 1000))
        const yest = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
        const yestKey = dateKeyForEpoch(Math.floor(yest.getTime() / 1000))
        if (key === todayKey)
            return "Today"
        if (key === yestKey)
            return "Yesterday"
        const e = Number(epoch || 0)
        if (e > 0)
            return Qt.formatDateTime(new Date(e * 1000), "ddd, MMM d, yyyy")
        // parse key yyyy-MM-dd
        const parts = key.split("-")
        if (parts.length === 3) {
            const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
            return Qt.formatDateTime(d, "ddd, MMM d, yyyy")
        }
        return key
    }

    function dateCollapseKey(cat, dateKey) {
        return String(cat) + "\x1f" + String(dateKey)
    }

    // Sectioned rows: feed header → (when open) date subheaders → articles
    readonly property var listRows: {
        const _tick = collapseVersion  // dependency for collapse toggles
        const _counts = countsVersion  // rebind when FreshRSS unread maps update
        const list = filteredItems
        const collapsed = collapsedCategories || ({})
        const collapsedDt = collapsedDates || ({})
        const byCat = ({})
        for (let i = 0; i < list.length; i++) {
            const it = list[i]
            const cat = (it.category || it.feed_title || "Other").toString()
            if (!byCat[cat])
                byCat[cat] = []
            byCat[cat].push(it)
        }
        const cats = Object.keys(byCat)
        // Category headers A–Z
        cats.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }))
        const rows = []
        for (let c = 0; c < cats.length; c++) {
            const cat = cats[c]
            const itemsIn = byCat[cat]
            const isCollapsed = !!collapsed[cat]
            const sampleFid = itemsIn[0] ? itemsIn[0].feed_id : ""
            const srvUnread = serverUnreadForCategory(cat, sampleFid)
            const loadedUnread = loadedUnreadInList(itemsIn)
            const loadedRead = itemsIn.length - loadedUnread
            rows.push({
                kind: "header",
                category: cat,
                // FreshRSS-style unread (server); fall back to loaded unread
                unread: srvUnread >= 0 ? srvUnread : loadedUnread,
                read: loadedRead,
                shown: itemsIn.length,
                count: srvUnread >= 0 ? srvUnread : loadedUnread,
                collapsed: isCollapsed,
                id: "hdr:" + cat
            })
            if (isCollapsed)
                continue

            // Sub-group by calendar date (newest dates first)
            const byDate = ({})
            for (let j = 0; j < itemsIn.length; j++) {
                const it = itemsIn[j]
                const dk = dateKeyForEpoch(it.created_on_time)
                if (!byDate[dk])
                    byDate[dk] = []
                byDate[dk].push(it)
            }
            const dateKeys = Object.keys(byDate)
            dateKeys.sort((a, b) => {
                // unknown last; otherwise newest date first (string yyyy-MM-dd sorts lexically)
                if (a === "unknown")
                    return 1
                if (b === "unknown")
                    return -1
                return b.localeCompare(a)
            })

            for (let d = 0; d < dateKeys.length; d++) {
                const dk = dateKeys[d]
                const dayItems = byDate[dk]
                // newest articles first within the day
                dayItems.sort((a, b) => Number(b.created_on_time || 0) - Number(a.created_on_time || 0))
                const dKey = dateCollapseKey(cat, dk)
                const dateCollapsed = !!collapsedDt[dKey]
                const sampleEpoch = dayItems[0] ? dayItems[0].created_on_time : 0
                const dayUnread = loadedUnreadInList(dayItems)
                const dayRead = dayItems.length - dayUnread
                rows.push({
                    kind: "date",
                    category: cat,
                    dateKey: dk,
                    dateLabel: dateLabelForKey(dk, sampleEpoch),
                    unread: dayUnread,
                    read: dayRead,
                    shown: dayItems.length,
                    count: dayUnread,
                    collapsed: dateCollapsed,
                    id: "date:" + dKey
                })
                if (dateCollapsed)
                    continue
                for (let k = 0; k < dayItems.length; k++) {
                    const it = dayItems[k]
                    rows.push({
                        kind: "item",
                        id: it.id,
                        item: it,
                        category: cat,
                        dateKey: dk
                    })
                }
            }
        }
        return rows
    }

    function isCategoryCollapsed(cat) {
        return !!(collapsedCategories && collapsedCategories[cat])
    }

    function toggleCategory(cat) {
        if (!cat)
            return
        const next = ({})
        const cur = collapsedCategories || ({})
        const keys = Object.keys(cur)
        for (let i = 0; i < keys.length; i++)
            next[keys[i]] = cur[keys[i]]
        if (next[cat])
            delete next[cat]
        else
            next[cat] = true
        collapsedCategories = next
        collapseVersion++
    }

    function toggleDateGroup(cat, dateKey) {
        if (!cat || !dateKey)
            return
        const key = dateCollapseKey(cat, dateKey)
        const next = ({})
        const cur = collapsedDates || ({})
        const keys = Object.keys(cur)
        for (let i = 0; i < keys.length; i++)
            next[keys[i]] = cur[keys[i]]
        if (next[key])
            delete next[key]
        else
            next[key] = true
        collapsedDates = next
        collapseVersion++
    }

    function expandAllCategories() {
        collapsedCategories = ({})
        collapsedDates = ({})
        collapseVersion++
    }

    function collapseAllCategories() {
        // Collapse every category present in the current item set (pre-date-filter),
        // so headers still show even when "Today" hides some feeds' rows until expanded.
        const list = items.length ? items : filteredItems
        const next = ({})
        for (let i = 0; i < list.length; i++) {
            const cat = (list[i].category || list[i].feed_title || "Other").toString()
            next[cat] = true
        }
        collapsedCategories = next
        // leave date collapse state; irrelevant while feeds are closed
        collapseVersion++
    }

    Layout.preferredWidth: Math.max(42, pillInner.implicitWidth + 16)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    radius: bar.pillRadius
    color: pillMouse.containsMouse || readerWindow.visible ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: (pillMouse.containsMouse || readerWindow.visible) ? bar.accent : bar.pillBorder

    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

    function toggle() {
        if (readerWindow.visible)
            hide()
        else
            show()
    }

    function show() {
        readerWindow.visible = true
        refresh()
    }

    function hide() {
        readerWindow.visible = false
    }

    function refresh() {
        loadItems()
        pollStatus()
    }

    function pollStatus() {
        if (statusProcess.running)
            statusProcess.running = false
        statusProcess.command = [apiScript, "status"]
        statusProcess.running = true
    }

    function loadItems() {
        loading = true
        errorMsg = ""
        if (itemsProcess.running)
            itemsProcess.running = false
        // scope: unread | all | read | saved — see scripts/freshrss-api.sh
        // 4th arg: per-feed count for All/Read (ensures every channel is represented)
        itemsProcess.command = [
            apiScript, "items",
            String(root.itemLimit),
            root.readScope || "all",
            String(root.perFeedLimit)
        ]
        itemsProcess.running = true
    }

    function setReadScope(scope) {
        if (!scope)
            return
        // "All" = every feed, read + unread. Clear a "Today" date filter so quiet
        // channels (Dark Journalist, David Bombal, …) are not hidden when they
        // have no posts today.
        if (scope === "all" && dateFilter === "today")
            dateFilter = "all"
        if (scope === readScope) {
            // Still reload if user re-clicks All after changing other filters
            if (scope === "all")
                loadItems()
            return
        }
        readScope = scope
        loadItems()
    }

    function setPerFeedLimit(n) {
        const v = Math.max(1, Math.min(40, Number(n) || 12))
        if (v === perFeedLimit)
            return
        perFeedLimit = v
        if (readScope === "all" || readScope === "read")
            loadItems()
    }

    function setItemLimit(n) {
        const v = Math.max(5, Math.min(500, Number(n) || 80))
        if (v === itemLimit)
            return
        itemLimit = v
        if (readScope === "unread" || readScope === "saved")
            loadItems()
    }

    function nudgePerFeed(delta) {
        const choices = perFeedChoices
        let idx = choices.indexOf(perFeedLimit)
        if (idx < 0) {
            // snap to nearest
            idx = 0
            for (let i = 0; i < choices.length; i++) {
                if (choices[i] >= perFeedLimit) {
                    idx = i
                    break
                }
                idx = i
            }
        }
        idx = Math.max(0, Math.min(choices.length - 1, idx + delta))
        setPerFeedLimit(choices[idx])
    }

    function nudgeItemLimit(delta) {
        const choices = itemLimitChoices
        let idx = choices.indexOf(itemLimit)
        if (idx < 0) {
            idx = 0
            for (let i = 0; i < choices.length; i++) {
                if (choices[i] >= itemLimit) {
                    idx = i
                    break
                }
                idx = i
            }
        }
        idx = Math.max(0, Math.min(choices.length - 1, idx + delta))
        setItemLimit(choices[idx])
    }

    function isVideoUrl(url) {
        if (!url)
            return false
        const u = String(url).toLowerCase()
        return u.indexOf("youtube.com") >= 0
            || u.indexOf("youtu.be") >= 0
            || u.indexOf("youtube-nocookie.com") >= 0
            || u.indexOf("/shorts/") >= 0
            || u.indexOf("vimeo.com") >= 0
            || u.indexOf("twitch.tv") >= 0
            || /\.(m4v|mp4|webm|mkv)(\?|$)/i.test(u)
    }

    function itemIsVideo(it) {
        if (!it)
            return false
        if (Number(it.is_video) === 1)
            return true
        return isVideoUrl(it.media_url) || isVideoUrl(it.url)
            || /youtube/i.test(String(it.feed_title || ""))
            || /youtube/i.test(String(it.group_title || ""))
    }

    function playableUrl(it) {
        if (!it)
            return ""
        if (it.media_url && String(it.media_url).length > 0)
            return it.media_url
        return it.url || ""
    }

    function selectItemById(id) {
        if (id === undefined || id === null) {
            selectedIndex = -1
            return
        }
        const sid = String(id)
        for (let j = 0; j < items.length; j++) {
            if (String(items[j].id) === sid) {
                selectedIndex = j
                return
            }
        }
        selectedIndex = -1
    }

    function selectIndex(i) {
        // i is index into filteredItems (article-only, not section headers)
        if (i < 0 || i >= filteredItems.length) {
            selectedIndex = -1
            return
        }
        selectItemById(filteredItems[i].id)
    }

    function selectRelative(delta) {
        if (filteredItems.length === 0)
            return
        let fi = 0
        if (selectedItem) {
            for (let i = 0; i < filteredItems.length; i++) {
                if (String(filteredItems[i].id) === String(selectedItem.id)) {
                    fi = i
                    break
                }
            }
        }
        fi = Math.max(0, Math.min(filteredItems.length - 1, fi + delta))
        selectIndex(fi)
    }

    function openBrowser() {
        const it = selectedItem
        if (!it || !it.url)
            return
        runAction(["open-browser", it.url])
    }

    function playMpv() {
        const it = selectedItem
        if (!it)
            return
        const url = playableUrl(it)
        if (!url)
            return
        statusMsg = "Starting mpv…"
        runAction(["play-mpv", url])
    }

    function openOrPlayUrl(url) {
        if (!url)
            return
        if (isVideoUrl(url)) {
            statusMsg = "Starting mpv…"
            runAction(["play-mpv", url])
        } else {
            runAction(["open-browser", url])
        }
    }

    function activateItem(it) {
        if (!it)
            return
        selectItemById(it.id)
        if (itemIsVideo(it))
            playMpv()
        else
            openBrowser()
    }

    function markRead() {
        if (!writable || !selectedItem)
            return
        runAction(["mark-read", String(selectedItem.id)])
    }

    function starItem() {
        if (!writable || !selectedItem)
            return
        const act = Number(selectedItem.is_saved) === 1 ? "unstar" : "star"
        runAction([act, String(selectedItem.id)])
    }

    function runAction(args) {
        if (actionProcess.running)
            actionProcess.running = false
        actionProcess.command = [apiScript].concat(args)
        actionProcess.running = true
    }

    function formatTime(epoch) {
        if (!epoch || epoch <= 0)
            return ""
        const d = new Date(epoch * 1000)
        return Qt.formatDateTime(d, "MMM d  HH:mm")
    }

    function bodyHtml(it) {
        if (!it)
            return ""
        // Prefer HTML; Qt RichText is limited but good enough for simple feeds
        const raw = it.html || ""
        if (raw.length > 0)
            return raw
        return (it.text || "").replace(/\n/g, "<br/>")
    }

    // ── Pill face ───────────────────────────────────────────────────────────
    Row {
        id: pillInner
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰑫"   // RSS-ish nerd font glyph; fallback below if missing
            color: bar.accent
            font.pixelSize: bar.iconSizePillLarge || 16
            font.family: bar.fontFamily
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.unreadCount > 0 ? (root.unreadCount > 99 ? "99+" : String(root.unreadCount)) : "RSS"
            color: bar.text
            font.pixelSize: bar.fontTiny || 11
            font.family: bar.fontMono
            font.bold: root.unreadCount > 0
        }
    }

    MouseArea {
        id: pillMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
    }

    // Background status poll (badge)
    Timer {
        interval: th.freshRssPollIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollStatus()
    }

    Io.Process {
        id: statusProcess
        stdout: Io.StdioCollector {
            onStreamFinished: {
                const line = (text || "").trim()
                if (!line.startsWith("{"))
                    return
                try {
                    const j = JSON.parse(line)
                    if (j.ok === false) {
                        root.errorMsg = j.error || "status failed"
                        return
                    }
                    // Prefer explicit unread field; never treat "items loaded" as unread
                    if (j.unread !== undefined)
                        root.unreadCount = Math.max(0, Number(j.unread) || 0)
                    else if (j.count !== undefined && j.mode)
                        root.unreadCount = Math.max(0, Number(j.count) || 0)
                    if (j.mode)
                        root.mode = j.mode
                    if (j.writable !== undefined)
                        root.writable = !!j.writable
                    // Per-feed / per-title unread (FreshRSS sidebar)
                    if (j.feeds && typeof j.feeds === "object")
                        root.feedUnreadById = j.feeds
                    if (j.titles && typeof j.titles === "object")
                        root.feedUnreadByTitle = j.titles
                    root.countsVersion++
                } catch (e) {}
            }
        }
    }

    Io.Process {
        id: itemsProcess
        stdout: Io.StdioCollector {
            onStreamFinished: {
                root.loading = false
                const line = (text || "").trim()
                if (!line.startsWith("{")) {
                    root.errorMsg = "invalid items response"
                    return
                }
                try {
                    const j = JSON.parse(line)
                    if (j.ok === false) {
                        root.errorMsg = j.error || "items failed"
                        return
                    }
                    root.mode = j.mode || root.mode
                    root.writable = !!j.writable
                    // Do NOT overwrite unreadCount with loaded item count.
                    // Refresh true unread from status after load.
                    const list = j.items || []
                    root.items = list
                    root.loadedCount = list.length
                    root.statusMsg = root.viewStatusText
                    root.pollStatus()
                    // Start collapsed so you open only the feeds you care about
                    if (root.autoCollapseOnLoad)
                        root.collapseAllCategories()
                    // keep selection if possible
                    if (root.selectedItem) {
                        const sid = root.selectedItem.id
                        let found = -1
                        for (let i = 0; i < list.length; i++) {
                            if (list[i].id === sid) {
                                found = i
                                break
                            }
                        }
                        root.selectedIndex = found
                    } else if (list.length > 0) {
                        root.selectedIndex = 0
                    }
                    root.errorMsg = ""
                } catch (e) {
                    root.errorMsg = "parse error"
                }
            }
        }
        stderr: Io.StdioCollector {
            onStreamFinished: {
                if ((text || "").trim().length > 0 && root.loading)
                    root.errorMsg = text.trim().slice(0, 200)
            }
        }
    }

    Io.Process {
        id: actionProcess
        stdout: Io.StdioCollector {
            onStreamFinished: {
                const line = (text || "").trim()
                if (!line.startsWith("{"))
                    return
                try {
                    const j = JSON.parse(line)
                    if (j.ok === false) {
                        root.statusMsg = j.error || "action failed"
                        return
                    }
                    if (j.as === "read" || j.as === "saved" || j.as === "unsaved" || j.as === "unread")
                        root.loadItems()
                    else if (j.action === "mpv")
                        root.statusMsg = "Playing in mpv…"
                    else if (j.action === "browser")
                        root.statusMsg = "Opened in browser"
                } catch (e) {}
            }
        }
    }

    // ── Reader window ───────────────────────────────────────────────────────
    FloatingWindow {
        id: readerWindow
        visible: false
        title: "FreshRSS"
        color: "transparent"
        implicitWidth: th.freshRssWidth
        implicitHeight: th.freshRssHeight
        minimumSize: Qt.size(th.freshRssMinWidth, th.freshRssMinHeight)

        onClosed: root.hide()

        Shortcut {
            sequence: "Escape"
            enabled: readerWindow.visible
            onActivated: root.hide()
        }
        Shortcut {
            sequence: "Ctrl+R"
            enabled: readerWindow.visible
            onActivated: root.refresh()
        }
        Shortcut {
            sequence: "R"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.refresh()
        }
        Shortcut {
            sequence: "Ctrl+F"
            enabled: readerWindow.visible
            onActivated: searchField.forceActiveFocus()
        }
        Shortcut {
            sequence: "/"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: searchField.forceActiveFocus()
        }
        Shortcut {
            sequence: "J"
            enabled: readerWindow.visible
            onActivated: root.selectRelative(1)
        }
        Shortcut {
            sequence: "K"
            enabled: readerWindow.visible
            onActivated: root.selectRelative(-1)
        }
        Shortcut {
            sequence: "O"
            enabled: readerWindow.visible
            onActivated: root.openBrowser()
        }
        Shortcut {
            sequence: "V"
            enabled: readerWindow.visible
            onActivated: root.playMpv()
        }
        Shortcut {
            sequence: "M"
            enabled: readerWindow.visible && root.writable
            onActivated: root.markRead()
        }
        Shortcut {
            sequence: "S"
            enabled: readerWindow.visible && root.writable
            onActivated: root.starItem()
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: th.popupRadiusLarge || 12
            color: th.inspWindowBg || bar.glassPopupBg
            border.width: 1
            border.color: th.inspWindowBorder || bar.glassPopupBorder
            focus: readerWindow.visible

            // top highlight
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
                anchors.margins: 14
                spacing: 10

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "FreshRSS"
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
                        implicitWidth: modeLabel.implicitWidth + 14
                        Text {
                            id: modeLabel
                            anchors.centerIn: parent
                            text: root.mode === "fever"
                                  ? (root.writable ? "Fever · read/write" : "Fever")
                                  : "RSS · read-only"
                            color: bar.accent
                            font.pixelSize: 11
                            font.family: bar.fontMono
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.loading
                              ? "Loading…"
                              : (root.errorMsg || root.viewStatusText)
                        color: root.errorMsg ? "#e06c75" : bar.subtext
                        font.pixelSize: 12
                        font.family: bar.fontMono
                        elide: Text.ElideRight
                        Layout.maximumWidth: 420
                    }

                    Rectangle {
                        radius: 6
                        implicitHeight: 28
                        implicitWidth: refreshTxt.implicitWidth + 18
                        color: refreshMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        Text {
                            id: refreshTxt
                            anchors.centerIn: parent
                            text: "Refresh"
                            color: bar.text
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: refreshMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh()
                        }
                    }
                }

                // Search + filters row
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
                                onTextChanged: root.searchQuery = text

                                Text {
                                    anchors.fill: parent
                                    visible: !searchField.text && !searchField.activeFocus
                                    text: "Search title, feed, author…"
                                    color: bar.subtext
                                    font.pixelSize: 13
                                }
                            }
                            Text {
                                visible: searchField.text.length > 0
                                text: "✕"
                                color: bar.subtext
                                font.pixelSize: 12
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchField.text = ""
                                        root.searchQuery = ""
                                    }
                                }
                            }
                        }
                    }

                    // Date chips
                    Repeater {
                        model: [
                            { id: "all", label: "All dates" },
                            { id: "today", label: "Today" },
                            { id: "week", label: "7 days" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            radius: 6
                            implicitHeight: 28
                            implicitWidth: dateTxt.implicitWidth + 14
                            color: root.dateFilter === modelData.id
                                   ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                                   : (dateMa.containsMouse ? bar.iconHoverBg : "transparent")
                            border.width: 1
                            border.color: root.dateFilter === modelData.id ? bar.accent : bar.pillBorder
                            Text {
                                id: dateTxt
                                anchors.centerIn: parent
                                text: modelData.label
                                color: bar.text
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: dateMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.dateFilter = modelData.id
                            }
                        }
                    }

                    // Read state scope (server fetch)
                    Repeater {
                        model: [
                            { id: "unread", label: "Unread" },
                            { id: "all", label: "All" },
                            { id: "read", label: "Read" },
                            { id: "saved", label: "Starred" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            radius: 6
                            implicitHeight: 28
                            implicitWidth: scopeTxt.implicitWidth + 14
                            color: root.readScope === modelData.id
                                   ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                                   : (scopeMa.containsMouse ? bar.iconHoverBg : "transparent")
                            border.width: 1
                            border.color: root.readScope === modelData.id ? bar.accent : bar.pillBorder
                            Text {
                                id: scopeTxt
                                anchors.centerIn: parent
                                text: modelData.label
                                color: bar.text
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: scopeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setReadScope(modelData.id)
                            }
                        }
                    }

                    // Type chips (client filter on current list)
                    Repeater {
                        model: [
                            { id: "all", label: "Any type" },
                            { id: "video", label: "Video" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            radius: 6
                            implicitHeight: 28
                            implicitWidth: typeTxt.implicitWidth + 14
                            color: root.filterMode === modelData.id
                                   ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                                   : (typeMa.containsMouse ? bar.iconHoverBg : "transparent")
                            border.width: 1
                            border.color: root.filterMode === modelData.id ? bar.accent : bar.pillBorder
                            Text {
                                id: typeTxt
                                anchors.centerIn: parent
                                text: modelData.label
                                color: bar.text
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: typeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.filterMode = modelData.id
                            }
                        }
                    }

                    // Expand / collapse all categories
                    Rectangle {
                        radius: 6
                        implicitHeight: 28
                        implicitWidth: foldTxt.implicitWidth + 14
                        color: foldMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        Text {
                            id: foldTxt
                            anchors.centerIn: parent
                            text: "Collapse all"
                            color: bar.text
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: foldMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.collapseAllCategories()
                        }
                    }
                    Rectangle {
                        radius: 6
                        implicitHeight: 28
                        implicitWidth: expandTxt.implicitWidth + 14
                        color: expandMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        Text {
                            id: expandTxt
                            anchors.centerIn: parent
                            text: "Expand all"
                            color: bar.text
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: expandMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.expandAllCategories()
                        }
                    }
                }

                // Amount controls: how many articles to download
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: (root.readScope === "all" || root.readScope === "read")
                              ? "Per feed:"
                              : "Max items:"
                        color: bar.subtext
                        font.pixelSize: 12
                    }

                    // − button
                    Rectangle {
                        radius: 6
                        implicitWidth: 28
                        implicitHeight: 28
                        color: minusMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        Text {
                            anchors.centerIn: parent
                            text: "−"
                            color: bar.text
                            font.pixelSize: 16
                            font.bold: true
                        }
                        MouseArea {
                            id: minusMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.readScope === "all" || root.readScope === "read")
                                    root.nudgePerFeed(-1)
                                else
                                    root.nudgeItemLimit(-1)
                            }
                        }
                    }

                    Text {
                        text: (root.readScope === "all" || root.readScope === "read")
                              ? String(root.perFeedLimit)
                              : String(root.itemLimit)
                        color: bar.text
                        font.pixelSize: 13
                        font.bold: true
                        font.family: bar.fontMono
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // + button
                    Rectangle {
                        radius: 6
                        implicitWidth: 28
                        implicitHeight: 28
                        color: plusMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: bar.text
                            font.pixelSize: 16
                            font.bold: true
                        }
                        MouseArea {
                            id: plusMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.readScope === "all" || root.readScope === "read")
                                    root.nudgePerFeed(1)
                                else
                                    root.nudgeItemLimit(1)
                            }
                        }
                    }

                    // Quick presets for current mode
                    Repeater {
                        model: (root.readScope === "all" || root.readScope === "read")
                               ? [5, 10, 12, 15, 20, 30]
                               : [20, 50, 80, 100, 150]
                        delegate: Rectangle {
                            required property var modelData
                            radius: 6
                            implicitHeight: 26
                            implicitWidth: presetTxt.implicitWidth + 12
                            readonly property bool active: {
                                if (root.readScope === "all" || root.readScope === "read")
                                    return root.perFeedLimit === modelData
                                return root.itemLimit === modelData
                            }
                            color: active
                                   ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                                   : (presetMa.containsMouse ? bar.iconHoverBg : "transparent")
                            border.width: 1
                            border.color: active ? bar.accent : bar.pillBorder
                            Text {
                                id: presetTxt
                                anchors.centerIn: parent
                                text: String(modelData)
                                color: bar.text
                                font.pixelSize: 11
                                font.family: bar.fontMono
                            }
                            MouseArea {
                                id: presetMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.readScope === "all" || root.readScope === "read")
                                        root.setPerFeedLimit(modelData)
                                    else
                                        root.setItemLimit(modelData)
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: (root.readScope === "all" || root.readScope === "read")
                              ? "articles downloaded from each feed"
                              : "total for Unread / Starred"
                        color: bar.subtext
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                // Body split
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    // List (grouped by feed/category title, newest sections & items on top)
                    Rectangle {
                        Layout.preferredWidth: th.freshRssListWidth
                        Layout.fillHeight: true
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.18)
                        border.width: 1
                        border.color: bar.divider || bar.pillBorder

                        ListView {
                            id: listView
                            anchors.fill: parent
                            anchors.margins: 4
                            clip: true
                            spacing: 2
                            model: root.listRows
                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            delegate: Rectangle {
                                id: rowDelegate
                                required property var modelData
                                required property int index
                                width: listView.width
                                readonly property bool isHeader: modelData.kind === "header"
                                readonly property bool isDate: modelData.kind === "date"
                                readonly property bool isItem: modelData.kind === "item"
                                readonly property var art: isItem ? (modelData.item || null) : null
                                height: isHeader ? 28 : (isDate ? 24 : (titleCol.implicitHeight + 14))
                                radius: isHeader ? 4 : (isDate ? 3 : 6)
                                color: {
                                    if (isHeader)
                                        return Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.12)
                                    if (isDate)
                                        return Qt.rgba(1, 1, 1, 0.04)
                                    const sel = root.selectedItem && art && String(root.selectedItem.id) === String(art.id)
                                    if (sel)
                                        return Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.22)
                                    return rowMa.containsMouse ? (th.inspRowHoverBg || bar.iconHoverBg) : "transparent"
                                }
                                border.width: (isItem && root.selectedItem && art && String(root.selectedItem.id) === String(art.id)) ? 1 : 0
                                border.color: bar.accent

                                // Feed category header (click to collapse / expand)
                                RowLayout {
                                    visible: rowDelegate.isHeader
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Text {
                                        text: modelData.collapsed ? "▸" : "▾"
                                        color: bar.accent
                                        font.pixelSize: 13
                                        font.bold: true
                                        Layout.preferredWidth: 14
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.category || "Other"
                                        color: bar.accent
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    // FreshRSS sidebar style: primary number = unread on server
                                    Text {
                                        text: String(Number(modelData.unread || 0))
                                        color: Number(modelData.unread || 0) > 0 ? bar.accent : bar.subtext
                                        font.pixelSize: 11
                                        font.bold: Number(modelData.unread || 0) > 0
                                        font.family: bar.fontMono
                                    }
                                    // Optional: how many of this feed are in the current window
                                    Text {
                                        visible: Number(modelData.shown || 0) > 0
                                        text: "·" + String(modelData.shown || 0)
                                        color: bar.overlay || bar.subtext
                                        font.pixelSize: 10
                                        font.family: bar.fontMono
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    visible: rowDelegate.isHeader
                                    enabled: rowDelegate.isHeader
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleCategory(modelData.category || "Other")
                                }

                                // Date sub-header under an open feed (click to collapse that day)
                                RowLayout {
                                    visible: rowDelegate.isDate
                                    anchors.fill: parent
                                    anchors.leftMargin: 22
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Text {
                                        text: modelData.collapsed ? "▸" : "▾"
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        Layout.preferredWidth: 12
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.dateLabel || modelData.dateKey || "Date"
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    // unread / total for that day (from loaded list)
                                    Text {
                                        text: {
                                            const u = Number(modelData.unread || 0)
                                            const s = Number(modelData.shown || 0)
                                            if (u > 0 && s > 0 && u !== s)
                                                return u + "/" + s
                                            if (u > 0)
                                                return String(u)
                                            return String(s)
                                        }
                                        color: Number(modelData.unread || 0) > 0 ? bar.accent : (bar.overlay || bar.subtext)
                                        font.pixelSize: 10
                                        font.bold: Number(modelData.unread || 0) > 0
                                        font.family: bar.fontMono
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    visible: rowDelegate.isDate
                                    enabled: rowDelegate.isDate
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleDateGroup(modelData.category, modelData.dateKey)
                                }

                                // Article content (indented under date)
                                Column {
                                    id: titleCol
                                    visible: rowDelegate.isItem
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 28
                                    anchors.rightMargin: 8
                                    spacing: 2

                                    RowLayout {
                                        width: parent.width
                                        spacing: 6
                                        Text {
                                            visible: rowDelegate.art && root.itemIsVideo(rowDelegate.art)
                                            text: "▶"
                                            color: bar.accent
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (rowDelegate.art && rowDelegate.art.title) ? rowDelegate.art.title : "(no title)"
                                            color: bar.text
                                            font.pixelSize: 13
                                            font.bold: rowDelegate.art ? Number(rowDelegate.art.is_read) !== 1 : false
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                            maximumLineCount: 2
                                        }
                                    }
                                    Text {
                                        width: parent.width
                                        text: {
                                            if (!rowDelegate.art)
                                                return ""
                                            const g = rowDelegate.art.group_title || ""
                                            const t = root.formatTime(rowDelegate.art.created_on_time)
                                            if (g && t)
                                                return g + " · " + t
                                            return t || g || ""
                                        }
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: rowMa
                                    anchors.fill: parent
                                    visible: rowDelegate.isItem
                                    hoverEnabled: rowDelegate.isItem
                                    enabled: rowDelegate.isItem
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (rowDelegate.art)
                                            root.selectItemById(rowDelegate.art.id)
                                    }
                                    onDoubleClicked: {
                                        if (rowDelegate.art)
                                            root.activateItem(rowDelegate.art)
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !root.loading && root.filteredItems.length === 0
                                text: root.errorMsg || "No matching items"
                                color: bar.subtext
                                font.pixelSize: 13
                            }
                        }
                    }

                    // Detail
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.12)
                        border.width: 1
                        border.color: bar.divider || bar.pillBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: root.selectedItem ? (root.selectedItem.title || "") : "Select an article"
                                color: bar.text
                                font.pixelSize: 16
                                font.bold: true
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!root.selectedItem
                                text: {
                                    const it = root.selectedItem
                                    if (!it)
                                        return ""
                                    const bits = []
                                    if (it.feed_title)
                                        bits.push(it.feed_title)
                                    if (it.author)
                                        bits.push(it.author)
                                    const t = root.formatTime(it.created_on_time)
                                    if (t)
                                        bits.push(t)
                                    return bits.join(" · ")
                                }
                                color: bar.subtext
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            // Actions
                            Flow {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: !!root.selectedItem

                                Repeater {
                                    model: {
                                        const it = root.selectedItem
                                        if (!it)
                                            return []
                                        const acts = [
                                            { id: "browser", label: "Open in browser", enabled: !!(it.url) },
                                            {
                                                id: "mpv",
                                                label: root.itemIsVideo(it) ? "Play in mpv" : "Play URL in mpv",
                                                enabled: !!(root.playableUrl(it))
                                            },
                                        ]
                                        if (root.writable) {
                                            acts.push({ id: "read", label: "Mark read", enabled: true })
                                            acts.push({
                                                id: "star",
                                                label: Number(it.is_saved) === 1 ? "Unstar" : "Star",
                                                enabled: true
                                            })
                                        }
                                        return acts
                                    }
                                    delegate: Rectangle {
                                        required property var modelData
                                        radius: 6
                                        implicitHeight: 28
                                        implicitWidth: actTxt.implicitWidth + 18
                                        opacity: modelData.enabled ? 1 : 0.4
                                        color: actMa.containsMouse && modelData.enabled
                                               ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.25)
                                               : "transparent"
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: actTxt
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: bar.text
                                            font.pixelSize: 12
                                        }
                                        MouseArea {
                                            id: actMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: modelData.enabled
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.id === "browser")
                                                    root.openBrowser()
                                                else if (modelData.id === "mpv")
                                                    root.playMpv()
                                                else if (modelData.id === "read")
                                                    root.markRead()
                                                else if (modelData.id === "star")
                                                    root.starItem()
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: bar.divider || bar.pillBorder
                                visible: !!root.selectedItem
                            }

                            Flickable {
                                id: bodyFlick
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentWidth: width
                                contentHeight: bodyText.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                Text {
                                    id: bodyText
                                    width: bodyFlick.width - 4
                                    textFormat: Text.RichText
                                    wrapMode: Text.Wrap
                                    color: bar.text
                                    font.pixelSize: 13
                                    font.family: bar.fontFamily
                                    text: root.selectedItem ? root.bodyHtml(root.selectedItem) : ""
                                    onLinkActivated: (link) => {
                                        // YouTube / video links → mpv; everything else → browser
                                        root.openOrPlayUrl(link)
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !root.writable
                                text: "Read-only (anonymous RSS). To mark read/star: log into FreshRSS → Profile → set API password, then put it in secrets/freshrss.env as FRESHRSS_API_PASSWORD."
                                color: bar.subtext
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // Footer shortcuts
                Text {
                    Layout.fillWidth: true
                    text: "Feed ▾ → date groups · click date to collapse · j/k · / search · o browser · v mpv · r refresh · Esc"
                          + (root.writable ? " · m mark read · s star" : "")
                    color: bar.overlay || bar.subtext
                    font.pixelSize: 11
                    font.family: bar.fontMono
                    wrapMode: Text.WordWrap
                }
            }

            // Drag region on empty header area — click title bar strip
            MouseArea {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 18
                cursorShape: Qt.SizeAllCursor
                onPressed: readerWindow.startSystemMove()
            }
        }
    }
}
