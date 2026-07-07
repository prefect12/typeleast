import AVFoundation
import Combine
import Foundation
import os.log
import Speech

@MainActor
internal final class StreamingSpeechTranscriber: ObservableObject {
    typealias UpdateHandler = @MainActor (_ text: String, _ isFinal: Bool) -> Void

    @Published private(set) var currentText: String = ""
    @Published private(set) var isStreaming = false

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var pendingStartTask: Task<Void, Never>?
    private var updateHandler: UpdateHandler?

    func start(language: TranscriptionLanguage, updateHandler: UpdateHandler? = nil) {
        cancel()
        currentText = ""
        self.updateHandler = updateHandler

        guard !AppEnvironment.isRunningTests else { return }

        pendingStartTask = Task { [weak self] in
            guard let self else { return }
            guard await self.requestAuthorizationIfNeeded() else { return }
            guard !Task.isCancelled else { return }

            do {
                try self.startAuthorized(language: language)
            } catch {
                Logger.speechToText.error("Failed to start streaming speech recognition: \(error.localizedDescription)")
                self.cleanup()
            }
        }
    }

    func finish(timeout: Duration = .milliseconds(700)) async -> String? {
        pendingStartTask?.cancel()
        pendingStartTask = nil

        if isStreaming {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            recognitionRequest?.endAudio()
            try? await Task.sleep(for: timeout)
        }

        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanup()
        return text.isEmpty ? nil : text
    }

    func cancel() {
        pendingStartTask?.cancel()
        pendingStartTask = nil

        if isStreaming {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
        }
        recognitionTask?.cancel()
        cleanup()
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func startAuthorized(language: TranscriptionLanguage) throws {
        let recognizer = SFSpeechRecognizer(locale: language.streamingRecognitionLocale)
            ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechToTextError.transcriptionFailed("Streaming speech recognizer is unavailable")
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechToTextError.transcriptionFailed("Microphone input format is unavailable")
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.currentText = text
                    self.updateHandler?(text, result.isFinal)
                }

                if error != nil {
                    self.isStreaming = false
                }
            }
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        recognitionRequest = request
        isStreaming = true
    }

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        updateHandler = nil
        isStreaming = false
    }
}

extension TranscriptionLanguage {
    var streamingRecognitionLocale: Locale {
        switch self {
        case .auto:
            return Self.automaticStreamingRecognitionLocale()
        case .chinese:
            return Locale(identifier: "zh_CN")
        case .english:
            return Locale(identifier: "en_US")
        case .japanese:
            return Locale(identifier: "ja_JP")
        case .korean:
            return Locale(identifier: "ko_KR")
        case .spanish:
            return Locale(identifier: "es_ES")
        case .french:
            return Locale(identifier: "fr_FR")
        case .german:
            return Locale(identifier: "de_DE")
        }
    }

    static func automaticStreamingRecognitionLocale(
        preferredLanguages: [String] = Locale.preferredLanguages,
        currentLocale: Locale = .current
    ) -> Locale {
        for language in preferredLanguages {
            let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized.hasPrefix("zh-hant") ||
                normalized.hasPrefix("zh-tw") ||
                normalized.hasPrefix("zh-hk") ||
                normalized.hasPrefix("zh-mo") {
                return Locale(identifier: "zh_TW")
            }
            if normalized.hasPrefix("zh") {
                return Locale(identifier: "zh_CN")
            }
        }

        if let languageCode = currentLocale.language.languageCode?.identifier,
           languageCode == "zh" {
            return currentLocale
        }

        let chineseRegions: Set<String> = ["CN", "HK", "MO", "SG", "TW"]
        if let region = currentLocale.region?.identifier,
           chineseRegions.contains(region) {
            return region == "TW" || region == "HK" || region == "MO"
                ? Locale(identifier: "zh_TW")
                : Locale(identifier: "zh_CN")
        }

        return currentLocale
    }
}
