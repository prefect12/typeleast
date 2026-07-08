import AppKit
import Foundation

@MainActor
internal final class LiveDictationCoordinator {
    static let shared = LiveDictationCoordinator()

    private let streamingTranscriber = StreamingSpeechTranscriber()
    private let openAIRealtimeTranscriber = OpenAIRealtimeTranscriber()
    private let liveTextInsertionManager = LiveTextInsertionManager()
    private var activeTargetApp: NSRunningApplication?

    private init() {}

    var hasInsertedLiveText: Bool {
        liveTextInsertionManager.hasInsertedText
    }

    @discardableResult
    func beginIfNeeded(
        targetApp: NSRunningApplication?,
        updateHandler: StreamingSpeechTranscriber.UpdateHandler? = nil,
        useExternalAudioCapture: Bool = false
    ) -> AudioRecorder.PCM16AudioDataHandler? {
        let settings = TranscriptionSettingsStore.shared
        guard settings.isStreamingTranscriptionEnabled else {
            cancel()
            return nil
        }

        activeTargetApp = targetApp
        liveTextInsertionManager.begin()

        let handler: StreamingSpeechTranscriber.UpdateHandler = { text, isFinal in
            updateHandler?(text, isFinal)
            NotificationCenter.default.post(
                name: .streamingTranscriptUpdated,
                object: text
            )

            if settings.isSmartPasteEnabled {
                self.liveTextInsertionManager.scheduleUpdate(text: text, targetApp: targetApp)
            }
        }

        switch settings.transcriptionProvider {
        case .openAIRealtime:
            openAIRealtimeTranscriber.start(
                language: settings.transcriptionLanguage,
                updateHandler: handler,
                capturesMicrophoneAudio: !useExternalAudioCapture
            )
        case .openai, .mimo, .gemini, .local, .parakeet:
            streamingTranscriber.start(language: settings.transcriptionLanguage, updateHandler: handler)
        }

        guard settings.transcriptionProvider == .openAIRealtime, useExternalAudioCapture else {
            return nil
        }

        return { [weak self] data in
            Task { @MainActor [weak self] in
                self?.openAIRealtimeTranscriber.appendPCM16AudioData(data)
            }
        }
    }

    func finishRecognition() async -> String? {
        let settings = TranscriptionSettingsStore.shared
        let text: String?
        switch settings.transcriptionProvider {
        case .openAIRealtime:
            text = await openAIRealtimeTranscriber.finish()
        case .openai, .mimo, .gemini, .local, .parakeet:
            text = await streamingTranscriber.finish()
        }

        if let text, settings.isSmartPasteEnabled {
            await liveTextInsertionManager.finish(finalText: text, targetApp: activeTargetApp)
        }
        activeTargetApp = nil
        return text
    }

    func cancel() {
        streamingTranscriber.cancel()
        openAIRealtimeTranscriber.cancel()
        liveTextInsertionManager.cancel()
        activeTargetApp = nil
        NotificationCenter.default.post(name: .streamingTranscriptUpdated, object: "")
    }
}
