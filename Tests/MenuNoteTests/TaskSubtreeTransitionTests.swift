import XCTest
@testable import MenuNote

final class TaskSubtreeTransitionTests: XCTestCase {
    func testCompletingParentArchivesEntireSubtree() throws {
        let source = "- [ ] 根\n    - [ ] 子一\n        - [ ] 孙\n    - [ ] 子二\n- [ ] 外部"
        let change = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 0, now: date()))
        XCTAssertEqual(change.tasks.map(\.title), ["孙", "子一", "子二", "根"])
        XCTAssertEqual(change.tasks[0].markdownLine, "        - [x] 孙 [完成时间: 2026-09-03 14:00:00]")
        XCTAssertEqual(change.active, "- [ ] 外部")
    }

    func testCompletingNestedParentKeepsSubtreeInActiveMarkdown() throws {
        let source = "- [ ] 根\n    - [ ] 子一\n        - [ ] 孙\n    - [ ] 子二"
        let change = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 1, now: date()))
        XCTAssertTrue(change.tasks.isEmpty)
        XCTAssertEqual(
            change.active,
            "- [ ] 根\n    - [x] 子一 [完成时间: 2026-09-03 14:00:00] <!-- menunote:active-completed -->\n        - [x] 孙 [完成时间: 2026-09-03 14:00:00] <!-- menunote:active-completed -->\n    - [ ] 子二"
        )
    }

    func testPartialRestoreBringsEntireTreeBackWithTargetAndRootUnchecked() throws {
        let source = "- [ ] 根\n    - [ ] 子一\n    - [ ] 子二"
        let completed = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 0, now: date()))
        let target = try XCTUnwrap(completed.tasks.first { $0.title == "子一" })
        let restored = TaskArchiveCodec.partiallyRestore(target, active: completed.active, completed: completed.tasks)

        XCTAssertEqual(restored.remaining, [])
        XCTAssertTrue(restored.active.contains("- [ ] 根"))
        XCTAssertTrue(restored.active.contains("    - [ ] 子一"))
        XCTAssertTrue(restored.active.contains("    - [x] 子二 [完成时间: 2026-09-03 14:00:00] <!-- menunote:active-completed -->"))

        let saved = TaskArchiveCodec.compose(active: restored.active, completed: restored.remaining)
        let split = TaskArchiveCodec.split(saved)
        XCTAssertEqual(split.completed, [])
        XCTAssertEqual(split.active, restored.active)
    }

    func testPartialRestoreReturnsGroupToOriginalPositionAndUnchecksRoot() throws {
        let source = "- [ ] 任务 1\n- [ ] 任务 2\n- [ ] 任务 3\n    - [ ] 任务 3.1\n    - [ ] 任务 3.2\n- [ ] 任务 4\n- [ ] 任务 5"
        let now = date()
        let completed = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 2, now: now))
        let target = try XCTUnwrap(completed.tasks.first { $0.title == "任务 3.1" })

        let restored = TaskArchiveCodec.partiallyRestore(target, active: completed.active, completed: completed.tasks)

        let expected = "- [ ] 任务 1\n- [ ] 任务 2\n- [ ] 任务 3\n    - [ ] 任务 3.1\n    - [x] 任务 3.2 [完成时间: 2026-09-03 14:00:00] <!-- menunote:active-completed -->\n- [ ] 任务 4\n- [ ] 任务 5"
        XCTAssertEqual(restored.active, expected)
        XCTAssertEqual(restored.remaining, [])
    }

    func testPartialRestoreKeepsGroupWithRepeatedSiblingTitles() throws {
        let source = "- [ ] 任务1\n- [ ] 任务2\n- [ ] 任务4\n- [ ] 任务3\n    - [ ] 任务3.1\n    - [ ] 任务3.2\n- [ ] 任务4\n- [ ] 任务5"
        let completed = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 3, now: date()))
        let target = try XCTUnwrap(completed.tasks.first { $0.title == "任务3.1" })

        let restored = TaskArchiveCodec.partiallyRestore(target, active: completed.active, completed: completed.tasks)

        let expected = "- [ ] 任务1\n- [ ] 任务2\n- [ ] 任务4\n- [ ] 任务3\n    - [ ] 任务3.1\n    - [x] 任务3.2 [完成时间: 2026-09-03 14:00:00] <!-- menunote:active-completed -->\n- [ ] 任务4\n- [ ] 任务5"
        XCTAssertEqual(restored.active, expected)
        XCTAssertEqual(restored.remaining, [])
    }

    func testRestoredGroupKeepsChildrenActiveUntilRootIsCompleted() throws {
        let source = "- [ ] 任务1\n- [ ] 任务2\n- [ ] 任务4\n- [ ] 任务3\n    - [ ] 任务3.1\n    - [ ] 任务3.2\n    - [ ] 任务3.3\n- [ ] 任务4\n- [ ] 任务5"
        let firstCompleted = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 3, now: date()))
        let firstTarget = try XCTUnwrap(firstCompleted.tasks.first { $0.title == "任务3.2" })
        let firstRestore = TaskArchiveCodec.partiallyRestore(firstTarget, active: firstCompleted.active, completed: firstCompleted.tasks)

        let secondCompleted = try XCTUnwrap(TaskArchiveCodec.complete(active: firstRestore.active, at: 5, now: date()))
        XCTAssertTrue(secondCompleted.tasks.isEmpty)
        XCTAssertTrue(secondCompleted.active.contains("    - [x] 任务3.1"))

        let rootCompleted = try XCTUnwrap(TaskArchiveCodec.complete(active: secondCompleted.active, at: 3, now: date()))

        XCTAssertEqual(rootCompleted.active, "- [ ] 任务1\n- [ ] 任务2\n- [ ] 任务4\n- [ ] 任务4\n- [ ] 任务5")
        XCTAssertEqual(rootCompleted.tasks.map(\.title), ["任务3.1", "任务3.2", "任务3.3", "任务3"])
    }

    private func date() -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: "2026-09-03 14:00:00")!
    }
}
