import SwiftUI
import ServiceManagement
import os.log

internal struct DashboardPreferencesView: View {
    @AppStorage("startAtLogin") private var startAtLogin = true
    @AppStorage("immediateRecording") private var immediateRecording = false
    @AppStorage("globalHotkey") private var globalHotkey = "⌘⇧Space"
    @AppStorage("autoBoostMicrophoneVolume") private var autoBoostMicrophoneVolume = false
    @AppStorage("enableSmartPaste") private var enableSmartPaste = true
    @AppStorage(AppDefaults.Keys.enableStreamingTranscription) private var enableStreamingTranscription = true
    @AppStorage("playCompletionSound") private var playCompletionSound = true
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

                HStack(alignment: .center, spacing: 16) {
                    Toggle(isOn: $immediateRecording) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.Preferences.expressMode)
                            Text(L10n.Preferences.expressModeDesc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

#Preview {
    DashboardPreferencesView()
        .frame(width: 900, height: 700)
}
