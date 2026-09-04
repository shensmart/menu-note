import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 纯原生 TextKit 所见即所得编辑器。Markdown 标记只存在于文件中，
/// 编辑区显示语义化的标题、列表、格式文本与任务方框。
struct MarkdownRichTextEditor: NSViewRepresentable {
    let markdown: String
    let focusTaskLine: Int?
    var focusRequest: Int = 0
    var undoRequest: Int = 0
    var redoRequest: Int = 0
    let onChange: (String) -> Void
    let onCompleteTask: (Int) -> Void
    let onUncompleteTask: (Int) -> Void
    var copyLineHotKey: HotKey = .init(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey))
    var deleteLineHotKey: HotKey = .init(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey))
    var makeTaskHotKey: HotKey = LineActionHotKey.defaultMakeTask
    var taskFontSize: CGFloat = MarkdownDocumentCodec.defaultTaskFontSize
    var headingFontSize: CGFloat = MarkdownDocumentCodec.defaultHeadingFontSize

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onChange: onChange,
            onCompleteTask: onCompleteTask,
            onUncompleteTask: onUncompleteTask
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = TaskTextView()
        // NSScrollView 的 documentView 需要显式配置伸缩；否则在非激活 NSPanel 中
        // 可能保留 0 尺寸的初始 text container，导致看得到内容却不能放置编辑光标。
        textView.frame = scrollView.contentView.bounds
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.taskDelegate = context.coordinator
        textView.copyLineHotKey = copyLineHotKey
        textView.deleteLineHotKey = deleteLineHotKey
        textView.makeTaskHotKey = makeTaskHotKey
        textView.taskFontSize = taskFontSize
        textView.headingFontSize = headingFontSize
        textView.textStorage?.setAttributedString(MarkdownDocumentCodec.attributedDocument(
            from: markdown,
            taskFontSize: taskFontSize,
            headingFontSize: headingFontSize
        ))
        if markdown.isEmpty {
            textView.setHeadingTypingAttributes()
        }
        context.coordinator.lastMarkdown = markdown
        context.coordinator.lastTaskFontSize = taskFontSize
        context.coordinator.lastHeadingFontSize = headingFontSize
        context.coordinator.handledUndoRequest = undoRequest
        context.coordinator.handledRedoRequest = redoRequest
        context.coordinator.textView = textView
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onCompleteTask = onCompleteTask
        context.coordinator.onUncompleteTask = onUncompleteTask
        (scrollView.documentView as? TaskTextView)?.copyLineHotKey = copyLineHotKey
        (scrollView.documentView as? TaskTextView)?.deleteLineHotKey = deleteLineHotKey
        (scrollView.documentView as? TaskTextView)?.makeTaskHotKey = makeTaskHotKey
        (scrollView.documentView as? TaskTextView)?.taskFontSize = taskFontSize
        (scrollView.documentView as? TaskTextView)?.headingFontSize = headingFontSize
        guard let textView = scrollView.documentView as? TaskTextView,
              !context.coordinator.isApplying else { return }
        if context.coordinator.handledUndoRequest != undoRequest {
            context.coordinator.handledUndoRequest = undoRequest
            textView.window?.makeFirstResponder(textView)
            textView.undoManager?.undo()
            return
        }
        if context.coordinator.handledRedoRequest != redoRequest {
            context.coordinator.handledRedoRequest = redoRequest
            textView.window?.makeFirstResponder(textView)
            textView.undoManager?.redo()
            return
        }
        let needsFormattingRefresh = context.coordinator.lastMarkdown != markdown
            || context.coordinator.lastTaskFontSize != taskFontSize
            || context.coordinator.lastHeadingFontSize != headingFontSize
        guard needsFormattingRefresh else {
            // 本地编辑保存后的 SwiftUI 确认：绝不能重建 NSTextStorage，
            // 否则 TextKit 原生维护的光标和多段选区都会丢失。
            if let line = focusTaskLine, context.coordinator.focusedTaskRequest != focusRequest {
                context.coordinator.focusTaskLine(line)
                context.coordinator.focusedTaskRequest = focusRequest
            }
            return
        }

        let oldSelection = textView.selectedRange()
        // 外部状态（例如从“已完成”恢复任务组）刷新编辑器时，先取消旧的延迟保存。
        // 否则旧 TextStorage 可能在刷新后再次写回，覆盖刚恢复的任务顺序和缩进。
        context.coordinator.cancelPendingChange()
        context.coordinator.isApplying = true
        textView.textStorage?.setAttributedString(MarkdownDocumentCodec.attributedDocument(
            from: markdown,
            taskFontSize: taskFontSize,
            headingFontSize: headingFontSize
        ))
        if markdown.isEmpty {
            textView.setHeadingTypingAttributes()
        }
        let maxLocation = textView.string.utf16.count
        textView.setSelectedRange(NSRange(
            location: min(oldSelection.location, maxLocation),
            length: min(oldSelection.length, max(0, maxLocation - min(oldSelection.location, maxLocation)))
        ))
        context.coordinator.lastMarkdown = markdown
        context.coordinator.lastTaskFontSize = taskFontSize
        context.coordinator.lastHeadingFontSize = headingFontSize
        context.coordinator.isApplying = false
        if let line = focusTaskLine, context.coordinator.focusedTaskRequest != focusRequest {
            context.coordinator.focusTaskLine(line)
            context.coordinator.focusedTaskRequest = focusRequest
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        // 切换到 Markdown 源码/预览模式时，旧富文本编辑器可能仍有一个延迟保存任务。
        // 如果不取消，它会在切换后用旧内容覆盖用户刚刚编辑的源码。
        coordinator.cancelPendingChange()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, TaskTextViewDelegate {
        var onChange: (String) -> Void
        var onCompleteTask: (Int) -> Void
        var onUncompleteTask: (Int) -> Void
        weak var textView: TaskTextView?
        var lastMarkdown = ""
        var lastTaskFontSize = MarkdownDocumentCodec.defaultTaskFontSize
        var lastHeadingFontSize = MarkdownDocumentCodec.defaultHeadingFontSize
        var isApplying = false
        var focusedTaskRequest: Int?
        var handledUndoRequest = 0
        var handledRedoRequest = 0
        private var saveWorkItem: DispatchWorkItem?
        private var saveGeneration = 0

        init(
            onChange: @escaping (String) -> Void,
            onCompleteTask: @escaping (Int) -> Void,
            onUncompleteTask: @escaping (Int) -> Void
        ) {
            self.onChange = onChange
            self.onCompleteTask = onCompleteTask
            self.onUncompleteTask = onUncompleteTask
        }

        func focusTaskLine(_ line: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            for index in 0..<storage.length {
                if storage.attribute(.menuNoteTaskLine, at: index, effectiveRange: nil) as? Int == line {
                    textView.window?.makeFirstResponder(textView)
                    let target = min(index + 3, storage.length)
                    textView.setSelectedRange(NSRange(location: target, length: 0))
                    textView.scrollRangeToVisible(NSRange(location: target, length: 0))
                    return
                }
            }
        }

        func cancelPendingChange() {
            saveGeneration += 1
            saveWorkItem?.cancel()
            saveWorkItem = nil
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying else { return }
            cancelPendingChange()
            let generation = saveGeneration
            let task = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.saveGeneration == generation else { return }
                // 删除任务框后，TextKit 可能仍把这一行保留为任务字体。
                // 以当前可见内容重新判断行类型，避免后续输入继续继承旧任务样式。
                guard let textView = self.textView else { return }
                textView.normalizeLinePresentation()
                let markdown = MarkdownDocumentCodec.markdown(from: textView.attributedString())
                self.reindexTaskLines(using: markdown)
                // 与存储层确认的 Markdown 完全一致时，updateNSView 不会替换 TextKit 内容。
                self.lastMarkdown = markdown
                self.onChange(markdown)
            }
            saveWorkItem = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: task)
        }

        private func reindexTaskLines(using markdown: String) {
            guard let textView, let storage = textView.textStorage else { return }
            let sourceLines = markdown.components(separatedBy: "\n")
            var sourceLine = 0
            let text = storage.string as NSString
            var location = 0
            while location < text.length {
                let range = text.lineRange(for: NSRange(location: location, length: 0))
                let contentLength = max(0, range.length - (text.substring(with: range).hasSuffix("\n") ? 1 : 0))
                if contentLength > 0,
                   storage.attribute(.menuNoteTaskLine, at: range.location, effectiveRange: nil) != nil {
                    while sourceLine < sourceLines.count, !isTaskLine(sourceLines[sourceLine]) { sourceLine += 1 }
                    if sourceLine < sourceLines.count {
                        let contentRange = NSRange(location: range.location, length: contentLength)
                        let sourceTask = sourceLines[sourceLine]
                        storage.addAttribute(.menuNoteTaskLine, value: sourceLine, range: contentRange)
                        if let taskIndent = taskIndent(from: sourceTask) {
                            let indentation = CGFloat(taskIndent.prefix { $0 == " " }.count / 2) * 18
                            let paragraph = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                                ?? NSMutableParagraphStyle()
                            paragraph.firstLineHeadIndent = indentation
                            paragraph.headIndent = indentation + 25
                            storage.addAttributes([
                                .menuNoteTaskIndent: taskIndent,
                                .paragraphStyle: paragraph,
                            ], range: contentRange)
                        }
                        sourceLine += 1
                    }
                }
                location = NSMaxRange(range)
            }
        }

        private func isTaskLine(_ line: String) -> Bool {
            line.range(of: "^(\\s*[-*+]\\s+)\\[([ xX])\\]", options: .regularExpression) != nil
        }

        private func taskIndent(from line: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: "^(\\s*)([-*+])\\s+\\[[ xX]\\]") else { return nil }
            let nsLine = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges >= 3 else {
                return nil
            }
            return "\(nsLine.substring(with: match.range(at: 1)))\(nsLine.substring(with: match.range(at: 2))) "
        }

        func taskTextView(_ textView: TaskTextView, didClickTaskAt line: Int, checked: Bool) {
            // 不取消刚输入的内容：先立刻把当前富文本同步到存储层，再完成该任务。
            cancelPendingChange()
            let markdown = MarkdownDocumentCodec.markdown(from: textView.attributedString())
            lastMarkdown = ""
            onChange(markdown)
            DispatchQueue.main.async { [weak self] in
                if checked {
                    self?.onUncompleteTask(line)
                } else {
                    self?.onCompleteTask(line)
                }
            }
        }

    }
}

