import XCTest
@testable import MenuNote

final class NotesStoreTaskTests: XCTestCase {
    func testAddTaskToEmptyDocumentCreatesCheckboxTask() {
        let store = NotesStore()
        let line = store.addTask()
        XCTAssertEqual(line, 0)
        XCTAssertEqual(store.activeMarkdown, "- [ ] ")
        XCTAssertEqual(store.draft, "- [ ] ")
    }

    func testAddTaskAppendsAfterExistingContent() {
        let store = NotesStore()
        _ = store.addTask()
        _ = store.addTask()
        XCTAssertEqual(store.activeMarkdown, "- [ ] \n- [ ] ")
    }

    func testRemovingLastTaskLeavesDocumentWithoutTask() {
        let store = NotesStore()
        store.updateActiveMarkdown("# 今日")
        _ = store.addTask()

        let focusLine = store.updateActiveMarkdown("# 今日")

        XCTAssertNil(focusLine)
        XCTAssertEqual(store.activeMarkdown, "# 今日")
    }

    func testRemovingOnlyTaskFromEmptyDocumentLeavesItEmpty() {
        let store = NotesStore()
        _ = store.addTask()

        let focusLine = store.updateActiveMarkdown("")

        XCTAssertNil(focusLine)
        XCTAssertEqual(store.activeMarkdown, "")
    }
}
