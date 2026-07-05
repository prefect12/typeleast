import Foundation
import AppKit

internal enum PressAndHoldMode: String, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold:
            return "Press and Hold"
        case .toggle:
            return "Press to Toggle"
        }
    }
}

internal enum PressAndHoldKey: String, CaseIterable, Identifiable {
    case rightCommand
    case leftCommand
    case rightOption
    case leftOption
    case rightControl
    case leftControl
    case globe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightCommand:
            return "Right Command (⌘)"
        case .leftCommand:
            return "Left Command (⌘)"
        case .rightOption:
            return "Right Option (⌥)"
        case .leftOption:
            return "Left Option (⌥)"
        case .rightControl:
            return "Right Control (⌃)"
        case .leftControl:
            return "Left Control (⌃)"
        case .globe:
            return "Globe / Fn (🌐)"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightCommand:
            return 54
        case .leftCommand:
            return 55
        case .rightOption:
            return 61
        case .leftOption:
            return 58
        case .rightControl:
            return 62
        case .leftControl:
            return 59
        case .globe:
            return 63
        }
    }

    /// Modifier flag that macOS sets when the key is active.
    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand, .leftCommand:
            return .command
        case .rightOption, .leftOption:
            return .option
        case .rightControl, .leftControl:
            return .control
        case .globe:
            return .function
        }
    }

    var deviceModifierMask: UInt {
        switch self {
        case .rightCommand:
            return DeviceModifierMask.rightCommand
        case .leftCommand:
            return DeviceModifierMask.leftCommand
        case .rightOption:
            return DeviceModifierMask.rightOption
        case .leftOption:
            return DeviceModifierMask.leftOption
        case .rightControl:
            return DeviceModifierMask.rightControl
        case .leftControl:
            return DeviceModifierMask.leftControl
        case .globe:
            return NSEvent.ModifierFlags.function.rawValue
        }
    }
}

private enum DeviceModifierMask {
    // Side-specific modifier bits from IOKit/hidsystem/IOLLEvent.h.
    static let leftControl: UInt = 0x00000001
    static let leftCommand: UInt = 0x00000008
    static let rightCommand: UInt = 0x00000010
    static let leftOption: UInt = 0x00000020
    static let rightOption: UInt = 0x00000040
    static let rightControl: UInt = 0x00002000
}

internal struct PressAndHoldConfiguration: Equatable {
    var enabled: Bool
    var key: PressAndHoldKey
    var mode: PressAndHoldMode

    static let defaults = PressAndHoldConfiguration(
        enabled: false,
        key: .rightCommand,
        mode: .hold
    )
}

internal enum PressAndHoldSettings {
    private static let enabledKey = "pressAndHoldEnabled"
    private static let keyIdentifierKey = "pressAndHoldKeyIdentifier"
    private static let modeKey = "pressAndHoldMode"

    static func configuration(using defaults: UserDefaults = .standard) -> PressAndHoldConfiguration {
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? PressAndHoldConfiguration.defaults.enabled
        let keyIdentifier = defaults.string(forKey: keyIdentifierKey) ?? PressAndHoldConfiguration.defaults.key.rawValue
        let modeIdentifier = defaults.string(forKey: modeKey) ?? PressAndHoldConfiguration.defaults.mode.rawValue

        let key = PressAndHoldKey(rawValue: keyIdentifier) ?? legacyKey(from: keyIdentifier) ?? PressAndHoldConfiguration.defaults.key
        let mode = PressAndHoldMode(rawValue: modeIdentifier) ?? PressAndHoldConfiguration.defaults.mode

        return PressAndHoldConfiguration(enabled: enabled, key: key, mode: mode)
    }

    static func update(_ configuration: PressAndHoldConfiguration, using defaults: UserDefaults = .standard) {
        defaults.set(configuration.enabled, forKey: enabledKey)
        defaults.set(configuration.key.rawValue, forKey: keyIdentifierKey)
        defaults.set(configuration.mode.rawValue, forKey: modeKey)
        defaults.synchronize()

        NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: configuration)
    }

    private static func legacyKey(from rawValue: String) -> PressAndHoldKey? {
        switch rawValue {
        case "option":
            return .leftOption
        case "control":
            return .leftControl
        case "fn", "globe":
            return .globe
        default:
            return nil
        }
    }
}