protocol TaskTextViewDelegate: AnyObject {
    func taskTextView(_ textView: TaskTextView, didClickTaskAt line: Int, checked: Bool)
}

final class TaskTextView: NSTextView {
    weak var taskDelegate: TaskTextViewDelegate?
    // NSTextView 从 window 获取 undoManager；在 SwiftUI 的非激活面板以及脱离 window
    // 的编辑器测试中可能拿不到它。编辑器的结构化操作（例如删除任务框并调整子任务）
    // 必须始终使用同一个撤销栈，因此为每个编辑器保留独立的本地 UndoManager。
    private let localUndoManager = UndoManager()
    var copyLineHotKey: HotKey = .init(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey))
    var deleteLineHotKey: HotKey = .init(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey))
    var makeTaskHotKey: HotKey = LineActionHotKey.defaultMakeTask
    var taskFontSize: CGFloat = MarkdownDocumentCodec.defaultTaskFontSize
    var headingFontSize: CGFloat = MarkdownDocumentCodec.defaultHeadingFontSize

    override var undoManager: UndoManager? {
        localUndoManager
    }

    override func mouseDown(with event: NSEvent) {
        // 非激活面板不会总是自动把 NSTextView 放进 responder chain；显式接管。
        window?.makeFirstResponder(self)
        guard let layoutManager, let textContainer else {
            super.mouseDown(with: event)
            setTypingAttributesForCurrentLine()
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let point = NSPoint(x: location.x - origin.x, y: location.y - origin.y)
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        guard character < textStorage?.length ?? 0 else {
            super.mouseDown(with: event)
            setTypingAttributesForCurrentLine()
            return
        }
        let attrs = textStorage?.attributes(at: character, effectiveRange: nil) ?? [:]
        guard let line = attrs[.menuNoteTaskLine] as? Int else {
            super.mouseDown(with: event)
            setTypingAttributesForCurrentLine()
            return
        }
        let checked = attrs[.menuNoteTaskChecked] as? Bool ?? false
        let taskParagraph = (textStorage?.string as NSString?)?.lineRange(for: NSRange(location: character, length: 0)) ?? .init()
        let checkboxCharacter = NSRange(location: taskParagraph.location, length: 1)
        guard taskParagraph.length > 0,
              ["☐", "☑"].contains((textStorage?.string as NSString?)?.substring(with: checkboxCharacter)) else {
            super.mouseDown(with: event)
            setTypingAttributesForCurrentLine()
            return
        }
        let checkboxGlyphs = layoutManager.glyphRange(forCharacterRange: checkboxCharacter, actualCharacterRange: nil)
        let checkboxRect = layoutManager.boundingRect(forGlyphRange: checkboxGlyphs, in: textContainer)
        guard checkboxGlyphs.length > 0, checkboxRect.contains(point) else {
            // 标题、空白和任务正文：交给 NSTextView 的标准编辑/选取行为。
            super.mouseDown(with: event)
            setTypingAttributesForCurrentLine()
            return
        }
        taskDelegate?.taskTextView(self, didClickTaskAt: line, checked: checked)
    }

    override func insertTab(_ sender: Any?) {
        if adjustSelectedTaskIndent(by: 1) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if adjustSelectedTaskIndent(by: -1) { return }
        super.insertBacktab(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if removeTaskMarkerIfNeeded(forward: false) { return }
        let hadSelection = selectedRange().length > 0
        super.deleteBackward(sender)
        if hadSelection, textStorage?.length == 0 {
            setHeadingTypingAttributes()
        }
    }

    override func deleteForward(_ sender: Any?) {
        if removeTaskMarkerIfNeeded(forward: true) { return }
        let hadSelection = selectedRange().length > 0
        super.deleteForward(sender)
        if hadSelection, textStorage?.length == 0 {
            setHeadingTypingAttributes()
        }
    }

    /// 删除光标附近的任务框，并把该行变为标题。
    /// 如果任务有子任务，子任务同时向上收缩一级，避免脱离原来的层级。
    @discardableResult
    private func removeTaskMarkerIfNeeded(forward: Bool) -> Bool {
        guard let storage = textStorage, selectedRange().length == 0 else { return false }
        let source = storage.string as NSString
        let cursor = min(selectedRange().location, source.length)
        let paragraph = source.lineRange(for: NSRange(location: cursor, length: 0))
        let contentLength = max(0, paragraph.length - (source.substring(with: paragraph).hasSuffix("\n") ? 1 : 0))
        guard contentLength > 0 else { return false }
        let contentRange = NSRange(location: paragraph.location, length: contentLength)
        let attrs = storage.attributes(at: contentRange.location, effectiveRange: nil)
        guard attrs[.menuNoteTaskLine] != nil else { return false }
        let visible = storage.attributedSubstring(from: contentRange).string
        guard visible.hasPrefix("☐  ") || visible.hasPrefix("☑  ") else { return false }
        if visible.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 空任务仍按原行为只删除整行的可视化任务框，保留空行；它不是一个
            // 可以转换为标题并参与任务组重排的标题。
            let activeUndoManager = undoManager
            activeUndoManager?.disableUndoRegistration()
            defer { activeUndoManager?.enableUndoRegistration() }
            guard shouldChangeText(in: contentRange, replacementString: "") else { return false }
            storage.replaceCharacters(in: contentRange, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: min(contentRange.location, storage.length), length: 0))
            setHeadingTypingAttributes()
            return true
        }
        let markerEnd = paragraph.location + 3
        if forward {
            guard cursor == paragraph.location else { return false }
        } else {
            guard cursor > paragraph.location, cursor <= markerEnd else { return false }
        }

        let originalIndent = (attrs[.paragraphStyle] as? NSParagraphStyle)?.firstLineHeadIndent ?? 0
        let beforeChange = attributedSnapshot()
        let beforeSelection = selectedRange()

        // 只移除可视化的“☐  ”，保留标题正文和行尾换行符。
        let removal = NSRange(location: paragraph.location, length: min(3, contentLength))
        let activeUndoManager = undoManager
        activeUndoManager?.disableUndoRegistration()
        guard shouldChangeText(in: removal, replacementString: "") else {
            activeUndoManager?.enableUndoRegistration()
            return false
        }
        storage.replaceCharacters(in: removal, with: "")

        var updatedSource = storage.string as NSString
        var updatedParagraph = updatedSource.lineRange(for: NSRange(location: min(removal.location, updatedSource.length), length: 0))

        // 目标任务变成顶级标题后，原来排在它后面的同级任务不能继续留在
        // “脱离出来的子任务”之后，否则 Markdown 会把它们解析成最后一个顶级子任务的孩子。
        // 将这一段兄弟任务整体移到目标标题之前，保留它们原本属于父任务的关系。
        if let parentIndent = taskParentIndent(before: updatedParagraph.location, childIndent: originalIndent) {
            let targetSubtreeEnd = descendantBlockEnd(after: updatedParagraph, childIndent: originalIndent)
            let parentSubtreeEnd = blockEnd(after: targetSubtreeEnd, greaterThan: parentIndent)
            if parentSubtreeEnd > targetSubtreeEnd {
                let siblingBlock = NSRange(
                    location: targetSubtreeEnd,
                    length: parentSubtreeEnd - targetSubtreeEnd
                )
                let moved = NSAttributedString(attributedString: storage.attributedSubstring(from: siblingBlock))
                storage.deleteCharacters(in: siblingBlock)
                storage.insert(moved, at: updatedParagraph.location)
                updatedSource = storage.string as NSString
                updatedParagraph = updatedSource.lineRange(
                    for: NSRange(location: updatedParagraph.location + moved.length, length: 0)
                )
            }
        }

        if taskParentIndent(before: updatedParagraph.location, childIndent: originalIndent) != nil {
            // 转成标题的任务及其子任务属于一个新的标题区块。把这个区块放到当前
            // 标题下剩余的顶级任务之后、下一个标题之前，避免最后一个顶级任务被
            // 视觉上误认为是新标题下的任务。
            let targetBlockEnd = descendantBlockEnd(after: updatedParagraph, childIndent: originalIndent)
            let sectionContentEnd = sectionContentEnd(after: targetBlockEnd)
            if sectionContentEnd > targetBlockEnd {
                let targetBlock = NSRange(
                    location: updatedParagraph.location,
                    length: targetBlockEnd - updatedParagraph.location
                )
                let moved = NSAttributedString(attributedString: storage.attributedSubstring(from: targetBlock))
                var insertion = sectionContentEnd - targetBlock.length
                storage.deleteCharacters(in: targetBlock)

                // 目标区块可能被移到原文最后一行之后；如果前一行没有换行，
                // 补上行边界，避免标题和最后一个任务粘成同一行。
                if insertion > 0,
                   sourceCharacter(at: insertion - 1, in: storage.string as NSString) != "\n" {
                    storage.insert(NSAttributedString(string: "\n"), at: insertion)
                    insertion += 1
                }
                storage.insert(moved, at: insertion)
                updatedSource = storage.string as NSString
                updatedParagraph = updatedSource.lineRange(
                    for: NSRange(location: insertion, length: 0)
                )
            }
        }

        updatedSource = storage.string as NSString
        let updatedHasNewline = updatedParagraph.length > 0
            && updatedSource.substring(with: NSRange(location: NSMaxRange(updatedParagraph) - 1, length: 1)) == "\n"
        let updatedContentLength = max(0, updatedParagraph.length - (updatedHasNewline ? 1 : 0))
        var titleAttributes = attrs
        let titleParagraph = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        titleParagraph.firstLineHeadIndent = 0
        titleParagraph.headIndent = 0
        titleAttributes[.paragraphStyle] = titleParagraph
        if updatedContentLength > 0 {
            applyHeadingPresentation(
                to: NSRange(location: updatedParagraph.location, length: updatedContentLength),
                basedOn: titleAttributes
            )
        } else if updatedParagraph.location < storage.length {
            applyHeadingPresentation(
                to: NSRange(location: updatedParagraph.location, length: 1),
                basedOn: titleAttributes
            )
        }
        promoteDescendantLines(
            after: updatedParagraph,
            originalParentIndent: originalIndent,
            targetParentIndent: titleParagraph.firstLineHeadIndent
        )
        didChangeText()
        // 标题可能已经被移到当前任务组末尾，光标也要跟随标题，避免下一次输入
        // 落到原位置的 4.2/4.3 任务行中。
        setSelectedRange(NSRange(location: min(updatedParagraph.location, storage.length), length: 0))
        activeUndoManager?.enableUndoRegistration()
        registerSnapshotUndo(before: beforeChange, selection: beforeSelection, actionName: "删除任务框")
        setHeadingTypingAttributes()
        return true
    }

    private func taskParentIndent(before location: Int, childIndent: CGFloat) -> CGFloat? {
        guard let storage = textStorage else { return nil }
        let source = storage.string as NSString
        var cursor = min(location, source.length)
        while cursor > 0 {
            let line = source.lineRange(for: NSRange(location: cursor - 1, length: 0))
            let attributes = storage.attributes(at: line.location, effectiveRange: nil)
            let indent = (attributes[.paragraphStyle] as? NSParagraphStyle)?.firstLineHeadIndent ?? 0
            if attributes[.menuNoteTaskLine] != nil, indent < childIndent {
                return indent
            }
            cursor = line.location
        }
        return nil
    }

    private func descendantBlockEnd(after parent: NSRange, childIndent: CGFloat) -> Int {
        guard let storage = textStorage else { return NSMaxRange(parent) }
        let source = storage.string as NSString
        var location = NSMaxRange(parent)
        while location < source.length {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            let attributes = storage.attributes(at: line.location, effectiveRange: nil)
            let indent = (attributes[.paragraphStyle] as? NSParagraphStyle)?.firstLineHeadIndent ?? 0
            guard indent > childIndent else { break }
            location = NSMaxRange(line)
        }
        return location
    }

    private func blockEnd(after location: Int, greaterThan indentLimit: CGFloat) -> Int {
        guard let storage = textStorage else { return location }
        let source = storage.string as NSString
        var cursor = location
        while cursor < source.length {
            let line = source.lineRange(for: NSRange(location: cursor, length: 0))
            let attributes = storage.attributes(at: line.location, effectiveRange: nil)
            let indent = (attributes[.paragraphStyle] as? NSParagraphStyle)?.firstLineHeadIndent ?? 0
            guard indent > indentLimit else { break }
            cursor = NSMaxRange(line)
        }
        return cursor
    }

    /// 返回当前标题区块内容的末尾，去掉区块末尾的空白行。
    /// 标题行的结构属性由 MarkdownDocumentCodec 写入，普通文本行在所见即所得
    /// 模式下也会使用标题前缀，因此这里不依赖源文本是否显式写了 `#`。
    private func sectionContentEnd(after location: Int) -> Int {
        guard let storage = textStorage else { return location }
        let source = storage.string as NSString
        var cursor = min(location, source.length)
        var boundary = source.length

        while cursor < source.length {
            let line = source.lineRange(for: NSRange(location: cursor, length: 0))
            let hasNewline = line.length > 0
                && source.substring(with: NSRange(location: NSMaxRange(line) - 1, length: 1)) == "\n"
            let contentLength = max(0, line.length - (hasNewline ? 1 : 0))
            let visible = contentLength > 0
                ? source.substring(with: NSRange(location: line.location, length: contentLength))
                : ""
            let attributes = storage.attributes(at: line.location, effectiveRange: nil)
            let prefix = attributes[.menuNoteBlockPrefix] as? String ?? ""
            if !visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               prefix.hasPrefix("#") {
                boundary = line.location
                break
            }
            cursor = NSMaxRange(line)
        }

        var contentEnd = boundary
        while contentEnd > location {
            let previousLine = source.lineRange(for: NSRange(location: contentEnd - 1, length: 0))
            let hasNewline = previousLine.length > 0
                && source.substring(with: NSRange(location: NSMaxRange(previousLine) - 1, length: 1)) == "\n"
            let contentLength = max(0, previousLine.length - (hasNewline ? 1 : 0))
            let visible = contentLength > 0
                ? source.substring(with: NSRange(location: previousLine.location, length: contentLength))
                : ""
            guard visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            contentEnd = previousLine.location
        }
        return contentEnd
    }

    private func sourceCharacter(at location: Int, in source: NSString) -> String {
        guard location >= 0, location < source.length else { return "" }
        return source.substring(with: NSRange(location: location, length: 1))
    }

    private func registerSnapshotUndo(before: NSAttributedString, selection: NSRange, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            let current = target.attributedSnapshot()
            let currentSelection = target.selectedRange()
            target.restoreSnapshot(before, selection: selection)
            target.registerSnapshotUndo(before: current, selection: currentSelection, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// NSTextView.attributedString() 可能直接返回当前 NSTextStorage；结构化编辑前必须复制，
    /// 否则后续调整段落属性会把 Undo 快照一起改掉。
    private func attributedSnapshot() -> NSAttributedString {
        NSAttributedString(attributedString: attributedString())
    }

    private func restoreSnapshot(_ snapshot: NSAttributedString, selection: NSRange) {
        let activeUndoManager = undoManager
        activeUndoManager?.disableUndoRegistration()
        defer { activeUndoManager?.enableUndoRegistration() }
        textStorage?.setAttributedString(snapshot)
        let maxLocation = textStorage?.length ?? 0
        setSelectedRange(NSRange(
            location: min(selection.location, maxLocation),
            length: min(selection.length, max(0, maxLocation - min(selection.location, maxLocation)))
        ))
    }

    private func promoteDescendantLines(
        after parent: NSRange,
        originalParentIndent: CGFloat,
        targetParentIndent: CGFloat
    ) {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        var location = NSMaxRange(parent)
        let oneLevel = CGFloat(36)
        let levelsToRemove = max(
            1,
            Int(round((originalParentIndent - targetParentIndent) / oneLevel)) + 1
        )
        let spacesToRemove = levelsToRemove * 4

        while location < source.length {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            let contentLength = max(0, line.length - (source.substring(with: line).hasSuffix("\n") ? 1 : 0))
            let attributes = storage.attributes(at: line.location, effectiveRange: nil)
            let currentIndent = (attributes[.paragraphStyle] as? NSParagraphStyle)?.firstLineHeadIndent ?? 0
            guard currentIndent > originalParentIndent else { break }

            let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = max(targetParentIndent, currentIndent - CGFloat(spacesToRemove / 4) * oneLevel)
            paragraph.headIndent = max(25, paragraph.headIndent - CGFloat(spacesToRemove / 4) * oneLevel)
            let targetLength = max(1, contentLength)
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: line.location, length: targetLength))

            if let taskIndent = attributes[.menuNoteTaskIndent] as? String,
               taskIndent.count >= spacesToRemove,
               taskIndent.prefix(spacesToRemove).allSatisfy({ $0 == " " }) {
                storage.addAttribute(.menuNoteTaskIndent, value: String(taskIndent.dropFirst(spacesToRemove)), range: NSRange(location: line.location, length: targetLength))
            }
            if let prefix = attributes[.menuNoteBlockPrefix] as? String,
               prefix.count >= spacesToRemove,
               prefix.prefix(spacesToRemove).allSatisfy({ $0 == " " }) {
                storage.addAttribute(.menuNoteBlockPrefix, value: String(prefix.dropFirst(spacesToRemove)), range: NSRange(location: line.location, length: targetLength))
            }
            location = NSMaxRange(line)
        }
    }

    /// 改变当前行或选中多行任务的 Markdown 缩进层级。使用四个空格，绝不写入实际 Tab 字符。
    @discardableResult
    private func adjustSelectedTaskIndent(by levels: Int) -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let source = storage.string as NSString
        let selection = selectedRange()
        let end = max(selection.location, NSMaxRange(selection) - 1)
        var location = source.lineRange(for: NSRange(location: min(selection.location, source.length), length: 0)).location
        let finalEnd = NSMaxRange(source.lineRange(for: NSRange(location: min(end, source.length), length: 0)))
        var changed = false

        while location < finalEnd {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let contentLength = max(0, lineRange.length - (source.substring(with: lineRange).hasSuffix("\n") ? 1 : 0))
            guard contentLength > 0 else { location = NSMaxRange(lineRange); continue }
            let contentRange = NSRange(location: lineRange.location, length: contentLength)
            let attrs = storage.attributes(at: contentRange.location, effectiveRange: nil)
            guard attrs[.menuNoteTaskLine] != nil,
                  let oldPrefix = attrs[.menuNoteTaskIndent] as? String else {
                location = NSMaxRange(lineRange)
                continue
            }

            let newPrefix: String
            if levels > 0 {
                newPrefix = "    " + oldPrefix
            } else {
                guard oldPrefix.hasPrefix("    ") else {
                    location = NSMaxRange(lineRange)
                    continue
                }
                newPrefix = String(oldPrefix.dropFirst(4))
            }
            let indentation = CGFloat(newPrefix.prefix { $0 == " " }.count / 2) * 18
            let paragraph = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = indentation
            paragraph.headIndent = indentation + 25
            let newAttrs: [NSAttributedString.Key: Any] = [
                .menuNoteTaskIndent: newPrefix,
                .paragraphStyle: paragraph,
            ]
            // 只更新结构属性，绝不复制方框字符的蓝色/16pt 外观到整行正文。
            storage.addAttributes(newAttrs, range: contentRange)
            changed = true
            location = NSMaxRange(lineRange)
        }
        if changed { didChangeText() }
        return changed
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == [.command] {
            switch key {
            case "a":
                selectAll(nil)
                return
            case "c":
                copy(nil)
                return
            case "v":
                paste(nil)
                return
            case "x":
                cut(nil)
                return
            case "z":
                undoManager?.undo()
                return
            case "b":
                toggleTrait(.boldFontMask)
                return
            case "i":
                toggleTrait(.italicFontMask)
                return
            case "7" where event.modifierFlags.contains(.shift):
                toggleOrderedList()
                return
            default:
                break
            }
        }
        if flags == [.command, .shift], key == "z" {
            undoManager?.redo()
            return
        }
        if matchesHotKey(event, hotKey: makeTaskHotKey) {
            convertCurrentLineToTask()
            return
        }
        if matchesHotKey(event, hotKey: copyLineHotKey) {
            duplicateCurrentLines()
            return
        }
        if matchesHotKey(event, hotKey: deleteLineHotKey) {
            deleteCurrentLines()
            return
        }
        super.keyDown(with: event)
    }

    /// 将光标所在行转换为未完成任务，保留当前行的缩进和正文格式。
    /// 已经是任务行时不重复添加任务框。
    @discardableResult
    func convertCurrentLineToTask() -> Bool {
        guard let storage = textStorage else { return false }
        let source = storage.string as NSString
        let cursor = min(selectedRange().location, source.length)
        let lineRange = source.lineRange(for: NSRange(location: cursor, length: 0))
        let hasNewline = lineRange.length > 0
            && source.substring(with: NSRange(location: NSMaxRange(lineRange) - 1, length: 1)) == "\n"
        let contentLength = max(0, lineRange.length - (hasNewline ? 1 : 0))
        let contentRange = NSRange(location: lineRange.location, length: contentLength)
        let visibleLine = source.substring(with: contentRange)
        let attributes = contentLength > 0
            ? storage.attributes(at: contentRange.location, effectiveRange: nil)
            : typingAttributes

        if attributes[.menuNoteTaskLine] != nil
            || visibleLine.hasPrefix("☐  ")
            || visibleLine.hasPrefix("☑  ") {
            return false
        }

        let oldCursor = selectedRange().location
        var titleRange = contentRange
        var indent = ""

        if let prefix = attributes[.menuNoteBlockPrefix] as? String,
           let list = MarkdownDocumentCodec.listPrefix(from: prefix) {
            indent = list.indent
            let visibleMarker = list.marker.first?.isNumber == true
                ? "\(list.marker)  "
                : "•  "
            let markerLength = (visibleMarker as NSString).length
            if visibleLine.hasPrefix(visibleMarker), markerLength <= titleRange.length {
                titleRange.location += markerLength
                titleRange.length -= markerLength
            }
        } else {
            let leadingCount = visibleLine.prefix { $0 == " " || $0 == "\t" }.count
            if leadingCount >= 4 {
                let indentCount = (leadingCount / 4) * 4
                indent = String(visibleLine.prefix(indentCount))
                titleRange.location += (indent as NSString).length
                titleRange.length -= (indent as NSString).length
            } else if leadingCount > 0 {
                // 删除过任务框后残留的两个显示空格属于任务框间距，不是层级缩进。
                titleRange.location += leadingCount
                titleRange.length -= leadingCount
            } else if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
                let levels = max(0, Int(round(paragraph.firstLineHeadIndent / 18)))
                indent = String(repeating: "    ", count: levels)
            }
        }

        let title = taskTitlePresentation(from: storage.attributedSubstring(from: titleRange))
        let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        let visualIndent = CGFloat(indent.count / 2) * 18
        paragraph.firstLineHeadIndent = visualIndent
        paragraph.headIndent = visualIndent + 25

        var taskAttributes = attributes
        taskAttributes[.font] = NSFont.systemFont(ofSize: taskFontSize)
        taskAttributes[.foregroundColor] = NSColor.labelColor
        taskAttributes[.paragraphStyle] = paragraph
        taskAttributes[.menuNoteBlockPrefix] = "task"
        taskAttributes[.menuNoteTaskLine] = -1
        taskAttributes[.menuNoteTaskIndent] = indent + "- "
        taskAttributes[.menuNoteTaskChecked] = false
        taskAttributes.removeValue(forKey: .menuNoteTaskCompletionStamp)
        taskAttributes.removeValue(forKey: .menuNoteTaskPresentationStrike)

        let replacement = NSMutableAttributedString(string: "☐  ", attributes: taskAttributes)
        replacement.append(title)
        replacement.addAttributes([
            .paragraphStyle: paragraph,
            .menuNoteBlockPrefix: "task",
            .menuNoteTaskLine: -1,
            .menuNoteTaskIndent: indent + "- ",
            .menuNoteTaskChecked: false,
        ], range: NSRange(location: 0, length: replacement.length))
        replacement.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: NSRange(location: 0, length: 1))
        replacement.addAttribute(.font, value: NSFont.systemFont(ofSize: 16), range: NSRange(location: 0, length: 1))

        guard shouldChangeText(in: contentRange, replacementString: replacement.string) else { return false }
        storage.replaceCharacters(in: contentRange, with: replacement)
        didChangeText()

        let titleOffset = max(0, min(oldCursor, NSMaxRange(titleRange)) - titleRange.location)
        setSelectedRange(NSRange(
            location: min(lineRange.location + 3 + titleOffset, storage.length),
            length: 0
        ))
        typingAttributes = [
            .font: NSFont.systemFont(ofSize: taskFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        return true
    }

    private func taskTitlePresentation(from title: NSAttributedString) -> NSMutableAttributedString {
        let result = title.mutableCopy() as? NSMutableAttributedString ?? NSMutableAttributedString(attributedString: title)
        guard result.length > 0 else { return result }
        var fontRanges: [(NSRange, NSFont)] = []
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length), options: []) { value, range, _ in
            if let font = value as? NSFont { fontRanges.append((range, font)) }
        }
        for (range, currentFont) in fontRanges where !currentFont.fontName.contains("Mono") {
            let traits = NSFontManager.shared.traits(of: currentFont)
            var taskFont = NSFont.systemFont(ofSize: taskFontSize)
            // 标题默认使用 semibold；这里只继承真正的斜体，避免把标题字重
            // 误当成任务正文的粗体。
            if traits.contains(.italicFontMask) {
                taskFont = NSFontManager.shared.convert(taskFont, toHaveTrait: .italicFontMask)
            }
            result.addAttributes([
                .font: taskFont,
                .foregroundColor: NSColor.labelColor,
            ], range: range)
        }
        return result
    }

    /// 空白文档的第一行作为标题输入，后续回车会继续使用标题样式。
    func setHeadingTypingAttributes(prefix: String = "#") {
        let level = max(1, min(6, prefix.filter { $0 == "#" }.count))
        let ratios: [CGFloat] = [0, 1, 18 / 21, 16 / 21, 15 / 21, 14 / 21, 14 / 21]
        typingAttributes = [
            .font: NSFont.systemFont(ofSize: headingFontSize * ratios[level], weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .menuNoteBlockPrefix: prefix,
            .menuNoteStructuralFont: true,
        ]
    }

    /// 按编辑器当前可见文本重新整理非任务行的字体。
    /// 任务行必须以方框开头；其余普通内容统一使用标题样式。
    func normalizeLinePresentation() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let source = storage.string as NSString
        var location = 0
        while location < source.length {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            let hasNewline = line.length > 0
                && source.substring(with: NSRange(location: NSMaxRange(line) - 1, length: 1)) == "\n"
            let contentLength = max(0, line.length - (hasNewline ? 1 : 0))
            let contentRange = NSRange(location: line.location, length: contentLength)
            let visible = contentLength > 0 ? source.substring(with: contentRange) : ""
            let isTask = visible.hasPrefix("☐  ") || visible.hasPrefix("☑  ")
            if isTask {
                normalizeTaskPresentation(in: contentRange)
            } else {
                let attributes = contentLength > 0
                    ? storage.attributes(at: contentRange.location, effectiveRange: nil)
                    : storage.attributes(at: line.location, effectiveRange: nil)
                let oldPrefix = attributes[.menuNoteBlockPrefix] as? String ?? ""
                let prefix = oldPrefix.isEmpty || oldPrefix == "task" ? "#" : oldPrefix
                let target = contentLength > 0
                    ? contentRange
                    : NSRange(location: line.location, length: min(1, source.length - line.location))
                applyHeadingPresentation(to: target, basedOn: attributes, prefix: prefix)
            }
            location = NSMaxRange(line)
        }
    }

    private func normalizeTaskPresentation(in range: NSRange) {
        guard let storage = textStorage, range.length >= 3 else { return }
        let markerRange = NSRange(location: range.location, length: 1)
        let bodyRange = NSRange(location: range.location + 3, length: range.length - 3)
        let lineAttributes = storage.attributes(at: range.location, effectiveRange: nil)
        let isChecked = lineAttributes[.menuNoteTaskChecked] as? Bool ?? false

        // 任务框只是视觉标记；任务正文不能继续沿用标题的字号/字重。
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 16), range: markerRange)
        storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: markerRange)
        storage.removeAttribute(.menuNoteStructuralFont, range: range)

        guard bodyRange.length > 0 else { return }
        var fontRanges: [(NSRange, NSFont)] = []
        storage.enumerateAttribute(.font, in: bodyRange, options: []) { value, subrange, _ in
            if let font = value as? NSFont { fontRanges.append((subrange, font)) }
        }
        for (fontRange, currentFont) in fontRanges where !currentFont.fontName.contains("Mono") {
            let traits = NSFontManager.shared.traits(of: currentFont)
            var taskFont = NSFont.systemFont(ofSize: taskFontSize)
            if traits.contains(.italicFontMask) {
                taskFont = NSFontManager.shared.convert(taskFont, toHaveTrait: .italicFontMask)
            }
            if !isChecked {
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fontRange)
            }
            storage.addAttribute(.font, value: taskFont, range: fontRange)
        }
    }

    private func applyHeadingPresentation(
        to range: NSRange,
        basedOn attributes: [NSAttributedString.Key: Any]? = nil,
        prefix: String = "#"
    ) {
        guard let storage = textStorage, range.length > 0 else { return }
        let original = attributes ?? storage.attributes(at: range.location, effectiveRange: nil)
        let paragraph = (original[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 10
        storage.addAttributes([
            .paragraphStyle: paragraph,
            .menuNoteBlockPrefix: prefix,
            .menuNoteStructuralFont: true,
        ], range: range)
        storage.removeAttribute(.menuNoteTaskLine, range: range)
        storage.removeAttribute(.menuNoteTaskIndent, range: range)
        storage.removeAttribute(.menuNoteTaskChecked, range: range)
        storage.removeAttribute(.menuNoteTaskCompletionStamp, range: range)
        storage.removeAttribute(.menuNoteTaskPresentationStrike, range: range)

        // 只替换普通字体，保留标题中的粗体、斜体、代码和链接等局部样式。
        var fontRanges: [(NSRange, NSFont)] = []
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            if let font = value as? NSFont { fontRanges.append((subrange, font)) }
        }
        for (fontRange, currentFont) in fontRanges where !currentFont.fontName.contains("Mono") {
            storage.addAttribute(.font, value: headingFont(for: currentFont, prefix: prefix), range: fontRange)
        }
    }

    private func headingFont(for currentFont: NSFont?, prefix: String) -> NSFont {
        let level = max(1, min(6, prefix.filter { $0 == "#" }.count))
        let ratios: [CGFloat] = [0, 1, 18 / 21, 16 / 21, 15 / 21, 14 / 21, 14 / 21]
        var heading = NSFont.systemFont(ofSize: headingFontSize * ratios[level], weight: .semibold)
        if let currentFont {
            let traits = NSFontManager.shared.traits(of: currentFont)
            if traits.contains(.boldFontMask) {
                heading = NSFontManager.shared.convert(heading, toHaveTrait: .boldFontMask)
            }
            if traits.contains(.italicFontMask) {
                heading = NSFontManager.shared.convert(heading, toHaveTrait: .italicFontMask)
            }
        }
        return heading
    }

    private func setTypingAttributesForCurrentLine() {
        guard let storage = textStorage, storage.length > 0 else {
            setHeadingTypingAttributes()
            return
        }
        let source = storage.string as NSString
        let cursor = min(selectedRange().location, source.length)
        let line = source.lineRange(for: NSRange(location: cursor, length: 0))
        let location = min(line.location, max(0, storage.length - 1))
        let attrs = storage.attributes(at: location, effectiveRange: nil)
        if attrs[.menuNoteTaskLine] != nil {
            setTaskTypingAttributes()
        } else {
            let prefix = attrs[.menuNoteBlockPrefix] as? String ?? ""
            setHeadingTypingAttributes(prefix: prefix.isEmpty || prefix == "task" ? "#" : prefix)
        }
    }

    private func matchesHotKey(_ event: NSEvent, hotKey: HotKey) -> Bool {
        guard hotKey.isValid else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return UInt32(event.keyCode) == hotKey.keyCode && carbon == hotKey.modifiers
    }

    private func deleteCurrentLines() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let selection = selectedRange()
        let selectionEnd = max(selection.location, NSMaxRange(selection) - 1)
        let firstLine = source.lineRange(for: NSRange(location: min(selection.location, source.length), length: 0))
        let lastLine = source.lineRange(for: NSRange(location: min(selectionEnd, source.length), length: 0))
        let block = NSRange(location: firstLine.location, length: NSMaxRange(lastLine) - firstLine.location)
        guard block.length > 0 else { return }
        guard shouldChangeText(in: block, replacementString: "") else { return }
        let cursor = firstLine.location
        storage.replaceCharacters(in: block, with: "")
        didChangeText()
        setSelectedRange(NSRange(location: min(cursor, storage.length), length: 0))
    }

    private func duplicateCurrentLines() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let selection = selectedRange()
        let selectionEnd = max(selection.location, NSMaxRange(selection) - 1)
        let firstLine = source.lineRange(for: NSRange(location: min(selection.location, source.length), length: 0))
        let lastLine = source.lineRange(for: NSRange(location: min(selectionEnd, source.length), length: 0))
        let block = NSRange(location: firstLine.location, length: NSMaxRange(lastLine) - firstLine.location)
        let copied = storage.attributedSubstring(from: block).mutableCopy() as! NSMutableAttributedString
        let needsLeadingNewline = NSMaxRange(block) == storage.length && !copied.string.hasPrefix("\n")
        if needsLeadingNewline {
            copied.insert(NSAttributedString(string: "\n", attributes: storage.attributes(at: max(0, block.location), effectiveRange: nil)), at: 0)
        }
        let insertAt = NSMaxRange(block)
        guard shouldChangeText(in: NSRange(location: insertAt, length: 0), replacementString: copied.string) else { return }
        storage.insert(copied, at: insertAt)
        didChangeText()
        let selectionStart = insertAt + (needsLeadingNewline ? 1 : 0)
        setSelectedRange(NSRange(location: selectionStart, length: block.length))
    }

    private func toggleOrderedList() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let source = storage.string as NSString
        let selection = selectedRange()
        let end = max(selection.location, NSMaxRange(selection) - 1)
        var lineStart = source.lineRange(for: NSRange(location: min(selection.location, source.length), length: 0)).location
        let finalEnd = NSMaxRange(source.lineRange(for: NSRange(location: min(end, source.length), length: 0)))
        var number = 1
        while lineStart < finalEnd {
            let range = source.lineRange(for: NSRange(location: lineStart, length: 0))
            let contentRange = NSRange(location: range.location, length: max(0, range.length - (source.substring(with: range).hasSuffix("\n") ? 1 : 0)))
            guard contentRange.length > 0 else { lineStart = NSMaxRange(range); continue }
            let attrs = storage.attributes(at: contentRange.location, effectiveRange: nil)
            if attrs[.menuNoteTaskLine] == nil {
                let currentPrefix = attrs[.menuNoteBlockPrefix] as? String ?? ""
                var updated = attrs
                if MarkdownDocumentCodec.listPrefix(from: currentPrefix)?.marker.first?.isNumber == true {
                    updated[.menuNoteBlockPrefix] = ""
                    let text = storage.attributedSubstring(from: contentRange).string
                    let marker = MarkdownDocumentCodec.listPrefix(from: currentPrefix)?.marker ?? ""
                    storage.replaceCharacters(in: contentRange, with: MarkdownDocumentCodec.stripVisibleListMarker(from: text, fallback: marker))
                } else {
                    updated[.foregroundColor] = NSColor.labelColor
                    updated[.font] = headingFont(for: updated[.font] as? NSFont, prefix: "#")
                    updated[.menuNoteBlockPrefix] = "\(number)."
                    let visible = "\(number).  " + storage.attributedSubstring(from: contentRange).string
                    storage.replaceCharacters(in: contentRange, with: visible)
                    storage.addAttributes(updated, range: NSRange(location: contentRange.location, length: (visible as NSString).length))
                    number += 1
                }
            }
            lineStart = NSMaxRange(range)
        }
        didChangeText()
    }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        guard range.length > 0 else { NSSound.beep(); return }
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: 14.5)
            let traits = NSFontManager.shared.traits(of: font)
            let replacement = traits.contains(trait)
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: replacement, range: subrange)
        }
        didChangeText()
    }

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else { super.insertNewline(sender); return }
        let cursor = selectedRange().location
        let source = storage.string as NSString
        let paragraph = source.lineRange(for: NSRange(location: min(cursor, source.length), length: 0))
        let contentRange = NSRange(location: paragraph.location, length: max(0, paragraph.length - (source.substring(with: paragraph).hasSuffix("\n") ? 1 : 0)))
        let attrs = contentRange.length > 0
            ? storage.attributes(at: contentRange.location, effectiveRange: nil)
            : typingAttributes
        let prefix = attrs[.menuNoteBlockPrefix] as? String ?? ""

        if attrs[.menuNoteTaskLine] != nil {
            // 不能直接继承方框字符的属性：它是蓝色 16pt，正文必须保持系统正文颜色。
            var taskTextAttrs = attrs
            taskTextAttrs[.foregroundColor] = NSColor.labelColor
            taskTextAttrs[.font] = NSFont.systemFont(ofSize: taskFontSize)
            let inherited = NSMutableAttributedString(string: "\n☐  ", attributes: taskTextAttrs)
            inherited.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: NSRange(location: 1, length: 1))
            inherited.addAttribute(.font, value: NSFont.systemFont(ofSize: 16), range: NSRange(location: 1, length: 1))
            insert(inherited, replacing: selectedRange(), cursorOffset: inherited.length)
            setTaskTypingAttributes()
            return
        }

        if prefix.hasPrefix("#") {
            var headingAttrs = attrs
            let level = max(1, min(6, prefix.filter { $0 == "#" }.count))
            let ratios: [CGFloat] = [0, 1, 18 / 21, 16 / 21, 15 / 21, 14 / 21, 14 / 21]
            headingAttrs[.font] = NSFont.systemFont(ofSize: headingFontSize * ratios[level], weight: .semibold)
            headingAttrs[.foregroundColor] = NSColor.labelColor
            headingAttrs[.menuNoteBlockPrefix] = prefix
            headingAttrs[.menuNoteStructuralFont] = true
            insert(NSAttributedString(string: "\n", attributes: headingAttrs), replacing: selectedRange(), cursorOffset: 1)
            setHeadingTypingAttributes(prefix: prefix)
            return
        }

        if let ordered = MarkdownDocumentCodec.listPrefix(from: prefix), ordered.marker.first?.isNumber == true {
            let currentText = MarkdownDocumentCodec.stripVisibleListMarker(
                from: storage.attributedSubstring(from: contentRange).string,
                fallback: ordered.marker
            )
            if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var plainAttrs = attrs
                plainAttrs[.menuNoteBlockPrefix] = ""
                let replacement = NSAttributedString(string: "", attributes: plainAttrs)
                storage.replaceCharacters(in: contentRange, with: replacement)
                insert(NSAttributedString(string: "\n", attributes: plainAttrs), replacing: NSRange(location: paragraph.location, length: 0), cursorOffset: 1)
                return
            }
            let number = (Int(ordered.marker.dropLast()) ?? 0) + 1
            var nextAttrs = attrs
            nextAttrs[.foregroundColor] = NSColor.labelColor
            nextAttrs[.font] = headingFont(for: nextAttrs[.font] as? NSFont, prefix: "#")
            nextAttrs[.menuNoteBlockPrefix] = "\(ordered.indent)\(number)."
            let inherited = NSMutableAttributedString(string: "\n\(number).  ", attributes: nextAttrs)
            insert(inherited, replacing: selectedRange(), cursorOffset: inherited.length)
            return
        }

        if let unordered = MarkdownDocumentCodec.listPrefix(from: prefix) {
            let currentText = MarkdownDocumentCodec.stripVisibleListMarker(
                from: storage.attributedSubstring(from: contentRange).string,
                fallback: unordered.marker
            )
            if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var nextAttrs = attrs
                nextAttrs[.foregroundColor] = NSColor.labelColor
                nextAttrs[.font] = headingFont(for: nextAttrs[.font] as? NSFont, prefix: "#")
                nextAttrs[.menuNoteBlockPrefix] = "\(unordered.indent)\(unordered.marker)"
                let inherited = NSMutableAttributedString(string: "\n•  ", attributes: nextAttrs)
                insert(inherited, replacing: selectedRange(), cursorOffset: inherited.length)
                return
            }
        }

        // 普通文本行回车继续保持标题格式，不再默认生成任务。
        var plainAttrs = attrs
        let titlePrefix = prefix.isEmpty || prefix == "task" ? "#" : prefix
        plainAttrs[.font] = NSFont.systemFont(ofSize: headingFontSize, weight: .semibold)
        plainAttrs[.foregroundColor] = NSColor.labelColor
        plainAttrs[.menuNoteBlockPrefix] = titlePrefix
        plainAttrs[.menuNoteStructuralFont] = true
        plainAttrs.removeValue(forKey: .menuNoteTaskLine)
        plainAttrs.removeValue(forKey: .menuNoteTaskIndent)
        plainAttrs.removeValue(forKey: .menuNoteTaskChecked)
        plainAttrs.removeValue(forKey: .menuNoteTaskCompletionStamp)
        plainAttrs.removeValue(forKey: .menuNoteTaskPresentationStrike)
        insert(NSAttributedString(string: "\n", attributes: plainAttrs), replacing: selectedRange(), cursorOffset: 1)
        typingAttributes = plainAttrs
    }

    /// 回车创建任务后，后续输入必须使用正文样式，不能继续继承复选框的 16pt 属性。
    private func setTaskTypingAttributes() {
        typingAttributes = [
            .font: NSFont.systemFont(ofSize: taskFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
    }

    private func insert(_ text: NSAttributedString, replacing range: NSRange, cursorOffset: Int) {
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: text.string) else { return }
        let cursor = range.location
        storage.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(NSRange(location: cursor + cursorOffset, length: 0))
    }
}
