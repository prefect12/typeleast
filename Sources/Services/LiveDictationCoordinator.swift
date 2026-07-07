import AppKit
import Foundation

@MainActor
internal final class LiveDictationCoordinator {
    static let shared = LiveDictationCoordinator()

    private let streamingTranscriber = StreamingSpeechTranscriber()

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

        streamingTranscriber.start(language: settings.transcriptionLanguage) { text, isFinal in
            updateHandler?(text, isFinal)
            NotificationCenter.default.post(
                name: .streamingTranscriptUpdated,
                object: text
            )
        }

        return true
    }

    func finishRecognition() async -> String? {
        await streamingTranscriber.finish()
    }

    func cancel() {
        streamingTranscriber.cancel()
        NotificationCenter.default.post(name: .streamingTranscriptUpdated, object: "")
    }
}
