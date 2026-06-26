import QtQuick
import QtQuick.Controls

// Monospace Lua/Hyprland viewer. Uses TextEdit for reliable rendering, with
// per-line colored segments when the source is non-empty.
Item {
    id: root

    property string source: ""
    property int fontSize: 11
    property string fontFamily: "monospace"

    property color defaultColor: "#cdd6f4"
    property color commentColor: "#6c7086"
    property color stringColor: "#a6e3a1"
    property color keywordColor: "#cba6f7"
    property color apiColor: "#89b4fa"
    property color numberColor: "#fab387"

    readonly property var lines: source ? source.split("\n") : []

    anchors.fill: parent

    function segmentsForLine(line) {
        const out = []
        const trimmed = line.trimStart()
        if (trimmed.startsWith("--")) {
            out.push({ text: line, color: commentColor })
            return out
        }

        let i = 0
        while (i < line.length) {
            const ch = line[i]

            if (ch === '"' || ch === "'") {
                let j = i + 1
                while (j < line.length) {
                    if (line[j] === "\\") { j += 2; continue }
                    if (line[j] === ch) { j++; break }
                    j++
                }
                out.push({ text: line.substring(i, j), color: stringColor })
                i = j
                continue
            }

            if (ch === "-" && line[i + 1] === "-") {
                out.push({ text: line.substring(i), color: commentColor })
                break
            }

            if (/[0-9]/.test(ch) || (ch === "-" && /[0-9]/.test(line[i + 1]))) {
                let j = i
                if (line[j] === "-") j++
                while (j < line.length && /[0-9.xxa-fA-F]/.test(line[j])) j++
                out.push({ text: line.substring(i, j), color: numberColor })
                i = j
                continue
            }

            if (/[a-zA-Z_]/.test(ch)) {
                let j = i
                while (j < line.length && /[a-zA-Z0-9_.]/.test(line[j])) j++
                const token = line.substring(i, j)

                if (token === "hl" && line[j] === ".") {
                    const rest = line.substring(i)
                    const apiMatch = rest.match(/^hl(?:\.[a-zA-Z_][a-zA-Z0-9_]*)+/)
                    if (apiMatch) {
                        out.push({ text: apiMatch[0], color: apiColor })
                        i += apiMatch[0].length
                        continue
                    }
                }

                const keywords = {
                    local: 1, function: 1, end: 1, for: 1, do: 1, if: 1, then: 1,
                    else: 1, elseif: 1, return: 1, true: 1, false: 1, nil: 1, in: 1,
                    require: 1, not: 1, and: 1, or: 1, break: 1, repeat: 1, until: 1,
                    while: 1
                }
                out.push({
                    text: token,
                    color: keywords[token] ? keywordColor : defaultColor
                })
                i = j
                continue
            }

            out.push({ text: ch, color: defaultColor })
            i++
        }

        if (!out.length) out.push({ text: " ", color: defaultColor })
        return out
    }

    Flickable {
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        contentWidth: Math.max(width, lineColumn.implicitWidth + 24)
        contentHeight: Math.max(height, lineColumn.implicitHeight + 24)

        Column {
            id: lineColumn
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 1

            Repeater {
                model: root.lines

                Row {
                    required property string modelData
                    spacing: 0

                    Repeater {
                        model: root.segmentsForLine(parent.modelData)

                        Text {
                            required property var modelData
                            text: modelData.text
                            color: modelData.color
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                        }
                    }
                }
            }
        }
    }

    // Plain-text fallback layer — visible only if highlighted lines failed to render
    ScrollView {
        anchors.fill: parent
        visible: root.source.length > 0 && lineColumn.height <= 1
        clip: true

        TextArea {
            readOnly: true
            text: root.source
            color: root.defaultColor
            font.pixelSize: root.fontSize
            font.family: root.fontFamily
            wrapMode: TextArea.NoWrap
            background: null
            selectByMouse: true
        }
    }
}