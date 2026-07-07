import AppKit
import Foundation

@MainActor
internal final class LiveDictationCoordinator {
    static let shared = LiveDictationCoordinator()

    private let streamingTranscriber = StreamingSpeechTranscriber()
    private let liveTextInsertionManager = LiveTextInsertionManager()
    private var activeTargetApp: NSRunningApplication?

    private init() {}

    var hasInsertedText: Bool {
        liveTextInsertionManager.hasInsertedText
    }

    @discardableResult
    func beginIfNeeded(
        targetApp: NSRunningApplication?,
        updateHandler: StreamingSpeechTranscriber.UpdateHandler? = nil
    ) -> Bool {
        let settings = TranscriptionSettingsStore.shared
        guard settings.isStreamingTranscriptionEnabled else {
            cancel()
            return false
        }

        activeTargetApp = targetApp
        if settings.isSmartPasteEnabled {
            liveTextInsertionManager.begin()
            targetApp?.activate(options: [])
        }

        streamingTranscriber.start(language: settings.transcriptionLanguage) { [weak self] text, isFinal in
            updateHandler?(text, isFinal)
            guard let self else { return }
            guard TranscriptionSettingsStore.shared.isSmartPasteEnabled else { return }
            self.liveTextInsertionManager.scheduleUpdate(
                text: text,
                targetApp: self.activeTargetApp
            )
        }

        return true
    }

    func finishRecognition() async -> String? {
        await streamingTranscriber.finish()
    }

    func finishInsertion(finalText: String, targetApp: NSRunningApplication?) async {
        activeTargetApp = targetApp ?? activeTargetApp
        if liveTextInsertionManager.hasInsertedText {
            await liveTextInsertionManager.finish(
                finalText: finalText,
                targetApp: activeTargetApp
            )
        } else {
            liveTextInsertionManager.cancel()
        }
        activeTargetApp = nil
    }

    func cancel() {
        streamingTranscriber.cancel()
        liveTextInsertionManager.cancel()
        activeTargetApp = nil
    }
}
