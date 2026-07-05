import SwiftUI
import HotKey
import AppKit

internal enum HotKeyRecordingResult: Equatable {
    case keyCombo(String)
    case modifierOnly(PressAndHoldKey)
}

internal enum GlobalShortcutDisplay {
    private static let modifierOnlyPrefix = "modifierOnly:"

    static func storedValue(for key: PressAndHoldKey) -> String {
        "\(modifierOnlyPrefix)\(key.rawValue)"
    }

    static func modifierOnlyKey(from value: String) -> PressAndHoldKey? {
        if value.hasPrefix(modifierOnlyPrefix) {
            let rawValue = String(value.dropFirst(modifierOnlyPrefix.count))
            return PressAndHoldKey(rawValue: rawValue)
        }

        switch value {
        case "Right Command (⌘)", "右 Command (⌘)":
            return .rightCommand
        case "Left Command (⌘)", "左 Command (⌘)":
            return .leftCommand
        case "Right Option (⌥)", "右 Option (⌥)":
            return .rightOption
        case "Left Option (⌥)", "左 Option (⌥)":
            return .leftOption
        case "Right Control (⌃)", "右 Control (⌃)":
            return .rightControl
        case "Left Control (⌃)", "左 Control (⌃)":
            return .leftControl
        case "Globe / Fn (🌐)":
            return .globe
        default:
            break
        }

        return PressAndHoldKey.allCases.first { key in
            value == key.displayName || value == key.rawValue
        }
    }

    static func text(for value: String) -> String {
        modifierOnlyKey(from: value)?.displayName ?? value
    }
}

internal struct HotKeyRecorderView: View {
    @Binding var isRecording: Bool
    @Binding var recordedModifiers: NSEvent.ModifierFlags
    @Binding var recordedKey: Key?
    let onComplete: (HotKeyRecordingResult) -> Void
    
    @State private var displayText = L10n.RecordingSettings.pressKeys
    @State private var eventMonitor: Any?
    @State private var pendingModifierOnlyKey: PressAndHoldKey?
    
    private var accentColor: Color { DashboardTheme.accent }
    
    var body: some View {
        HStack {
            Text(displayText)
                .foregroundStyle(accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            
            Button(L10n.Common.cancel) {
                stopRecording()
                isRecording = false
            }
            .buttonStyle(.bordered)
        }
        .onAppear {
            startRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        guard eventMonitor == nil else { return }
        displayText = HotKeyRecorderLogic.displayText(
            modifiers: recordedModifiers,
            key: recordedKey,
            modifierOnlyKey: pendingModifierOnlyKey
        )
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleKeyEvent(event)
            return nil // Consume the event
        }
    }
    
    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            let modifierOnlyKey = HotKeyRecorderLogic.modifierOnlyKey(fromKeyCode: event.keyCode)
            let currentModifiers = HotKeyRecorderLogic.modifiers(from: event.modifierFlags)

            if let modifierOnlyKey {
                if currentModifiers.contains(modifierOnlyKey.modifierFlag) {
                    pendingModifierOnlyKey = modifierOnlyKey
                    recordedModifiers = modifierOnlyKey.modifierFlag
                    recordedKey = nil
                    updateDisplayText()
                } else if pendingModifierOnlyKey == modifierOnlyKey, recordedKey == nil {
                    completeRecording(.modifierOnly(modifierOnlyKey))
                }

                return
            }

            if !currentModifiers.isEmpty {
                pendingModifierOnlyKey = nil
                recordedModifiers = currentModifiers
                recordedKey = nil
            }
            updateDisplayText()
        } else if event.type == .keyDown {
            pendingModifierOnlyKey = nil
            recordedModifiers = HotKeyRecorderLogic.modifiers(from: event.modifierFlags)

            if let key = HotKeyRecorderLogic.keyFromKeyCode(event.keyCode) {
                recordedKey = key
                
                // Complete the recording if we have both modifiers and a key
                if HotKeyRecorderLogic.isComplete(modifiers: recordedModifiers, key: key) {
                    if HotKeyRecorderLogic.isValidHotkey(modifiers: recordedModifiers, key: key) {
                        let hotkeyString = HotKeyRecorderLogic.formatHotkey(modifiers: recordedModifiers, key: key)
                        completeRecording(.keyCombo(hotkeyString))
                    } else {
                        // Invalid hotkey, show error briefly
                        displayText = L10n.RecordingSettings.invalidHotkey
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            recordedModifiers = []
                            recordedKey = nil
                            pendingModifierOnlyKey = nil
                            displayText = L10n.RecordingSettings.pressKeys
                        }
                    }
                } else {
                    updateDisplayText()
                }
            }
        }
    }
    
    private func updateDisplayText() {
        displayText = HotKeyRecorderLogic.displayText(
            modifiers: recordedModifiers,
            key: recordedKey,
            modifierOnlyKey: pendingModifierOnlyKey
        )
    }

    private func completeRecording(_ result: HotKeyRecordingResult) {
        stopRecording()
        onComplete(result)
        isRecording = false
    }
}

internal enum HotKeyRecorderLogic {
    private static let modifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    static func modifiers(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(modifierMask)
    }

    static func displayText(
        modifiers: NSEvent.ModifierFlags,
        key: Key?,
        modifierOnlyKey: PressAndHoldKey? = nil
    ) -> String {
        if let modifierOnlyKey, key == nil {
            return "\(modifierOnlyKey.displayName)  \(L10n.RecordingSettings.releaseToSave)"
        }

        var parts: [String] = []
        
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("⌃") }
        
