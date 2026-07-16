import AppKit
import Foundation

internal struct TranscriptionPipelineRequest {
    let audioURL: URL
    let provider: TranscriptionProvider
    let whisperModel: WhisperModel?
    var openAIModelOverride: String? = nil
    let duration: TimeInterval?
    let estimatedDuration: TimeInterval?
    let sourceAppInfo: SourceAppInfo
    let modelReadyTime: TimeInterval?
    let processStart: Date
}

internal struct TranscriptionPipelineResult {
    let text: String
    let savedRecordID: UUID?
    let processStart: Date
    let clipboardTime: TimeInterval
}

@MainActor
internal final class TranscriptionPipeline {
    typealias ProgressHandler = @MainActor (String) -> Void

    private let speechService: RawTranscriptionServicing
    private let semanticCorrectionService: SemanticCorrectionService
    private let settingsStore: TranscriptionSettingsReadable
    private let dataManager: DataManagerProtocol
    private let usageMetricsStore: UsageMetricsStore
    private let sourceUsageStore: SourceUsageStore

    init(
        speechService: RawTranscriptionServicing = SpeechToTextService(),
        semanticCorrectionService: SemanticCorrectionService = SemanticCorrectionService(),
        settingsStore: TranscriptionSettingsReadable = TranscriptionSettingsStore.shared,
        dataManager: DataManagerProtocol = DataManager.shared,
        usageMetricsStore: UsageMetricsStore? = nil,
        sourceUsageStore: SourceUsageStore? = nil
    ) {
        self.speechService = speechService
        self.semanticCorrectionService = semanticCorrectionService
        self.settingsStore = settingsStore
        self.dataManager = dataManager
        self.usageMetricsStore = usageMetricsStore ?? .shared
        self.sourceUsageStore = sourceUsageStore ?? .shared
    }

    func run(
        _ request: TranscriptionPipelineRequest,
        progressHandler: ProgressHandler? = nil
    ) async throws -> TranscriptionPipelineResult {
        let transcriptionStart = Date()
        let asrStart = Date()
        let rawText = try await speechService.transcribeRaw(
            audioURL: request.audioURL,
            provider: request.provider,
            model: request.whisperModel,
            openAIModelOverride: request.openAIModelOverride
        )
        let asrTime = Date().timeIntervalSince(asrStart)

        try Task.checkCancellation()

        return try await finish(
            request,
            rawText: rawText,
            transcriptionStart: transcriptionStart,
            asrTime: asrTime,
            progressHandler: progressHandler
        )
    }

    func runPretranscribed(
        _ request: TranscriptionPipelineRequest,
        rawText: String,
        asrTime: TimeInterval = 0,
        progressHandler: ProgressHandler? = nil
    ) async throws -> TranscriptionPipelineResult {
        let transcriptionStart = Date()
        let cleanedText = SpeechToTextService.cleanTranscriptionText(rawText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            throw SpeechToTextError.transcriptionFailed("No streaming transcription text")
        }

        try Task.checkCancellation()

        return try await finish(
            request,
            rawText: cleanedText,
            transcriptionStart: transcriptionStart,
            asrTime: asrTime,
            progressHandler: progressHandler
        )
    }

    private func finish(
        _ request: TranscriptionPipelineRequest,
        rawText: String,
        transcriptionStart: Date,
        asrTime: TimeInterval,
        progressHandler: ProgressHandler?
    ) async throws -> TranscriptionPipelineResult {
        var correctionTime: TimeInterval = 0
        var finalText = rawText
        if settingsStore.semanticCorrectionMode != .off {
            progressHandler?(L10n.Recording.semanticCorrection)
            let correctionStart = Date()
            let outcome = await semanticCorrectionService.correctWithWarning(
                text: rawText,
                providerUsed: request.provider,
                sourceAppBundleId: request.sourceAppInfo.bundleIdentifier
            )
            correctionTime = Date().timeIntervalSince(correctionStart)
            if let warning = outcome.warning {
                progressHandler?(warning)
            }
            let trimmed = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                finalText = outcome.text
            }
        }

        let measuredTranscriptionElapsed = Date().timeIntervalSince(transcriptionStart)
        let minimumStageElapsed = asrTime + correctionTime
        let transcriptionElapsed = max(measuredTranscriptionElapsed, minimumStageElapsed)
        let wordCount = UsageMetricsStore.estimatedWordCount(for: finalText)
        let characterCount = finalText.count

        let clipboardStart = Date()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(finalText, forType: .string)
        let clipboardTime = Date().timeIntervalSince(clipboardStart)

        var savedRecordID: UUID?
        if dataManager.isHistoryEnabled {
            let record = TranscriptionRecord(
                text: finalText,
                provider: request.provider,
                duration: request.duration ?? request.estimatedDuration,
                modelUsed: modelUsed(for: request),
                wordCount: wordCount,
                characterCount: characterCount,
                sourceAppBundleId: request.sourceAppInfo.bundleIdentifier,
                sourceAppName: request.sourceAppInfo.displayName,
                sourceAppIconData: request.sourceAppInfo.iconData,
                transcriptionTime: transcriptionElapsed,
                modelReadyTime: request.modelReadyTime,
                asrTime: asrTime,
                correctionTime: correctionTime,
                clipboardTime: clipboardTime,
                endToEndTime: Date().timeIntervalSince(request.processStart)
            )
            savedRecordID = record.id
            await dataManager.saveTranscriptionQuietly(record)
        }

        usageMetricsStore.recordSession(
            duration: request.duration ?? request.estimatedDuration,
            wordCount: wordCount,
            characterCount: characterCount
        )
        sourceUsageStore.recordUsage(
            for: request.sourceAppInfo,
            words: wordCount,
            characters: characterCount
        )

        return TranscriptionPipelineResult(
            text: finalText,
            savedRecordID: savedRecordID,
            processStart: request.processStart,
            clipboardTime: clipboardTime
        )
    }

    private func modelUsed(for request: TranscriptionPipelineRequest) -> String? {
        switch request.provider {
        case .local:
            return request.whisperModel?.rawValue
        case .parakeet:
            return settingsStore.selectedParakeetModel.rawValue
        case .openai:
            return request.openAIModelOverride ?? settingsStore.openAITranscriptionModel
        case .openAIRealtime:
            return settingsStore.openAIRealtimeTranscriptionModel
        case .mimo:
            return settingsStore.miMoASRModel
        case .gemini:
            return nil
        }
    }
}
