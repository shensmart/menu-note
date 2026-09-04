import XCTest
@testable import MenuNote

final class CompletedTaskTreeTests: XCTestCase {
    func testParentAppearsBeforeCascadedChild() {
        let child = task("子任务", source: 1, parent: 0)
        let parent = task("父任务", source: 0, parent: -1)
        let roots = completedTaskTree(from: [child, parent])

        XCTAssertEqual(roots.map { $0.task.title }, ["父任务"])
        XCTAssertEqual(roots[0].children.map { $0.task.title }, ["子任务"])
    }

    func testSiblingAndRootOrderRemainStable() {
        let firstRoot = task("第一组", source: 0, parent: -1)
        let firstChild = task("子一", source: 1, parent: 0)
        let secondChild = task("子二", source: 2, parent: 0)
        let secondRoot = task("第二组", source: 3, parent: -1)
        let roots = completedTaskTree(from: [firstChild, secondRoot, firstRoot, secondChild])

        XCTAssertEqual(roots.map { $0.task.title }, ["第二组", "第一组"])
        XCTAssertEqual(roots[1].children.map { $0.task.title }, ["子一", "子二"])
    }

    func testLegacyAndOrphanedTasksRemainVisibleAtRoot() {
        let legacy = task("旧任务", source: -1, parent: -1)
        let orphan = task("孤儿任务", source: 5, parent: 999)
        let roots = completedTaskTree(from: [legacy, orphan])
        XCTAssertEqual(roots.map { $0.task.title }, ["旧任务", "孤儿任务"])
    }

    private func task(_ title: String, source: Int, parent: Int) -> CompletedTask {
        CompletedTask(
            markdownLine: "- [x] \(title) [完成时间: 2026-09-03 12:00:00]",
            title: title,
            completedAt: nil,
            sourceLine: source,
            parentSourceLine: parent
        )
    }
}
