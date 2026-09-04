import AppKit
import XCTest
@testable import MenuNote

final class MarkdownDocumentCodecTests: XCTestCase {
    func testHeadingAndTaskMarkersAreHiddenInRichText() {
        let rich = MarkdownDocumentCodec.attributedDocument(from: "# 标题\n- [ ] 任务")
        XCTAssertEqual(rich.string, "标题\n☐  任务")
        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: rich), "# 标题\n- [ ] 任务")
    }

    func testCommonBlockSyntaxRoundTrips() {
        let source = "## 二级\n\n> 引用\n\n- 项目\n1. 有序\n\n---\n\n```swift\nlet a = 1\n```"
        let rich = MarkdownDocumentCodec.attributedDocument(from: source)
        let roundTrip = MarkdownDocumentCodec.markdown(from: rich)
        XCTAssertTrue(roundTrip.contains("## 二级"))
        XCTAssertTrue(roundTrip.contains("> 引用"))
        XCTAssertTrue(roundTrip.contains("- 项目"))
        XCTAssertTrue(roundTrip.contains("1. 有序"))
        XCTAssertTrue(roundTrip.contains("---"))
        XCTAssertTrue(roundTrip.contains("let a = 1"))
    }

    func testActiveCompletedTaskStaysCheckedThroughCodec() {
        let source = "- [x] 已完成 [完成时间: 2026-09-03 14:00:00] <!-- menunote:active-completed -->"
        let rich = MarkdownDocumentCodec.attributedDocument(from: source)
        XCTAssertTrue(rich.string.hasPrefix("☑  已完成"))
        XCTAssertEqual(rich.attribute(.menuNoteTaskChecked, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: rich), source)
    }

    func testNestedTaskKeepsIndentInRichText() {
        let source = "- [ ] 父任务\n    - [x] 子任务 [完成时间: 2026-09-03 14:00:00] <!-- menunote:active-completed -->"
        let rich = MarkdownDocumentCodec.attributedDocument(from: source)
        let childLocation = (rich.string as NSString).range(of: "☑  子任务").location
        let attributes = rich.attributes(at: childLocation, effectiveRange: nil)
        let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
        let titleFont = rich.attribute(.font, at: childLocation + 3, effectiveRange: nil) as? NSFont

        XCTAssertEqual(attributes[.menuNoteTaskIndent] as? String, "    - ")
        XCTAssertEqual(paragraph?.firstLineHeadIndent, 36)
        XCTAssertEqual(paragraph?.headIndent, 61)
        XCTAssertEqual(titleFont?.pointSize ?? 0, 14.5, accuracy: 0.01)
        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: rich), source)
    }

    func testConfiguredTaskAndHeadingFontSizes() {
        let rich = MarkdownDocumentCodec.attributedDocument(
            from: "# 标题\n- [ ] 任务",
            taskFontSize: 18,
            headingFontSize: 30
        )
        let headingFont = rich.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let taskLocation = (rich.string as NSString).range(of: "☐  任务").location
        let taskFont = rich.attribute(.font, at: taskLocation + 3, effectiveRange: nil) as? NSFont

        XCTAssertEqual(headingFont?.pointSize ?? 0, 30, accuracy: 0.01)
        XCTAssertEqual(taskFont?.pointSize ?? 0, 18, accuracy: 0.01)
    }

    func testStandaloneTextLineUsesHeadingFormat() {
        let rich = MarkdownDocumentCodec.attributedDocument(from: "大家好")
        let font = rich.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize ?? 0, MarkdownDocumentCodec.defaultHeadingFontSize, accuracy: 0.01)
        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: rich), "# 大家好")
    }

    func testNonTaskListLineAlsoUsesHeadingFormat() {
        let rich = MarkdownDocumentCodec.attributedDocument(from: "- 普通内容")
        let contentLocation = (rich.string as NSString).range(of: "普通内容").location
        let font = rich.attribute(.font, at: contentLocation, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize ?? 0, MarkdownDocumentCodec.defaultHeadingFontSize, accuracy: 0.01)
        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: rich), "- 普通内容")
    }

    func testTaskOnlyCheckboxUsesAccentColor() {
        let rich = MarkdownDocumentCodec.attributedDocument(from: "- [ ] 任务正文")
        let checkboxColor = rich.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let textColor = rich.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor
        XCTAssertEqual(checkboxColor, NSColor.controlAccentColor)
        XCTAssertEqual(textColor, NSColor.labelColor)
    }

    func testOrderedListMarkerIsVisibleAndRoundTrips() {
        let source = "1. 第一项\n2. 第二项"
        let rich = MarkdownDocumentCodec.attributedDocument(from: source)
        XCTAssertEqual(rich.string, "1.  第一项\n2.  第二项")
        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: rich), source)
    }

    func testVisibleBulletRoundTrips() {
        let source = "- 一个项目"
        let rich = MarkdownDocumentCodec.attributedDocument(from: source)
        XCTAssertEqual(rich.string, "•  一个项目")
        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: rich), source)
    }

    func testEmptyDocumentEncodesToEmptyMarkdown() {
        let rich = MarkdownDocumentCodec.attributedDocument(from: "")
        XCTAssertEqual(rich.string, "")
        XCTAssertEqual(MarkdownDocumentCodec.markdown(from: rich), "")
    }

    func testInlineFormattingIsDisplayedWithoutMarkers() {
        let rich = MarkdownDocumentCodec.attributedDocument(from: "支持 **加粗** 和 *斜体*、`代码`、~~删除~~")
        XCTAssertEqual(rich.string, "支持 加粗 和 斜体、代码、删除")
    }
}
