import AppKit
import Foundation

internal enum RecognitionSource: Equatable, Sendable {
    case contextual
    case live
    case appleSpeech
}

@MainActor
internal final class LiveDictationCoordinator {
    static let shared = LiveDictationCoordinator()

    /// How long a finished realtime transcript waits for the contextual one before being used.
    static let contextualGrace: Duration = .seconds(1)

    private let streamingTranscriber = StreamingSpeechTranscriber()
    private let openAIRealtimeTranscriber = OpenAIRealtimeTranscriber()
    private let contextualTranscriber = OpenAIRealtimeTranscriber(
        profile: .contextual(prompt: { DictationContextProvider.shared.prompt })
    )
    private let liveTextInsertionManager = LiveTextInsertionManager()
    private var activeTargetApp: NSRunningApplication?
    private var isOpenAIRealtimeActive = false
    private var isContextualActive = false
    private var sessionAudioBytes = 0
    private(set) var lastRecognitionSource: RecognitionSource?
    private var appleStreamingText = ""
    private var keepWarmUntil: Date?
    private var consecutivePrewarmFailures = 0
    private var rewarmTask: Task<Void, Never>?
    private var keepWarmActivity: NSObjectProtocol?
    private var keepWarmActivityEndTask: Task<Void, Never>?

    /// Most follow-up dictations land within this window (61% within 10 min, 68% within 30 min),
    /// so a connected session is kept ready for that long after the last use.
    static let keepWarmWindow: TimeInterval = 30 * 60

    private init() {
        for transcriber in [openAIRealtimeTranscriber, contextualTranscriber] {
            transcriber.warmSessionEventHandler = { [weak self] event in
                self?.handleWarmSessionEvent(event)
            }
        }
    }

    /// The contextual prompt is written for Chinese speech with English jargon mixed in.
    nonisolated static func shouldUseContextualTranscription(
        language: TranscriptionLanguage,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let isEnabled = defaults.object(forKey: AppDefaults.Keys.contextualTranscriptionEnabled) as? Bool ?? true
        return isEnabled && (language == .chineseEnglish || language == .chinese)
    }

    var isContextualTranscriptionActive: Bool { isContextualActive }

