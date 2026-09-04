import AppKit
import Combine
import Darwin

struct NoteFile: Identifiable, Equatable {
    let id: String
    var name: String { (id as NSString).deletingPathExtension }
}

/// 便签仓库：主编辑内容和已完成归档在内存中分开管理，落盘时组合成一个 .md 文件。
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [NoteFile] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var activeMarkdown = ""
    @Published private(set) var completedTasks: [CompletedTask] = []
    /// 完整持久化文本，包含内部完成任务归档。
    @Published private(set) var draft = "" {
        didSet {
            guard !isLoading else { return }
            scheduleSave()
        }
    }

    private let folder: URL
    private var isLoading = false
    private var saveTask: DispatchWorkItem?
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherDebounce: DispatchWorkItem?
    private var lastWritten: [String: String] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        folder = base.appendingPathComponent("MenuNote/Notes", isDirectory: true)
    }

    var selectedNote: NoteFile? { notes.first { $0.id == selectedID } }
    var displayName: String { selectedNote?.name ?? "便签" }

    func load() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if fileNames().isEmpty { createDefaultNote() }
        rescanNoteList()
        if selectedID == nil, let newest = notes.first { select(newest.id) }
        startWatcher()
    }

    private func fileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".md") }
    }

    private func createDefaultNote() {
        let sample = """
        # 今日任务

        - [ ] 点击方框可以直接勾选完成
        - [ ] 直接点击文字即可编辑，不需要切换模式
        - [ ] 按 ⌘B 加粗，⌘I 斜体，⌘K 添加链接
        - [ ] 右键点菜单栏图标：新建便签、设置自定义快捷键、退出

        ## 稍后

        - 支持 **Markdown**：*斜体*、`代码`、[链接](https://www.apple.com)
        - 嵌套列表也没问题
            - 子任务 A
            - 子任务 B
        """
        writeToFile(id: "今日任务.md", text: sample)
    }

    private func readText(id: String) -> String { (try? String(contentsOf: url(for: id), encoding: .utf8)) ?? "" }
    private func writeToFile(id: String, text: String) {
        lastWritten[id] = text
        try? text.data(using: .utf8)?.write(to: url(for: id), options: .atomic)
    }
    private func url(for id: String) -> URL { folder.appendingPathComponent(id) }

    func select(_ id: String) {
        guard selectedID != id, fileNames().contains(id) else { return }
        flushSave()
        loadDocument(readText(id: id), selected: id)
    }

    @discardableResult
    func updateActiveMarkdown(_ markdown: String) -> Int? {
        guard markdown != activeMarkdown else { return nil }
        activeMarkdown = markdown
        rebuildDraft()
        return nil
    }

    /// 在主编辑区末尾创建一个未完成任务，返回新任务的 Markdown 行号以便编辑器聚焦。
    @discardableResult
    func addTask() -> Int {
        var lines = activeMarkdown.isEmpty ? [] : activeMarkdown.components(separatedBy: "\n")
        let line = lines.count
        lines.append("- [ ] ")
        activeMarkdown = lines.joined(separator: "\n")
        rebuildDraft()
        return line
    }

    func completeTask(at line: Int) {
        guard let change = TaskArchiveCodec.complete(
            active: activeMarkdown,
            at: line,
            occurrence: completedTasks.count
        ) else { return }
        activeMarkdown = change.active
        completedTasks.append(contentsOf: change.tasks)
        rebuildDraft()
    }

    func uncompleteTask(at line: Int) {
        guard let active = TaskArchiveCodec.uncompleteActiveTask(active: activeMarkdown, at: line) else { return }
        activeMarkdown = active
        rebuildDraft()
    }

    func clearCompletedTasks() {
        guard !completedTasks.isEmpty else { return }
        completedTasks = []
        rebuildDraft()
    }

    func deleteCompletedTask(_ task: CompletedTask) {
        let remaining = TaskArchiveCodec.deletingCompletedTask(task, from: completedTasks)
        guard remaining.count != completedTasks.count else { return }
        completedTasks = remaining
        rebuildDraft()
    }

    func restoreTask(_ task: CompletedTask) {
        guard completedTasks.contains(where: { $0.id == task.id }) else { return }
        let change = TaskArchiveCodec.partiallyRestore(task, active: activeMarkdown, completed: completedTasks)
        activeMarkdown = change.active
        completedTasks = change.remaining
        rebuildDraft()
    }

    func updateCompletedTask(_ task: CompletedTask, title: String) {
        guard let index = completedTasks.firstIndex(where: { $0.id == task.id }) else { return }
        let date = task.completedAt.map { " [完成时间: \(TaskArchiveCodec.format($0))]" } ?? ""
        var updated = task
        updated.title = title
        let prefix = task.markdownLine.replacingOccurrences(of: "\\[x\\].*$", with: "[x] \(title)\(date)", options: .regularExpression)
        updated.markdownLine = prefix
        completedTasks[index] = updated
        rebuildDraft()
    }

    private func rebuildDraft() {
        draft = TaskArchiveCodec.compose(active: activeMarkdown, completed: completedTasks)
    }

    private func loadDocument(_ text: String, selected id: String? = nil) {
        isLoading = true
        if let id { selectedID = id }
        draft = text
        let document = TaskArchiveCodec.split(text)
        activeMarkdown = document.active
        completedTasks = document.completed
        isLoading = false
    }

    private func scheduleSave() {
        guard let id = selectedID else { return }
        saveTask?.cancel()
        let text = draft
        let task = DispatchWorkItem { [weak self] in self?.writeToFile(id: id, text: text) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
        saveTask = task
    }

    func flushSave() {
        saveTask?.cancel(); saveTask = nil
        guard let id = selectedID, draft != lastWritten[id] else { return }
        writeToFile(id: id, text: draft)
    }

    @discardableResult
    func createNote() -> String {
        flushSave()
        let existing = Set(fileNames())
        var name = "便签"; var index = 2
        while existing.contains(name + ".md") { name = "便签 \(index)"; index += 1 }
        let id = name + ".md"
        // 新便签保持空白，由用户主动添加任务或使用快捷键转换当前行。
        writeToFile(id: id, text: "")
        rescanNoteList(); select(id)
        return name
    }

    func renameCurrent(to newName: String) {
        guard let oldID = selectedID else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != selectedNote?.name else { return }
        var finalName = trimmed; let existing = Set(fileNames()); var index = 2
        while existing.contains(finalName + ".md") { finalName = "\(trimmed) \(index)"; index += 1 }
        let newID = finalName + ".md"
        guard (try? FileManager.default.moveItem(at: url(for: oldID), to: url(for: newID))) != nil else { return }
        lastWritten[newID] = lastWritten.removeValue(forKey: oldID)
        flushSave(); rescanNoteList(); selectedID = newID
    }

    func deleteCurrent() {
        guard let id = selectedID else { return }
        saveTask?.cancel(); saveTask = nil
        try? FileManager.default.trashItem(at: url(for: id), resultingItemURL: nil)
        lastWritten[id] = nil
        isLoading = true; selectedID = nil; draft = ""; activeMarkdown = ""; completedTasks = []; isLoading = false
        rescanNoteList()
        if let first = notes.first { select(first.id) }
    }

    func revealInFinder() {
        let target = selectedID.map { url(for: $0) } ?? folder
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private func rescanNoteList() {
        let entries = fileNames().compactMap { name -> (String, Date)? in
            let attrs = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            return (name, (attrs?[.modificationDate] as? Date) ?? .distantPast)
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        notes = entries.map { NoteFile(id: $0.0) }
        if let id = selectedID, !notes.contains(where: { $0.id == id }) {
            isLoading = true; selectedID = nil; draft = ""; activeMarkdown = ""; completedTasks = []; isLoading = false
        }
    }

    private func rescanFromWatcher() {
        let hadSelection = selectedID
        rescanNoteList()
        if selectedID == nil, let first = notes.first { select(first.id) }
        if let id = hadSelection, notes.contains(where: { $0.id == id }), id == selectedID {
            let disk = readText(id: id)
            if disk != lastWritten[id], disk != draft {
                loadDocument(disk)
                lastWritten[id] = disk
            }
        }
    }

    private func startWatcher() {
        let fd = open(folder.path, O_EVTONLY); guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.watcherDebounce?.cancel()
            let task = DispatchWorkItem { [weak self] in self?.rescanFromWatcher() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
            self.watcherDebounce = task
        }
        source.setCancelHandler { close(fd) }
        source.resume(); watcher = source
    }
}
