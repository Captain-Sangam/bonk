import AppKit
import XCTest
@testable import BonkCore

final class ShortcutTests: XCTestCase {
    @MainActor
    func testLegacyLetterMigratesToShiftCommand() {
        let shortcut = makeSettings(legacyLetter: "K").shortcut
        XCTAssertEqual(shortcut.keyCode, 40)
        XCTAssertEqual(shortcut.modifierFlags, [.shift, .command])
        XCTAssertEqual(shortcut.displayString, "⇧⌘K")
    }

    @MainActor
    func testMissingOrInvalidLegacyValueBecomesDefault() {
        XCTAssertEqual(makeSettings(legacyLetter: nil).shortcut, .defaultShortcut)
        XCTAssertEqual(makeSettings(legacyLetter: "7").shortcut, .defaultShortcut)
        XCTAssertEqual(Shortcut.defaultShortcut.displayString, "⇧⌘B")
    }

    @MainActor
    func testSavedShortcutSurvivesReload() {
        let defaults = UserDefaults(suiteName: "BonkShortcutTests.\(UUID())")!
        let recorded = Shortcut(keyCode: 40, modifiers: [.control, .option], label: "k")
        SettingsStore(defaults: defaults).shortcut = recorded
        XCTAssertEqual(SettingsStore(defaults: defaults).shortcut, recorded)
    }

    func testRecorderRefusesUnsafeCombinations() {
        let k: UInt16 = 40
        let refused: [(UInt16, NSEvent.ModifierFlags, String)] = [
            (k, [], "k"), (k, [.shift], "k"), (k, [.option], "k"), (k, [.option, .shift], "k"), (53, [.command], "\u{1B}")
        ]
        for (keyCode, modifiers, characters) in refused {
            XCTAssertThrowsError(try Shortcut.recorded(keyCode: keyCode, modifiers: modifiers, characters: characters))
        }
    }

    func testRecorderAcceptsCommandOrControl() throws {
        XCTAssertEqual(try Shortcut.recorded(keyCode: 40, modifiers: [.command], characters: "k").displayString, "⌘K")
        XCTAssertEqual(try Shortcut.recorded(keyCode: 40, modifiers: [.control, .option], characters: "k").displayString, "⌃⌥K")
    }

    @MainActor
    private func makeSettings(legacyLetter: String?) -> SettingsStore {
        let defaults = UserDefaults(suiteName: "BonkShortcutTests.\(UUID())")!
        defaults.set(legacyLetter, forKey: "shortcutKey")
        return SettingsStore(defaults: defaults)
    }
}
