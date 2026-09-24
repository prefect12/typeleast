import Foundation
import AppKit

internal enum PressAndHoldMode: String, CaseIterable, Identifiable {
    case hold
    case toggle
    case doubleTapToggle

    static let allCases: [PressAndHoldMode] = [.doubleTapToggle, .hold]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold:
            return L10n.RecordingSettings.holdMode
        case .toggle, .doubleTapToggle:
            return L10n.RecordingSettings.toggleMode
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
            return L10n.RecordingSettings.rightCommand
        case .leftCommand:
            return L10n.RecordingSettings.leftCommand
        case .rightOption:
            return L10n.RecordingSettings.rightOption
        case .leftOption:
            return L10n.RecordingSettings.leftOption
        case .rightControl:
            return L10n.RecordingSettings.rightControl
        case .leftControl:
            return L10n.RecordingSettings.leftControl
        case .globe:
            return L10n.RecordingSettings.globe
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

        let key = PressAndHoldKey(rawValue: keyIdentifier) ?? migratedKey(from: keyIdentifier) ?? PressAndHoldConfiguration.defaults.key
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

    private static func migratedKey(from rawValue: String) -> PressAndHoldKey? {
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
    typealias DelayedWorkScheduler = (TimeInterval, @escaping () -> Void) -> Void

    private let configuration: PressAndHoldConfiguration
    private let keyDownHandler: () -> Void
    private let keyUpHandler: (() -> Void)?
    private let holdStartHandler: (() -> Void)?
    private let holdEndHandler: (() -> Void)?
    private let holdCancelHandler: (() -> Void)?
    private let addGlobalMonitor: EventMonitorFactory
    private let addLocalMonitor: LocalEventMonitorFactory
    private let removeMonitor: EventMonitorRemoval
    private let now: () -> Date
    private let doubleTapInterval: TimeInterval
    private let holdDelay: TimeInterval
    private let shortcutCancelWindow: TimeInterval
    private let scheduleAfter: DelayedWorkScheduler?

    private var flagsMonitors: [Any] = []
    private var keyDownMonitors: [Any] = []
    private var keyUpMonitors: [Any] = []
    private var interruptionMonitors: [Any] = []
    private let monitorQueue = DispatchQueue(label: "com.typeleast.pressAndHoldMonitor")

    private var isPressed = false
    private var lastTapTime: Date?
    private var pressGeneration = 0
    private var isHolding = false
    private var holdStartedAt: Date?

    init(
        configuration: PressAndHoldConfiguration,
        keyDownHandler: @escaping () -> Void,
        keyUpHandler: (() -> Void)? = nil,
        holdStartHandler: (() -> Void)? = nil,
        holdEndHandler: (() -> Void)? = nil,
        holdCancelHandler: (() -> Void)? = nil,
        addGlobalMonitor: @escaping EventMonitorFactory = NSEvent.addGlobalMonitorForEvents(matching:handler:),
        addLocalMonitor: @escaping LocalEventMonitorFactory = NSEvent.addLocalMonitorForEvents(matching:handler:),
        removeMonitor: @escaping EventMonitorRemoval = NSEvent.removeMonitor(_:),
        now: @escaping () -> Date = Date.init,
        doubleTapInterval: TimeInterval = 0.35,
        holdDelay: TimeInterval = 0.2,
        shortcutCancelWindow: TimeInterval = 1.0,
        scheduleAfter: DelayedWorkScheduler? = nil
    ) {
        self.configuration = configuration
        self.keyDownHandler = keyDownHandler
        self.keyUpHandler = keyUpHandler
        self.holdStartHandler = holdStartHandler
        self.holdEndHandler = holdEndHandler
        self.holdCancelHandler = holdCancelHandler
        self.addGlobalMonitor = addGlobalMonitor
        self.addLocalMonitor = addLocalMonitor
        self.removeMonitor = removeMonitor
        self.now = now
        self.doubleTapInterval = doubleTapInterval
        self.holdDelay = holdDelay
        self.shortcutCancelWindow = shortcutCancelWindow
        self.scheduleAfter = scheduleAfter
    }

    func start() {
        stop()

        let modifierFlag = configuration.key.modifierFlag
        if modifierFlag == .command || modifierFlag == .option || modifierFlag == .control || modifierFlag == .function {
            flagsMonitors = addEventMonitors(matching: .flagsChanged) { [weak self] event in
                self?.handleModifierEvent(event)
            }
            if configuration.mode == .doubleTapToggle {
                // Any other key pressed with the modifier means a shortcut like ⌘C, not dictation.
                interruptionMonitors = addEventMonitors(matching: .keyDown) { [weak self] _ in
                    self?.scheduleInterruption()
                }
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

        for monitor in interruptionMonitors {
            removeMonitor(monitor)
        }
        interruptionMonitors.removeAll()

        isPressed = false
        lastTapTime = nil
        isHolding = false
        holdStartedAt = nil
        pressGeneration += 1
    }

    deinit {
        stop()
    }

    private func handleModifierEvent(_ event: NSEvent) {
        guard event.type == .flagsChanged else { return }
        guard event.keyCode == configuration.key.keyCode else {
            if configuration.mode == .doubleTapToggle { scheduleInterruption() }
            return
        }

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
            if configuration.mode == .doubleTapToggle {
                handleDoubleTapKeyDown()
                return
            }
            Task { @MainActor [keyDownHandler] in
                keyDownHandler()
            }
        } else {
            guard isPressed else { return }
            isPressed = false
            if isHolding {
                isHolding = false
                if let holdEndHandler {
                    Task { @MainActor in holdEndHandler() }
                }
                return
            }
            guard let keyUpHandler else { return }
            Task { @MainActor in
                keyUpHandler()
            }
        }
    }

    /// A quick second tap toggles recording; holding the first press past `holdDelay`
    /// records push-to-talk style until release.
    private func handleDoubleTapKeyDown() {
        let currentTime = now()
        pressGeneration += 1

        guard let previousTapTime = lastTapTime,
              currentTime.timeIntervalSince(previousTapTime) <= doubleTapInterval else {
            lastTapTime = currentTime
            scheduleHoldStart(for: pressGeneration)
            return
        }

        lastTapTime = nil
        Task { @MainActor [keyDownHandler] in
            keyDownHandler()
        }
    }

    private func scheduleInterruption() {
        monitorQueue.async { [weak self] in
            self?.processInterruption()
        }
    }

    /// Cancels a pending hold and forgets the tap once the modifier is used as part of a shortcut.
    /// A hold that started just before the shortcut key (e.g. a slow ⌘C) is cancelled too.
    func processInterruption() {
        guard isPressed else { return }
        if isHolding {
            guard let holdCancelHandler,
                  let holdStartedAt,
                  now().timeIntervalSince(holdStartedAt) <= shortcutCancelWindow else { return }
            isHolding = false
            self.holdStartedAt = nil
            Task { @MainActor in holdCancelHandler() }
            return
        }
        pressGeneration += 1
        lastTapTime = nil
    }

    private func scheduleHoldStart(for generation: Int) {
        guard let holdStartHandler else { return }
        let work: () -> Void = { [weak self] in
            guard let self, self.isPressed, self.pressGeneration == generation else { return }
            self.isHolding = true
            self.holdStartedAt = self.now()
            self.lastTapTime = nil
            Task { @MainActor in holdStartHandler() }
        }
        if let scheduleAfter {
            scheduleAfter(holdDelay, work)
        } else {
            monitorQueue.asyncAfter(deadline: .now() + holdDelay, execute: work)
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
