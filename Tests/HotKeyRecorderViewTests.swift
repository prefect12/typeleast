import AppKit
import HotKey
import XCTest
@testable import Typeleast

final class HotKeyRecorderViewTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "appLanguage")
        super.tearDown()
    }

    func testModifiersIgnoreKeyUpClearEvents() {
        LanguageManager.shared.current = .chinese

        let modifiers: NSEvent.ModifierFlags = [.command, .control]
        let displayText = HotKeyRecorderLogic.displayText(modifiers: modifiers, key: nil)

        XCTAssertEqual(displayText, "⌘⌃  再按一个键")
    }

    func testRightCommandShowsReleaseToSave() {
        LanguageManager.shared.current = .chinese

        let displayText = HotKeyRecorderLogic.displayText(
            modifiers: [.command],
            key: nil,
            modifierOnlyKey: .rightCommand
        )

        XCTAssertEqual(HotKeyRecorderLogic.modifierOnlyKey(fromKeyCode: 54), .rightCommand)
        XCTAssertEqual(displayText, "右 Command (⌘)  松开保存")
    }

    func testModifierOnlyShortcutUsesStableStoredValue() {
        let storedValue = GlobalShortcutDisplay.storedValue(for: .rightCommand)

        XCTAssertEqual(storedValue, "modifierOnly:rightCommand")
        XCTAssertEqual(GlobalShortcutDisplay.modifierOnlyKey(from: storedValue), .rightCommand)
    }

    func testKeyDownModifiersAreFormattedFromCurrentEventFlags() {
        let modifiers = HotKeyRecorderLogic.modifiers(from: [.command, .control, .capsLock])

        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertTrue(modifiers.contains(.control))
        XCTAssertFalse(modifiers.contains(.capsLock))
        XCTAssertEqual(HotKeyRecorderLogic.formatHotkey(modifiers: modifiers, key: .space), "⌘⌃Space")
    }

    func testModifierOnlyHotkeyDoesNotCompleteGlobalShortcut() {
        XCTAssertFalse(HotKeyRecorderLogic.isComplete(modifiers: [.command], key: nil))
        XCTAssertTrue(HotKeyRecorderLogic.isComplete(modifiers: [.command], key: .space))
        XCTAssertTrue(HotKeyRecorderLogic.isComplete(modifiers: [], key: .f5))
    }

    func testInvalidGlobalShortcutCombinations() {
        XCTAssertFalse(HotKeyRecorderLogic.isValidHotkey(modifiers: [.shift], key: .a))
        XCTAssertFalse(HotKeyRecorderLogic.isValidHotkey(modifiers: [.option], key: .a))
        XCTAssertFalse(HotKeyRecorderLogic.isValidHotkey(modifiers: [.command], key: .escape))
        XCTAssertTrue(HotKeyRecorderLogic.isValidHotkey(modifiers: [.command], key: .a))
    }
}
