import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Live disk / storage monitoring tab (SysMonService + usage bars + I/O sparklines).
Item {
    id: root

    required property var service

    property bool live: false

    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#89b4fa"
    property color surfaceColor: "#313244"
    property color overlayColor: "#6c7086"
    property color gaugeLowColor: "#a6e3a1"
    property color gaugeMidColor: "#f9e2af"
    property color gaugeHighColor: "#f38ba8"
    property color readSparkColor: "#89b4fa"
    property color writeSparkColor: "#f9e2af"

    readonly property int cardRadius: 6
    readonly property int cardMargin: 10
    readonly property int fsRowHeight: 15
    readonly property int fsHeaderHeight: 17
    readonly property int dirRowHeight: 14
    readonly property int sectionSpacing: 8
    readonly property int tblSpacing: 4
    readonly property int colMountW: 108
    readonly property int colSizeW: 44
    readonly property int colUsedW: 44
    readonly property int colAvailW: 44
    readonly property int colPctW: 34
    readonly property int colBarW: 72

    property var filesystemRows: []
    property var importantDisks: []
    property var topDirRows: []
    property var storageTotals: ({ count: 0, total: 0, used: 0, pct: 0 })

    function fsTableFixedWidth() {
        return colMountW + colSizeW + colUsedW + colAvailW + colPctW + colBarW + tblSpacing * 6
    }

    function fsDeviceColWidth(totalWidth) {
        return Math.max(48, totalWidth - fsTableFixedWidth())
    }

    function barColor(pct) {
        const v = Number(pct) || 0
        if (v > 85) return root.gaugeHighColor
        if (v > 65) return root.gaugeMidColor
        return root.gaugeLowColor
    }

    function formatGiB(gb) {
        if (gb === undefined || gb === null) return "--"
        const v = Number(gb)
        if (v >= 1024) return (v / 1024).toFixed(1) + " TiB"
        return v.toFixed(1) + " GiB"
    }

    function formatMiB(mb) {
        if (!mb) return "--"
        const v = Number(mb)
        if (v >= 1024) return (v / 1024).toFixed(1) + " GiB"
        return Math.round(v) + " MiB"
    }

    function formatRate(bytesPerSec) {
        const bps = Number(bytesPerSec) || 0
        const kib = bps / 1024
        if (kib >= 1024) return (kib / 1024).toFixed(1) + " MiB/s"
        return Math.round(kib) + " KiB/s"
    }

    function mountLabel(mount) {
        if (!mount) return "--"
        if (mount === "/") return "Root (/)"
        if (mount === "/home") return "Home"
        if (mount.indexOf("/run/media/") === 0) {
            const parts = mount.split("/")
            return parts.length >= 4 ? parts[parts.length - 1] : mount
        }
        return mount
    }

    function shortPath(path) {
        if (!path) return "--"
        if (path.length <= 28) return path
        return "…" + path.slice(-27)
    }

    readonly property int summaryHeight: Math.max(100, Math.min(130, Math.round(height * 0.16)))
    readonly property int middleHeight: Math.max(124, Math.min(260, Math.round(height * 0.34)))

    readonly property bool topDirsPending: root.live && service
        ? ((service.diskExtras && service.diskExtras.top_dirs_pending === true)
            || service.diskExtrasRefreshing) : false

    function rebuildCachedRows() {
        if (!root.live || !service) {
            filesystemRows = []
            importantDisks = []
            topDirRows = []
            storageTotals = { count: 0, total: 0, used: 0, pct: 0 }
            return
        }

        const data = service.data || {}
        filesystemRows = data.filesystems || []
        importantDisks = data.disks || []

        const extras = service.diskExtras || {}
        const mounts = (extras.top_dirs && extras.top_dirs.length)
            ? extras.top_dirs
            : (data.top_dirs || [])
        const rows = []
        for (let i = 0; i < mounts.length; i++) {
            const block = mounts[i]
            const dirs = block.dirs || []
            for (let j = 0; j < dirs.length && j < 4; j++) {
                rows.push({
                    mount: block.mount,
                    path: dirs[j].path,
                    size_mb: dirs[j].size_mb
                })
            }
        }
        topDirRows = rows.slice(0, 10)

        let total = 0
        let used = 0
        let count = 0
        const fsRows = filesystemRows
        for (let k = 0; k < fsRows.length; k++) {
            total += Number(fsRows[k].total_gb || 0)
            used += Number(fsRows[k].used_gb || 0)
            count++
        }
        const pct = total > 0 ? (used * 100 / total) : 0
        storageTotals = { count: count, total: total, used: used, pct: pct }
    }

    function scheduleRowRebuild() {
        rowRebuildDebounce.restart()
    }

    onLiveChanged: scheduleRowRebuild()

    Timer {
        id: rowRebuildDebounce
        interval: 32
        repeat: false
        onTriggered: root.rebuildCachedRows()
    }

    Connections {
        target: service
        function onDataVersionChanged() { root.scheduleRowRebuild() }
        function onDiskExtrasVersionChanged() { root.scheduleRowRebuild() }
    }

    Component.onCompleted: scheduleRowRebuild()

    function resetScroll() {
        if (fsList.contentHeight > fsList.height)
            fsList.contentY = 0
        if (importantList.contentHeight > importantList.height)
            importantList.contentY = 0
        if (dirList.contentHeight > dirList.height)
            dirList.contentY = 0
    }

    function pageScroll(direction) {
        const step = Math.max(80, height * 0.85)
        fsList.contentY = Math.max(0, Math.min(fsList.contentHeight - fsList.height, fsList.contentY + direction * step))
        importantList.contentY = Math.max(0, Math.min(importantList.contentHeight - importantList.height, importantList.contentY + direction * step))
        dirList.contentY = Math.max(0, Math.min(dirList.contentHeight - dirList.height, dirList.contentY + direction * step))
    }

    function lineScroll(direction) {
        const step = 28
        fsList.contentY = Math.max(0, Math.min(fsList.contentHeight - fsList.height, fsList.contentY + direction * step))
        importantList.contentY = Math.max(0, Math.min(importantList.contentHeight - importantList.height, importantList.contentY + direction * step))
        dirList.contentY = Math.max(0, Math.min(dirList.contentHeight - dirList.height, dirList.contentY + direction * step))
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.sectionSpacing

        property int _dataTick: service ? service.dataVersion : 0
        property int _diskExtrasTick: service ? service.diskExtrasVersion : 0
        property int _diskReadTick: service ? service.diskReadHistory.length : 0
        property int _diskWriteTick: service ? service.diskWriteHistory.length : 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.summaryHeight
            Layout.minimumHeight: 96
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: 4

                Text {
                    text: "DISK SUMMARY"
                    color: root.accentColor
                    font.pixelSize: 12
                    font.bold: true
                    font.family: "monospace"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: "Mounts: " + root.storageTotals.count
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "Used: " + root.formatGiB(root.storageTotals.used) + " / " + root.formatGiB(root.storageTotals.total)
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "Read: " + (service.data.disk ? root.formatRate(service.data.disk.read_rate) : "--")
                            color: root.readSparkColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "Write: " + (service.data.disk ? root.formatRate(service.data.disk.write_rate) : "--")
                            color: root.writeSparkColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.storageTotals.pct.toFixed(0) + "%"
                        color: root.textColor
                        font.pixelSize: 25
                        font.bold: true
                        font.family: "monospace"
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.25)

                    Rectangle {
                        width: parent.width * Math.min(1, root.storageTotals.pct / 100)
                        height: parent.height
                        radius: 3
                        color: root.barColor(root.storageTotals.pct)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.middleHeight
            Layout.minimumHeight: 116
            spacing: root.sectionSpacing

            Rectangle {
                Layout.preferredWidth: Math.max(180, Math.min(260, root.width * 0.34))
                Layout.fillHeight: true
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: 4

                    Text {
                        text: "Important Mounts"
                        color: root.accentColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    Flickable {
                        id: importantList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: importantMounts.implicitHeight

                        Column {
                            id: importantMounts
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: root.importantDisks
                                delegate: Column {
                                    width: parent.width
                                    spacing: 2

                                    Row {
                                        width: parent.width
                                        spacing: 4

                                        Text {
                                            width: parent.width - 44
                                            text: root.mountLabel(modelData.mount)
                                            color: root.textColor
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.family: "monospace"
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: 40
                                            text: Number(modelData.pct || 0).toFixed(0) + "%"
                                            color: root.barColor(modelData.pct)
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.family: "monospace"
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }

                                    Text {
                                        width: parent.width
                                        text: (modelData.model || "Disk") + "  ·  " + root.formatGiB(modelData.used_gb) + " / " + root.formatGiB(modelData.total_gb)
                                        color: root.overlayColor
                                        font.pixelSize: 9
                                        font.family: "monospace"
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 5
                                        radius: 3
                                        color: Qt.rgba(0, 0, 0, 0.25)

                                        Rectangle {
                                            width: parent.width * Math.min(1, Number(modelData.pct || 0) / 100)
                                            height: parent.height
                                            radius: 3
                                            color: root.barColor(modelData.pct)
                                        }
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: root.importantDisks.length === 0
                                text: "No important mounts detected"
                                color: root.overlayColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                topPadding: 4
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: 4

                    Text {
                        text: "Mounted Filesystems"
                        color: root.accentColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: root.fsHeaderHeight
                        radius: 3
                        color: Qt.rgba(0.55, 0.70, 0.96, 0.12)

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: root.tblSpacing

                            Text { width: root.colMountW; height: parent.height; text: "Mount"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Text { width: root.fsDeviceColWidth(parent.width - 8); height: parent.height; text: "Device"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Text { width: root.colSizeW; height: parent.height; text: "Size"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colUsedW; height: parent.height; text: "Used"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colAvailW; height: parent.height; text: "Avail"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colPctW; height: parent.height; text: "%"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Item { width: root.colBarW; height: parent.height }
                        }
                    }

                    ListView {
                        id: fsList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.filesystemRows
                        cacheBuffer: root.fsRowHeight * 8

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        delegate: Item {
                            width: fsList.width
                            height: root.fsRowHeight

                            Rectangle {
                                anchors.fill: parent
                                radius: 2
                                color: index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02)
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                spacing: root.tblSpacing

                                Text { width: root.colMountW; height: parent.height; text: modelData.mount; color: root.subtextColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: root.fsDeviceColWidth(parent.width - 8); height: parent.height; text: modelData.device; color: root.overlayColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: root.colSizeW; height: parent.height; text: root.formatGiB(modelData.total_gb); color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colUsedW; height: parent.height; text: root.formatGiB(modelData.used_gb); color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colAvailW; height: parent.height; text: root.formatGiB(modelData.avail_gb); color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colPctW; height: parent.height; text: Number(modelData.pct || 0).toFixed(0) + "%"; color: root.barColor(modelData.pct); font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }

                                Rectangle {
                                    width: root.colBarW
                                    height: 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 3
                                    color: Qt.rgba(0, 0, 0, 0.25)

                                    Rectangle {
                                        width: parent.width * Math.min(1, Number(modelData.pct || 0) / 100)
                                        height: parent.height
                                        radius: 3
                                        color: root.barColor(modelData.pct)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(72, Math.min(110, Math.round(height * 0.14)))
            Layout.minimumHeight: 64
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            clip: true
            visible: root.topDirRows.length > 0 || root.topDirsPending

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Top Directories"
                        color: root.accentColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    Text {
                        visible: root.topDirsPending
                        text: "scanning…"
                        color: root.overlayColor
                        font.pixelSize: 10
                        font.family: "monospace"
                    }
                }

                Flickable {
                    id: dirList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: dirRows.implicitHeight

                    Column {
                        id: dirRows
                        width: parent.width
                        spacing: 0

                        Repeater {
                            model: root.topDirRows
                            delegate: Item {
                                width: parent.width
                                height: root.dirRowHeight

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 2
                                    color: index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02)
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    spacing: 8

                                    Text {
                                        width: Math.max(80, parent.width * 0.62)
                                        height: parent.height
                                        text: root.shortPath(modelData.path)
                                        color: root.subtextColor
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: 72
                                        height: parent.height
                                        text: root.mountLabel(modelData.mount)
                                        color: root.overlayColor
                                        font.pixelSize: 9
                                        font.family: "monospace"
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width - Math.max(80, parent.width * 0.62) - 80
                                        height: parent.height
                                        text: root.formatMiB(modelData.size_mb)
                                        color: root.accentColor
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 88
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: 4

                Text {
                    text: "Disk I/O History"
                    color: root.accentColor
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "monospace"
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: root.sectionSpacing

                    Sparkline {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 48
                        history: service.diskReadHistory
                        fixedRange: false
                        drawGrid: true
                        gridStep: 0
                        chartTitle: "Read KiB/s"
                        titleColor: root.textColor
                        lineColor: root.readSparkColor
                        fillColor: Qt.rgba(0.53, 0.71, 0.98, 0.22)
                        leftPadding: 30
                        lineWidth: 1.2
                    }

                    Sparkline {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 48
                        history: service.diskWriteHistory
                        fixedRange: false
                        drawGrid: true
                        gridStep: 0
                        chartTitle: "Write KiB/s"
                        titleColor: root.textColor
                        lineColor: root.writeSparkColor
                        fillColor: Qt.rgba(0.98, 0.89, 0.69, 0.22)
                        leftPadding: 30
                        lineWidth: 1.2
                    }
                }
            }
        }
    }
}