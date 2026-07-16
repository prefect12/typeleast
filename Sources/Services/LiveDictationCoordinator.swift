import AppKit
import Foundation

@MainActor
internal final class LiveDictationCoordinator {
    static let shared = LiveDictationCoordinator()

    private let streamingTranscriber = StreamingSpeechTranscriber()
    private let openAIRealtimeTranscriber = OpenAIRealtimeTranscriber()
    private let liveTextInsertionManager = LiveTextInsertionManager()
    private var activeTargetApp: NSRunningApplication?
    private var isOpenAIRealtimeActive = false
    private var appleStreamingText = ""

    private init() {}

    nonisolated static func shouldUseOpenAIRealtime(for provider: TranscriptionProvider) -> Bool {
        provider == .openAIRealtime
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
        let containsHanCharacters = scalarValues.contains {
            (0x3400...0x4DBF).contains($0)
                || (0x4E00...0x9FFF).contains($0)
                || (0xF900...0xFAFF).contains($0)
        }
        let containsUnexpectedScript = scalarValues.contains {
            (0x3040...0x30FF).contains($0) // Hiragana and Katakana
                || (0x0400...0x052F).contains($0) // Cyrillic
                || (0x0600...0x06FF).contains($0) // Arabic
                || (0x0900...0x097F).contains($0) // Devanagari
        }
        return !containsHanCharacters || containsUnexpectedScript
    }

    nonisolated static func shouldUseHighAccuracyEnglishFinalization(
        transcript: String?,
        language: TranscriptionLanguage
    ) -> Bool {
        guard language == .chineseEnglish,
              let transcript,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return transcript.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x0041...0x005A).contains(value) // Basic Latin uppercase
                || (0x0061...0x007A).contains(value) // Basic Latin lowercase
                || (0x00C0...0x024F).contains(value) // Latin-1 and Latin Extended
        }
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
            appleStreamingText = ""
            streamingTranscriber.startWithExternalAudio(language: settings.transcriptionLanguage) { [weak self] text, isFinal in
                guard let self else { return }
                self.appleStreamingText = text
                updateHandler?(text, isFinal)
                NotificationCenter.default.post(name: .streamingTranscriptUpdated, object: text)
            }
            openAIRealtimeTranscriber.start(language: settings.transcriptionLanguage) { text, isFinal in
                guard self.appleStreamingText.isEmpty else { return }
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
        streamingTranscriber.appendPCM16AudioData(data)
        openAIRealtimeTranscriber.appendPCM16AudioData(data)
    }

    func finishRecognition(finalizeLiveText: Bool) async -> String? {
        let text: String?
        if isOpenAIRealtimeActive {
            async let openAIText = openAIRealtimeTranscriber.finish()
            async let appleText = streamingTranscriber.finish()
            let results = await (openAIText, appleText)
            text = results.0 ?? results.1
            if results.0 == nil, results.1 != nil {
                Task { await RealtimeDiagnostics.shared.record("apple_speech_fallback") }
            }
        } else {
            text = await streamingTranscriber.finish()
        }
        isOpenAIRealtimeActive = false
        appleStreamingText = ""
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
        appleStreamingText = ""
        activeTargetApp = nil
        NotificationCenter.default.post(name: .streamingTranscriptUpdated, object: "")
    }
}
