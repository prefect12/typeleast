import AppKit
import ApplicationServices
import Carbon
import Foundation

internal struct LiveTextEditPlan: Equatable {
    let deleteCount: Int
    let insertText: String
}

private enum LiveTextApplyMode {
    case liveUpdate
    case finalReplacement
}

@MainActor
internal final class LiveTextInsertionManager {
    private let accessibilityManager: AccessibilityPermissionManager
    private var insertedText = ""
    private var queuedText: String?
    private var queuedTargetApp: NSRunningApplication?
    private var updateTask: Task<Void, Never>?
    private var isActive = false

    init(
        accessibilityManager: AccessibilityPermissionManager = AccessibilityPermissionManager()
    ) {
        self.accessibilityManager = accessibilityManager
    }

    var hasInsertedText: Bool {
        !insertedText.isEmpty
    }

    func begin() {
        resetState(cancelTask: true)
        isActive = true
    }

    func cancel() {
        resetState(cancelTask: true)
    }

    func scheduleUpdate(text: String, targetApp: NSRunningApplication?) {
        guard isActive else { return }

        queuedText = text
        queuedTargetApp = targetApp

        guard updateTask == nil else { return }
        updateTask = Task { @MainActor [weak self] in
            await self?.drainQueuedUpdates()
        }
    }

    func finish(finalText: String, targetApp: NSRunningApplication?) async {
        guard isActive || hasInsertedText else { return }

        updateTask?.cancel()
        updateTask = nil
        queuedText = nil
        queuedTargetApp = nil

        await apply(text: finalText, targetApp: targetApp, mode: .finalReplacement)
        isActive = false
    }

    private func drainQueuedUpdates() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(90))
            guard let text = queuedText else {
                updateTask = nil
                return
            }

            let targetApp = queuedTargetApp
            queuedText = nil
            queuedTargetApp = nil
            await apply(text: text, targetApp: targetApp, mode: .liveUpdate)
        }

        updateTask = nil
    }

    private func apply(
        text: String,
        targetApp: NSRunningApplication?,
        mode: LiveTextApplyMode
    ) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != insertedText else { return }

        if AppEnvironment.isRunningTests {
            insertedText = text
            return
        }

        guard accessibilityManager.checkPermission(),
              let targetApp,
              !targetApp.isTerminated else {
            return
        }

        targetApp.activate(options: [])
        try? await Task.sleep(for: activationDelay(for: mode))

        guard let editPlan = Self.editPlan(from: insertedText, to: text) else { return }

        do {
            try await apply(editPlan: editPlan, mode: mode)
            insertedText = text
        } catch {
            return
        }
    }

    private func activationDelay(for mode: LiveTextApplyMode) -> Duration {
        switch mode {
        case .liveUpdate:
            return insertedText.isEmpty ? .milliseconds(100) : .milliseconds(30)
        case .finalReplacement:
            return .milliseconds(150)
        }
    }

    private func apply(editPlan: LiveTextEditPlan, mode: LiveTextApplyMode) async throws {
        if editPlan.deleteCount > 0 {
            try await deleteBackward(count: editPlan.deleteCount)
            try? await Task.sleep(for: .milliseconds(30))
        }

        switch mode {
        case .liveUpdate:
            try typeText(editPlan.insertText)
        case .finalReplacement:
            try await pasteText(editPlan.insertText)
        }
    }

    private func typeText(_ text: String) throws {
        guard !text.isEmpty else { return }

        let utf16Units = Array(text.utf16)
        var offset = 0
        while offset < utf16Units.count {
            let end = min(offset + Self.maxUnicodeEventLength, utf16Units.count)
            try typeUTF16(Array(utf16Units[offset..<end]))
            offset = end
        }
    }

    private func typeUTF16(_ utf16Units: [UInt16]) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceCreationFailed
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw PasteError.keyboardEventCreationFailed
        }

        utf16Units.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: baseAddress
            )
        }
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private func deleteBackward(count: Int) async throws {
        guard count > 0 else { return }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceCreationFailed
        }

        let deleteKey = CGKeyCode(kVK_Delete)
        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: false) else {
                throw PasteError.keyboardEventCreationFailed
            }

            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    private func pasteText(_ text: String) async throws {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try? await Task.sleep(for: .milliseconds(30))

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            throw PasteError.keyboardEventCreationFailed
        }

        let commandFlag = CGEventFlags([.maskCommand])
        keyDown.flags = commandFlag
        keyUp.flags = commandFlag
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        try? await Task.sleep(for: .milliseconds(80))
    }

    private func resetState(cancelTask: Bool) {
        if cancelTask {
            updateTask?.cancel()
            updateTask = nil
        }
        queuedText = nil
        queuedTargetApp = nil
        insertedText = ""
        isActive = false
    }

    nonisolated static func editPlan(from oldText: String, to newText: String) -> LiveTextEditPlan? {
        let oldCharacters = Array(oldText)
        let newCharacters = Array(newText)
        var sharedPrefixCount = 0

        while sharedPrefixCount < oldCharacters.count,
              sharedPrefixCount < newCharacters.count,
              oldCharacters[sharedPrefixCount] == newCharacters[sharedPrefixCount] {
            sharedPrefixCount += 1
        }

        let deleteCount = oldCharacters.count - sharedPrefixCount
        let insertText = String(newCharacters.dropFirst(sharedPrefixCount))
        guard deleteCount > 0 || !insertText.isEmpty else { return nil }

        return LiveTextEditPlan(deleteCount: deleteCount, insertText: insertText)
    }

    private nonisolated static let maxUnicodeEventLength = 64
}
