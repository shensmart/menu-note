import Carbon.HIToolbox
import XCTest
@testable import MenuNote

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MenuNoteTests.SettingsStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testPinningInvertsAutoHideAndPersists() {
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.isWindowPinned)
        XCTAssertTrue(settings.autoHideOnFocusLoss)
        XCTAssertEqual(settings.makeTaskHotKey, LineActionHotKey.defaultMakeTask)
        XCTAssertEqual(settings.taskFontSize, MarkdownDocumentCodec.defaultTaskFontSize)
        XCTAssertEqual(settings.headingFontSize, MarkdownDocumentCodec.defaultHeadingFontSize)

        settings.isWindowPinned = true
        XCTAssertTrue(settings.isWindowPinned)
        XCTAssertFalse(settings.autoHideOnFocusLoss)

        let restored = SettingsStore(defaults: defaults)
        XCTAssertTrue(restored.isWindowPinned)
        XCTAssertFalse(restored.autoHideOnFocusLoss)
    }

    func testMakeTaskHotKeyPersistsAndLegacyLineSettingsGetDefault() throws {
        let settings = SettingsStore(defaults: defaults)
        let custom = HotKey(keyCode: UInt32(kVK_ANSI_Y), modifiers: UInt32(cmdKey | shiftKey))
        settings.makeTaskHotKey = custom
        settings.taskFontSize = 18
        settings.headingFontSize = 30

        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.makeTaskHotKey, custom)
        XCTAssertEqual(restored.taskFontSize, 18)
        XCTAssertEqual(restored.headingFontSize, 30)

        let legacy = LineActionHotKey(
            copyLine: HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey)),
            deleteLine: HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey))
        )
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(LineActionHotKey.self, from: data)
        XCTAssertEqual(decoded.makeTask, LineActionHotKey.defaultMakeTask)
    }
}
