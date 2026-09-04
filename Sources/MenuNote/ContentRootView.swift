import SwiftUI

/// 面板主界面：便笺工具栏 + 编辑工具栏 + 内容区
struct ContentRootView: View {
    private enum CompletedConfirmation: Identifiable {
        case clearAll
        case delete(task: CompletedTask, isGroup: Bool)

        var id: String {
            switch self {
            case .clearAll:
                return "clear-all"
            case let .delete(task, _):
                return "delete-\(task.id.uuidString)"
            }
        }
    }

    @ObservedObject var store: NotesStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var appState: AppState
    let interaction: InteractionRelay

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingDelete = false
    @State private var completedConfirmation: CompletedConfirmation?
    @State private var isCompletedExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            divider
            if isRenaming {
                renameRow
                divider
            }
            if isConfirmingDelete {
                deleteRow
                divider
            }
            content
        }
        // 不透明的内容底色（浅色近白/深色近黑，跟随系统），
        // 保证正文对比度；半透明材质会让文字发灰难读。
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .alert(item: $completedConfirmation) { confirmation in
            switch confirmation {
            case .clearAll:
                return Alert(
                    title: Text("清除所有已完成任务？"),
                    message: Text("已完成任务将从便签文件中删除，且无法恢复。"),
                    primaryButton: .destructive(Text("清除")) {
                        interact()
                        store.clearCompletedTasks()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case let .delete(task, isGroup):
                return Alert(
                    title: Text(isGroup ? "删除已完成任务组？" : "删除已完成任务？"),
                    message: Text(isGroup ? "将同时删除主任务及其全部子任务，且无法恢复。" : "该任务将从便签文件中删除，且无法恢复。"),
                    primaryButton: .destructive(Text("删除")) {
                        interact()
                        store.deleteCompletedTask(task)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }

    private var divider: some View {
        Divider().opacity(0.35)
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(store.notes) { note in
                    Button(note.name) {
                        interact()
                        store.select(note.id)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text(store.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .simultaneousGesture(TapGesture().onEnded { interact() })

            Spacer()

            HStack(spacing: 4) {
                toolbarButton("plus.circle", "新建便签") {
                    interact()
                    _ = store.createNote()
                    appState.contentMode = .formattedEditing
                }
                toolbarButton(settings.isWindowPinned ? "pin.fill" : "pin", settings.isWindowPinned ? "取消固定窗口" : "固定窗口") {
                    interact()
                    settings.isWindowPinned.toggle()
                }
                toolbarButton("square.and.pencil", "重命名") {
                    interact()
                    renameText = store.displayName
                    isRenaming = true
                    isConfirmingDelete = false
                    appState.isSettingsVisible = false
                }
                toolbarButton("trash", "删除") {
                    interact()
                    isConfirmingDelete = true
                    isRenaming = false
                    appState.isSettingsVisible = false
                }
                toolbarButton("gearshape", "设置") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.isSettingsVisible.toggle()
                    }
                    isRenaming = false
                    isConfirmingDelete = false
                    interact()
                }
                .popover(isPresented: $appState.isSettingsVisible, arrowEdge: .bottom) {
                    settingsPanel
                        .frame(width: 320)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toolbarButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .imageScale(.medium)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    // MARK: - 设置区

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("呼出快捷键").font(.subheadline)
                Spacer()
                HotKeyRecorderView(
                    hotKey: settings.hotKey,
                    onRecord: { candidate in
                        _ = settings.setHotKey(candidate)
                    },
                    onCancel: {
                        settings.clearHotKeyError()
                    }
                )
                .frame(width: 142, height: 28)
            }
            Text("点击后按下组合键；必须包含 ⌃、⌥、⇧ 或 ⌘；按 Esc 取消")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = settings.hotKeyError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                Button("恢复默认 ⌥空格") {
                    _ = settings.setHotKey(.default)
                }
                Spacer()
            }
            .font(.subheadline)
            lineActionRow("复制当前行", hotKey: settings.copyLineHotKey) { settings.copyLineHotKey = $0 }
            lineActionRow("删除当前行", hotKey: settings.deleteLineHotKey) { settings.deleteLineHotKey = $0 }
            lineActionRow("当前行转为任务", hotKey: settings.makeTaskHotKey) { settings.makeTaskHotKey = $0 }
            fontSizeRow(
                "任务字体大小",
                value: $settings.taskFontSize,
                range: SettingsStore.taskFontSizeRange,
                step: 0.5
            )
            fontSizeRow(
                "标题字体大小",
                value: $settings.headingFontSize,
                range: SettingsStore.headingFontSizeRange,
                step: 1
            )
            Toggle("固定窗口", isOn: Binding(
                get: { settings.isWindowPinned },
                set: { settings.isWindowPinned = $0 }
            ))
                .font(.subheadline)
            Toggle("登录时自动启动", isOn: $settings.launchAtLogin)
                .font(.subheadline)
            HStack(spacing: 16) {
                Button("在 Finder 中显示便签") {
                    interact()
                    store.revealInFinder()
                }
                Button("退出 MenuNote") {
                    NSApp.terminate(nil)
                }
                Spacer()
            }
            .font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
    }

    // MARK: - 重命名 / 删除

    private func lineActionRow(_ label: String, hotKey: HotKey, onRecord: @escaping (HotKey) -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label).font(.subheadline)
            Spacer()
            HotKeyRecorderView(
                hotKey: hotKey,
                onRecord: onRecord,
                onCancel: { settings.clearHotKeyError() }
            )
            .frame(width: 142, height: 28)
        }
    }

    private func fontSizeRow(
        _ label: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat
    ) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.subheadline)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue, specifier: "%.1f") pt")
                    .font(.subheadline)
                    .monospacedDigit()
                    .frame(minWidth: 54, alignment: .trailing)
            }
        }
    }

    private var renameRow: some View {
        HStack(spacing: 8) {
            TextField("便签名称", text: $renameText, onCommit: commitRename)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            Button("确定", action: commitRename)
                .font(.subheadline)
            Button("取消") {
                isRenaming = false
            }
            .font(.subheadline)
        }
        .padding(10)
    }

    private func commitRename() {
        interact()
        store.renameCurrent(to: renameText)
        isRenaming = false
    }

    private var deleteRow: some View {
        HStack(spacing: 8) {
            Text("删除「\(store.displayName)」？（移到废纸篓）")
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Button("删除", role: .destructive) {
                interact()
                store.deleteCurrent()
                isConfirmingDelete = false
            }
            .font(.subheadline)
            Button("取消") {
                isConfirmingDelete = false
            }
            .font(.subheadline)
        }
        .padding(10)
    }

    // MARK: - 内容区

    private var content: some View {
        VStack(spacing: 0) {
            editorToolbar
            divider
            switch appState.contentMode {
            case .formattedEditing:
                MarkdownRichTextEditor(
                    markdown: store.activeMarkdown,
                    focusTaskLine: appState.requestedTaskLine,
                    focusRequest: appState.taskFocusRequest,
                    undoRequest: appState.editorUndoRequest,
                    redoRequest: appState.editorRedoRequest,
                    onChange: { markdown in
                        if let line = store.updateActiveMarkdown(markdown) {
                            appState.contentMode = .formattedEditing
                            appState.requestTaskFocus(at: line)
                        }
                    },
                    onCompleteTask: { store.completeTask(at: $0) },
                    onUncompleteTask: { store.uncompleteTask(at: $0) },
                    copyLineHotKey: settings.copyLineHotKey,
                    deleteLineHotKey: settings.deleteLineHotKey,
                    makeTaskHotKey: settings.makeTaskHotKey,
                    taskFontSize: settings.taskFontSize,
                    headingFontSize: settings.headingFontSize
                )
            case .preview:
                MarkdownPreviewView(
                    markdown: store.activeMarkdown,
                    taskFontSize: settings.taskFontSize,
                    headingFontSize: settings.headingFontSize,
                    onToggleTask: { line, checked in
                        if checked {
                            store.uncompleteTask(at: line)
                        } else {
                            store.completeTask(at: line)
                        }
                    }
                )
            case .sourceEditing:
                EditorView(text: Binding(
                    get: { store.activeMarkdown },
                    set: { store.updateActiveMarkdown($0) }
                ))
            }
            completedSection
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 4) {
            Image(systemName: "pencil.line")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("编辑")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            toolbarButton("checklist", "添加任务") {
                interact()
                let line = store.addTask()
                appState.contentMode = .formattedEditing
                appState.requestTaskFocus(at: line)
            }
            toolbarButton("arrow.uturn.backward", "撤销") {
                interact()
                appState.requestEditorUndo()
            }
            .disabled(appState.contentMode != .formattedEditing)
            toolbarButton("arrow.uturn.forward", "重做") {
                interact()
                appState.requestEditorRedo()
            }
            .disabled(appState.contentMode != .formattedEditing)
            toolbarButton(
                appState.contentMode == .sourceEditing ? "arrow.uturn.backward" : "pencil.line",
                appState.contentMode == .sourceEditing ? "返回排版编辑" : "编辑 Markdown 原文"
            ) {
                interact()
                withAnimation(.easeInOut(duration: 0.15)) {
                    appState.contentMode = appState.contentMode == .sourceEditing
                        ? .formattedEditing
                        : .sourceEditing
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            toolbarButton(
                appState.contentMode == .preview ? "eye.slash" : "eye",
                appState.contentMode == .preview ? "返回排版编辑" : "预览 Markdown"
            ) {
                interact()
                withAnimation(.easeInOut(duration: 0.15)) {
                    appState.contentMode = appState.contentMode == .preview
                        ? .formattedEditing
                        : .preview
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.035))
    }

    private var completedSection: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.45)
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCompletedExpanded.toggle()
                    }
                    interact()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isCompletedExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Text("已完成")
                            .font(.system(size: 13, weight: .medium))
                        Text("\(store.completedTasks.count)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !store.completedTasks.isEmpty {
                    Button {
                        interact()
                        completedConfirmation = .clearAll
                    } label: {
                        Image(systemName: "eraser.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
                    .help("清除所有已完成任务")
                }
            }
            .frame(height: 36)

            if isCompletedExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if store.completedTasks.isEmpty {
                            Text("暂无已完成任务")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        } else {
                            completedTreeRows(completedTaskTree(from: store.completedTasks), depth: 0)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 180)
                .background(Color.primary.opacity(0.025))
            }
        }
    }

    /// 树形完成区递归需要类型擦除，否则 SwiftUI 的 `some View` 会无限展开。
    private func completedTreeRows(_ nodes: [CompletedTaskTreeNode], depth: Int) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                VStack(spacing: 0) {
                    CompletedTaskRow(
                        task: node.task,
                        depth: depth,
                        onRestore: { store.restoreTask(node.task) },
                        onUpdate: { store.updateCompletedTask(node.task, title: $0) },
                        onDelete: {
                            // 弹出确认框前先抑制失焦自动隐藏，否则确认框出现时
                            // 非激活面板会被自动收起，留下灰色的模态遮罩。
                            interact()
                            completedConfirmation = .delete(
                                task: node.task,
                                isGroup: !node.children.isEmpty
                            )
                        },
                        showsDeleteButton: depth == 0
                    )
                    if !node.children.isEmpty {
                        completedTreeRows(node.children, depth: depth + 1)
                    }
                    Divider().padding(.leading, 42 + CGFloat(depth) * 20)
                }
            }
        )
    }

    /// 用户与面板交互期间抑制「失焦自动隐藏」误触发
    private func interact() {
        interaction.suppress()
    }
}
