import Foundation
import AppKit
import ApplicationServices

internal enum AccessibilityPermissionRequestDecision: Equatable {
    case alreadyGranted
    case startRequest
    case waitingForActiveRequest
    case skippedRecentlyPrompted
}

internal final class AccessibilityPermissionRequestCoordinator {
    static let shared = AccessibilityPermissionRequestCoordinator()

    private let lock = NSLock()
    private var isRequestInProgress = false
    private var hasPromptedWhileDenied = false
    private var completions: [(Bool) -> Void] = []

    func register(permissionGranted: Bool, completion: @escaping (Bool) -> Void) -> AccessibilityPermissionRequestDecision {
        lock.lock()

        if permissionGranted {
            isRequestInProgress = false
            hasPromptedWhileDenied = false
            lock.unlock()
            completion(true)
            return .alreadyGranted
        }

        if isRequestInProgress {
            completions.append(completion)
            lock.unlock()
            return .waitingForActiveRequest
        }

        if hasPromptedWhileDenied {
            lock.unlock()
            completion(false)
            return .skippedRecentlyPrompted
        }

        isRequestInProgress = true
        hasPromptedWhileDenied = true
        completions.append(completion)
        lock.unlock()
        return .startRequest
    }

    func complete(_ granted: Bool) {
        lock.lock()
        isRequestInProgress = false
        if granted {
            hasPromptedWhileDenied = false
        }
        let callbacks = completions
        completions.removeAll()
        lock.unlock()

        callbacks.forEach { $0(granted) }
    }

    func resetForTesting() {
        lock.lock()
        isRequestInProgress = false
        hasPromptedWhileDenied = false
        completions.removeAll()
        lock.unlock()
    }
}

/// Dedicated manager for handling Accessibility permissions with proper explanations and error handling
internal class AccessibilityPermissionManager {
    private let isTestEnvironment: Bool
    private let permissionCheck: () -> Bool
    private let requestCoordinator: AccessibilityPermissionRequestCoordinator
    
    init(
        permissionCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
        requestCoordinator: AccessibilityPermissionRequestCoordinator = .shared
    ) {
        isTestEnvironment = NSClassFromString("XCTestCase") != nil
        self.permissionCheck = permissionCheck
        self.requestCoordinator = requestCoordinator
    }
    
    /// Checks if the app has Accessibility permission without prompting the user
    /// - Returns: true if permission is granted, false otherwise
    func checkPermission() -> Bool {
        // Check without prompting user - never bypass this check
        return permissionCheck()
    }
    
    /// Requests Accessibility permission with a proper explanation dialog
    /// - Parameter completion: Called with the result of the permission request
    func requestPermissionWithExplanation(completion: @escaping (Bool) -> Void) {
        let decision = requestCoordinator.register(
            permissionGranted: checkPermission(),
            completion: completion
        )

        switch decision {
        case .alreadyGranted, .waitingForActiveRequest, .skippedRecentlyPrompted:
            return
        case .startRequest:
            break
        }
        
        if isTestEnvironment {
            requestCoordinator.complete(false)
            return
        }

        let coordinator = requestCoordinator

        // Show explanation alert before requesting permission (runtime only)
        showPermissionExplanationAlert { [weak self, coordinator] userWantsToGrant in
            guard let self else {
                coordinator.complete(false)
                return
            }

            guard userWantsToGrant else {
                self.showPermissionDeniedMessage()
                coordinator.complete(false)
                return
            }
            
            // Request permission with system prompt
            self.requestPermissionFromSystem { granted in
                coordinator.complete(granted)
            }
        }
    }
    
    /// Shows a detailed explanation of why Accessibility permission is needed
    private func showPermissionExplanationAlert(completion: @escaping (Bool) -> Void) {
        if isTestEnvironment { completion(false); return }
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = L10n.SmartPastePermission.requestTitle
            alert.informativeText = L10n.SmartPastePermission.requestMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.SmartPastePermission.grantPermission)
            alert.addButton(withTitle: L10n.SmartPastePermission.continueWithout)
            alert.addButton(withTitle: L10n.SmartPastePermission.learnMore)
            
            let response = alert.runModal()
            
