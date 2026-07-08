import Foundation

/// Centralized defaults so "fresh install" behavior is deterministic and consistent across the app.
///
/// Notes:
/// - We use `register(defaults:)` (registration domain) rather than eagerly writing values, so we don't
///   accidentally clobber user preferences or treat a first-run as "already configured".
/// - AppStorage initial values across the app should match these constants.
internal enum AppDefaults {
    private static let productionBundleIdentifier = AppIdentity.bundleIdentifier
    private static let developmentBundleIdentifier = AppIdentity.developmentBundleIdentifier

    internal enum Keys {
        static let transcriptionProvider = "transcriptionProvider"
        static let selectedWhisperModel = "selectedWhisperModel"
        static let selectedParakeetModel = "selectedParakeetModel"
        static let openAITranscriptionModel = "openAITranscriptionModel"
        static let openAIRealtimeTranscriptionModel = "openAIRealtimeTranscriptionModel"
        static let openAIRealtimeTranscriptionDelay = "openAIRealtimeTranscriptionDelay"
        static let miMoASRModel = "miMoASRModel"
        static let transcriptionLanguage = "transcriptionLanguage"

        static let semanticCorrectionMode = "semanticCorrectionMode"
        static let semanticCorrectionModelRepo = "semanticCorrectionModelRepo"

        static let startAtLogin = "startAtLogin"
        static let playCompletionSound = "playCompletionSound"
        static let transcriptionHistoryEnabled = "transcriptionHistoryEnabled"
        static let transcriptionRetentionPeriod = "transcriptionRetentionPeriod"
        static let maxModelStorageGB = "maxModelStorageGB"
        static let enableSmartPaste = "enableSmartPaste"
        static let enableStreamingTranscription = "enableStreamingTranscription"
        static let recordingHUDStyle = "recordingHUDStyle"
        static let immediateRecording = "immediateRecording"
        static let globalHotkey = "globalHotkey"

        static let pressAndHoldEnabled = "pressAndHoldEnabled"
        static let pressAndHoldKeyIdentifier = "pressAndHoldKeyIdentifier"
        static let pressAndHoldMode = "pressAndHoldMode"

        static let hasCompletedWelcome = "hasCompletedWelcome"
        static let lastWelcomeVersion = "lastWelcomeVersion"

        static let hasSetupLocalLLM = "hasSetupLocalLLM"
        static let hasSetupParakeet = "hasSetupParakeet"
    }

    // Bump when the welcome flow/content needs to be re-shown for existing users.
    internal static let currentWelcomeVersion = "1.1"

    // Chosen defaults.
    internal static let defaultTranscriptionProvider: TranscriptionProvider = .local
    internal static let defaultWhisperModel: WhisperModel = .base
    internal static let defaultParakeetModel: ParakeetModel = .v3Multilingual
    internal static let defaultOpenAITranscriptionModel = "gpt-4o-transcribe"
    internal static let defaultOpenAIRealtimeTranscriptionModel = "gpt-realtime-whisper"
    internal static let defaultOpenAIRealtimeTranscriptionDelay: OpenAIRealtimeTranscriptionDelay = .minimal
    internal static let defaultMiMoASRModel = "mimo-v2.5-asr"
    internal static let defaultTranscriptionLanguage: TranscriptionLanguage = .auto
    internal static let defaultRecordingHUDStyle: RecordingHUDStyle = .appleGlass
    internal static let defaultSemanticCorrectionMode: SemanticCorrectionMode = .off
    internal static let defaultSemanticCorrectionModelRepo: String = "mlx-community/Qwen3-1.7B-4bit"

    internal static func register() {
        UserDefaults.standard.register(defaults: [
            Keys.transcriptionProvider: defaultTranscriptionProvider.rawValue,
            Keys.selectedWhisperModel: defaultWhisperModel.rawValue,
            Keys.selectedParakeetModel: defaultParakeetModel.rawValue,
            Keys.openAITranscriptionModel: defaultOpenAITranscriptionModel,
            Keys.openAIRealtimeTranscriptionModel: defaultOpenAIRealtimeTranscriptionModel,
            Keys.openAIRealtimeTranscriptionDelay: defaultOpenAIRealtimeTranscriptionDelay.rawValue,
            Keys.miMoASRModel: defaultMiMoASRModel,
            Keys.transcriptionLanguage: defaultTranscriptionLanguage.rawValue,

            Keys.semanticCorrectionMode: defaultSemanticCorrectionMode.rawValue,
            Keys.semanticCorrectionModelRepo: defaultSemanticCorrectionModelRepo,

            Keys.startAtLogin: true,
            Keys.playCompletionSound: true,
            Keys.transcriptionHistoryEnabled: true,
            Keys.transcriptionRetentionPeriod: RetentionPeriod.forever.rawValue,
            Keys.maxModelStorageGB: 5.0,
            Keys.enableSmartPaste: true,
            Keys.enableStreamingTranscription: true,
            Keys.recordingHUDStyle: defaultRecordingHUDStyle.rawValue,
            Keys.immediateRecording: false,
            Keys.globalHotkey: "⌘⇧Space",

            Keys.pressAndHoldEnabled: PressAndHoldConfiguration.defaults.enabled,
            Keys.pressAndHoldKeyIdentifier: PressAndHoldConfiguration.defaults.key.rawValue,
            Keys.pressAndHoldMode: PressAndHoldConfiguration.defaults.mode.rawValue,

            Keys.hasCompletedWelcome: true,
            Keys.lastWelcomeVersion: currentWelcomeVersion,

            Keys.hasSetupLocalLLM: false,
            Keys.hasSetupParakeet: false
        ])
    }

    /// Dev builds use a different bundle identifier and therefore a different preferences domain.
    /// If history was enabled in the production app, keep the dev app aligned on first launch so
    /// local debugging doesn't silently disable history persistence.
    internal static func migrateHistoryPreferencesIfNeeded(
        bundle: Bundle = .main,
        currentBundleIdentifier: String? = nil,
        userDefaults: UserDefaults = .standard,
        sourceBundleIdentifier: String = productionBundleIdentifier
    ) {
        let activeBundleIdentifier = currentBundleIdentifier ?? bundle.bundleIdentifier
        guard activeBundleIdentifier == developmentBundleIdentifier else { return }

        let hasLocalHistoryPreference = userDefaults.object(forKey: Keys.transcriptionHistoryEnabled) != nil
        let hasLocalRetentionPreference = userDefaults.object(forKey: Keys.transcriptionRetentionPeriod) != nil
        guard !hasLocalHistoryPreference, !hasLocalRetentionPreference else { return }

        guard let productionDefaults = userDefaults.persistentDomain(forName: sourceBundleIdentifier) else {
            return
        }

        if let enabled = productionDefaults[Keys.transcriptionHistoryEnabled] as? Bool {
            userDefaults.set(enabled, forKey: Keys.transcriptionHistoryEnabled)
        }

        if let retention = productionDefaults[Keys.transcriptionRetentionPeriod] as? String {
            userDefaults.set(retention, forKey: Keys.transcriptionRetentionPeriod)
        }
    }
}
