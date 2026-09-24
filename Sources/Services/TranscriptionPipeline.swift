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

internal protocol ClipboardWriting: AnyObject {
    func replaceContents(with string: String)
}

extension NSPasteboard: ClipboardWriting {
    func replaceContents(with string: String) {
        clearContents()
        setString(string, forType: .string)
    }
}

/// A batch transcription started ahead of time so it can overlap realtime finalization.
internal struct PendingRawTranscription {
    let task: Task<String, Error>
    let startedAt: Date
    let openAIModelOverride: String?

    func cancel() { task.cancel() }
}

internal extension TranscriptionPipelineRequest {
    func with(provider: TranscriptionProvider, openAIModelOverride: String? = nil) -> TranscriptionPipelineRequest {
        var copy = TranscriptionPipelineRequest(
            audioURL: audioURL,
            provider: provider,
            whisperModel: provider == .local ? whisperModel : nil,
            duration: duration,
            estimatedDuration: estimatedDuration,
            sourceAppInfo: sourceAppInfo,
            modelReadyTime: modelReadyTime,
            processStart: processStart
        )
        copy.openAIModelOverride = openAIModelOverride
        return copy
    }
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
    private let clipboard: ClipboardWriting

    init(
        speechService: RawTranscriptionServicing = SpeechToTextService(),
        semanticCorrectionService: SemanticCorrectionService = SemanticCorrectionService(),
        settingsStore: TranscriptionSettingsReadable = TranscriptionSettingsStore.shared,
        dataManager: DataManagerProtocol = DataManager.shared,
        usageMetricsStore: UsageMetricsStore? = nil,
        sourceUsageStore: SourceUsageStore? = nil,
        clipboard: ClipboardWriting = NSPasteboard.general
    ) {
        self.speechService = speechService
        self.semanticCorrectionService = semanticCorrectionService
        self.settingsStore = settingsStore
        self.dataManager = dataManager
        self.usageMetricsStore = usageMetricsStore ?? .shared
        self.sourceUsageStore = sourceUsageStore ?? .shared
        self.clipboard = clipboard
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

    func startRawTranscription(
        audioURL: URL,
        provider: TranscriptionProvider,
        openAIModelOverride: String? = nil
    ) -> PendingRawTranscription {
        let speechService = speechService
        let task = Task { @MainActor in
            try await speechService.transcribeRaw(
                audioURL: audioURL,
                provider: provider,
                model: nil,
                openAIModelOverride: openAIModelOverride
            )
        }
        return PendingRawTranscription(task: task, startedAt: Date(), openAIModelOverride: openAIModelOverride)
    }

    /// Finishes a batch transcription that was started early, with no fallback text to race against.
    func run(
        _ request: TranscriptionPipelineRequest,
        prestarted: PendingRawTranscription,
        progressHandler: ProgressHandler? = nil
    ) async throws -> TranscriptionPipelineResult {
        let rawText = try await withTaskCancellationHandler {
            try await prestarted.task.value
        } onCancel: {
            prestarted.cancel()
        }
        try Task.checkCancellation()

        return try await finish(
            request,
            rawText: rawText,
            transcriptionStart: prestarted.startedAt,
            asrTime: Date().timeIntervalSince(prestarted.startedAt),
            progressHandler: progressHandler
        )
    }

    /// Budget for a refinement pass, measured from when its upload started. Longer audio gets a bit
    /// more time, but a refinement can never stall the paste the way an unbounded request did.
    nonisolated static func refinementTimeout(forAudioDuration duration: TimeInterval?) -> TimeInterval {
        min(6, 3 + 0.1 * max(0, duration ?? 0))
    }

    /// Once a usable streamed transcript exists, the English accuracy pass may delay the paste by at
    /// most this much. Measured: realtime finished 0.8s after release while the batch pass still
    /// hadn't returned 3.3s later, so waiting longer mostly buys latency, not accuracy.
    nonisolated static let englishRefinementGrace: TimeInterval = 1

    /// Uses a slower, more accurate batch transcription only if it lands within `timeout`
    /// (measured from when it started); otherwise keeps the already-available streamed text.
    func runRefining(
        _ request: TranscriptionPipelineRequest,
        refinement: PendingRawTranscription,
        fallbackRequest: TranscriptionPipelineRequest,
        fallbackText: String,
        fallbackASRTime: TimeInterval,
        timeout: TimeInterval,
        maximumExtraWait: TimeInterval? = nil,
        progressHandler: ProgressHandler? = nil
    ) async throws -> TranscriptionPipelineResult {
        let remaining = min(
            max(0, timeout - Date().timeIntervalSince(refinement.startedAt)),
            maximumExtraWait ?? .infinity
        )
        let outcome = await Self.firstResult(of: refinement.task, within: remaining)
        if Task.isCancelled {
            refinement.cancel()
            throw CancellationError()
        }

        let elapsedMilliseconds = Int(Date().timeIntervalSince(refinement.startedAt) * 1_000)
        let refinedText = outcome.flatMap { text in
            let cleaned = SpeechToTextService.cleanTranscriptionText(text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        Task {
            await RealtimeDiagnostics.shared.record(
                "refinement",
                fields: [
                    "outcome": refinedText != nil ? "batch" : (outcome == nil ? "timeout_or_error" : "empty"),
                    "milliseconds": "\(elapsedMilliseconds)"
                ]
            )
        }

        guard let refinedText else {
            refinement.cancel()
            return try await runPretranscribed(
                fallbackRequest,
                rawText: fallbackText,
                asrTime: fallbackASRTime,
                progressHandler: progressHandler
            )
        }

        return try await finish(
            request,
            rawText: refinedText,
            transcriptionStart: refinement.startedAt,
            asrTime: Date().timeIntervalSince(refinement.startedAt),
            progressHandler: progressHandler
        )
    }

    /// Resolves with the task's value, or nil on error or once `timeout` elapses — without waiting
    /// for a task that ignores cancellation to wind down.
    static func firstResult(of task: Task<String, Error>, within timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            var didResume = false
            let resume: @MainActor (String?) -> Void = { value in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
            }
            Task { @MainActor in resume(try? await task.value) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                resume(nil)
            }
        }
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

        DictationContextProvider.shared.recordTranscript(finalText)

        let clipboardStart = Date()
        clipboard.replaceContents(with: finalText)
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
            return request.openAIModelOverride ?? settingsStore.openAIRealtimeTranscriptionModel
        case .mimo:
            return settingsStore.miMoASRModel
        case .gemini:
            return SpeechToTextService.geminiTranscriptionModel
        }
    }
}
