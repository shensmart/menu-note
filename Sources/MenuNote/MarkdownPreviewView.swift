import AppKit
import SwiftUI

/// Markdown 渲染视图：纯 SwiftUI 原生渲染，无 WKWebView。
/// 块级结构来自 MarkdownParser，行内格式交给 AttributedString；
/// 任务复选框是原生按钮，点击通过 onToggleTask 写回源文件对应行。
struct MarkdownPreviewView: View {
    let markdown: String
    let onToggleTask: (Int, Bool) -> Void
    let taskFontSize: CGFloat
    let headingFontSize: CGFloat

    init(
        markdown: String,
        taskFontSize: CGFloat = MarkdownDocumentCodec.defaultTaskFontSize,
        headingFontSize: CGFloat = MarkdownDocumentCodec.defaultHeadingFontSize,
        onToggleTask: @escaping (Int, Bool) -> Void
    ) {
        self.markdown = markdown
        self.taskFontSize = taskFontSize
        self.headingFontSize = headingFontSize
        self.onToggleTask = onToggleTask
    }

    var body: some View {
        ScrollView {
            blockList(MarkdownParser.parse(markdown))
                .font(.system(size: taskFontSize))
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    /// blockList ↔ blockView 互递归：必须用 AnyView 在递归边界擦除类型，
    /// 否则 `some View` 的具体类型无限展开，Swift 5.9 编译器会挂死。
    private func blockList(_ blocks: [MarkdownBlock]) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        )
    }

    private func blockView(_ block: MarkdownBlock) -> AnyView {
        switch block {
        case let .heading(level, inline):
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    inlineText(inline)
                        .font(headingFont(level))
                    if level == 1 {
                        Divider()
                    }
                }
            )
        case let .paragraph(inline):
            return AnyView(inlineText(inline))
        case let .codeBlock(_, code):
            return AnyView(
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            )
        case let .blockquote(inner):
            return AnyView(
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(0.25))
                        .frame(width: 3)
                    blockList(inner)
                        .foregroundStyle(Color.primary.opacity(0.72))
                }
            )
        case let .list(ordered, items):
            return AnyView(
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.offset) { position, item in
                        itemView(item, number: position + 1, ordered: ordered)
                    }
                }
            )
        case .thematicBreak:
            return AnyView(Divider().padding(.vertical, 4))
        }
    }

    private func itemView(_ item: MarkdownListItem, number: Int, ordered: Bool) -> AnyView {
        AnyView(
            HStack(alignment: .top, spacing: 7) {
                if let task = item.task {
                    Button {
                        onToggleTask(task.line, task.checked)
                    } label: {
                        Image(systemName: task.checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 15))
                            .foregroundStyle(task.checked ? Color.accentColor : Color.primary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(ordered ? "\(number)." : "•")
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .frame(minWidth: 14, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 3) {
                    inlineText(item.inline)
                        .font(item.task == nil ? nil : .system(size: taskFontSize))
                        .strikethrough(item.task?.checked == true)
                        .foregroundStyle(item.task?.checked == true
                            ? Color.primary.opacity(0.55)
                            : Color.primary)
                    if !item.children.isEmpty {
                        blockList(item.children)
                            .padding(.leading, 2)
                    }
                }
            }
        )
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: headingFontSize)
        case 2: return .system(size: headingFontSize * 18 / 21)
        case 3: return .system(size: headingFontSize * 15.5 / 21)
        default: return .system(size: headingFontSize * 14 / 21)
        }
    }

    private func inlineText(_ markdown: String) -> Text {
        let attributed = (try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(markdown)
        return Text(attributed)
    }
}
