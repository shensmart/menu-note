import Foundation

struct CompletedTask: Identifiable, Equatable {
    let id: UUID
    var markdownLine: String
    var title: String
    var completedAt: Date?
    var sourceLine: Int
    var parentSourceLine: Int

    init(markdownLine: String, title: String, completedAt: Date?, sourceLine: Int = -1, parentSourceLine: Int = -1, occurrence: Int = 0) {
        self.markdownLine = markdownLine
        self.title = title
        self.completedAt = completedAt
        self.sourceLine = sourceLine
        self.parentSourceLine = parentSourceLine
        self.id = UUID(uuidString: Self.stableID(for: "\(occurrence)|\(sourceLine)|\(parentSourceLine)|\(markdownLine)")) ?? UUID()
    }

    private static func stableID(for value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        let a = hash
        let b = hash ^ 0x9e3779b97f4a7c15
        return String(format: "%08X-%04X-%04X-%04X-%012llX", a >> 32, (a >> 16) & 0xffff, a & 0xffff, b >> 48, b & 0xffffffffffff)
    }
}

struct CompletedTaskTreeNode: Identifiable, Equatable {
    let task: CompletedTask
    let children: [CompletedTaskTreeNode]
    var id: UUID { task.id }
}

func completedTaskTree(from tasks: [CompletedTask]) -> [CompletedTaskTreeNode] {
    let indexed = Array(tasks.enumerated())
    let bySource = Dictionary(indexed.filter { $0.element.sourceLine >= 0 }.map { ($0.element.sourceLine, $0.offset) }, uniquingKeysWith: { first, _ in first })
    var children: [Int: [Int]] = [:]
    var roots: [Int] = []
    for (index, task) in indexed {
        guard task.parentSourceLine >= 0, let parent = bySource[task.parentSourceLine], parent != index else {
            roots.append(index); continue
        }
        children[parent, default: []].append(index)
    }
    func node(_ index: Int, seen: Set<Int>) -> CompletedTaskTreeNode {
        guard !seen.contains(index) else { return CompletedTaskTreeNode(task: tasks[index], children: []) }
        var next = seen; next.insert(index)
        return CompletedTaskTreeNode(task: tasks[index], children: (children[index] ?? []).map { node($0, seen: next) })
    }
    return roots.map { node($0, seen: []) }
}

/// 归档完成任务与主区“保留完成状态”共用 Markdown。后者带内部尾随标记，
/// 既可保留完成时间，又不会在重新加载时再次被收进底部归档。
struct TaskArchiveCodec {
    static let beginMarker = "<!-- menunote:completed-tasks -->"
    static let endMarker = "<!-- /menunote:completed-tasks -->"
    static let activeCompletedMarker = "<!-- menunote:active-completed -->"
    private static let sourceMarker = "<!-- menunote:source=(\\d+) -->"
    private static let parentMarker = "<!-- menunote:parent-source=(-?\\d+) -->"
    private static let checkedTask = "^(\\s*[-*+]\\s+)\\[([xX])\\]\\s*(.*)$"
    private static let uncheckedTask = "^(\\s*[-*+]\\s+)\\[ \\]\\s*(.*)$"
    private static let timestamp = "\\s*\\[完成时间:\\s*(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\]\\s*$"

    private struct ActiveTask {
        let line: Int
        let indent: Int
        let prefix: String
        let title: String
        let parentLine: Int
        let checked: Bool
        let raw: String
    }

    static func split(_ markdown: String) -> (active: String, completed: [CompletedTask]) {
        var active: [String] = []
        var archive: [String] = []
        var inArchive = false
        for line in lines(markdown) {
            if line == beginMarker { inArchive = true; continue }
            if line == endMarker { inArchive = false; continue }
            if inArchive || (isCheckedTask(line) && !line.contains(activeCompletedMarker)) {
                archive.append(line)
            } else {
                active.append(line)
            }
        }

        var tasks: [CompletedTask] = []
        var sourceLine = -1
        var parentLine = -1
        for line in archive {
            if let groups = capture(sourceMarker, in: line), groups.count > 1, let value = Int(groups[1]) { sourceLine = value; continue }
            if let groups = capture(parentMarker, in: line), groups.count > 1, let value = Int(groups[1]) { parentLine = value; continue }
            if let task = task(from: line, sourceLine: sourceLine, parentSourceLine: parentLine, occurrence: tasks.count) { tasks.append(task) }
            sourceLine = -1; parentLine = -1
        }
        return (trim(active).joined(separator: "\n"), tasks)
    }