    nonisolated static func rewarmDelay(afterConsecutiveFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 1 }
        return min(300, 3 * pow(2, Double(failures - 1)))
    }

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

    /// Best partial transcript heard so far, available before realtime finalization completes.
    var currentTranscript: String {
        guard isOpenAIRealtimeActive else { return "" }
        let realtimeText = openAIRealtimeTranscriber.currentText
        return realtimeText.isEmpty ? appleStreamingText : realtimeText
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
            sessionAudioBytes = 0
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
            isContextualActive = Self.shouldUseContextualTranscription(language: settings.transcriptionLanguage)
            if isContextualActive {
                contextualTranscriber.start(language: settings.transcriptionLanguage)
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
        sessionAudioBytes += data.count
        streamingTranscriber.appendPCM16AudioData(data)
        openAIRealtimeTranscriber.appendPCM16AudioData(data)
        if isContextualActive { contextualTranscriber.appendPCM16AudioData(data) }
    }

    /// Keeps a realtime session connected between dictations; most follow-ups come within minutes.
    func prewarmRealtimeSessionIfNeeded() {
        keepWarmUntil = Date().addingTimeInterval(Self.keepWarmWindow)
        guard shouldKeepRealtimeSessionWarm else { return }
        holdKeepWarmActivity()
        prewarmIfWithinKeepWarmWindow()
    }

    private var shouldKeepRealtimeSessionWarm: Bool {
        let settings = TranscriptionSettingsStore.shared
        return !AppEnvironment.isRunningTests
            && settings.isStreamingTranscriptionEnabled
            && Self.shouldUseOpenAIRealtime(for: settings.transcriptionProvider)
    }

    /// As a menu bar app Typeleast is eligible for App Nap, which can defer the keep-alive and
    /// re-warm timers indefinitely while it sits in the background. Opt out only for the
    /// keep-warm window; idle system sleep stays allowed.
    private func holdKeepWarmActivity() {
        if keepWarmActivity == nil {
            keepWarmActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Keeping the dictation connection ready"
            )
        }
        keepWarmActivityEndTask?.cancel()
        keepWarmActivityEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.keepWarmWindow))
            guard !Task.isCancelled, let self, let activity = self.keepWarmActivity else { return }
            ProcessInfo.processInfo.endActivity(activity)
            self.keepWarmActivity = nil
        }
    }

    private func prewarmIfWithinKeepWarmWindow() {
        let settings = TranscriptionSettingsStore.shared
        guard shouldKeepRealtimeSessionWarm,
              let keepWarmUntil, Date() < keepWarmUntil else { return }
        openAIRealtimeTranscriber.prewarm(language: settings.transcriptionLanguage)
        if Self.shouldUseContextualTranscription(language: settings.transcriptionLanguage) {
            contextualTranscriber.prewarm(language: settings.transcriptionLanguage)
            Task { await DictationContextProvider.shared.refreshIfNeeded() }
        }
    }

    private func handleWarmSessionEvent(_ event: WarmSessionEvent) {
        switch event {
        case .ready:
            consecutivePrewarmFailures = 0
        case .lost:
            scheduleRewarm(after: Self.rewarmDelay(afterConsecutiveFailures: 0))
        case .prewarmFailed:
            consecutivePrewarmFailures += 1
            scheduleRewarm(after: Self.rewarmDelay(afterConsecutiveFailures: consecutivePrewarmFailures))
        }
    }

    private func scheduleRewarm(after delay: TimeInterval) {
        rewarmTask?.cancel()
        rewarmTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.prewarmIfWithinKeepWarmWindow()
        }
    }

    func finishRecognition(finalizeLiveText: Bool) async -> String? {
        let text: String?
        let wasOpenAIRealtimeActive = isOpenAIRealtimeActive
        lastRecognitionSource = nil
        if isOpenAIRealtimeActive {
            let liveTask = Task { await self.openAIRealtimeTranscriber.finish() }
            let contextualTask: Task<String?, Never>? = isContextualActive ? finishContextualTranscript() : nil
            async let appleText = streamingTranscriber.finish()
            let decision = await RealtimeTranscriptArbiter.decide(
                live: liveTask,
                contextual: contextualTask,
                grace: Self.contextualGrace
            )
            let apple = await appleText
            // "" means the realtime model heard no speech; on-device recognition may still have
            // caught something, otherwise the empty result stands and nothing is pasted.
            let heardText = decision.text.flatMap { $0.isEmpty ? nil : $0 }
            text = heardText ?? apple ?? decision.text
            switch (heardText, decision.source) {
            case (.some, .contextual): lastRecognitionSource = .contextual
            case (.some, .live): lastRecognitionSource = .live
            default: lastRecognitionSource = apple == nil ? decision.source.map { _ in .live } : .appleSpeech
            }
            if decision.text == nil, apple != nil {
                Task { await RealtimeDiagnostics.shared.record("apple_speech_fallback") }
            }
            if let contextualTask {
                recordDualResult(decision, live: liveTask, contextual: contextualTask)
            }
        } else {
            text = await streamingTranscriber.finish()
        }
        isOpenAIRealtimeActive = false
        isContextualActive = false
        appleStreamingText = ""
        if wasOpenAIRealtimeActive { prewarmRealtimeSessionIfNeeded() }
        let settings = TranscriptionSettingsStore.shared

        if let text, settings.isSmartPasteEnabled, finalizeLiveText {
            await liveTextInsertionManager.finish(finalText: text, targetApp: activeTargetApp)
            activeTargetApp = nil
        }
        return text
    }

    /// Finishes the contextual session, discarding output it most likely invented from its prompt.
    /// An empty contextual result carries no opinion, so the realtime result decides instead.
    private func finishContextualTranscript() -> Task<String?, Never> {
        let audioSeconds = Double(sessionAudioBytes)
            / (RealtimeAudioPCMConverter.sampleRate * Double(RealtimeAudioPCMConverter.bytesPerFrame))
        let recentTranscripts = DictationContextProvider.shared.recentTranscripts
        return Task {
            guard let text = await self.contextualTranscriber.finish(), !text.isEmpty else { return nil }
            if let rejection = ContextualTranscriptGuard.rejection(
                for: text,
                audioSeconds: audioSeconds,
                recentTranscripts: recentTranscripts
            ) {
                await RealtimeDiagnostics.shared.record(
                    "contextual_rejected",
                    fields: ["reason": rejection.rawValue, "text": text, "audio_ms": "\(Int(audioSeconds * 1_000))"]
                )
                return nil
            }
            return text
        }
    }

    /// Logs both transcripts once each session settles, so the two models can be compared on real
    /// dictation, then re-warms whichever session was still finishing when the first prewarm ran.
    private func recordDualResult(
        _ decision: RealtimeTranscriptArbiter.Decision,
        live: Task<String?, Never>,
        contextual: Task<String?, Never>
    ) {
        Task { @MainActor [weak self] in
            let liveText = await live.value
            let contextualText = await contextual.value
            let isSame = Self.comparableText(liveText) == Self.comparableText(contextualText)
            var fields = [
                "chosen": decision.source?.rawValue ?? "none",
                "same_text": isSame ? "true" : "false"
            ]
            if !isSame {
                fields["live_text"] = liveText ?? ""
                fields["contextual_text"] = contextualText ?? ""
            }
            await RealtimeDiagnostics.shared.record("dual_result", fields: fields)
            self?.prewarmIfWithinKeepWarmWindow()
        }
    }

    nonisolated static func comparableText(_ text: String?) -> String {
        (text ?? "").lowercased().unicodeScalars
            .filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
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
        // A transcriber that lost the race is still finishing so its result can be logged; it is
        // bounded by its own final timeout and superseded by the next start().
        for transcriber in [openAIRealtimeTranscriber, contextualTranscriber] where !transcriber.isFinalizing {
            transcriber.cancel()
        }
        liveTextInsertionManager.cancel()
        isOpenAIRealtimeActive = false
        isContextualActive = false
        appleStreamingText = ""
        activeTargetApp = nil
        NotificationCenter.default.post(name: .streamingTranscriptUpdated, object: "")
    }
}
