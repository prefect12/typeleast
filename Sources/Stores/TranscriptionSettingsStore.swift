import Foundation

internal protocol TranscriptionSettingsReadable: AnyObject {
    var transcriptionProvider: TranscriptionProvider { get }
    var selectedWhisperModel: WhisperModel { get }
    var selectedParakeetModel: ParakeetModel { get }
    var openAITranscriptionModel: String { get }
    var openAIRealtimeTranscriptionModel: String { get }
    var miMoASRModel: String { get }
    var transcriptionLanguage: TranscriptionLanguage { get }
    var recordingHUDStyle: RecordingHUDStyle { get }
    var semanticCorrectionMode: SemanticCorrectionMode { get }
    var semanticCorrectionModelRepo: String { get }
    var isTranscriptionHistoryEnabled: Bool { get }
    var transcriptionRetentionPeriod: RetentionPeriod { get set }
    var isSmartPasteEnabled: Bool { get }
    var isStreamingTranscriptionEnabled: Bool { get }
    var maxModelStorageGB: Double { get }
}

internal struct TranscriptionSettingsSnapshot: Equatable {
    let transcriptionProvider: TranscriptionProvider
    let selectedWhisperModel: WhisperModel
    let selectedParakeetModel: ParakeetModel
    let openAITranscriptionModel: String
    let openAIRealtimeTranscriptionModel: String
    let miMoASRModel: String
    let transcriptionLanguage: TranscriptionLanguage
    let recordingHUDStyle: RecordingHUDStyle
    let semanticCorrectionMode: SemanticCorrectionMode
    let semanticCorrectionModelRepo: String
    let isTranscriptionHistoryEnabled: Bool
    let transcriptionRetentionPeriod: RetentionPeriod
    let isSmartPasteEnabled: Bool
    let isStreamingTranscriptionEnabled: Bool
    let maxModelStorageGB: Double
}

internal final class TranscriptionSettingsStore: TranscriptionSettingsReadable {
    static let shared = TranscriptionSettingsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var transcriptionProvider: TranscriptionProvider {
        let rawValue = defaults.string(forKey: AppDefaults.Keys.transcriptionProvider)
            ?? AppDefaults.defaultTranscriptionProvider.rawValue
        return TranscriptionProvider(rawValue: rawValue) ?? AppDefaults.defaultTranscriptionProvider
    }

    var selectedWhisperModel: WhisperModel {
        let rawValue = defaults.string(forKey: AppDefaults.Keys.selectedWhisperModel)
            ?? AppDefaults.defaultWhisperModel.rawValue
        return WhisperModel(rawValue: rawValue) ?? AppDefaults.defaultWhisperModel
    }

    var selectedParakeetModel: ParakeetModel {
        let rawValue = defaults.string(forKey: AppDefaults.Keys.selectedParakeetModel)
            ?? AppDefaults.defaultParakeetModel.rawValue
        return ParakeetModel(rawValue: rawValue) ?? AppDefaults.defaultParakeetModel
    }

    var openAITranscriptionModel: String {
        nonEmptyString(
            forKey: AppDefaults.Keys.openAITranscriptionModel,
            fallback: AppDefaults.defaultOpenAITranscriptionModel
        )
    }

    var openAIRealtimeTranscriptionModel: String {
        AppDefaults.defaultOpenAIRealtimeTranscriptionModel
    }

    var miMoASRModel: String {
        nonEmptyString(
            forKey: AppDefaults.Keys.miMoASRModel,
            fallback: AppDefaults.defaultMiMoASRModel
        )
    }

    var transcriptionLanguage: TranscriptionLanguage {
        let rawValue = defaults.string(forKey: AppDefaults.Keys.transcriptionLanguage)
            ?? AppDefaults.defaultTranscriptionLanguage.rawValue
        return TranscriptionLanguage(rawValue: rawValue) ?? AppDefaults.defaultTranscriptionLanguage
    }

    var recordingHUDStyle: RecordingHUDStyle {
        let rawValue = defaults.string(forKey: AppDefaults.Keys.recordingHUDStyle)
            ?? AppDefaults.defaultRecordingHUDStyle.rawValue
        return RecordingHUDStyle(rawValue: rawValue) ?? AppDefaults.defaultRecordingHUDStyle
    }

    var semanticCorrectionMode: SemanticCorrectionMode {
        let rawValue = defaults.string(forKey: AppDefaults.Keys.semanticCorrectionMode)
            ?? AppDefaults.defaultSemanticCorrectionMode.rawValue
        return SemanticCorrectionMode(rawValue: rawValue) ?? AppDefaults.defaultSemanticCorrectionMode
    }

    var semanticCorrectionModelRepo: String {
        nonEmptyString(
            forKey: AppDefaults.Keys.semanticCorrectionModelRepo,
            fallback: AppDefaults.defaultSemanticCorrectionModelRepo
        )
    }

    var isTranscriptionHistoryEnabled: Bool {
        defaults.bool(forKey: AppDefaults.Keys.transcriptionHistoryEnabled)
    }

    var transcriptionRetentionPeriod: RetentionPeriod {
        get {
            let rawValue = defaults.string(forKey: AppDefaults.Keys.transcriptionRetentionPeriod)
                ?? RetentionPeriod.forever.rawValue
            return RetentionPeriod(rawValue: rawValue) ?? .forever
        }
        set {
            defaults.set(newValue.rawValue, forKey: AppDefaults.Keys.transcriptionRetentionPeriod)
        }
    }

    var isSmartPasteEnabled: Bool {
        defaults.bool(forKey: AppDefaults.Keys.enableSmartPaste)
    }

    var isStreamingTranscriptionEnabled: Bool {
        defaults.bool(forKey: AppDefaults.Keys.enableStreamingTranscription)
    }

    var maxModelStorageGB: Double {
        let value = defaults.object(forKey: AppDefaults.Keys.maxModelStorageGB) as? Double
        guard let value, value > 0 else { return 5.0 }
        return value
    }

    func snapshot() -> TranscriptionSettingsSnapshot {
        TranscriptionSettingsSnapshot(
            transcriptionProvider: transcriptionProvider,
            selectedWhisperModel: selectedWhisperModel,
            selectedParakeetModel: selectedParakeetModel,
            openAITranscriptionModel: openAITranscriptionModel,
            openAIRealtimeTranscriptionModel: openAIRealtimeTranscriptionModel,
            miMoASRModel: miMoASRModel,
            transcriptionLanguage: transcriptionLanguage,
            recordingHUDStyle: recordingHUDStyle,
            semanticCorrectionMode: semanticCorrectionMode,
            semanticCorrectionModelRepo: semanticCorrectionModelRepo,
            isTranscriptionHistoryEnabled: isTranscriptionHistoryEnabled,
            transcriptionRetentionPeriod: transcriptionRetentionPeriod,
            isSmartPasteEnabled: isSmartPasteEnabled,
            isStreamingTranscriptionEnabled: isStreamingTranscriptionEnabled,
            maxModelStorageGB: maxModelStorageGB
        )
    }

    private func nonEmptyString(forKey key: String, fallback: String) -> String {
        let value = defaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return fallback }
        return value
    }
}
