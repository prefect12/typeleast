import SwiftUI
import AVFoundation
import HotKey
import AppKit

internal struct DashboardRecordingView: View {
    @AppStorage("selectedMicrophone") private var selectedMicrophone = ""
    @AppStorage("globalHotkey") private var globalHotkey = "⌘⇧Space"
    @AppStorage("pressAndHoldEnabled") private var pressAndHoldEnabled = PressAndHoldConfiguration.defaults.enabled
    @AppStorage("pressAndHoldKeyIdentifier") private var pressAndHoldKeyIdentifier = PressAndHoldConfiguration.defaults.key.rawValue
    @AppStorage("pressAndHoldMode") private var pressAndHoldModeRaw = PressAndHoldConfiguration.defaults.mode.rawValue
    @AppStorage(AppDefaults.Keys.recordingHUDStyle) private var recordingHUDStyle = AppDefaults.defaultRecordingHUDStyle

    @State private var availableMicrophones: [AVCaptureDevice] = []
    @State private var isRecordingHotkey = false
    @State private var recordedModifiers: NSEvent.ModifierFlags = []
    @State private var recordedKey: Key?

    var body: some View {
        Form {
            Section {
                if availableMicrophones.isEmpty {
                    Text(L10n.RecordingSettings.noMicrophones)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(L10n.RecordingSettings.inputDevice, selection: $selectedMicrophone) {
                        Text(L10n.RecordingSettings.systemDefault).tag("")
                        ForEach(availableMicrophones, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text(L10n.RecordingSettings.microphone)
            }

            Section {
                if isRecordingHotkey {
                    HotKeyRecorderView(
                        isRecording: $isRecordingHotkey,
                        recordedModifiers: $recordedModifiers,
                        recordedKey: $recordedKey,
                        onComplete: { result in
                            applyRecordedHotkey(result)
                        }
                    )
                } else {
                    HStack(spacing: 10) {
                        Text(GlobalShortcutDisplay.text(for: globalHotkey))
                            .font(.system(.body, design: .monospaced))
                            .monospacedDigit()

                        Spacer()

                        Button(L10n.RecordingSettings.changeHotkey) {
                            isRecordingHotkey = true
                            recordedModifiers = []
                            recordedKey = nil
                        }
                    }
                }
            } header: {
                Text(L10n.RecordingSettings.globalHotkey)
            } footer: {
                Text(L10n.RecordingSettings.globalHotkeyFooter)
            }

            Section {
                Picker(L10n.RecordingSettings.hudStyle, selection: $recordingHUDStyle) {
                    ForEach(RecordingHUDStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text(L10n.RecordingSettings.hudStyle)
            } footer: {
                Text(L10n.RecordingSettings.hudStyleFooter)
            }

            Section {
                Toggle(isOn: $pressAndHoldEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.RecordingSettings.enablePressAndHold)
                        Text(L10n.RecordingSettings.pressAndHoldDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: pressAndHoldEnabled) { _, _ in
                    publishPressAndHoldConfiguration()
                }

                if pressAndHoldEnabled {
                    Picker(L10n.RecordingSettings.behavior, selection: $pressAndHoldModeRaw) {
                        ForEach(PressAndHoldMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: pressAndHoldModeRaw) { _, _ in
                        publishPressAndHoldConfiguration()
                    }

                    Picker(L10n.RecordingSettings.key, selection: $pressAndHoldKeyIdentifier) {
                        ForEach(PressAndHoldKey.allCases, id: \.rawValue) { key in
                            Text(key.displayName).tag(key.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: pressAndHoldKeyIdentifier) { _, _ in
                        publishPressAndHoldConfiguration()
                    }
                }
            } header: {
                Text(L10n.RecordingSettings.pressAndHold)
            } footer: {
                Text(L10n.RecordingSettings.pressAndHoldFooter)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadMicrophones)
    }

    private func loadMicrophones() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        availableMicrophones = discoverySession.devices
    }

    private func publishPressAndHoldConfiguration() {
        let selectedMode = PressAndHoldMode(rawValue: pressAndHoldModeRaw) ?? PressAndHoldConfiguration.defaults.mode
        let selectedKey = PressAndHoldKey(rawValue: pressAndHoldKeyIdentifier) ?? PressAndHoldConfiguration.defaults.key
        let configuration = PressAndHoldConfiguration(
            enabled: pressAndHoldEnabled,
            key: selectedKey,
            mode: selectedMode
        )
        NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: configuration)
    }

    private func updateGlobalHotkey(_ newHotkey: String) {
        NotificationCenter.default.post(
            name: .updateGlobalHotkey,
            object: newHotkey
        )
    }

    private func applyRecordedHotkey(_ result: HotKeyRecordingResult) {
        switch result {
        case .keyCombo(let newHotkey):
            let wasModifierOnly = GlobalShortcutDisplay.modifierOnlyKey(from: globalHotkey) != nil
            globalHotkey = newHotkey
            updateGlobalHotkey(newHotkey)

            if wasModifierOnly {
                pressAndHoldEnabled = false
                publishPressAndHoldConfiguration(
                    PressAndHoldConfiguration(
                        enabled: false,
                        key: PressAndHoldKey(rawValue: pressAndHoldKeyIdentifier) ?? PressAndHoldConfiguration.defaults.key,
                        mode: PressAndHoldMode(rawValue: pressAndHoldModeRaw) ?? PressAndHoldConfiguration.defaults.mode
                    )
                )
            }

        case .modifierOnly(let key):
            let storedValue = GlobalShortcutDisplay.storedValue(for: key)
            globalHotkey = storedValue
            pressAndHoldEnabled = true
            pressAndHoldKeyIdentifier = key.rawValue
            pressAndHoldModeRaw = PressAndHoldMode.hold.rawValue

            updateGlobalHotkey(storedValue)
            publishPressAndHoldConfiguration(
                PressAndHoldConfiguration(
                    enabled: true,
                    key: key,
                    mode: .hold
                )
            )
        }
    }

    private func publishPressAndHoldConfiguration(_ configuration: PressAndHoldConfiguration) {
        NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: configuration)
    }
}

#Preview {
    DashboardRecordingView()
        .frame(width: 900, height: 700)
}