/// Observes global keyboard events so that modifier-only keys (e.g. right command)
/// can trigger recording. Uses NSEvent global monitors, which continue to fire even
/// when the app is not focused.
internal final class PressAndHoldKeyMonitor {
    typealias EventMonitorFactory = (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    typealias LocalEventMonitorFactory = (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?
    typealias EventMonitorRemoval = (Any) -> Void

    private let configuration: PressAndHoldConfiguration
    private let keyDownHandler: () -> Void
    private let keyUpHandler: (() -> Void)?
    private let addGlobalMonitor: EventMonitorFactory
    private let addLocalMonitor: LocalEventMonitorFactory
    private let removeMonitor: EventMonitorRemoval

    private var flagsMonitors: [Any] = []
    private var keyDownMonitors: [Any] = []
    private var keyUpMonitors: [Any] = []
    private let monitorQueue = DispatchQueue(label: "com.audiowhisper.pressAndHoldMonitor")

    private var isPressed = false

    init(
        configuration: PressAndHoldConfiguration,
        keyDownHandler: @escaping () -> Void,
        keyUpHandler: (() -> Void)? = nil,
        addGlobalMonitor: @escaping EventMonitorFactory = NSEvent.addGlobalMonitorForEvents(matching:handler:),
        addLocalMonitor: @escaping LocalEventMonitorFactory = NSEvent.addLocalMonitorForEvents(matching:handler:),
        removeMonitor: @escaping EventMonitorRemoval = NSEvent.removeMonitor(_:)
    ) {
        self.configuration = configuration
        self.keyDownHandler = keyDownHandler
        self.keyUpHandler = keyUpHandler
        self.addGlobalMonitor = addGlobalMonitor
        self.addLocalMonitor = addLocalMonitor
        self.removeMonitor = removeMonitor
    }

    func start() {
        stop()

        let modifierFlag = configuration.key.modifierFlag
        if modifierFlag == .command || modifierFlag == .option || modifierFlag == .control || modifierFlag == .function {
            flagsMonitors = addEventMonitors(matching: .flagsChanged) { [weak self] event in
                self?.handleModifierEvent(event)
            }
        } else {
            keyDownMonitors = addEventMonitors(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event, isKeyDown: true)
            }
            keyUpMonitors = addEventMonitors(matching: .keyUp) { [weak self] event in
                self?.handleKeyEvent(event, isKeyDown: false)
            }
        }
    }

    func stop() {
        for monitor in flagsMonitors {
            removeMonitor(monitor)
        }
        flagsMonitors.removeAll()

        for monitor in keyDownMonitors {
            removeMonitor(monitor)
        }
        keyDownMonitors.removeAll()

        for monitor in keyUpMonitors {
            removeMonitor(monitor)
        }
        keyUpMonitors.removeAll()

        isPressed = false
    }

    deinit {
        stop()
    }

    private func handleModifierEvent(_ event: NSEvent) {
        guard event.type == .flagsChanged, event.keyCode == configuration.key.keyCode else { return }

        let isKeyDownEvent = (event.modifierFlags.rawValue & configuration.key.deviceModifierMask) != 0
        monitorQueue.async { [weak self] in
            self?.processTransition(isKeyDownEvent: isKeyDownEvent)
        }
    }

    private func handleKeyEvent(_ event: NSEvent, isKeyDown: Bool) {
        guard event.keyCode == configuration.key.keyCode else { return }

        if isKeyDown, event.isARepeat {
            return
        }

        monitorQueue.async { [weak self] in
            self?.processTransition(isKeyDownEvent: isKeyDown)
        }
    }

    func processTransition(isKeyDownEvent: Bool) {
        if isKeyDownEvent {
            guard !isPressed else { return }
            isPressed = true
            Task { @MainActor [keyDownHandler] in
                keyDownHandler()
            }
        } else {
            guard isPressed else { return }
            isPressed = false
            guard let keyUpHandler else { return }
            Task { @MainActor in
                keyUpHandler()
            }
        }
    }

    private func addEventMonitors(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> [Any] {
        var monitors: [Any] = []
        if let globalMonitor = addGlobalMonitor(mask, handler) {
            monitors.append(globalMonitor)
        }
        if let localMonitor = addLocalMonitor(mask, { event in
            handler(event)
            return event
        }) {
            monitors.append(localMonitor)
        }
        return monitors
    }
}