    static func compose(active: String, completed: [CompletedTask]) -> String {
        var sections: [String] = []
        let body = trim(lines(active)).joined(separator: "\n")
        if !body.isEmpty { sections.append(body) }
        guard !completed.isEmpty else { return sections.joined(separator: "\n") }
        var archive = [beginMarker]
        for task in completed {
            if task.sourceLine >= 0 { archive.append("<!-- menunote:source=\(task.sourceLine) -->") }
            archive.append("<!-- menunote:parent-source=\(task.parentSourceLine) -->")
            archive.append(task.markdownLine)
        }
        archive.append(endMarker)
        sections.append(archive.joined(separator: "\n"))
        return sections.joined(separator: "\n\n")
    }

    /// 只有顶级任务可以进入完成区。嵌套任务只在正文中保留完成状态，
    /// 点击有子任务的嵌套任务时，连同它的整个子树一起显示为已完成。
    static func complete(active: String, at line: Int, now: Date = Date(), occurrence: Int = 0) -> (active: String, tasks: [CompletedTask])? {
        let original = lines(active)
        let all = activeTasks(in: original)
        guard let target = all.first(where: { $0.line == line }), !target.checked else { return nil }
        let targetDescendants = descendants(of: target, in: all)
        let stamp = format(now)
        let subtree = [target] + targetDescendants

        guard target.parentLine < 0 else {
            // 子任务完成后仍属于原任务组，只保留删除线和内部标记，
            // 不能因为它是二级/三级父任务就单独移入完成区。
            var retained = original
            for item in subtree {
                retained[item.line] = activeCompletionLine(for: item, stamp: stamp)
            }
            return (trim(retained).joined(separator: "\n"), [])
        }

        // 只有顶级主任务完成时，才以主任务为单位归档整个任务组。
        let pending = Set(subtree.map(\.line))

        let ordered = all.filter { pending.contains($0.line) }.sorted { $0.indent > $1.indent }
        var archived: [CompletedTask] = []
        for (index, item) in ordered.enumerated() {
            let completedLine = completionLine(for: item, stamp: stamp)
            if let task = task(from: completedLine, sourceLine: item.line, parentSourceLine: item.parentLine, occurrence: occurrence + index) { archived.append(task) }
        }
        let retained = original.enumerated().filter { !pending.contains($0.offset) }.map(\.element)
        return (trim(retained).joined(separator: "\n"), archived)
    }

    /// 在完成区点击一个任务：将所属完整子树带回主区，只有被点击的任务变未完成。
    static func partiallyRestore(_ task: CompletedTask, active: String, completed: [CompletedTask]) -> (active: String, remaining: [CompletedTask]) {
        let root = rootTask(of: task, in: completed)
        let subtree = archivedSubtree(of: root, in: completed)
        let subtreeIDs = Set(subtree.map(\.id))
        let ordered = subtree.sorted { $0.sourceLine < $1.sourceLine }
        let restoredLines = ordered.map { item -> String in
            // 子任务反选后，主任务不能继续保持完成状态，否则会出现
            // “主任务已完成但子任务未完成”的矛盾显示。
            if item.id == task.id || item.id == root.id { return uncheckedLine(from: item) }
            return activeCompletedLine(from: item)
        }
        var activeLines = lines(active)
        if activeLines.count == 1, activeLines[0].trimmingCharacters(in: .whitespaces).isEmpty { activeLines = [] }
        // sourceLine 是任务组从主区归档时的根任务行号。根任务被移除后，
        // 根任务之前的内容仍保持原顺序，因此直接插回该行号位置，避免插到下一个任务之后。
        let insertion = root.sourceLine >= 0 ? min(root.sourceLine, activeLines.count) : activeLines.count
        activeLines.insert(contentsOf: restoredLines, at: insertion)
        return (trim(activeLines).joined(separator: "\n"), completed.filter { !subtreeIDs.contains($0.id) })
    }

