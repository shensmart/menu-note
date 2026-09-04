import Carbon.HIToolbox
import XCTest
@testable import MenuNote

final class HotKeyTests: XCTestCase {
    func testDefaultShortcutDisplay() {
        XCTAssertEqual(HotKey.default.displayString, "⌥空格")
        XCTAssertTrue(HotKey.default.isValid)
    }

    func testModifierDisplayOrdering() {
        let hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        XCTAssertEqual(hotKey.displayString, "⌃⌥⇧⌘K")
    }

    func testCommonKeyDisplayNames() {
        XCTAssertEqual(HotKey(keyCode: UInt32(kVK_Return), modifiers: UInt32(cmdKey)).displayString, "⌘↩")
        XCTAssertEqual(HotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(optionKey)).displayString, "⌥←")
        XCTAssertEqual(HotKey(keyCode: UInt32(kVK_F12), modifiers: UInt32(cmdKey)).displayString, "⌘F12")
    }

    func testLegacyPresetMigration() {
        XCTAssertEqual(HotKey.legacyPreset(named: "optionSpace"), .default)
        XCTAssertEqual(
            HotKey.legacyPreset(named: "cmdOptionM"),
            HotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | optionKey))
        )
        XCTAssertEqual(
            HotKey.legacyPreset(named: "ctrlOptionM"),
            HotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey))
        )
        XCTAssertNil(HotKey.legacyPreset(named: "unknown"))
    }

    func testCodingRoundTrip() throws {
        let original = HotKey(keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(cmdKey | optionKey))
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(HotKey.self, from: data), original)
    }

    func testUnknownKeyHasReadableFallback() {
        let hotKey = HotKey(keyCode: 999, modifiers: UInt32(cmdKey))
        XCTAssertEqual(hotKey.displayString, "⌘键999")
    }
}
