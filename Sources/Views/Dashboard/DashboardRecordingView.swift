import SwiftUI
import AVFoundation
import HotKey
import AppKit

internal struct DashboardRecordingView: View {
    @AppStorage("selectedMicrophone") private var selectedMicrophone = ""
    @AppStorage("globalHotkey") private var globalHotkey = "⌘⇧Space"
    @AppStorage(AppDefaults.Keys.immediateRecording) private var immediateRecording = false
    @AppStorage("pressAndHoldEnabled") private var pressAndHoldEnabled = PressAndHoldConfiguration.defaults.enabled
    @AppStorage("pressAndHoldKeyIdentifier") private var pressAndHoldKeyIdentifier = PressAndHoldConfiguration.defaults.key.rawValue
    @AppStorage("pressAndHoldMode") private var pressAndHoldModeRaw = PressAndHoldConfiguration.defaults.mode.rawValue
    @AppStorage("autoBoostMicrophoneVolume") private var autoBoostMicrophoneVolume = false
    @AppStorage(AppDefaults.Keys.enableStreamingTranscription) private var enableStreamingTranscription = true
    @AppStorage("playCompletionSound") private var playCompletionSound = true
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

            Section {
                Toggle(isOn: $autoBoostMicrophoneVolume) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.RecordingSettings.autoBoost)
                        Text(L10n.RecordingSettings.autoBoostDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $enableStreamingTranscription) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.RecordingSettings.livePreview)
                        Text(L10n.RecordingSettings.livePreviewDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $playCompletionSound) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.RecordingSettings.completionSound)
                        Text(L10n.RecordingSettings.completionSoundDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L10n.RecordingSettings.recordingExperience)
            }

            Section {
                HUDStylePickerGrid(selection: $recordingHUDStyle)
            } header: {
                Text(L10n.RecordingSettings.hudStyle)
            } footer: {
                Text(L10n.RecordingSettings.hudStyleFooter)
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

private struct HUDStylePickerGrid: View {
    @Binding var selection: RecordingHUDStyle

    private let columns = [
        GridItem(.adaptive(minimum: 172, maximum: 240), spacing: 12, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(RecordingHUDStyle.allCases) { style in
                HUDStyleOptionCard(
                    style: style,
                    isSelected: selection == style
                ) {
                    selection = style
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HUDStyleOptionCard: View {
    let style: RecordingHUDStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                RecordingHUDStylePreview(style: style)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    Text(style.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DashboardTheme.ink)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? DashboardTheme.accent : DashboardTheme.inkFaint)
                }
            }
            .padding(10)
            .frame(minHeight: 118, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? DashboardTheme.accentSubtle : DashboardTheme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? DashboardTheme.accent : DashboardTheme.rule, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct RecordingHUDStylePreview: View {
    let style: RecordingHUDStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(previewBackdrop)

            hudShape
                .frame(width: style == .candidateBar ? 132 : 122, height: style == .candidateBar ? 34 : 42)
        }
        .frame(height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var previewBackdrop: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                DashboardTheme.cardBgAlt
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var hudShape: some View {
        switch style {
        case .appleGlass:
            previewCapsule(
                fill: LinearGradient(
                    colors: [
                        Color.white.opacity(0.82),
                        Color(red: 0.86, green: 0.94, blue: 1.0).opacity(0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                border: Color.white.opacity(0.82),
                indicator: appleGlassIndicator,
                textColor: Color.black.opacity(0.70)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)

        case .siriAura:
            ZStack(alignment: .leading) {
                Circle()
                    .fill(siriGradient)
                    .frame(width: 54, height: 54)
                    .blur(radius: 10)
                    .opacity(0.50)
                    .offset(x: -14)

                previewCapsule(
                    fill: LinearGradient(
                        colors: [
                            Color.white.opacity(0.86),
                            Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.56)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    border: Color(red: 0.42, green: 0.62, blue: 1.0).opacity(0.55),
                    indicator: siriAuraIndicator,
                    textColor: Color.black.opacity(0.72)
                )
            }
            .shadow(color: Color(red: 0.42, green: 0.62, blue: 1.0).opacity(0.18), radius: 9, y: 4)

        case .candidateBar:
            previewCapsule(
                fill: LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        Color(red: 0.96, green: 0.98, blue: 1.0).opacity(0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                border: Color.black.opacity(0.14),
                indicator: candidateBarIndicator,
                textColor: Color.black.opacity(0.76)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 6, y: 3)
        }
    }

    private func previewCapsule<Indicator: View>(
        fill: LinearGradient,
        border: Color,
        indicator: Indicator,
        textColor: Color
    ) -> some View {
        HStack(spacing: 7) {
            indicator
                .frame(width: style == .candidateBar ? 24 : 18, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(textColor.opacity(0.54))
                    .frame(width: style == .candidateBar ? 66 : 58, height: 4)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(textColor.opacity(0.26))
                    .frame(width: style == .candidateBar ? 48 : 42, height: 3)
            }
        }
        .padding(.horizontal, style == .candidateBar ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: style == .candidateBar ? 12 : 14, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: style == .candidateBar ? 12 : 14, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
    }

    private var appleGlassIndicator: some View {
        ZStack {
            Circle()
                .fill(siriGradient)
                .frame(width: 18, height: 18)
                .blur(radius: 4)
                .opacity(0.52)
            Circle()
                .fill(siriGradient)
                .frame(width: 8, height: 8)
        }
    }

    private var siriAuraIndicator: some View {
        ZStack {
            Circle()
                .fill(siriGradient)
                .frame(width: 22, height: 22)
                .blur(radius: 5)
                .opacity(0.76)
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 7, height: 7)
        }
    }

    private var candidateBarIndicator: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach([7, 13, 17, 11, 15], id: \.self) { height in
                Capsule(style: .continuous)
                    .fill(siriLinearGradient)
                    .frame(width: 3, height: CGFloat(height))
            }
        }
    }

    private var siriGradient: AngularGradient {
        AngularGradient(
            colors: [
                Color(red: 0.20, green: 0.60, blue: 1.0),
                Color(red: 0.67, green: 0.34, blue: 1.0),
                Color(red: 1.0, green: 0.35, blue: 0.78),
                Color(red: 1.0, green: 0.45, blue: 0.22),
                Color(red: 0.20, green: 0.60, blue: 1.0)
            ],
            center: .center
        )
    }

    private var siriLinearGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.58, blue: 1.0),
                Color(red: 0.76, green: 0.32, blue: 1.0),
                Color(red: 1.0, green: 0.37, blue: 0.72)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
