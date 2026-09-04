import AppKit
import SwiftUI

/// 原文编辑模式。使用原生 NSTextView，确保非激活面板中的编辑命令仍能正常工作。
struct EditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SourceTextView()
        textView.frame = scrollView.contentView.bounds
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.string = text
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? SourceTextView,
              textView.string != text,
              !context.coordinator.isApplying else { return }

        let oldSelection = textView.selectedRange()
        context.coordinator.isApplying = true
        textView.string = text
        let maxLocation = textView.string.utf16.count
        textView.setSelectedRange(NSRange(
            location: min(oldSelection.location, maxLocation),
            length: min(oldSelection.length, max(0, maxLocation - min(oldSelection.location, maxLocation)))
        ))
        context.coordinator.isApplying = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isApplying = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying,
                  let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class SourceTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
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
            default:
                break
            }
        }
        if flags == [.command, .shift], key == "z" {
            undoManager?.redo()
            return
        }
        if flags == [.command, .shift], key == "t" {
            convertCurrentLineToTask()
            return
        }
        super.keyDown(with: event)
    }

    private func convertCurrentLineToTask() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let cursor = min(selectedRange().location, source.length)
        let lineRange = source.lineRange(for: NSRange(location: cursor, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard line.range(of: "^\\s*[-*+]\\s+\\[[ xX]\\]", options: .regularExpression) == nil else { return }

        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let insertionLocation = lineRange.location + (indentation as NSString).length
        let marker = "- [ ] "
        let insertionRange = NSRange(location: insertionLocation, length: 0)
        guard shouldChangeText(in: insertionRange, replacementString: marker) else { return }
        storage.replaceCharacters(in: insertionRange, with: marker)
        didChangeText()

        let selection = selectedRange()
        if selection.location >= insertionLocation {
            setSelectedRange(NSRange(
                location: selection.location + (marker as NSString).length,
                length: selection.length
            ))
        }
    }
}
