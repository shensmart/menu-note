import SwiftUI

struct CompletedTaskRow: View {
    let task: CompletedTask
    let depth: Int
    let onRestore: () -> Void
    let onUpdate: (String) -> Void
    let onDelete: () -> Void
    let showsDeleteButton: Bool

    @State private var title: String

    init(
        task: CompletedTask,
        depth: Int = 0,
        onRestore: @escaping () -> Void,
        onUpdate: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        showsDeleteButton: Bool
    ) {
        self.task = task
        self.depth = depth
        self.onRestore = onRestore
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.showsDeleteButton = showsDeleteButton
        _title = State(initialValue: task.title)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: onRestore) {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("取消完成")

            VStack(alignment: .leading, spacing: 3) {
                TextField("任务", text: $title, onCommit: save)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .strikethrough()
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .onChange(of: task.title) { title = $0 }
                    .onDisappear(perform: save)
                Text(completionLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsDeleteButton {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("删除已完成任务")
            }
        }
        .padding(.leading, 15 + CGFloat(depth) * 20)
        .padding(.trailing, 15)
        .padding(.vertical, 8)
    }

    private var completionLabel: String {
        guard let date = task.completedAt else { return "完成时间未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "完成于 \(formatter.string(from: date))"
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        onUpdate(trimmed)
    }
}