            switch response {
            case .alertFirstButtonReturn:
                completion(true)
            case .alertSecondButtonReturn:
                completion(false)
            case .alertThirdButtonReturn:
                self.showAccessibilityPermissionEducation()
                // After education, ask again
                self.showPermissionExplanationAlert(completion: completion)
            default:
                completion(false)
            }
        }
    }
    
    /// Requests permission from the system and monitors the result
    private func requestPermissionFromSystem(completion: @escaping (Bool) -> Void) {
        if isTestEnvironment { completion(false); return }
        // Request permission with system prompt
        let checkOptionPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptionPrompt: true] as CFDictionary
        
        // This call will show the system permission dialog
        let _ = AXIsProcessTrustedWithOptions(options)
        
        // Monitor permission status with periodic checks
        monitorPermissionStatus(completion: completion)
    }
    
    /// Monitors permission status after a system request
    private func monitorPermissionStatus(completion: @escaping (Bool) -> Void) {
        if isTestEnvironment { completion(false); return }
        var checkCount = 0
        let maxChecks = 60 // Check for up to 30 seconds (60 * 0.5s) - users might need time to navigate
        
        func checkStatus() {
            checkCount += 1
            
            if checkPermission() {
                // Permission granted
                Task { @MainActor in
                    self.showPermissionGrantedConfirmation()
                    completion(true)
                }
                return
            }
            
            if checkCount >= maxChecks {
                // Timeout - show helpful message and assume permission was denied
                Task { @MainActor in
                    self.showPermissionTimeoutMessage()
                    completion(false)
                }
                return
            }
            
            // Check again after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                checkStatus()
            }
        }
        
        // Start checking after initial delay to let system dialog appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            checkStatus()
        }
    }
    
    /// Shows confirmation when permission is successfully granted
    private func showPermissionGrantedConfirmation() {
        if isTestEnvironment { return }
        let alert = NSAlert()
        alert.messageText = L10n.SmartPastePermission.enabledTitle
        alert.informativeText = L10n.SmartPastePermission.enabledMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.SmartPastePermission.great)
        alert.runModal()
    }
    
    /// Shows helpful message when permission request times out
    private func showPermissionTimeoutMessage() {
        if isTestEnvironment { return }
        let alert = NSAlert()
        alert.messageText = L10n.SmartPastePermission.incompleteTitle
        alert.informativeText = L10n.SmartPastePermission.incompleteMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.Common.done)
        alert.addButton(withTitle: L10n.SmartPastePermission.showManualInstructions)
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            showManualPermissionInstructions()
        }
    }
    
    /// Shows detailed education about Accessibility permissions in macOS
    private func showAccessibilityPermissionEducation() {
        if isTestEnvironment { return }
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = L10n.SmartPastePermission.educationTitle
            alert.informativeText = L10n.SmartPastePermission.educationMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.SmartPastePermission.iUnderstand)
            alert.runModal()
        }
    }
    
    /// Shows an alert with instructions for manually enabling permission
    func showManualPermissionInstructions() {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = L10n.SmartPastePermission.manualTitle
            alert.informativeText = L10n.SmartPastePermission.manualMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.SmartPastePermission.openSystemSettings)
            alert.addButton(withTitle: L10n.Common.cancel)
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openAccessibilitySystemSettings()
            }
        }
    }
    
    /// Opens System Settings to the Accessibility section
    private func openAccessibilitySystemSettings() {
        if isTestEnvironment { return }
        // Try modern URL scheme first (macOS 13+)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            if NSWorkspace.shared.open(url) {
                return
            }
        }
        
        // Fallback to general Privacy & Security settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Returns a user-friendly status message for the current permission state
    var permissionStatusMessage: String {
        if checkPermission() {
            return L10n.SmartPastePermission.statusGranted
        } else {
            return L10n.SmartPastePermission.statusRequired
        }
    }
    
    /// Returns detailed status information for debugging and user support
    var detailedPermissionStatus: (isGranted: Bool, statusMessage: String, troubleshootingInfo: String?) {
        let isGranted = checkPermission()
        
        if isGranted {
            return (
                isGranted: true,
                statusMessage: L10n.SmartPastePermission.detailedConfigured,
                troubleshootingInfo: nil
            )
        } else {
            return (
                isGranted: false,
                statusMessage: L10n.SmartPastePermission.detailedNotGranted,
                troubleshootingInfo: L10n.SmartPastePermission.troubleshootingInfo
            )
        }
    }
    
    /// Handles errors that occur during permission requests
    func handlePermissionError(_ error: Error) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = L10n.SmartPastePermission.errorTitle
            alert.informativeText = L10n.SmartPastePermission.errorMessage(error.localizedDescription)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.SmartPastePermission.openSystemSettings)
            alert.addButton(withTitle: L10n.SmartPastePermission.continueWithout)
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openAccessibilitySystemSettings()
            }
        }
    }
    
    /// Shows a denial message when user explicitly declines permission
    func showPermissionDeniedMessage() {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = L10n.SmartPastePermission.disabledTitle
            alert.informativeText = L10n.SmartPastePermission.disabledMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.Common.done)
            alert.runModal()
        }
    }
}
