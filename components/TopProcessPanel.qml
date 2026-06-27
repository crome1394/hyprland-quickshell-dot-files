import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Top processes table with Grouped / Ungrouped toggle (CPU, Memory, GPU tabs).
Item {
    id: root

    required property var rows
    required property string title
    required property string mode

    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#89b4fa"
    property color surfaceColor: "#313244"
    property color overlayColor: "#6c7086"
    property string emptyText: ""

    property bool groupedView: true
    property int viewModeVersion: 0

    readonly property int processRowHeight: 15
    readonly property int processHeaderHeight: 17
    readonly property int tblSpacing: 4
    readonly property int colPidW: 34
    readonly property int colUserW: 44
    readonly property int colCpuW: 34
    readonly property int colRamPctW: 34
    readonly property int colMemW: 38
    readonly property int colThreadsW: 30
    readonly property int colTypeW: 36
    readonly property int colVramW: 52

    function commandGroupKey(name) {
        const cmd = (name || "").toLowerCase().trim()
        if (!cmd)
            return ""
        let base = cmd.split(/\s+/)[0]
        const slash = base.lastIndexOf("/")
        if (slash >= 0)
            base = base.substring(slash + 1)
        return base
    }

    function sortMetric() {
        if (root.mode === "mem")
            return "mem"
        if (root.mode === "gpu")
            return "vram"
        return "cpu"
    }

    function formatRssMiB(rss) {
        if (!rss)
            return "--"
        return Math.round(Number(rss) / 1024) + "M"
    }

    function formatGpuType(type) {
        if (!type || type.length === 0)
            return "--"
        return type
    }

    function processRow(p, rowType) {
        return {
            rowType: rowType || "process",
            pid: p.pid,
            name: p.name || "",
            user: p.user || "",
            cpu: Number(p.cpu || 0),
            mem: Number(p.mem || 0),
            rss: p.rss,
            threads: p.threads,
            vram: Number(p.vram || 0),
            type: p.type || "",
            count: 1,
            label: p.name || ""
        }
    }

    function buildGroupRow(key, members) {
        let cpu = 0
        let mem = 0
        let rss = 0
        let threads = 0
        let vram = 0
        let user = members[0].user || ""
        let mixedUser = false
        const types = {}
        for (let i = 0; i < members.length; i++) {
            const p = members[i]
            cpu += Number(p.cpu || 0)
            mem += Number(p.mem || 0)
            rss += Number(p.rss) || 0
            threads += Number(p.threads) || 0
            vram += Number(p.vram || 0)
            if ((p.user || "") !== user)
                mixedUser = true
            const t = p.type || ""
            if (t)
                types[t] = (types[t] || 0) + 1
        }
        let dominantType = ""
        let typeCount = 0
        for (const t in types) {
            if (types[t] > typeCount) {
                typeCount = types[t]
                dominantType = t
            }
        }
        const typeKeys = Object.keys(types)
        return {
            rowType: "group",
            pid: 0,
            name: key + " (" + members.length + ")",
            label: key,
            user: mixedUser ? "…" : user,
            cpu: cpu,
            mem: mem,
            rss: rss,
            threads: threads,
            vram: vram,
            type: typeKeys.length > 1 ? "…" : dominantType,
            count: members.length
        }
    }

    function displayRows() {
        const tick = viewModeVersion + "|" + (groupedView ? "1" : "0")
        void tick
        void rows

        const source = rows || []
        if (!source.length)
            return []

        if (!groupedView) {
            const flat = []
            for (let i = 0; i < source.length; i++)
                flat.push(processRow(source[i], "process"))
            return flat
        }

        const metric = sortMetric()
        const groups = {}
        const order = []
        for (let j = 0; j < source.length; j++) {
            const p = source[j]
            const key = commandGroupKey(p.name)
            if (!groups[key]) {
                groups[key] = []
                order.push(key)
            }
            groups[key].push(p)
        }

        for (let g = 0; g < order.length; g++) {
            groups[order[g]].sort(function(a, b) {
                return Number(b[metric] || 0) - Number(a[metric] || 0)
            })
        }

        order.sort(function(a, b) {
            const ma = groups[a]
            const mb = groups[b]
            let sumA = 0
            let sumB = 0
            for (let i = 0; i < ma.length; i++)
                sumA += Number(ma[i][metric] || 0)
            for (let k = 0; k < mb.length; k++)
                sumB += Number(mb[k][metric] || 0)
            if (sumB !== sumA)
                return sumB - sumA
            return a < b ? -1 : 1
        })

        const out = []
        for (let o = 0; o < order.length; o++) {
            const key = order[o]
            const members = groups[key]
            if (members.length === 1)
                out.push(processRow(members[0], "process"))
            else
                out.push(buildGroupRow(key, members))
        }
        return out
    }

    function tableFixedWidth() {
        if (mode === "gpu")
            return colPidW + colTypeW + colVramW + tblSpacing * 3
        if (mode === "mem")
            return colPidW + colUserW + colRamPctW + colMemW + colThreadsW + tblSpacing * 5
        return colPidW + colUserW + colCpuW + colRamPctW + colMemW + colThreadsW + tblSpacing * 6
    }

    function appColWidth(totalWidth) {
        return Math.max(mode === "gpu" ? 64 : 56, totalWidth - tableFixedWidth())
    }

    function toggleGroupedView() {
        groupedView = !groupedView
        viewModeVersion++
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        property var _rowBind: root.rows
        property int _modeTick: root.viewModeVersion

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: root.title
                color: root.accentColor
                font.pixelSize: 11
                font.bold: true
                font.family: "monospace"
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: groupToggleLabel.implicitWidth + 16
                height: 20
                radius: 4
                color: groupToggleMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                border.width: 1
                border.color: root.groupedView ? root.accentColor : Qt.rgba(1, 1, 1, 0.1)

                Text {
                    id: groupToggleLabel
                    anchors.centerIn: parent
                    text: root.groupedView ? "Grouped" : "Ungrouped"
                    color: root.groupedView ? root.accentColor : root.textColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }

                MouseArea {
                    id: groupToggleMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleGroupedView()
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: processTable.implicitHeight

            Column {
                id: processTable
                width: parent.width
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: root.processHeaderHeight
                    radius: 3
                    color: Qt.rgba(0.55, 0.70, 0.96, 0.12)

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: root.tblSpacing

                        Text { width: root.colPidW; height: parent.height; text: "PID"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                        Text { width: root.appColWidth(parent.width - 8); height: parent.height; text: "App"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                        Text { visible: root.mode !== "gpu"; width: root.colUserW; height: parent.height; text: "User"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignLeft }
                        Text { visible: root.mode === "cpu"; width: root.colCpuW; height: parent.height; text: "CPU%"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                        Text { visible: root.mode !== "gpu"; width: root.colRamPctW; height: parent.height; text: "RAM%"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                        Text { visible: root.mode !== "gpu"; width: root.colMemW; height: parent.height; text: "Mem"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                        Text { visible: root.mode !== "gpu"; width: root.colThreadsW; height: parent.height; text: "Thr"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                        Text { visible: root.mode === "gpu"; width: root.colTypeW; height: parent.height; text: "Type"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                        Text { visible: root.mode === "gpu"; width: root.colVramW; height: parent.height; text: "VRAM"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                    }
                }

                Text {
                    width: parent.width
                    visible: (!root.rows || root.rows.length === 0) && root.emptyText.length > 0
                    text: root.emptyText
                    color: root.overlayColor
                    font.pixelSize: 10
                    font.family: "monospace"
                    topPadding: 4
                }

                Repeater {
                    property var _rowBind: root.rows
                    property int _modeTick: root.viewModeVersion
                    model: root.displayRows()
                    delegate: Item {
                        id: rowRoot
                        width: parent.width
                        height: root.processRowHeight

                        readonly property bool isGroup: modelData.rowType === "group"

                        Rectangle {
                            anchors.fill: parent
                            radius: 2
                            color: rowRoot.isGroup ? Qt.rgba(0.55, 0.70, 0.96, 0.08)
                                : (index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02))
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: root.tblSpacing
                            clip: true

                            Text {
                                width: root.colPidW
                                height: parent.height
                                text: rowRoot.isGroup ? String(modelData.count || "") : String(modelData.pid)
                                color: rowRoot.isGroup ? root.overlayColor : root.textColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: rowRoot.isGroup
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                clip: true
                            }
                            Text {
                                width: root.appColWidth(parent.width - 8)
                                height: parent.height
                                text: modelData.name || "--"
                                color: rowRoot.isGroup ? root.textColor : root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: rowRoot.isGroup
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                clip: true
                            }
                            Text {
                                visible: root.mode !== "gpu"
                                width: root.colUserW
                                height: parent.height
                                text: modelData.user || "--"
                                color: rowRoot.isGroup ? root.textColor : root.overlayColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: rowRoot.isGroup
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                clip: true
                            }
                            Text {
                                visible: root.mode === "cpu"
                                width: root.colCpuW
                                height: parent.height
                                text: (modelData.cpu || 0).toFixed(1) + "%"
                                color: root.accentColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: rowRoot.isGroup
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                clip: true
                            }
                            Text {
                                visible: root.mode !== "gpu"
                                width: root.colRamPctW
                                height: parent.height
                                text: (modelData.mem || 0).toFixed(1) + "%"
                                color: root.mode === "mem" ? root.accentColor : root.textColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: rowRoot.isGroup
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                clip: true
                            }
                            Text {
                                visible: root.mode !== "gpu"
                                width: root.colMemW
                                height: parent.height
                                text: root.formatRssMiB(modelData.rss)
                                color: root.textColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: rowRoot.isGroup
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                clip: true
                            }
                            Text {
                                visible: root.mode !== "gpu"
                                width: root.colThreadsW
                                height: parent.height
                                text: modelData.threads !== undefined ? modelData.threads : "--"
                                color: root.textColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: rowRoot.isGroup
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                clip: true
                            }
                            Text {
                                visible: root.mode === "gpu"
                                width: root.colTypeW
                                height: parent.height
                                text: root.formatGpuType(modelData.type)
                                color: rowRoot.isGroup ? root.textColor : root.overlayColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: rowRoot.isGroup
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                clip: true
                            }
                            Text {
                                visible: root.mode === "gpu"
                                width: root.colVramW
                                height: parent.height
                                text: (modelData.vram || 0) + " MiB"
                                color: root.accentColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: rowRoot.isGroup
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                clip: true
                            }
                        }
                    }
                }
            }
        }
    }
}