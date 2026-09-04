import Foundation

// MARK: - 模型

/// 列表项：普通项或任务项（任务记录源文本行号，用于勾选写回）
struct MarkdownListItem: Equatable {
    struct Task: Equatable {
        var checked: Bool
        /// 任务在源文本中的行号（0 起）
        var line: Int
    }

    var inline: String
    var task: Task?
    /// 嵌套的子列表（通常是 .list 块）
    var children: [MarkdownBlock]
}

/// 块级元素
/// indirect：与 MarkdownListItem 互递归，需要堆上间接层，
/// 否则 Swift 5.9 编译器在类型降级时会无限展开（SILGen 挂死）。
indirect enum MarkdownBlock: Equatable {
    case heading(level: Int, inline: String)
    case paragraph(inline: String)
    case codeBlock(language: String?, code: String)
    case blockquote(blocks: [MarkdownBlock])
    case list(ordered: Bool, items: [MarkdownListItem])
    case thematicBreak
}

// MARK: - 解析器

/// 轻量 Markdown 块级解析器（标题/段落/代码块/引用/有序无序列表/任务清单/分隔线）。
/// 行内格式（加粗/斜体/行内代码/链接/删除线）交给系统的 AttributedString 解析。
/// 任务清单只识别 `-`/`*`/`+` 圆点标记（与 GFM 一致），并记录行号供写回。
struct MarkdownParser {
    private let lines: [String]
    private var index = 0

    private enum Pattern {
        static let fenceOpen = "^\\s*```"
        static let fenceClose = "^\\s*```\\s*$"
        static let fenceWithLang = "^\\s*```(\\w*)\\s*$"
        static let heading = "^(#{1,6})\\s+(.*)$"
        static let hr = "^\\s*(-{3,}|\\*{3,}|_{3,})\\s*$"
        static let quote = "^\\s*>"
        static let quoteStrip = "^\\s*>\\s?"
        static let list = "^(\\s*)([-*+]|\\d{1,9}[.)])\\s+(.*)$"
        static let task = "^\\[([ xX])\\]\\s*(.*)$"
    }

    private init(lines: [String]) {
        self.lines = lines
    }

