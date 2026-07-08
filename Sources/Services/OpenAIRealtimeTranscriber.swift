@preconcurrency import AVFoundation
import Foundation
import os.log

@MainActor
internal final class OpenAIRealtimeTranscriber: ObservableObject {
    typealias UpdateHandler = @MainActor (_ text: String, _ isFinal: Bool) -> Void

    @Published private(set) var currentText = ""
    @Published private(set) var isStreaming = false

    private let keychainService: KeychainServiceProtocol
    private let settingsStore: TranscriptionSettingsReadable
    private let urlSession: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pendingStartTask: Task<Void, Never>?
    private var audioDrainTask: Task<Void, Never>?
    private var audioEngine: AVAudioEngine?
    private var periodicCommitTask: Task<Void, Never>?
    private var completionContinuation: CheckedContinuation<String, Error>?
    private var completionTargetCommitCount = 0
    private var finalTranscript = ""
    private var hasUncommittedAudio = false
    private var isCommitInFlight = false
    private var sentCommitCount = 0
    private var completedCommitCount = 0
    private var transcriptSegments: [String: TranscriptSegment] = [:]
    private var transcriptSegmentOrder: [String] = []
    private var lastError: Error?
    private var updateHandler: UpdateHandler?
    private let fallbackSegmentID = "fallback"
    private var hasSessionCreated = false
    private var hasSessionUpdated = false
    private var isSessionReadyForAudio = false
    private var queuedStartupAudioChunks: [Data] = []
    private var pendingSendAudioChunks: [Data] = []
    private let maxQueuedStartupAudioChunks = 240

    private struct TranscriptSegment {
        var text: String
        var isFinal: Bool
    }

    init(
        keychainService: KeychainServiceProtocol = KeychainService.shared,
        settingsStore: TranscriptionSettingsReadable = TranscriptionSettingsStore.shared,
        urlSession: URLSession = .shared
    ) {
        self.keychainService = keychainService
        self.settingsStore = settingsStore
        self.urlSession = urlSession
    }

    nonisolated static func transcriptionSessionURL() throws -> URL {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")
        components?.queryItems = [URLQueryItem(name: "intent", value: "transcription")]
        guard let url = components?.url else {
            throw SpeechToTextError.invalidURL
        }
        return url
    }

