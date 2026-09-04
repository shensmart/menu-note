import XCTest
@testable import MenuNote

final class MarkdownParserTests: XCTestCase {
    func testHeadingAndParagraph() {
        let blocks = MarkdownParser.parse("# 标题\n\n正文段落")
        XCTAssertEqual(blocks, [
            .heading(level: 1, inline: "标题"),
            .paragraph(inline: "正文段落"),
        ])
    }

    func testHeadingLevels() {
        let blocks = MarkdownParser.parse("## 二级\n### 三级\n#### 四级")
        XCTAssertEqual(blocks, [
            .heading(level: 2, inline: "二级"),
            .heading(level: 3, inline: "三级"),
            .heading(level: 4, inline: "四级"),
        ])
    }

    func testTaskListWithLineNumbers() {
        let blocks = MarkdownParser.parse("- [ ] 待办\n- [x] 完成")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let ordered, let items) = blocks[0] else {
            return XCTFail("应为无序列表")
        }
        XCTAssertFalse(ordered)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].inline, "待办")
        XCTAssertEqual(items[0].task?.checked, false)
        XCTAssertEqual(items[0].task?.line, 0)
        XCTAssertEqual(items[1].task?.checked, true)
        XCTAssertEqual(items[1].task?.line, 1)
    }

    func testActiveCompletedTaskHidesInternalMetadata() {
        let blocks = MarkdownParser.parse("- [x] 完成 [完成时间: 2026-09-04 10:07:32] <!-- menunote:active-completed -->")
        guard case .list(_, let items) = blocks[0] else {
            return XCTFail("应为无序列表")
        }
        XCTAssertEqual(items[0].inline, "完成")
        XCTAssertEqual(items[0].task?.checked, true)
    }

    func testTaskLineNumbersSkipBlankLinesAndHeading() {
        let blocks = MarkdownParser.parse("# h\n\n- [ ] t")
        guard case .list(_, let items) = blocks[1] else {
            return XCTFail("第二个块应为列表")
        }
        XCTAssertEqual(items[0].task?.line, 2)
    }

    func testStarAndPlusBulletsAreTasks() {
        for source in ["* [x] a", "+ [ ] b"] {
            let blocks = MarkdownParser.parse(source)
            guard case .list(_, let items) = blocks[0] else {
                return XCTFail("\(source) 应为列表")
            }
            XCTAssertEqual(items[0].task?.checked, source.contains("x"))
        }
    }

    func testOrderedItemWithTaskSyntaxIsNotTask() {
        let blocks = MarkdownParser.parse("1. [ ] x")
        guard case .list(let ordered, let items) = blocks[0] else {
            return XCTFail("应为有序列表")
        }
        XCTAssertTrue(ordered)
        XCTAssertNil(items[0].task)
        XCTAssertEqual(items[0].inline, "[ ] x")
    }

    func testNestedList() {
        let blocks = MarkdownParser.parse("- 父\n    - 子A\n    - 子B")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(_, let items) = blocks[0], items.count == 1 else {
            return XCTFail("应为单父项列表")
        }
        XCTAssertEqual(items[0].inline, "父")
        XCTAssertNil(items[0].task)
        guard case .list(_, let children) = items[0].children[0] else {
            return XCTFail("子级应为列表")
        }
        XCTAssertEqual(children.map(\.inline), ["子A", "子B"])
    }

    func testOrderedAfterUnorderedSplitsIntoTwoLists() {
        let blocks = MarkdownParser.parse("- a\n1. b")
        XCTAssertEqual(blocks.count, 2)
        guard case .list(let first, _) = blocks[0],
              case .list(let second, _) = blocks[1] else {
            return XCTFail("应为两个列表块")
        }
        XCTAssertFalse(first)
        XCTAssertTrue(second)
    }

    func testBlockquote() {
        let blocks = MarkdownParser.parse("> 一\n> 二")
        XCTAssertEqual(blocks, [.blockquote(blocks: [.paragraph(inline: "一\n二")])])
    }

    func testFencedCodePreservesRawContent() {
        let blocks = MarkdownParser.parse("```swift\nlet x = \"<b>\"\n```")
        XCTAssertEqual(blocks, [.codeBlock(language: "swift", code: "let x = \"<b>\"")])
    }

    func testThematicBreak() {
        XCTAssertEqual(MarkdownParser.parse("---"), [.thematicBreak])
        XCTAssertEqual(MarkdownParser.parse("***"), [.thematicBreak])
    }

    func testLazyContinuationJoinsItemText() {
        let blocks = MarkdownParser.parse("- a\nb")
        guard case .list(_, let items) = blocks[0] else {
            return XCTFail("应为列表")
        }
        XCTAssertEqual(items[0].inline, "a b")
    }

    func testParagraphMultiLineJoinsWithNewline() {
        let blocks = MarkdownParser.parse("第一行\n第二行")
        XCTAssertEqual(blocks, [.paragraph(inline: "第一行\n第二行")])
    }

    func testCRLFNormalized() {
        let blocks = MarkdownParser.parse("- [ ] a\r\n- [ ] b\r\n")
        XCTAssertEqual(blocks.count, 1)
        if case .list(_, let items) = blocks[0] {
            XCTAssertEqual(items.count, 2)
            XCTAssertEqual(items[1].task?.line, 1)
        } else {
            XCTFail("应为列表")
        }
    }
}