        if let key {
            parts.append(keyToString(key))
        }

        if parts.isEmpty {
            return L10n.RecordingSettings.pressKeys
        }

        if key == nil {
            return "\(parts.joined())  \(L10n.RecordingSettings.pressAnotherKey)"
        }

        return parts.joined()
    }

    static func modifierOnlyKey(fromKeyCode keyCode: UInt16) -> PressAndHoldKey? {
        PressAndHoldKey.allCases.first { $0.keyCode == keyCode }
    }
    
    static func formatHotkey(modifiers: NSEvent.ModifierFlags, key: Key) -> String {
        var parts: [String] = []
        
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("⌃") }
        
        parts.append(keyToString(key))
        
        return parts.joined()
    }

    static func isComplete(modifiers: NSEvent.ModifierFlags, key: Key?) -> Bool {
        guard let key else { return false }
        return !modifiers.isEmpty || isFunctionKey(key)
    }
    
    static func isValidHotkey(modifiers: NSEvent.ModifierFlags, key: Key) -> Bool {
        // Allow function keys with no modifiers
        if modifiers.isEmpty {
            return isFunctionKey(key)
        }
        
        // Some keys should not be used as hotkeys (like escape, which is used to cancel)
        let forbiddenKeys: [Key] = [.escape, .delete, .return, .tab]
        if forbiddenKeys.contains(key) {
            return false
        }
        
        // Single modifier keys (like just shift) should require Command or Control
        if modifiers == .shift || modifiers == .option {
            return false
        }
        
        return true
    }

    static func isFunctionKey(_ key: Key) -> Bool {
        switch key {
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
             .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            return true
        default:
            return false
        }
    }
    
    static func keyFromKeyCode(_ keyCode: UInt16) -> Key? {
        switch keyCode {
        case 0: return .a
        case 1: return .s
        case 2: return .d
        case 3: return .f
        case 4: return .h
        case 5: return .g
        case 6: return .z
        case 7: return .x
        case 8: return .c
        case 9: return .v
        case 11: return .b
        case 12: return .q
        case 13: return .w
        case 14: return .e
        case 15: return .r
        case 16: return .y
        case 17: return .t
        case 18: return .one
        case 19: return .two
        case 20: return .three
        case 21: return .four
        case 22: return .six
        case 23: return .five
        case 24: return .equal
        case 25: return .nine
        case 26: return .seven
        case 27: return .minus
        case 28: return .eight
        case 29: return .zero
        case 30: return .rightBracket
        case 31: return .o
        case 32: return .u
        case 33: return .leftBracket
        case 34: return .i
        case 35: return .p
        case 36: return .return
        case 37: return .l
        case 38: return .j
        case 39: return .quote
        case 40: return .k
        case 41: return .semicolon
        case 42: return .backslash
        case 43: return .comma
        case 44: return .slash
        case 45: return .n
        case 46: return .m
        case 47: return .period
        case 48: return .tab
        case 49: return .space
        case 50: return .grave
        case 51: return .delete
        case 53: return .escape
        case 122: return .f1
        case 120: return .f2
        case 99: return .f3
        case 118: return .f4
        case 96: return .f5
        case 97: return .f6
        case 98: return .f7
        case 100: return .f8
        case 101: return .f9
        case 109: return .f10
        case 103: return .f11
        case 111: return .f12
        case 105: return .f13
        case 107: return .f14
        case 113: return .f15
        case 106: return .f16
        case 64: return .f17
        case 79: return .f18
        case 80: return .f19
        case 90: return .f20
        case 126: return .upArrow
        case 125: return .downArrow
        case 123: return .leftArrow
        case 124: return .rightArrow
        default: return nil
        }
    }
    
    static func keyToString(_ key: Key) -> String {
        switch key {
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .f13: return "F13"
        case .f14: return "F14"
        case .f15: return "F15"
        case .f16: return "F16"
        case .f17: return "F17"
        case .f18: return "F18"
        case .f19: return "F19"
        case .f20: return "F20"
        case .a: return "A"
        case .s: return "S"
        case .d: return "D"
        case .f: return "F"
        case .h: return "H"
        case .g: return "G"
        case .z: return "Z"
        case .x: return "X"
        case .c: return "C"
        case .v: return "V"
        case .b: return "B"
        case .q: return "Q"
        case .w: return "W"
        case .e: return "E"
        case .r: return "R"
        case .y: return "Y"
        case .t: return "T"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .six: return "6"
        case .five: return "5"
        case .equal: return "="
        case .nine: return "9"
        case .seven: return "7"
        case .minus: return "-"
        case .eight: return "8"
        case .zero: return "0"
        case .rightBracket: return "]"
        case .o: return "O"
        case .u: return "U"
        case .leftBracket: return "["
        case .i: return "I"
        case .p: return "P"
        case .return: return "⏎"
        case .l: return "L"
        case .j: return "J"
        case .quote: return "'"
        case .k: return "K"
        case .semicolon: return ";"
        case .backslash: return "\\"
        case .comma: return ","
        case .slash: return "/"
        case .n: return "N"
        case .m: return "M"
        case .period: return "."
        case .tab: return "⇥"
        case .space: return "Space"
        case .grave: return "`"
        case .delete: return "⌫"
        case .escape: return "⎋"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        default: return ""
        }
    }
}