    func start(
        language: TranscriptionLanguage,
        updateHandler: UpdateHandler? = nil,
        capturesMicrophoneAudio: Bool = true
    ) {
        cancel()
        currentText = ""
        finalTranscript = ""
        resetTranscriptState()
        lastError = nil
        self.updateHandler = updateHandler

        guard !AppEnvironment.isRunningTests else { return }

        pendingStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.startStreaming(
                    language: language,
                    capturesMicrophoneAudio: capturesMicrophoneAudio
                )
            } catch {
                Logger.speechToText.error("Failed to start OpenAI realtime transcription: \(error.localizedDescription)")
                self.lastError = error
                self.cleanup()
            }
        }
    }

    func appendPCM16AudioData(_ data: Data) {
        guard !data.isEmpty else { return }

        guard webSocketTask != nil, isSessionReadyForAudio else {
            enqueueStartupAudioChunk(data)
            return
        }

        pendingSendAudioChunks.append(data)
        drainAudioSendQueue()
    }

    func finish(timeout: TimeInterval = 1.2) async -> String? {
        if let pendingStartTask {
            self.pendingStartTask = nil
            let didFinishStarting = await waitForPendingStart(
                pendingStartTask,
                timeout: 2.5
            )
            if !didFinishStarting {
                pendingStartTask.cancel()
                let text = currentBestText()
                cleanup()
                return text.isEmpty ? nil : text
            }
        }
        pendingStartTask = nil

        guard isStreaming, webSocketTask != nil else {
            let text = currentBestText()
            cleanup()
            return text.isEmpty ? nil : text
        }

        stopAudioCapture()

        do {
            try? await Task.sleep(for: .milliseconds(80))
            await waitForAudioDrain()
            await waitForInFlightCommit()
            try await commitBufferedAudioIfNeeded()

            guard sentCommitCount > 0 else {
                let text = currentBestText()
                cleanup()
                return text.isEmpty ? nil : text
            }

            let text = try await waitForCompletion(
                timeout: timeout,
                targetCommitCount: sentCommitCount
            )
            cleanup()
            return text.isEmpty ? nil : text
        } catch {
            Logger.speechToText.error("OpenAI realtime transcription did not complete: \(error.localizedDescription)")
            let text = currentBestText()
            cleanup()
            return text.isEmpty ? nil : text
        }
    }

    func cancel() {
        pendingStartTask?.cancel()
        pendingStartTask = nil
        resumeCompletion(with: SpeechToTextError.transcriptionFailed("Realtime transcription cancelled"))
        cleanup()
    }

    private func startStreaming(
        language: TranscriptionLanguage,
        capturesMicrophoneAudio: Bool
    ) async throws {
        guard let apiKey = keychainService.getQuietly(service: AppIdentity.keychainService, account: "OpenAI") else {
            throw SpeechToTextError.apiKeyMissing("OpenAI")
        }

        let url = try Self.transcriptionSessionURL()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = urlSession.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        receiveMessages()
        if capturesMicrophoneAudio {
            try startAudioCapture()
        }
        isStreaming = true
        try await waitForSessionCreated(timeout: 4)
        try await sendSessionUpdate(language: language)
        try await waitForSessionUpdated(timeout: 4)
        isSessionReadyForAudio = true
        flushQueuedStartupAudioChunks()
        startPeriodicCommits()
        try await commitBufferedAudioIfNeeded()
    }

    private func sendSessionUpdate(language: TranscriptionLanguage) async throws {
        var transcription: [String: Any] = [
            "model": settingsStore.openAIRealtimeTranscriptionModel,
            "delay": settingsStore.openAIRealtimeTranscriptionDelay.rawValue
        ]

        if let languageHint = language.openAIRealtimeLanguageHint {
            transcription["language"] = languageHint
        }

        try await sendEvent([
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000
                        ],
                        "transcription": transcription,
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ])
    }

    private func startAudioCapture() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechToTextError.transcriptionFailed("Microphone input format is unavailable")
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let audioData = RealtimeAudioPCMConverter.pcm16Mono24kData(from: buffer),
                  !audioData.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.appendPCM16AudioData(audioData)
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    private func stopAudioCapture() {
        if audioEngine?.isRunning == true {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
        }
    }

    private func sendAudioData(_ data: Data) async {
        guard webSocketTask != nil else { return }

        do {
            try await sendEvent([
                "type": "input_audio_buffer.append",
                "audio": data.base64EncodedString()
            ])
            hasUncommittedAudio = true
        } catch {
            Logger.speechToText.error("Failed to send OpenAI realtime audio chunk: \(error.localizedDescription)")
            lastError = error
        }
    }

    private func enqueueStartupAudioChunk(_ data: Data) {
        queuedStartupAudioChunks.append(data)
        if queuedStartupAudioChunks.count > maxQueuedStartupAudioChunks {
            queuedStartupAudioChunks.removeFirst(queuedStartupAudioChunks.count - maxQueuedStartupAudioChunks)
        }
    }

    private func flushQueuedStartupAudioChunks() {
        guard isSessionReadyForAudio, !queuedStartupAudioChunks.isEmpty else { return }

        pendingSendAudioChunks.append(contentsOf: queuedStartupAudioChunks)
        queuedStartupAudioChunks.removeAll(keepingCapacity: true)
        drainAudioSendQueue()
    }

    private func drainAudioSendQueue() {
        guard audioDrainTask == nil else { return }
        audioDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard !self.pendingSendAudioChunks.isEmpty else {
                    self.audioDrainTask = nil
                    return
                }
                let data = self.pendingSendAudioChunks.removeFirst()
                await self.sendAudioData(data)
            }
        }
    }

    private func waitForAudioDrain() async {
        while audioDrainTask != nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func startPeriodicCommits() {
        periodicCommitTask?.cancel()
        periodicCommitTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(450))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.commitLivePreviewBuffer()
            }
        }
    }

    private func commitLivePreviewBuffer() async {
        do {
            try await commitBufferedAudioIfNeeded()
        } catch {
            Logger.speechToText.error("Failed to commit OpenAI realtime preview buffer: \(error.localizedDescription)")
            lastError = error
        }
    }

    @discardableResult
    private func commitBufferedAudioIfNeeded() async throws -> Bool {
        guard webSocketTask != nil, hasUncommittedAudio, !isCommitInFlight else {
            return false
        }

        isCommitInFlight = true
        hasUncommittedAudio = false
        do {
            try await sendEvent(["type": "input_audio_buffer.commit"])
            sentCommitCount += 1
            isCommitInFlight = false
            return true
        } catch {
            hasUncommittedAudio = true
            isCommitInFlight = false
            throw error
        }
    }

    private func waitForInFlightCommit() async {
        while isCommitInFlight {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func waitForPendingStart(_ task: Task<Void, Never>, timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await task.value
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(Int(timeout * 1_000)))
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func waitForSessionCreated(timeout: TimeInterval) async throws {
        try await waitForSessionFlag(timeout: timeout) { $0.hasSessionCreated }
    }

    private func waitForSessionUpdated(timeout: TimeInterval) async throws {
        try await waitForSessionFlag(timeout: timeout) { $0.hasSessionUpdated }
    }

    private func waitForSessionFlag(
        timeout: TimeInterval,
        isReady: (OpenAIRealtimeTranscriber) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isReady(self) {
                return
            }
            if let lastError {
                throw lastError
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw SpeechToTextError.transcriptionFailed("OpenAI realtime session timed out")
    }

    private func sendEvent(_ event: [String: Any]) async throws {
        guard let webSocketTask else {
            throw SpeechToTextError.transcriptionFailed("OpenAI realtime session is not connected")
        }
        let data = try JSONSerialization.data(withJSONObject: event)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SpeechToTextError.transcriptionFailed("Failed to encode realtime event")
        }
        try await webSocketTask.send(.string(text))
    }

    private func receiveMessages() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let webSocketTask = self.webSocketTask else { return }
                do {
                    let message = try await webSocketTask.receive()
                    self.handle(message)
                } catch {
                    await MainActor.run {
                        self.lastError = error
                        self.resumeCompletion(with: error)
                    }
                    return
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let text):
            data = text.data(using: .utf8)
        case .data(let messageData):
            data = messageData
        @unknown default:
            data = nil
        }

        guard let data else { return }
        do {
            let event = try JSONDecoder().decode(OpenAIRealtimeServerEvent.self, from: data)
            handle(event)
        } catch {
            Logger.speechToText.error("Failed to decode OpenAI realtime event: \(error.localizedDescription)")
        }
    }

    private func handle(_ event: OpenAIRealtimeServerEvent) {
        switch event.type {
        case "session.created":
            hasSessionCreated = true
        case "session.updated":
            hasSessionUpdated = true
        case "conversation.item.input_audio_transcription.delta":
            guard let delta = event.delta, !delta.isEmpty else { return }
            updateSegment(for: event, text: delta, isFinal: false, appending: true)
            publishTranscriptUpdate(isFinal: false)
        case "conversation.item.input_audio_transcription.completed":
            let transcript = event.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? currentText
            updateSegment(for: event, text: transcript, isFinal: true, appending: false)
            completedCommitCount += 1
            publishTranscriptUpdate(isFinal: true)
            resumeCompletionIfReady()
        case "conversation.item.input_audio_transcription.failed", "error":
            let message = event.error?.message ?? "OpenAI realtime transcription failed"
            let error = SpeechToTextError.transcriptionFailed(message)
            lastError = error
            resumeCompletion(with: error)
        default:
            break
        }
    }

    private func updateSegment(
        for event: OpenAIRealtimeServerEvent,
        text: String,
        isFinal: Bool,
        appending: Bool
    ) {
        let segmentID = event.itemID ?? fallbackSegmentID
        if transcriptSegments[segmentID] == nil {
            transcriptSegmentOrder.append(segmentID)
            transcriptSegments[segmentID] = TranscriptSegment(text: "", isFinal: false)
        }

        var segment = transcriptSegments[segmentID] ?? TranscriptSegment(text: "", isFinal: false)
        segment.text = appending ? segment.text + text : text
        segment.isFinal = isFinal
        transcriptSegments[segmentID] = segment
    }

    private func publishTranscriptUpdate(isFinal: Bool) {
        let transcript = joinedTranscript()
        currentText = transcript
        if isFinal {
            finalTranscript = transcript
        }
        updateHandler?(transcript, isFinal)
    }

    private func joinedTranscript() -> String {
        transcriptSegmentOrder
            .compactMap { transcriptSegments[$0]?.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func waitForCompletion(timeout: TimeInterval, targetCommitCount: Int) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var bestText = currentBestText()
        var lastTextChange = Date()

        while Date() < deadline {
            if let lastError {
                throw lastError
            }

            let text = currentBestText()
            if !text.isEmpty {
                if text != bestText {
                    bestText = text
                    lastTextChange = Date()
                }

                if completedCommitCount >= targetCommitCount ||
                    Date().timeIntervalSince(lastTextChange) >= 0.18 {
                    return text
                }
            }

            try await Task.sleep(for: .milliseconds(60))
        }

        if !bestText.isEmpty {
            return bestText
        }

        throw SpeechToTextError.transcriptionFailed("OpenAI realtime transcription timed out")
    }

    private func resumeCompletion(with text: String) {
        guard let completionContinuation else { return }
        self.completionContinuation = nil
        completionContinuation.resume(returning: text)
    }

    private func resumeCompletion(with error: Error) {
        guard let completionContinuation else { return }
        self.completionContinuation = nil
        completionContinuation.resume(throwing: error)
    }

    private func resumeCompletionIfReady() {
        guard let completionContinuation,
              completedCommitCount >= completionTargetCommitCount else {
            return
        }
        self.completionContinuation = nil
        completionContinuation.resume(returning: currentBestText())
    }

    private func currentBestText() -> String {
        let text = finalTranscript.isEmpty ? currentText : finalTranscript
        return SpeechToTextService.cleanTranscriptionText(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanup() {
        stopAudioCapture()
        audioDrainTask?.cancel()
        audioDrainTask = nil
        periodicCommitTask?.cancel()
        periodicCommitTask = nil
        audioEngine = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        updateHandler = nil
        isStreaming = false
        isSessionReadyForAudio = false
        queuedStartupAudioChunks.removeAll(keepingCapacity: true)
        pendingSendAudioChunks.removeAll(keepingCapacity: true)
        hasUncommittedAudio = false
        isCommitInFlight = false
    }

    private func resetTranscriptState() {
        completionTargetCommitCount = 0
        sentCommitCount = 0
        completedCommitCount = 0
        hasUncommittedAudio = false
        isCommitInFlight = false
        hasSessionCreated = false
        hasSessionUpdated = false
        isSessionReadyForAudio = false
        queuedStartupAudioChunks.removeAll(keepingCapacity: true)
        pendingSendAudioChunks.removeAll(keepingCapacity: true)
        transcriptSegments.removeAll()
        transcriptSegmentOrder.removeAll()
    }
}

internal struct OpenAIRealtimeServerEvent: Decodable, Equatable {
    struct RealtimeError: Decodable, Equatable {
        let message: String?
    }

    let type: String
    let itemID: String?
    let delta: String?
    let transcript: String?
    let error: RealtimeError?

    enum CodingKeys: String, CodingKey {
        case type
        case itemID = "item_id"
        case delta
        case transcript
        case error
    }
}
