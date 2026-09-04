import AppKit
import XCTest
@testable import MenuNote

final class MarkdownRichTextEditorTests: XCTestCase {
    func testDeletingEmptyTaskRemovesWholeCheckboxAtOnce() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] 任务 5\n- [ ] ")
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        textView.deleteBackward(nil)

        XCTAssertEqual(textView.string, "☐  任务 5\n")
    }

    func testDeletingFirstEmptyTaskRemovesTheWholeFirstLine() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] \n- [ ] 后续任务")
        )
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        textView.deleteBackward(nil)

        XCTAssertEqual(textView.string, "\n☐  后续任务")
    }

    func testDeletingFirstEmptyTaskThenTypingUsesHeadingFormat() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.headingFontSize = 24
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] \n- [ ] 后续任务")
        )
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        textView.deleteBackward(nil)
        textView.insertText("明天任务", replacementRange: textView.selectedRange())

        XCTAssertEqual(
            MarkdownDocumentCodec.markdown(from: textView.attributedString()),
            "# 明天任务\n- [ ] 后续任务"
        )
        let titleLocation = (textView.string as NSString).range(of: "明天任务").location
        let titleFont = textView.textStorage?.attribute(.font, at: titleLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(titleFont?.pointSize ?? 0, 24, accuracy: 0.01)
    }

    func testTaskNewlineKeepsTaskFormat() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] 任务")
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        textView.insertNewline(nil)

        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: textView.attributedString()), "- [ ] 任务\n- [ ] ")
    }

    func testHeadingNewlineKeepsHeadingFormat() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.headingFontSize = 24
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "# 标题", headingFontSize: 24)
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        textView.insertNewline(nil)
        textView.insertText("下一标题", replacementRange: textView.selectedRange())

        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: textView.attributedString()), "# 标题\n# 下一标题")
        let nextTitleLocation = (textView.string as NSString).range(of: "下一标题").location
        let nextTitleFont = textView.textStorage?.attribute(.font, at: nextTitleLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(nextTitleFont?.pointSize ?? 0, 24, accuracy: 0.01)
    }

    func testEmptyDocumentTypingUsesHeadingFormat() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.headingFontSize = 24
        textView.setHeadingTypingAttributes()

        textView.insertText("标题", replacementRange: textView.selectedRange())

        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: textView.attributedString()), "# 标题")
        let titleFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(titleFont?.pointSize ?? 0, 24, accuracy: 0.01)
    }

    func testDeletingEmptyTaskThenTypingUsesHeadingFormat() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.headingFontSize = 24
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] 任务\n- [ ] ")
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        textView.deleteBackward(nil)
        textView.insertText("标题", replacementRange: textView.selectedRange())

        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: textView.attributedString()), "- [ ] 任务\n# 标题")
        let titleLocation = (textView.string as NSString).range(of: "标题").location
        let titleFont = textView.textStorage?.attribute(.font, at: titleLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(titleFont?.pointSize ?? 0, 24, accuracy: 0.01)
    }

    func testDeletingAllContentResetsHeadingColor() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] 任务\n# 标题")
        )
        textView.selectAll(nil)

        textView.deleteBackward(nil)
        textView.insertText("新标题", replacementRange: textView.selectedRange())

        let titleColor = textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: textView.attributedString()), "# 新标题")
        XCTAssertEqual(titleColor, NSColor.labelColor)
    }

    func testConvertingIndentedBulletToTaskPreservesIndent() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] 父任务\n    - 普通子任务")
        )
        let child = (textView.string as NSString).range(of: "•  普通子任务")
        textView.setSelectedRange(NSRange(location: NSMaxRange(child), length: 0))

        XCTAssertTrue(textView.convertCurrentLineToTask())
        XCTAssertEqual(textView.string, "☐  父任务\n☐  普通子任务")
        XCTAssertEqual(
            MarkdownDocumentCodec.markdown(from: textView.attributedString()),
            "- [ ] 父任务\n    - [ ] 普通子任务"
        )
        let titleLocation = (textView.string as NSString).range(of: "普通子任务").location
        let titleFont = textView.textStorage?.attribute(.font, at: titleLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(titleFont?.pointSize ?? 0, MarkdownDocumentCodec.defaultTaskFontSize, accuracy: 0.01)
    }

    func testConvertingHeadingBackToTaskUsesTaskFont() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.taskFontSize = 14.5
        textView.headingFontSize = 21
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] 父任务\n# 子任务\n    - [ ] 孙任务")
        )
        let title = (textView.string as NSString).range(of: "子任务")
        textView.setSelectedRange(NSRange(location: NSMaxRange(title), length: 0))

        XCTAssertTrue(textView.convertCurrentLineToTask())

        let taskFont = textView.textStorage?.attribute(.font, at: title.location + 3, effectiveRange: nil) as? NSFont
        XCTAssertEqual(taskFont?.pointSize ?? 0, 14.5, accuracy: 0.01)
    }

    func testNormalizingTaskLineRemovesStaleHeadingFont() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.taskFontSize = 14.5
        textView.headingFontSize = 21
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] 任务")
        )
        let title = (textView.string as NSString).range(of: "任务")
        textView.textStorage?.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: 21, weight: .semibold),
            range: title
        )

        textView.normalizeLinePresentation()

        let taskFont = textView.textStorage?.attribute(.font, at: title.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(taskFont?.pointSize ?? 0, 14.5, accuracy: 0.01)
        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: textView.attributedString()), "- [ ] 任务")
    }

    func testRemovingRootTaskMarkerPromotesDescendantsOneLevel() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        textView.isEditable = true
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] 根\n    - [ ] 二级\n        - [ ] 三级\n- [ ] 外部")
        )
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        textView.deleteBackward(nil)

        XCTAssertEqual(
            MarkdownDocumentCodec.markdown(from: textView.attributedString()),
            "# 根\n- [ ] 二级\n    - [ ] 三级\n- [ ] 外部"
        )
        let titleFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(titleFont?.pointSize ?? 0, MarkdownDocumentCodec.defaultHeadingFontSize, accuracy: 0.01)
    }

    func testRemovingNestedTaskMarkerPromotesDescendantsAndMovesTitleToRoot() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        textView.isEditable = true
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "- [ ] 任务4\n    - [ ] 任务4.1\n        - [ ] 任务4.1.1\n            - [ ] 任务4.1.1.1\n    - [ ] 任务4.2\n    - [ ] 任务4.3\n- [ ] 任务5")
        )
        let nestedTitle = (textView.string as NSString).range(of: "☐  任务4.1")
        textView.setSelectedRange(NSRange(location: nestedTitle.location + 3, length: 0))

        textView.deleteBackward(nil)

        XCTAssertEqual(
            MarkdownDocumentCodec.markdown(from: textView.attributedString()),
            "- [ ] 任务4\n    - [ ] 任务4.2\n    - [ ] 任务4.3\n- [ ] 任务5\n# 任务4.1\n- [ ] 任务4.1.1\n    - [ ] 任务4.1.1.1"
        )
        let promotedTitle = (textView.string as NSString).range(of: "任务4.1")
        let titleFont = textView.textStorage?.attribute(.font, at: promotedTitle.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(titleFont?.pointSize ?? 0, MarkdownDocumentCodec.defaultHeadingFontSize, accuracy: 0.01)
        let titleParagraph = textView.textStorage?.attribute(.paragraphStyle, at: promotedTitle.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(titleParagraph?.firstLineHeadIndent ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(titleParagraph?.headIndent ?? -1, 0, accuracy: 0.01)
        let promotedChild = (textView.string as NSString).range(of: "任务4.1.1")
        let childParagraph = textView.textStorage?.attribute(.paragraphStyle, at: promotedChild.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(childParagraph?.firstLineHeadIndent ?? -1, 0, accuracy: 0.01)
        let promotedGrandchild = (textView.string as NSString).range(of: "任务4.1.1.1")
        let grandchildParagraph = textView.textStorage?.attribute(.paragraphStyle, at: promotedGrandchild.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(grandchildParagraph?.firstLineHeadIndent ?? -1, 36, accuracy: 0.01)
        let completed = TaskArchiveCodec.complete(
            active: MarkdownDocumentCodec.markdown(from: textView.attributedString()),
            at: 0,
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(completed?.tasks.map(\.title).sorted(), ["任务4", "任务4.2", "任务4.3"])
    }

    func testRemovingTaskMarkerCanBeUndoneAsOneOperation() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        textView.isEditable = true
        textView.allowsUndo = true
        let source = "- [ ] 任务4\n    - [ ] 任务4.1\n        - [ ] 任务4.1.1"
        textView.textStorage?.setAttributedString(MarkdownDocumentCodec.attributedDocument(from: source))
        let nestedTitle = (textView.string as NSString).range(of: "☐  任务4.1")
        textView.setSelectedRange(NSRange(location: nestedTitle.location + 3, length: 0))

        textView.deleteBackward(nil)
        textView.undoManager?.undo()

        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: textView.attributedString()), source)
        let restoredTitle = (textView.string as NSString).range(of: "任务4.1")
        let restoredFont = textView.textStorage?.attribute(.font, at: restoredTitle.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(restoredFont?.pointSize ?? 0, MarkdownDocumentCodec.defaultTaskFontSize, accuracy: 0.01)

        textView.undoManager?.redo()
        XCTAssertEqual(
            MarkdownDocumentCodec.markdown(from: textView.attributedString()),
            "- [ ] 任务4\n# 任务4.1\n- [ ] 任务4.1.1"
        )
    }

    func testRemovingNestedTaskMarkerMovesNewTitleBeforeNextHeading() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.isEditable = true
        let source = "# 我的任务\n- [ ] 任务4\n    - [ ] 任务4.1\n        - [ ] 任务4.1.1\n        - [ ] 任务4.1.2\n    - [ ] 任务4.2\n    - [ ] 任务4.3\n- [ ] 任务5\n\n# 明天任务\n- [ ] 明天任务"
        textView.textStorage?.setAttributedString(MarkdownDocumentCodec.attributedDocument(from: source))
        let nestedTitle = (textView.string as NSString).range(of: "☐  任务4.1")
        textView.setSelectedRange(NSRange(location: nestedTitle.location + 3, length: 0))

        textView.deleteBackward(nil)

        XCTAssertEqual(
            MarkdownDocumentCodec.markdown(from: textView.attributedString()),
            "# 我的任务\n- [ ] 任务4\n    - [ ] 任务4.2\n    - [ ] 任务4.3\n- [ ] 任务5\n# 任务4.1\n- [ ] 任务4.1.1\n- [ ] 任务4.1.2\n\n# 明天任务\n- [ ] 明天任务"
        )
    }

    func testConvertingExistingTaskIsNoop() {
        let textView = TaskTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isEditable = true
        textView.textStorage?.setAttributedString(
            MarkdownDocumentCodec.attributedDocument(from: "    - [ ] 已经是任务")
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        let original = textView.string

        XCTAssertFalse(textView.convertCurrentLineToTask())
        XCTAssertEqual(textView.string, original)
    }
}
