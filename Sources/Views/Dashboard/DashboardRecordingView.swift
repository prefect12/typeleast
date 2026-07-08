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
    @AppStorage(AppDefaults.Keys.immediateRecording) private var immediateRecording = false
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
                VStack(alignment: .leading, spacing: 8) {
                    Picker(L10n.RecordingSettings.shortcutTrigger, selection: recordingModeBinding) {
                        Text(L10n.Preferences.continuousMode).tag(true)
                        Text(L10n.Preferences.quickMode).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)

                    Text(L10n.RecordingSettings.shortcutTriggerDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.RecordingSettings.shortcutTrigger)
            } footer: {
                Text(L10n.RecordingSettings.pressAndHoldFooter)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadMicrophones()
            syncModifierOnlyShortcutMode(isContinuous: immediateRecording)
        }
    }

    private func loadMicrophones() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        availableMicrophones = discoverySession.devices
    }

    private var recordingModeBinding: Binding<Bool> {
        Binding(
            get: { immediateRecording },
            set: { isContinuous in
                immediateRecording = isContinuous
                syncModifierOnlyShortcutMode(isContinuous: isContinuous)
            }
        )
    }

    private func syncModifierOnlyShortcutMode(isContinuous: Bool) {
        guard let key = GlobalShortcutDisplay.modifierOnlyKey(from: globalHotkey) else { return }

        pressAndHoldEnabled = true
        pressAndHoldKeyIdentifier = key.rawValue
        pressAndHoldModeRaw = isContinuous ? PressAndHoldMode.doubleTapToggle.rawValue : PressAndHoldMode.hold.rawValue

        publishPressAndHoldConfiguration(
            PressAndHoldConfiguration(
                enabled: true,
                key: key,
                mode: isContinuous ? .doubleTapToggle : .hold
            )
        )
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
            let selectedMode: PressAndHoldMode = immediateRecording ? .doubleTapToggle : .hold
            globalHotkey = storedValue
            pressAndHoldEnabled = true
            pressAndHoldKeyIdentifier = key.rawValue
            pressAndHoldModeRaw = selectedMode.rawValue

            updateGlobalHotkey(storedValue)
            publishPressAndHoldConfiguration(
                PressAndHoldConfiguration(
                    enabled: true,
                    key: key,
                    mode: selectedMode
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