    static func archivedAncestors(of task: CompletedTask, in completed: [CompletedTask]) -> [CompletedTask] {
        var result: [CompletedTask] = []
        var parentLine = task.parentSourceLine
        var visited = Set<UUID>()
        while parentLine >= 0, let parent = completed.first(where: { $0.sourceLine == parentLine }), !visited.contains(parent.id) {
            result.insert(parent, at: 0); visited.insert(parent.id); parentLine = parent.parentSourceLine
        }
        return result
    }

    static func restore(_ task: CompletedTask, to active: String) -> String {
        var all = lines(active)
        let insertion = task.sourceLine >= 0 ? min(task.sourceLine, all.count) : all.count
        all.insert(uncheckedLine(from: task), at: insertion)
        return trim(all).joined(separator: "\n")
    }

    static func activeLine(from task: CompletedTask) -> String { uncheckedLine(from: task) }

    /// 删除完成区中的任务。传入组内任意任务时，连同它所属的完整任务组一起删除。
    static func deletingCompletedTask(_ task: CompletedTask, from completed: [CompletedTask]) -> [CompletedTask] {
        guard completed.contains(where: { $0.id == task.id }) else { return completed }
        let root = rootTask(of: task, in: completed)
        let subtreeIDs = Set(archivedSubtree(of: root, in: completed).map(\.id))
        return completed.filter { !subtreeIDs.contains($0.id) }
    }

    /// 将恢复到主区、仍保留完成状态的任务重新设为未完成。
    /// 只有带内部活动完成标记的任务允许走这条路径，避免误处理普通 Markdown 中的已完成任务。
    static func uncompleteActiveTask(active: String, at line: Int) -> String? {
        var source = lines(active)
        let tasks = activeTasks(in: source)
        guard let target = tasks.first(where: { $0.line == line }),
              target.checked,
              isActiveCompleted(target.raw) else { return nil }

        // 与完成操作对称：反选一个有子任务的嵌套任务时，恢复它的整个子树。
        let subtree = [target] + descendants(of: target, in: tasks)
        var changed = false
        for item in subtree where item.checked && isActiveCompleted(item.raw) {
            source[item.line] = uncheckedActiveLine(from: item.raw)
            changed = true
        }
        guard changed else { return nil }
        return trim(source).joined(separator: "\n")
    }

    static func task(from line: String, sourceLine: Int = -1, parentSourceLine: Int = -1, occurrence: Int = 0) -> CompletedTask? {
        guard let groups = capture(checkedTask, in: line), groups.count >= 4 else { return nil }
        let rawTitle = groups[3]
        let cleanLine = line.replacingOccurrences(of: activeCompletedMarker, with: "").trimmingCharacters(in: .newlines)
        return CompletedTask(markdownLine: cleanLine, title: stripMetadata(rawTitle), completedAt: date(in: rawTitle), sourceLine: sourceLine, parentSourceLine: parentSourceLine, occurrence: occurrence)
    }

    static func isActiveCompleted(_ line: String) -> Bool { line.contains(activeCompletedMarker) }
    static func visibleTaskTitle(_ text: String) -> String { stripMetadata(text) }

    private static func rootTask(of task: CompletedTask, in all: [CompletedTask]) -> CompletedTask {
        var root = task
        var parentLine = task.parentSourceLine
        var seen = Set<UUID>()
        while parentLine >= 0, let parent = all.first(where: { $0.sourceLine == parentLine }), !seen.contains(parent.id) {
            root = parent; seen.insert(parent.id); parentLine = parent.parentSourceLine
        }
        return root
    }

    private static func archivedSubtree(of root: CompletedTask, in all: [CompletedTask]) -> [CompletedTask] {
        // 旧版本归档任务没有来源行号，不能用 -1 匹配所有顶层任务。
        guard root.sourceLine >= 0 else { return [root] }
        var result: [CompletedTask] = [root]
        var queue = [root.sourceLine]
        while let parent = queue.popLast() {
            let children = all.filter { $0.parentSourceLine == parent }
            result.append(contentsOf: children)
            queue.append(contentsOf: children.map(\.sourceLine))
        }
        return result
    }