    static func parse(_ text: String) -> [MarkdownBlock] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var parser = MarkdownParser(lines: normalized.components(separatedBy: "\n"))
        return parser.parseBlocks()
    }

    // MARK: 块级循环

    private mutating func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            if firstMatch(Pattern.fenceOpen, line) != nil {
                blocks.append(parseFencedCode())
                continue
            }
            if let g = firstMatch(Pattern.heading, line) {
                blocks.append(.heading(level: g[1].count, inline: g[2]))
                index += 1
                continue
            }
            if firstMatch(Pattern.hr, line) != nil {
                blocks.append(.thematicBreak)
                index += 1
                continue
            }
            if firstMatch(Pattern.quote, line) != nil {
                blocks.append(.blockquote(blocks: parseBlockquote()))
                continue
            }
            if firstMatch(Pattern.list, line) != nil {
                blocks.append(contentsOf: parseList())
                continue
            }
            blocks.append(parseParagraph())
        }
        return blocks
    }

    private mutating func parseFencedCode() -> MarkdownBlock {
        let opening = firstMatch(Pattern.fenceWithLang, lines[index])
        let language = opening.flatMap { $0.count > 1 && !$0[1].isEmpty ? $0[1] : nil }
        index += 1
        var code: [String] = []
        while index < lines.count, firstMatch(Pattern.fenceClose, lines[index]) == nil {
            code.append(lines[index])
            index += 1
        }
        index += 1 // 跳过收尾 ```（或到达末尾）
        return .codeBlock(language: language, code: code.joined(separator: "\n"))
    }

    private mutating func parseBlockquote() -> [MarkdownBlock] {
        var inner: [String] = []
        while index < lines.count, firstMatch(Pattern.quote, lines[index]) != nil {
            inner.append(lines[index].replacingOccurrences(
                of: Pattern.quoteStrip,
                with: "",
                options: .regularExpression
            ))
            index += 1
        }
        var subParser = MarkdownParser(lines: inner)
        return subParser.parseBlocks()
    }

    private mutating func parseParagraph() -> MarkdownBlock {
        var collected = [lines[index]]
        index += 1
        while index < lines.count {
            let line = lines[index]
            let isBlockStart =
                line.trimmingCharacters(in: .whitespaces).isEmpty
                || firstMatch(Pattern.fenceOpen, line) != nil
                || firstMatch(Pattern.heading, line) != nil
                || firstMatch(Pattern.quote, line) != nil
                || firstMatch(Pattern.list, line) != nil
            if isBlockStart { break }
            collected.append(line)
            index += 1
        }
        return .paragraph(inline: collected.joined(separator: "\n"))
    }

    // MARK: 列表

    private struct RawItem {
        let indent: Int
        let ordered: Bool
        let isBullet: Bool
        var text: String
        let line: Int
    }

    private mutating func parseList() -> [MarkdownBlock] {
        var items: [RawItem] = []
        while index < lines.count {
            let line = lines[index]
            if let g = firstMatch(Pattern.list, line) {
                let marker = g[2]
                let ordered = marker.first?.isNumber == true
                items.append(RawItem(
                    indent: g[1].count,
                    ordered: ordered,
                    isBullet: !ordered,
                    text: g[3],
                    line: index
                ))
                index += 1
            } else if !items.isEmpty,
                      !line.trimmingCharacters(in: .whitespaces).isEmpty,
                      firstMatch(Pattern.fenceOpen, line) == nil,
                      firstMatch(Pattern.heading, line) == nil,
                      firstMatch(Pattern.quote, line) == nil {
                // 懒续行：归属上一个列表项
                items[items.count - 1].text += " " + line.trimmingCharacters(in: .whitespaces)
                index += 1
            } else {
                break
            }
        }
        return buildLists(from: items)
    }

    /// 同层级缩进的列表项构造成列表；同层级中有序/无序类型切换时拆成两个列表；
    /// 缩进更深的项递归为子列表。
    private func buildLists(from items: [RawItem]) -> [MarkdownBlock] {
        guard !items.isEmpty else { return [] }
        var blocks: [MarkdownBlock] = []
        var current: [MarkdownListItem] = []
        var ordered = items[0].ordered
        let baseIndent = items[0].indent

        func flush() {
            guard !current.isEmpty else { return }
            blocks.append(.list(ordered: ordered, items: current))
            current = []
        }

        var k = 0
        while k < items.count {
            let item = items[k]
            if item.indent < baseIndent { break }
            if item.indent == baseIndent, item.ordered != ordered {
                flush()
                ordered = item.ordered
            }
            var childRaw: [RawItem] = []
            var j = k + 1
            while j < items.count, items[j].indent > item.indent {
                childRaw.append(items[j])
                j += 1
            }
            let childBlocks = childRaw.isEmpty ? [] : buildLists(from: childRaw)

            var task: MarkdownListItem.Task?
            var inline = item.text
            if item.isBullet, let g = firstMatch(Pattern.task, item.text) {
                task = MarkdownListItem.Task(checked: g[1] != " ", line: item.line)
                // 活动区已完成任务的时间戳和内部标记只用于持久化，预览中只显示标题。
                inline = TaskArchiveCodec.visibleTaskTitle(g[2])
            }
            current.append(MarkdownListItem(inline: inline, task: task, children: childBlocks))
            k = j
        }
        flush()
        return blocks
    }

    // MARK: 正则工具

    private func firstMatch(_ pattern: String, _ line: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { group in
            let range = match.range(at: group)
            guard range.location != NSNotFound, let r = Range(range, in: line) else { return "" }
            return String(line[r])
        }
    }
}
