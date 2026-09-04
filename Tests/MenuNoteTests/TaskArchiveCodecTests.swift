import XCTest
@testable import MenuNote

final class TaskArchiveCodecTests: XCTestCase {
    func testCompletingTaskAddsTimestampAndRemovesFromActiveText() throws {
        let source = "# 今天\n- [ ] 写报告\n- [ ] 发邮件"
        let now = try XCTUnwrap(date("2026-09-02 18:30:45"))
        let changed = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 1, now: now))

        XCTAssertEqual(changed.active, "# 今天\n- [ ] 发邮件")
        let task = try XCTUnwrap(changed.tasks.first)
        XCTAssertEqual(task.title, "写报告")
        XCTAssertEqual(task.completedAt, now)
        XCTAssertEqual(task.markdownLine, "- [x] 写报告 [完成时间: 2026-09-02 18:30:45]")
    }

    func testComposeAndSplitRoundTrip() throws {
        let now = try XCTUnwrap(date("2026-09-02 18:30:45"))
        let task = CompletedTask(
            markdownLine: "- [x] 完成事项 [完成时间: 2026-09-02 18:30:45]",
            title: "完成事项",
            completedAt: now,
            sourceLine: 1
        )
        let markdown = TaskArchiveCodec.compose(active: "# 任务\n- [ ] 未完成", completed: [task])
        XCTAssertTrue(markdown.contains(TaskArchiveCodec.beginMarker))
        XCTAssertTrue(markdown.contains("[完成时间: 2026-09-02 18:30:45]"))

        let split = TaskArchiveCodec.split(markdown)
        XCTAssertEqual(split.active, "# 任务\n- [ ] 未完成")
        XCTAssertEqual(split.completed.count, 1)
        XCTAssertEqual(split.completed[0].title, "完成事项")
        XCTAssertEqual(split.completed[0].completedAt, now)
        XCTAssertEqual(split.completed[0].sourceLine, 1)
    }

    func testRestoringTaskRemovesTimestampAndReturnsToOriginalPosition() {
        let task = CompletedTask(
            markdownLine: "- [x] 完成事项 [完成时间: 2026-09-02 18:30:45]",
            title: "完成事项",
            completedAt: nil,
            sourceLine: 1
        )
        XCTAssertEqual(
            TaskArchiveCodec.restore(task, to: "# 标题\n- [ ] 下一项"),
            "# 标题\n- [ ] 完成事项\n- [ ] 下一项"
        )
    }

    func testLegacyCheckedTasksAreStillCollected() {
        let split = TaskArchiveCodec.split("- [x] 旧任务\n- [ ] 新任务")
        XCTAssertEqual(split.active, "- [ ] 新任务")
        XCTAssertEqual(split.completed.count, 1)
        XCTAssertEqual(split.completed[0].title, "旧任务")
        XCTAssertNil(split.completed[0].completedAt)
    }

    func testUncompleteActiveCompletedTaskRemovesMarkerAndTimestamp() throws {
        let source = "- [x] 已恢复 [完成时间: 2026-09-02 18:30:45] <!-- menunote:active-completed -->"
        let uncompleted = try XCTUnwrap(TaskArchiveCodec.uncompleteActiveTask(active: source, at: 0))

        XCTAssertEqual(uncompleted, "- [ ] 已恢复")
    }

    func testDeletingTaskFromGroupRemovesEntireSubtree() {
        let parent = CompletedTask(
            markdownLine: "- [x] 父任务 [完成时间: 2026-09-02 18:30:45]",
            title: "父任务",
            completedAt: nil,
            sourceLine: 0,
            parentSourceLine: -1
        )
        let child = CompletedTask(
            markdownLine: "    - [x] 子任务 [完成时间: 2026-09-02 18:30:45]",
            title: "子任务",
            completedAt: nil,
            sourceLine: 1,
            parentSourceLine: 0
        )
        let other = CompletedTask(
            markdownLine: "- [x] 其他任务 [完成时间: 2026-09-02 18:30:45]",
            title: "其他任务",
            completedAt: nil,
            sourceLine: 2,
            parentSourceLine: -1
        )

        let remaining = TaskArchiveCodec.deletingCompletedTask(child, from: [parent, child, other])

        XCTAssertEqual(remaining.map(\.title), ["其他任务"])
    }

    func testDeletingLegacyTaskKeepsOtherCompletedTasks() {
        let first = CompletedTask(markdownLine: "- [x] 第一个任务", title: "第一个任务", completedAt: nil)
        let second = CompletedTask(markdownLine: "- [x] 第二个任务", title: "第二个任务", completedAt: nil)

        let remaining = TaskArchiveCodec.deletingCompletedTask(first, from: [first, second])

        XCTAssertEqual(remaining.map(\.title), ["第二个任务"])
    }

    func testCompleteThenRestoreReturnsAnUncheckedTask() throws {
        let source = "# 今天\n- [ ] 写报告\n- [ ] 发邮件"
        let now = try XCTUnwrap(date("2026-09-03 09:00:00"))
        let completed = try XCTUnwrap(TaskArchiveCodec.complete(active: source, at: 1, now: now))
        let saved = TaskArchiveCodec.compose(active: completed.active, completed: completed.tasks)
        let split = TaskArchiveCodec.split(saved)
        XCTAssertEqual(split.completed.count, 1)

        let restored = TaskArchiveCodec.restore(split.completed[0], to: split.active)
        XCTAssertEqual(restored, source)
        XCTAssertFalse(restored.contains("完成时间"))
        XCTAssertFalse(restored.contains("[x]"))
    }

    private func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }
}
