import AppKit

extension NSAttributedString.Key {
    static let menuNoteBlockPrefix = NSAttributedString.Key("MenuNoteBlockPrefix")
    static let menuNoteTaskLine = NSAttributedString.Key("MenuNoteTaskLine")
    static let menuNoteTaskIndent = NSAttributedString.Key("MenuNoteTaskIndent")
    static let menuNoteTaskChecked = NSAttributedString.Key("MenuNoteTaskChecked")
    static let menuNoteTaskCompletionStamp = NSAttributedString.Key("MenuNoteTaskCompletionStamp")
    static let menuNoteTaskPresentationStrike = NSAttributedString.Key("MenuNoteTaskPresentationStrike")
    static let menuNoteStructuralFont = NSAttributedString.Key("MenuNoteStructuralFont")
    static let menuNoteCodeLanguage = NSAttributedString.Key("MenuNoteCodeLanguage")
}

/// Markdown 与 TextKit 富文本之间的轻量双向编解码。
/// 设计目标是把 Markdown 标记变成样式属性，保存时从样式属性重建 Markdown。
struct MarkdownDocumentCodec {
    static let defaultTaskFontSize: CGFloat = 14.5
    static let defaultHeadingFontSize: CGFloat = 21
    private static let monoFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    static func attributedDocument(
        from markdown: String,
        taskFontSize: CGFloat = MarkdownDocumentCodec.defaultTaskFontSize,
        headingFontSize: CGFloat = MarkdownDocumentCodec.defaultHeadingFontSize
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var inCode = false
        var codeLanguage = ""
        let taskFont = NSFont.systemFont(ofSize: taskFontSize)
        let headingSizes: [CGFloat] = [
            0,
            headingFontSize,
            headingFontSize * 18 / 21,
            headingFontSize * 16 / 21,
            headingFontSize * 15 / 21,
            headingFontSize * 14 / 21,
            headingFontSize * 14 / 21,
        ]

        for (lineIndex, source) in lines.enumerated() {
            if source.hasPrefix("```") {
                inCode.toggle()
                codeLanguage = String(source.dropFirst(3))
                if !inCode { continue }
                continue
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = 5
            var prefix = ""
            var text = source
            // 所见即所得编辑区只区分两种常规行：任务行和标题行。
            // 具体任务行会在下面替换为 taskFont，其余普通内容统一使用标题字体。
            var font = NSFont.systemFont(ofSize: headingSizes[1], weight: .semibold)
            var color = NSColor.labelColor
            var taskLine: Int?
            var taskIndent = ""
            var taskCompletionStamp: String?

            if inCode {
                prefix = "```\(codeLanguage)"
                font = monoFont
                color = .labelColor
                paragraph.firstLineHeadIndent = 10
                paragraph.headIndent = 10
            } else if let heading = match("^(#{1,6})\\s+(.*)$", in: source) {
                let level = heading[1].count
                prefix = heading[1]
                text = heading[2]
                font = NSFont.systemFont(ofSize: headingSizes[min(level, 6)], weight: .semibold)
                paragraph.paragraphSpacing = level == 1 ? 10 : 6
            } else if let list = match("^(\\s*)([-*+]|\\d+[.)])\\s+(.*)$", in: source) {
                let indent = list[1]
                let marker = list[2]
                let content = list[3]
                let visualIndent = CGFloat(indent.count / 2) * 18
                paragraph.firstLineHeadIndent = visualIndent
                paragraph.headIndent = visualIndent + 22
                if let task = match("^\\[([ xX])\\]\\s*(.*)$", in: content), marker.first?.isNumber != true {
                    let isChecked = task[1].lowercased() == "x"
                    prefix = "task"
                    // 只显示任务标题，剥离完成时间等内部元数据。
                    let rawTitle = task[2]
                    let visibleTitle = TaskArchiveCodec.visibleTaskTitle(rawTitle)
                    text = (isChecked ? "☑" : "☐") + "  " + visibleTitle
                    font = taskFont
                    taskLine = lineIndex
                    taskIndent = indent + marker + " "
                    // 时间戳已从显示文本剥离，必须从原始任务标题读取，
                    // 否则富文本重新编码时会把完成时间丢掉。
                    taskCompletionStamp = completionStamp(from: rawTitle)
                    paragraph.firstLineHeadIndent = visualIndent
                    paragraph.headIndent = visualIndent + 25
                } else {
                    prefix = indent + marker
                    text = marker.first?.isNumber == true ? "\(marker)  \(content)" : "•  \(content)"
                    paragraph.firstLineHeadIndent = visualIndent
                    paragraph.headIndent = visualIndent + 25
                }
            } else if source.hasPrefix(">") {
                prefix = ">"
                text = source.replacingOccurrences(of: "^>\\s?", with: "", options: .regularExpression)
                color = .secondaryLabelColor
                paragraph.firstLineHeadIndent = 12
                paragraph.headIndent = 12
            } else if source.trimmingCharacters(in: .whitespaces) == "---" {
                prefix = "---"
                text = "────────────────────────"
                color = .separatorColor
            } else if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 在所见即所得编辑器中，没有任务框或其他 Markdown 结构的独立文本行按标题处理。
                // 这样用户新建便签后可以直接输入标题，无需先输入 Markdown 的 #。
                prefix = "#"
                font = NSFont.systemFont(ofSize: headingSizes[1], weight: .semibold)
                paragraph.paragraphSpacing = 10
            }

            let rendered = inlineAttributed(text, font: font, color: color)
            rendered.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: rendered.length))
            rendered.addAttribute(.menuNoteBlockPrefix, value: prefix, range: NSRange(location: 0, length: rendered.length))
            if prefix.hasPrefix("#") || taskLine == nil {
                rendered.addAttribute(.menuNoteStructuralFont, value: true, range: NSRange(location: 0, length: rendered.length))
            }
            if prefix.hasPrefix("```") {
                rendered.addAttribute(.menuNoteCodeLanguage, value: codeLanguage, range: NSRange(location: 0, length: rendered.length))
            }
            if let taskLine {
                let checked = text.hasPrefix("☑")
                rendered.addAttribute(.menuNoteTaskLine, value: taskLine, range: NSRange(location: 0, length: rendered.length))
                rendered.addAttribute(.menuNoteTaskIndent, value: taskIndent, range: NSRange(location: 0, length: rendered.length))
                rendered.addAttribute(.menuNoteTaskChecked, value: checked, range: NSRange(location: 0, length: rendered.length))
                if let taskCompletionStamp {
                    rendered.addAttribute(.menuNoteTaskCompletionStamp, value: taskCompletionStamp, range: NSRange(location: 0, length: rendered.length))
                }
                // 复选框使用 16pt 只是为了让图标清晰，标题必须保持正文 14.5pt。
                // 外部 Markdown 刷新或 TextKit 属性继承时，不能让复选框字号泄漏到标题。
                if rendered.length > 3 {
                    let bodyRange = NSRange(location: 3, length: rendered.length - 3)
                    var normalizedFonts: [(NSRange, NSFont)] = []
                    rendered.enumerateAttribute(.font, in: bodyRange, options: []) { value, range, _ in
                        guard let current = value as? NSFont, !current.fontName.contains("Mono") else { return }
                        let traits = NSFontManager.shared.traits(of: current)
                        var normalized = font
                        if traits.contains(.boldFontMask) {
                            normalized = NSFontManager.shared.convert(normalized, toHaveTrait: .boldFontMask)
                        }
                        if traits.contains(.italicFontMask) {
                            normalized = NSFontManager.shared.convert(normalized, toHaveTrait: .italicFontMask)
                        }
                        normalizedFonts.append((range, normalized))
                    }
                    for (range, normalized) in normalizedFonts {
                        rendered.addAttribute(.font, value: normalized, range: range)
                    }
                }
                if rendered.length >= 1 {
                    rendered.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: NSRange(location: 0, length: 1))
                    rendered.addAttribute(.font, value: NSFont.systemFont(ofSize: 16), range: NSRange(location: 0, length: 1))
                }
                if checked, rendered.length > 3 {
                    rendered.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: 3, length: rendered.length - 3))
                    rendered.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 3, length: rendered.length - 3))
                    rendered.addAttribute(.menuNoteTaskPresentationStrike, value: true, range: NSRange(location: 3, length: rendered.length - 3))
                }
            }
            result.append(rendered)
            if lineIndex < lines.count - 1 { result.append(NSAttributedString(string: "\n")) }
        }
        return result
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        let full = attributed.string as NSString
        var lines: [String] = []
        var codeLanguage: String?
        var start = 0
        while start <= full.length {
            let range = full.lineRange(for: NSRange(location: start, length: 0))
            var contentRange = range
            if contentRange.length > 0, full.substring(with: NSRange(location: NSMaxRange(contentRange) - 1, length: 1)) == "\n" {
                contentRange.length -= 1
            }
            let plain = full.substring(with: contentRange)
            let attributes = attributed.attributes(at: min(contentRange.location, max(0, attributed.length - 1)), effectiveRange: nil)
            let prefix = attributes[.menuNoteBlockPrefix] as? String ?? ""
            let taskLine = attributes[.menuNoteTaskLine] as? Int
            let taskIndent = attributes[.menuNoteTaskIndent] as? String ?? "- "
            let taskChecked = attributes[.menuNoteTaskChecked] as? Bool ?? false
            let taskCompletionStamp = attributes[.menuNoteTaskCompletionStamp] as? String
            let codeLanguageValue = attributes[.menuNoteCodeLanguage] as? String
            var encoded = inlineMarkdown(from: attributed, range: contentRange, ignoreStructuralFont: attributes[.menuNoteStructuralFont] != nil)

            if let language = codeLanguageValue {
                if codeLanguage == nil {
                    lines.append("```\(language)")
                    codeLanguage = language
                }
                lines.append(encoded)
            } else {
                if codeLanguage != nil {
                    lines.append("```")
                    codeLanguage = nil
                }
                if taskLine != nil {
                    encoded = encoded.replacingOccurrences(of: "☐  ", with: "", options: [.anchored])
                    encoded = encoded.replacingOccurrences(of: "☑  ", with: "", options: [.anchored])
                    let marker = taskChecked ? "[x]" : "[ ]"
                    let activeMarker = taskChecked ? " " + TaskArchiveCodec.activeCompletedMarker : ""
                    let completion = taskChecked
                        ? (taskCompletionStamp.map { " [完成时间: \($0)]" } ?? "")
                        : ""
                    lines.append("\(taskIndent)\(marker) \(encoded)\(completion)\(activeMarker)")
                } else if prefix == "task" {
                    lines.append("- [ ] \(encoded)")
                } else if prefix.hasPrefix("#") {
                    lines.append("\(prefix) \(encoded)")
                } else if prefix == ">" {
                    lines.append(encoded.isEmpty ? ">" : "> \(encoded)")
                } else if prefix == "---" {
                    lines.append("---")
                } else if !prefix.isEmpty, prefix != "task" {
                    if let listPrefix = listPrefix(from: prefix) {
                        encoded = stripVisibleListMarker(from: encoded, fallback: listPrefix.marker)
                        lines.append("\(listPrefix.indent)\(listPrefix.marker) \(encoded)")
                    } else {
                        lines.append("\(prefix) \(encoded)")
                    }
                } else {
                    lines.append(plain.isEmpty ? "" : encoded)
                }
            }

            let next = NSMaxRange(range)
            if next >= full.length { break }
            start = next
        }
        if codeLanguage != nil { lines.append("```") }
        return lines.joined(separator: "\n")
    }

    static func listPrefix(from prefix: String) -> (indent: String, marker: String)? {
        guard let groups = match("^(\\s*)([-*+]|\\d+[.)])$", in: prefix), groups.count >= 3 else { return nil }
        return (groups[1], groups[2])
    }

    static func stripVisibleListMarker(from text: String, fallback: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: fallback)
        return text.replacingOccurrences(of: "^(?:\(escaped)|•)\\s{1,2}", with: "", options: .regularExpression)
    }

    static func completionStamp(from text: String) -> String? {
        guard let groups = match("\\[完成时间:\\s*(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\]", in: text), groups.count > 1 else { return nil }
        return groups[1]
    }

    private static func inlineAttributed(_ source: String, font: NSFont, color: NSColor) -> NSMutableAttributedString {
        let output = NSMutableAttributedString(string: source, attributes: [.font: font, .foregroundColor: color])
        apply("`([^`]+)`", to: output) { attrs in
            attrs[.font] = monoFont
            attrs[.backgroundColor] = NSColor.labelColor.withAlphaComponent(0.08)
        }
        apply("\\*\\*([^*]+)\\*\\*", to: output) { attrs in attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        apply("(^|[^*])\\*([^*\\n]+)\\*", to: output) { attrs in attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        apply("~~([^~]+)~~", to: output) { attrs in attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)") {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
                guard match.numberOfRanges == 3 else { continue }
                let title = (source as NSString).substring(with: match.range(at: 1))
                let url = (source as NSString).substring(with: match.range(at: 2))
                output.replaceCharacters(in: match.range, with: title)
                output.addAttributes([.link: url, .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: NSRange(location: match.range.location, length: (title as NSString).length))
            }
        }
        // 删除剩余的样式标记；属性已应用到内容区。
        for regex in ["\\*\\*", "(?<!\\*)\\*", "~~", "`"] {
            output.mutableString.replaceOccurrences(of: regex, with: "", options: .regularExpression, range: NSRange(location: 0, length: output.length))
        }
        return output
    }

    private static func inlineMarkdown(from text: NSAttributedString, range: NSRange, ignoreStructuralFont: Bool = false) -> String {
        guard range.length > 0 else { return "" }
        var result = ""
        text.enumerateAttributes(in: range, options: []) { attrs, subrange, _ in
            var value = text.attributedSubstring(from: subrange).string
            if let link = attrs[.link] { value = "[\(value)](\(link))" }
            let font = attrs[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            if traits.contains(.boldFontMask), !ignoreStructuralFont { value = "**\(value)**" }
            if traits.contains(.italicFontMask) { value = "*\(value)*" }
            // 已完成活动任务的删除线只是视觉展示，不应被序列化成 Markdown 的 ~~…~~。
            if attrs[.strikethroughStyle] != nil, attrs[.menuNoteTaskPresentationStrike] == nil { value = "~~\(value)~~" }
            if font?.fontName.contains("Mono") == true { value = "`\(value)`" }
            result += value
        }
        return result
    }

    private static func apply(_ pattern: String, to output: NSMutableAttributedString, update: (inout [NSAttributedString.Key: Any]) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let original = output.string
        for match in regex.matches(in: original, range: NSRange(original.startIndex..., in: original)) {
            let target = match.numberOfRanges > 1 ? match.range(at: match.numberOfRanges - 1) : match.range
            var attrs = output.attributes(at: max(0, target.location), effectiveRange: nil)
            update(&attrs)
            output.addAttributes(attrs, range: target)
        }
    }

    private static func match(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<found.numberOfRanges).map { index in
            let range = found.range(at: index)
            guard range.location != NSNotFound, let swift = Range(range, in: text) else { return "" }
            return String(text[swift])
        }
    }
}
