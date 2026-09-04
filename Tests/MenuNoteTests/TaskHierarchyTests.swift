import XCTest
@testable import MenuNote

final class TaskHierarchyTests: XCTestCase {
    func testCompletingNestedLeafStaysInActiveGroup() throws {
        let source = "- [ ] 父任务\n    - [ ] 子任务"
        let change = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 1, now: date()))
        XCTAssertEqual(
            change.active,
            "- [ ] 父任务\n    - [x] 子任务 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->"
        )
        XCTAssertTrue(change.tasks.isEmpty)
    }

    func testCompletingOneOfTwoChildrenStaysInActiveGroup() throws {
        let source = "- [ ] 父任务\n    - [ ] 子一\n    - [ ] 子二"
        let change = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 1, now: date()))
        XCTAssertEqual(change.tasks, [])
        XCTAssertEqual(
            change.active,
            "- [ ] 父任务\n    - [x] 子一 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->\n    - [ ] 子二"
        )
    }

    func testCompletingLastChildDoesNotMoveGroupToCompleted() throws {
        let source = "- [ ] 父任务\n    - [ ] 子一\n    - [ ] 子二"
        let first = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 1, now: date()))
        let second = try XCTUnwrap(TaskArchiveCodec.complete(active: first.active, at: 2, now: date()))

        XCTAssertTrue(second.tasks.isEmpty)
        XCTAssertTrue(second.active.contains("- [ ] 父任务"))
        XCTAssertTrue(second.active.contains("    - [x] 子一"))
        XCTAssertTrue(second.active.contains("    - [x] 子二"))
    }

    func testCompletingTopLevelTaskArchivesWholeGroupIncludingActiveChildren() throws {
        let source = "- [ ] 父任务\n    - [ ] 子一\n        - [x] 孙 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->\n    - [x] 子二 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->"
        let change = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 0, now: date()))

        XCTAssertEqual(change.active, "")
        XCTAssertEqual(change.tasks.map(\.title), ["孙", "子一", "子二", "父任务"])
    }

    func testCompletingNestedParentMarksItsThreeLevelSubtreeWithoutArchiving() throws {
        let source = "- [ ] 根\n    - [ ] 二级\n        - [ ] 三级一\n            - [ ] 四级\n        - [ ] 三级二\n    - [ ] 另一个二级"
        let change = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 1, now: date()))

        XCTAssertTrue(change.tasks.isEmpty)
        XCTAssertEqual(
            change.active,
            "- [ ] 根\n    - [x] 二级 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->\n        - [x] 三级一 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->\n            - [x] 四级 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->\n        - [x] 三级二 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->\n    - [ ] 另一个二级"
        )
    }

    func testUncompletingNestedParentUnchecksItsSubtreeOnly() throws {
        let source = "- [ ] 根\n    - [x] 二级 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->\n        - [x] 三级 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->\n    - [x] 另一个二级 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->"
        let changed = try XCTUnwrap(TaskArchiveCodec.uncompleteActiveTask(active: source, at: 1))

        XCTAssertEqual(
            changed,
            "- [ ] 根\n    - [ ] 二级\n        - [ ] 三级\n    - [x] 另一个二级 [完成时间: 2026-09-03 11:00:00] <!-- menunote:active-completed -->"
        )
    }

    func testNestedPlainBulletDoesNotCascadeParent() throws {
        let source = "- [ ] 父任务\n    - 普通项目\n- [ ] 另一个任务"
        let change = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 0, now: date()))
        XCTAssertEqual(change.tasks.map(\.title), ["父任务"])
        XCTAssertEqual(change.active, "    - 普通项目\n- [ ] 另一个任务")
    }

    func testArchivedParentLinkSurvivesComposeAndSplit() throws {
        let source = "- [ ] 父任务\n    - [ ] 子任务"
        let change = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 0, now: date()))
        let saved = TaskArchiveCodec.compose(active: change.active, completed: change.tasks)
        let split = TaskArchiveCodec.split(saved)
        let child = try XCTUnwrap(split.completed.first { $0.title == "子任务" })
        XCTAssertEqual(child.parentSourceLine, 0)
        XCTAssertEqual(TaskArchiveCodec.archivedAncestors(of: child, in: split.completed).map(\.title), ["父任务"])
    }

    private func date() -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: "2026-09-03 11:00:00")!
    }
}
