import SwiftUI
import ServiceManagement
import os.log

internal struct DashboardPreferencesView: View {
    @AppStorage("startAtLogin") private var startAtLogin = true
    @AppStorage("immediateRecording") private var immediateRecording = false
    @AppStorage("globalHotkey") private var globalHotkey = "⌘⇧Space"
    @AppStorage("pressAndHoldEnabled") private var pressAndHoldEnabled = PressAndHoldConfiguration.defaults.enabled
    @AppStorage("pressAndHoldKeyIdentifier") private var pressAndHoldKeyIdentifier = PressAndHoldConfiguration.defaults.key.rawValue
    @AppStorage("pressAndHoldMode") private var pressAndHoldModeRaw = PressAndHoldConfiguration.defaults.mode.rawValue
    @AppStorage("autoBoostMicrophoneVolume") private var autoBoostMicrophoneVolume = false
    @AppStorage("enableSmartPaste") private var enableSmartPaste = true
    @AppStorage(AppDefaults.Keys.enableStreamingTranscription) private var enableStreamingTranscription = true
    @AppStorage("playCompletionSound") private var playCompletionSound = true
    @AppStorage(AppDefaults.Keys.recordingHUDStyle) private var recordingHUDStyle = AppDefaults.defaultRecordingHUDStyle
    @AppStorage("transcriptionHistoryEnabled") private var transcriptionHistoryEnabled = true
    @AppStorage("transcriptionRetentionPeriod") private var transcriptionRetentionPeriodRaw = RetentionPeriod.forever.rawValue
    @AppStorage("maxModelStorageGB") private var maxModelStorageGB = 5.0

    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var loginItemError: String?

    var onConfigureShortcuts: (() -> Void)?

    private let storageOptions: [Double] = [1, 2, 5, 10, 20]

    private var retentionBinding: Binding<RetentionPeriod> {
        Binding(
            get: { RetentionPeriod(rawValue: transcriptionRetentionPeriodRaw) ?? .forever },
            set: { transcriptionRetentionPeriodRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            // Language setting at the top
            Section {
                Picker(L10n.Preferences.language, selection: $languageManager.current) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: languageManager.current) { _, _ in
                    (NSApp.delegate as? AppDelegate)?.refreshStatusMenu()
                }
            } header: {
                Text(L10n.Preferences.language)
            } footer: {
                Text(L10n.Preferences.languageFooter)
            }

            Section(L10n.Preferences.general) {
                Toggle(isOn: $startAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Preferences.startAtLogin)
                        Text(L10n.Preferences.startAtLoginDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: startAtLogin) { _, newValue in
                    updateLoginItem(enabled: newValue)
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.Preferences.recordingMode)
                            Text(L10n.Preferences.recordingModeDesc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Picker(L10n.Preferences.recordingMode, selection: recordingModeBinding) {
                            Text(L10n.Preferences.continuousMode).tag(true)
                            Text(L10n.Preferences.quickMode).tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 240)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(GlobalShortcutDisplay.text(for: globalHotkey))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Button(L10n.Preferences.configureShortcut) {
                            onConfigureShortcuts?()
                        }
                        .buttonStyle(.link)
                        .disabled(onConfigureShortcuts == nil)
                    }
                }

                Toggle(isOn: $autoBoostMicrophoneVolume) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Preferences.autoBoost)
                        Text(L10n.Preferences.autoBoostDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $enableSmartPaste) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Preferences.smartPaste)
                        Text(L10n.Preferences.smartPasteDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $enableStreamingTranscription) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Preferences.streamingTranscription)
                        Text(L10n.Preferences.streamingTranscriptionDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $playCompletionSound) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Preferences.completionSound)
                        Text(L10n.Preferences.completionSoundDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
            }

            Section {
                HUDStylePickerGrid(selection: $recordingHUDStyle)
            } header: {
                Text(L10n.RecordingSettings.hudStyle)
            } footer: {
                Text(L10n.RecordingSettings.hudStyleFooter)
            }

            Section {
                Toggle(isOn: $transcriptionHistoryEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Preferences.saveHistory)
                        Text(L10n.Preferences.saveHistoryDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if transcriptionHistoryEnabled {
                    Picker("Retention Period", selection: retentionBinding) {
                        ForEach(RetentionPeriod.allCases, id: \.rawValue) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text(L10n.Preferences.history)
            }

            Section(L10n.Preferences.storage) {
                Picker(L10n.Preferences.maxModelStorage, selection: $maxModelStorageGB) {
                    ForEach(storageOptions, id: \.self) { option in
                        Text("\(Int(option)) GB").tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(L10n.Preferences.about) {
                LabeledContent(L10n.Preferences.version) {
                    Text(VersionInfo.fullVersionInfo)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if VersionInfo.gitHash != "dev-build" && VersionInfo.gitHash != "unknown" {
                    LabeledContent("Git") {
                        Text(VersionInfo.gitHash)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if !VersionInfo.buildDate.isEmpty {
                    LabeledContent("Built") {
                        Text(VersionInfo.buildDate)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            syncModifierOnlyShortcutMode(isContinuous: immediateRecording)
        }
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

        NotificationCenter.default.post(
            name: .pressAndHoldSettingsChanged,
            object: PressAndHoldConfiguration(
                enabled: true,
                key: key,
                mode: isContinuous ? .doubleTapToggle : .hold
            )
        )
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            Logger.settings.error("Failed to update login item: \(error.localizedDescription)")
            loginItemError = "Couldn't update login item: \(error.localizedDescription)"
        }
    }
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

#Preview {
    DashboardPreferencesView()
        .frame(width: 900, height: 700)
}
