import SwiftUI
import AVFoundation
import ApplicationServices
import AppKit

internal struct DashboardPermissionsView: View {
    @State private var microphoneStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    @AppStorage("enableSmartPaste") private var enableSmartPaste = true

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.Permissions.status) {
                    permissionLabel(
                        isGranted: microphoneStatus == .authorized,
                        grantedText: L10n.Permissions.granted,
                        requiredText: microphoneStatus == .denied ? L10n.Permissions.denied : L10n.Permissions.required
                    )
                }

                HStack(spacing: 10) {
                    Button(L10n.Permissions.requestAccess) {
                        requestMicrophonePermission()
                    }
                    .disabled(microphoneStatus == .authorized)

                    Button(L10n.Permissions.openSettings) {
                        openSystemSettings(path: "Privacy_Microphone")
                    }
                }
            } header: {
                Text(L10n.Permissions.microphone)
            } footer: {
                Text(L10n.Permissions.micDesc)
            }

            if enableSmartPaste {
                Section {
                    LabeledContent(L10n.Permissions.status) {
                        permissionLabel(
                            isGranted: isAccessibilityTrusted,
                            grantedText: L10n.Permissions.granted,
                            requiredText: L10n.Permissions.required
                        )
                    }

                    HStack(spacing: 10) {
                        Button(L10n.Permissions.openSettings) {
                            openSystemSettings(path: "Privacy_Accessibility")
                        }

                        Button(L10n.Permissions.refresh) {
                            refreshStatuses()
                        }
                    }
                } header: {
                    Text(L10n.Permissions.accessibility)
                } footer: {
                    Text(L10n.Permissions.a11yDesc)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshStatuses)
        .onChange(of: enableSmartPaste) { _, _ in
            refreshStatuses()
        }
    }

    private func permissionLabel(isGranted: Bool, grantedText: String, requiredText: String) -> some View {
        Label(isGranted ? grantedText : requiredText, systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(isGranted ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
    }

    private func refreshStatuses() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    private func requestMicrophonePermission() {
        guard !AppEnvironment.isRunningTests else { return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                microphoneStatus = granted ? .authorized : .denied
            }
        }
    }

    private func openSystemSettings(path: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    DashboardPermissionsView()
        .frame(width: 900, height: 700)
}