    private static func completionLine(for task: ActiveTask, stamp: String) -> String {
        let title = stripMetadata(task.title)
        if task.checked {
            // 已经在正文中完成的任务再次归档时，只能清理行尾的内部标记，
            // 不能使用 whitespaces 同时清掉行首缩进，否则恢复任务组会丢失层级。
            return task.raw
                .replacingOccurrences(of: activeCompletedMarker, with: "")
                .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
        return "\(task.prefix)[x] \(title) [完成时间: \(stamp)]"
    }

    private static func activeCompletionLine(for task: ActiveTask, stamp: String) -> String {
        "\(completionLine(for: task, stamp: stamp)) \(activeCompletedMarker)"
    }

    private static func activeCompletedLine(from task: CompletedTask) -> String {
        let line = task.markdownLine.replacingOccurrences(of: activeCompletedMarker, with: "").trimmingCharacters(in: .newlines)
        return "\(line) \(activeCompletedMarker)"
    }

    private static func uncheckedActiveLine(from line: String) -> String {
        var result = line.replacingOccurrences(of: activeCompletedMarker, with: "")
        result = result.replacingOccurrences(of: "\\[([xX])\\]", with: "[ ]", options: .regularExpression)
        result = result.replacingOccurrences(of: timestamp, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .newlines)
    }

    private static func uncheckedLine(from task: CompletedTask) -> String {
        var line = task.markdownLine.replacingOccurrences(of: "\\[([xX])\\]", with: "[ ]", options: .regularExpression)
        line = line.replacingOccurrences(of: timestamp, with: "", options: .regularExpression)
        return line.replacingOccurrences(of: activeCompletedMarker, with: "").trimmingCharacters(in: .newlines)
    }

    private static func activeTasks(in source: [String]) -> [ActiveTask] {
        var output: [ActiveTask] = []
        for (line, raw) in source.enumerated() {
            let groups = capture(uncheckedTask, in: raw) ?? capture(checkedTask, in: raw)
            guard let groups, groups.count >= 3 else { continue }
            let checked = capture(checkedTask, in: raw) != nil
            let markerPrefix = groups[1]
            let leading = String(raw.prefix { $0 == " " || $0 == "\t" })
            let prefix = leading + markerPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
                + " "
            let indent = leading.count
            let parent = output.last(where: { $0.indent < indent })?.line ?? -1
            let titleIndex = checked ? 3 : 2
            guard groups.count > titleIndex else { continue }
            output.append(ActiveTask(line: line, indent: indent, prefix: prefix, title: stripMetadata(groups[titleIndex]), parentLine: parent, checked: checked, raw: raw))
        }
        return output
    }

    private static func rootTask(of task: ActiveTask, in all: [ActiveTask]) -> ActiveTask {
        var root = task
        var parentLine = task.parentLine
        var seen = Set<Int>()
        while parentLine >= 0,
              let parent = all.first(where: { $0.line == parentLine }),
              !seen.contains(parent.line) {
            root = parent
            seen.insert(parent.line)
            parentLine = parent.parentLine
        }
        return root
    }

    private static func descendants(of task: ActiveTask, in all: [ActiveTask]) -> [ActiveTask] {
        guard let position = all.firstIndex(where: { $0.line == task.line }) else { return [] }
        var result: [ActiveTask] = []
        for candidate in all[(position + 1)...] {
            if candidate.indent <= task.indent { break }
            result.append(candidate)
        }
        return result
    }

    private static func isCheckedTask(_ line: String) -> Bool { capture(checkedTask, in: line) != nil }
    private static func stripMetadata(_ text: String) -> String {
        text.replacingOccurrences(of: activeCompletedMarker, with: "")
            .replacingOccurrences(of: timestamp, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
    private static func date(in text: String) -> Date? {
        guard let value = capture(timestamp, in: text)?.dropFirst().first else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }
    static func format(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    private static func lines(_ text: String) -> [String] { text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") }
    private static func trim(_ input: [String]) -> [String] { var result = input; while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeLast() }; return result }
    private static func capture(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swift = Range(range, in: text) else { return "" }
            return String(text[swift])
        }
    }
}
