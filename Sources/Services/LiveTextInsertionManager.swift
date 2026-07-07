import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
internal final class LiveTextInsertionManager {
    private let accessibilityManager: AccessibilityPermissionManager
    private let pasteboard: NSPasteboard
    private var insertedText = ""
    private var queuedText: String?
    private weak var queuedTargetApp: NSRunningApplication?
    private var updateTask: Task<Void, Never>?
    private var isActive = false

    init(
        accessibilityManager: AccessibilityPermissionManager = AccessibilityPermissionManager(),
        pasteboard: NSPasteboard = .general
    ) {
        self.accessibilityManager = accessibilityManager
        self.pasteboard = pasteboard
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

        await apply(text: finalText, targetApp: targetApp)
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
            await apply(text: text, targetApp: targetApp)
        }

        updateTask = nil
    }

    private func apply(text: String, targetApp: NSRunningApplication?) async {
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
        try? await Task.sleep(for: .milliseconds(30))

        do {
            let edit = Self.edit(from: insertedText, to: text)
            try deleteBackward(characterCount: edit.deleteCount)
            try paste(edit.insertText)
            insertedText = text
        } catch {
            return
        }
    }

    private func deleteBackward(characterCount: Int) throws {
        guard characterCount > 0 else { return }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceCreationFailed
        }

        for _ in 0..<characterCount {
            try postKey(CGKeyCode(kVK_Delete), source: source)
        }
    }

    private func paste(_ text: String) throws {
        guard !text.isEmpty else { return }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceCreationFailed
        }

        let commandV = CGKeyCode(kVK_ANSI_V)
        let flags = CGEventFlags([.maskCommand])
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: commandV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: commandV, keyDown: false) else {
            throw PasteError.keyboardEventCreationFailed
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private func postKey(_ keyCode: CGKeyCode, source: CGEventSource) throws {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw PasteError.keyboardEventCreationFailed
        }

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
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

    private static func edit(from oldText: String, to newText: String) -> (deleteCount: Int, insertText: String) {
        let oldCharacters = Array(oldText)
        let newCharacters = Array(newText)
        var prefixCount = 0

        while prefixCount < oldCharacters.count,
              prefixCount < newCharacters.count,
              oldCharacters[prefixCount] == newCharacters[prefixCount] {
            prefixCount += 1
        }

        let deleteCount = oldCharacters.count - prefixCount
        let insertText = String(newCharacters.dropFirst(prefixCount))
        return (deleteCount, insertText)
    }
}
