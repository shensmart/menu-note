import Combine

enum NoteContentMode: Equatable {
    case formattedEditing
    case preview
    case sourceEditing
}

/// 跨视图共享的界面状态（编辑/预览模式等）
final class AppState: ObservableObject {
    @Published var isSettingsVisible = false
    /// 内容区模式。默认保留所见即所得编辑，另有只读预览和 Markdown 原文编辑。
    @Published var contentMode: NoteContentMode = .formattedEditing
    /// 新建任务后请求编辑器聚焦到指定 Markdown 行。
    @Published var requestedTaskLine: Int?
    @Published private(set) var taskFocusRequest = 0
    /// 由编辑工具栏发给所见即所得编辑器的撤销/重做请求计数。
    @Published private(set) var editorUndoRequest = 0
    @Published private(set) var editorRedoRequest = 0

    func requestTaskFocus(at line: Int) {
        requestedTaskLine = line
        taskFocusRequest += 1
    }

    func requestEditorUndo() {
        editorUndoRequest += 1
    }

    func requestEditorRedo() {
        editorRedoRequest += 1
    }
}
