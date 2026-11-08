import AppKit
import XCTest
@testable import AlwaysOnTests

final class HotKeyTests: XCTestCase {
    func testDefaultIsOptionCommandK() {
        XCTAssertEqual(HotKey.default.displayString, "⌥⌘K")
        XCTAssertEqual(HotKey.default.keyCode, 40)
        // Carbon's optionKey | cmdKey
        XCTAssertEqual(HotKey.default.modifiers, 0x0800 | 0x0100)
    }

    func testDisplayUsesAppleModifierOrder() {
        let all = HotKey(keyCode: 0, modifiers: HotKey.commandMask | HotKey.shiftMask | HotKey.optionMask | HotKey.controlMask,
                         keyLabel: "A")
        XCTAssertEqual(all.displayString, "⌃⌥⇧⌘A")
    }

    func testRecordsLettersWithModifiers() {
        let result = HotKey.recorded(keyCode: 35, modifierFlags: [.control, .shift], charactersIgnoringModifiers: "p")
        XCTAssertEqual(result, .success(HotKey(keyCode: 35, modifiers: HotKey.controlMask | HotKey.shiftMask, keyLabel: "P")))
    }

    func testRejectsPlainAndShiftOnlyKeys() {
        XCTAssertEqual(HotKey.recorded(keyCode: 40, modifierFlags: [], charactersIgnoringModifiers: "k"),
                       .failure(.needsModifier))
        XCTAssertEqual(HotKey.recorded(keyCode: 40, modifierFlags: [.shift], charactersIgnoringModifiers: "k"),
                       .failure(.needsModifier))
    }

    func testFunctionKeysWorkAlone() {
        XCTAssertEqual(HotKey.recorded(keyCode: 96, modifierFlags: [], charactersIgnoringModifiers: "\u{F708}"),
                       .success(HotKey(keyCode: 96, modifiers: 0, keyLabel: "F5")))
    }

    func testSpecialKeysGetReadableLabels() {
        let space = HotKey.recorded(keyCode: 49, modifierFlags: [.option], charactersIgnoringModifiers: " ")
        XCTAssertEqual(try space.get().displayString, "⌥Space")
    }

    func testRejectsKeysWithoutALabel() {
        XCTAssertEqual(HotKey.recorded(keyCode: 200, modifierFlags: [.command], charactersIgnoringModifiers: ""),
                       .failure(.unsupportedKey))
        XCTAssertEqual(HotKey.recorded(keyCode: 200, modifierFlags: [.command], charactersIgnoringModifiers: "\u{1B}"),
                       .failure(.unsupportedKey))
    }

    func testCodableRoundTrip() throws {
        let hotKey = HotKey(keyCode: 96, modifiers: HotKey.commandMask, keyLabel: "F5")
        XCTAssertEqual(try JSONDecoder().decode(HotKey.self, from: JSONEncoder().encode(hotKey)), hotKey)
    }
}
