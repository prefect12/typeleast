import AppKit
import Foundation

@MainActor
internal final class LiveDictationCoordinator {
    static let shared = LiveDictationCoordinator()

    private let streamingTranscriber = StreamingSpeechTranscriber()
    private let liveTextInsertionManager = LiveTextInsertionManager()
    private var activeTargetApp: NSRunningApplication?

    private init() {}

    var hasInsertedLiveText: Bool {
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
        liveTextInsertionManager.begin()

        streamingTranscriber.start(language: settings.transcriptionLanguage) { text, isFinal in
            updateHandler?(text, isFinal)
            NotificationCenter.default.post(
                name: .streamingTranscriptUpdated,
                object: text
            )

            if settings.isSmartPasteEnabled {
                self.liveTextInsertionManager.scheduleUpdate(text: text, targetApp: targetApp)
            }
        }

        return true
    }

    func finishRecognition(finalizeLiveText: Bool) async -> String? {
        let text = await streamingTranscriber.finish()
        let settings = TranscriptionSettingsStore.shared

        if let text, settings.isSmartPasteEnabled, finalizeLiveText {
            await liveTextInsertionManager.finish(finalText: text, targetApp: activeTargetApp)
            activeTargetApp = nil
        }
        return text
    }

    func finishLiveText(with finalText: String) async {
        let settings = TranscriptionSettingsStore.shared
        guard settings.isSmartPasteEnabled else {
            activeTargetApp = nil
            liveTextInsertionManager.cancel()
            return
        }

        await liveTextInsertionManager.finish(finalText: finalText, targetApp: activeTargetApp)
        activeTargetApp = nil
    }

    func cancel() {
        streamingTranscriber.cancel()
        liveTextInsertionManager.cancel()
        activeTargetApp = nil
        NotificationCenter.default.post(name: .streamingTranscriptUpdated, object: "")
    }
}
