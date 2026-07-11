import AppKit
import Foundation

@MainActor
internal final class LiveDictationCoordinator {
    static let shared = LiveDictationCoordinator()
    nonisolated static let shortRealtimeVerificationMaximumDuration: TimeInterval = 2.5

    private let streamingTranscriber = StreamingSpeechTranscriber()
    private let openAIRealtimeTranscriber = OpenAIRealtimeTranscriber()
    private let liveTextInsertionManager = LiveTextInsertionManager()
    private var activeTargetApp: NSRunningApplication?
    private var isOpenAIRealtimeActive = false

    private init() {}

    nonisolated static func shouldUseOpenAIRealtime(for provider: TranscriptionProvider) -> Bool {
        provider == .openAIRealtime
    }

    nonisolated static func shouldVerifyRealtimeWithBatch(recordingDuration: TimeInterval?) -> Bool {
        guard let recordingDuration, recordingDuration > 0 else { return false }
        return recordingDuration <= shortRealtimeVerificationMaximumDuration
    }

    nonisolated static func shouldVerifyRealtimeLanguage(
        transcript: String?,
        language: TranscriptionLanguage
    ) -> Bool {
        guard language == .chineseEnglish || language == .chinese,
              let transcript,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let scalarValues = transcript.unicodeScalars.map(\.value)
        let containsLatinLetters = scalarValues.contains {
            (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
        }
        let containsHanCharacters = scalarValues.contains {
            (0x3400...0x4DBF).contains($0)
                || (0x4E00...0x9FFF).contains($0)
                || (0xF900...0xFAFF).contains($0)
        }
        return containsLatinLetters && !containsHanCharacters
    }

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
        if AppIdentity.isStreamingTest, settings.transcriptionProvider != .openAIRealtime {
            cancel()
            return false
        }

        if Self.shouldUseOpenAIRealtime(for: settings.transcriptionProvider) {
            isOpenAIRealtimeActive = true
            activeTargetApp = nil
            openAIRealtimeTranscriber.start(language: settings.transcriptionLanguage) { text, isFinal in
                updateHandler?(text, isFinal)
                NotificationCenter.default.post(name: .streamingTranscriptUpdated, object: text)
            }
            return true
        }

        isOpenAIRealtimeActive = false
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

    func appendPCM16AudioData(_ data: Data) {
        guard isOpenAIRealtimeActive else { return }
        openAIRealtimeTranscriber.appendPCM16AudioData(data)
    }

    func finishRecognition(finalizeLiveText: Bool) async -> String? {
        let text = isOpenAIRealtimeActive
            ? await openAIRealtimeTranscriber.finish()
            : await streamingTranscriber.finish()
        isOpenAIRealtimeActive = false
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
        openAIRealtimeTranscriber.cancel()
        liveTextInsertionManager.cancel()
        isOpenAIRealtimeActive = false
        activeTargetApp = nil
        NotificationCenter.default.post(name: .streamingTranscriptUpdated, object: "")
    }
}
