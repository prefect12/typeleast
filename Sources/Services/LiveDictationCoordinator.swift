import AppKit
import Foundation

@MainActor
internal final class LiveDictationCoordinator {
    static let shared = LiveDictationCoordinator()

    private let streamingTranscriber = StreamingSpeechTranscriber()
    private let openAIRealtimeTranscriber = OpenAIRealtimeTranscriber()

    private init() {}

    @discardableResult
    func beginIfNeeded(
        targetApp _: NSRunningApplication?,
        updateHandler: StreamingSpeechTranscriber.UpdateHandler? = nil
    ) -> Bool {
        let settings = TranscriptionSettingsStore.shared
        guard settings.isStreamingTranscriptionEnabled else {
            cancel()
            return false
        }

        let handler: StreamingSpeechTranscriber.UpdateHandler = { text, isFinal in
            updateHandler?(text, isFinal)
            NotificationCenter.default.post(
                name: .streamingTranscriptUpdated,
                object: text
            )
        }

        switch settings.transcriptionProvider {
        case .openAIRealtime:
            openAIRealtimeTranscriber.start(
                language: settings.transcriptionLanguage,
                updateHandler: handler
            )
        case .openai, .mimo, .gemini, .local, .parakeet:
            streamingTranscriber.start(language: settings.transcriptionLanguage, updateHandler: handler)
        }

        return true
    }

    func finishRecognition() async -> String? {
        let settings = TranscriptionSettingsStore.shared
        switch settings.transcriptionProvider {
        case .openAIRealtime:
            return await openAIRealtimeTranscriber.finish()
        case .openai, .mimo, .gemini, .local, .parakeet:
            return await streamingTranscriber.finish()
        }
    }

    func cancel() {
        streamingTranscriber.cancel()
        openAIRealtimeTranscriber.cancel()
        NotificationCenter.default.post(name: .streamingTranscriptUpdated, object: "")
    }
}
