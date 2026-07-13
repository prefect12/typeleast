import Foundation
import os.log

internal enum RealtimeTranscriptionFailure: String, Error, Equatable, Sendable {
    case handshakeTimeout
    case transportError
    case serverError
    case finalTimeout
    case cancelled
}

internal enum RealtimeTranscriptionState: Equatable, Sendable {
    case idle
    case connecting
    case ready
    case streaming
    case finalizing
    case completed
    case failed(RealtimeTranscriptionFailure)
}

internal struct RealtimeTranscriptAccumulator: Equatable, Sendable {
    private struct Segment: Equatable, Sendable {
        var text = ""
        var isFinal = false
    }

    private var order: [String] = []
    private var segments: [String: Segment] = [:]

    mutating func appendDelta(_ delta: String, itemID: String?) {
        guard !delta.isEmpty else { return }
        let id = itemID ?? "fallback"
        ensureSegment(id)
        segments[id]?.text.append(delta)
    }

    mutating func complete(_ transcript: String, itemID: String?) {
        let id = itemID ?? "fallback"
        ensureSegment(id)
        segments[id] = Segment(text: transcript, isFinal: true)
    }

    var text: String {
        order.compactMap { segments[$0]?.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private mutating func ensureSegment(_ id: String) {
        guard segments[id] == nil else { return }
        order.append(id)
        segments[id] = Segment()
    }
}

internal enum RealtimeSocketMessage: Sendable {
    case text(String)
    case data(Data)
}

internal protocol RealtimeSocketTransport: AnyObject, Sendable {
    func connect()
    func send(text: String) async throws
    func receive() async throws -> RealtimeSocketMessage
    func close()
}

internal final class URLSessionRealtimeSocketTransport: RealtimeSocketTransport, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest, session: URLSession = .shared) {
        task = session.webSocketTask(with: request)
    }

    func connect() { task.resume() }

    func send(text: String) async throws { try await task.send(.string(text)) }

    func receive() async throws -> RealtimeSocketMessage {
        switch try await task.receive() {
        case .string(let text): return .text(text)
        case .data(let data): return .data(data)
        @unknown default: throw RealtimeTranscriptionFailure.transportError
        }
    }

    func close() { task.cancel(with: .normalClosure, reason: nil) }
}

internal struct OpenAIRealtimeServerEvent: Decodable, Equatable, Sendable {
    struct ServerError: Decodable, Equatable, Sendable { let message: String? }

    let type: String
    let itemID: String?
    let delta: String?
    let transcript: String?
    let error: ServerError?

    enum CodingKeys: String, CodingKey {
        case type
        case itemID = "item_id"
        case delta
        case transcript
        case error
    }
}

@MainActor
internal final class OpenAIRealtimeTranscriber: ObservableObject {
    typealias UpdateHandler = @MainActor (_ text: String, _ isFinal: Bool) -> Void
    typealias TransportFactory = @Sendable (URLRequest) -> any RealtimeSocketTransport

    @Published private(set) var currentText = ""
    @Published private(set) var state: RealtimeTranscriptionState = .idle

    private let keychainService: KeychainServiceProtocol
    private let settingsStore: TranscriptionSettingsReadable
    private let transportFactory: TransportFactory
    private let handshakeTimeout: Duration
    private var transport: (any RealtimeSocketTransport)?
    private var startTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var audioDrainTask: Task<Void, Never>?
    private var updateHandler: UpdateHandler?
    private var startupAudio: [Data] = []
    private var startupAudioBytes = 0
    private var sendQueue: [Data] = []
    private var accumulator = RealtimeTranscriptAccumulator()
    private var receivedCompleted = false
    private var startedAt: Date?
    private var firstDeltaAt: Date?
    private let maximumStartupAudioBytes = Int(RealtimeAudioPCMConverter.sampleRate * 5) * RealtimeAudioPCMConverter.bytesPerFrame

    init(
        keychainService: KeychainServiceProtocol = KeychainService.shared,
        settingsStore: TranscriptionSettingsReadable = TranscriptionSettingsStore.shared,
        handshakeTimeout: Duration = .seconds(5),
        transportFactory: @escaping TransportFactory = { URLSessionRealtimeSocketTransport(request: $0) }
    ) {
        self.keychainService = keychainService
        self.settingsStore = settingsStore
        self.handshakeTimeout = handshakeTimeout
        self.transportFactory = transportFactory
    }

    func start(language: TranscriptionLanguage, updateHandler: UpdateHandler? = nil) {
        cancel(setCancelledState: false)
        currentText = ""
        accumulator = RealtimeTranscriptAccumulator()
        receivedCompleted = false
        startedAt = Date()
        firstDeltaAt = nil
        self.updateHandler = updateHandler
        transition(to: .connecting)

        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.establishSession(language: language)
            } catch let failure as RealtimeTranscriptionFailure {
                self.fail(failure)
            } catch {
                Logger.speechToText.error("OpenAI realtime start failed: \(error.localizedDescription, privacy: .public)")
                self.fail(.transportError)
            }
        }
    }

    func appendPCM16AudioData(_ data: Data) {
        guard !data.isEmpty else { return }
        switch state {
        case .connecting:
            guard startupAudioBytes + data.count <= maximumStartupAudioBytes else {
                fail(.handshakeTimeout)
                return
            }
            startupAudio.append(data)
            startupAudioBytes += data.count
        case .ready, .streaming:
            sendQueue.append(data)
            drainAudioQueue()
        case .idle, .finalizing, .completed, .failed:
            break
        }
    }

    func finish(timeout: Duration = .milliseconds(2_500)) async -> String? {
        await startTask?.value
        startTask = nil
        guard state == .ready || state == .streaming else { return nil }

        transition(to: .finalizing)
        await waitForAudioDrain()
        do {
            try await sendEvent(["type": "input_audio_buffer.commit"])
        } catch {
            fail(.transportError)
            return nil
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if receivedCompleted, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                transition(to: .completed)
                recordCompletion()
                closeTransport()
                return SpeechToTextService.cleanTranscriptionText(currentText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if case .failed = state { return nil }
            try? await Task.sleep(for: .milliseconds(40))
        }

        fail(.finalTimeout)
        return nil
    }

    func cancel() { cancel(setCancelledState: true) }

    nonisolated static func transcriptionSessionURL() throws -> URL {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")
        components?.queryItems = [URLQueryItem(name: "intent", value: "transcription")]
        guard let url = components?.url else { throw SpeechToTextError.invalidURL }
        return url
    }

    private func establishSession(language: TranscriptionLanguage) async throws {
        guard let apiKey = keychainService.getQuietly(service: AppIdentity.keychainService, account: "OpenAI") else {
            throw SpeechToTextError.apiKeyMissing("OpenAI")
        }

        var request = URLRequest(url: try Self.transcriptionSessionURL())
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = transportFactory(request)
        transport = socket
        socket.connect()

        let deadline = ContinuousClock().now.advanced(by: handshakeTimeout)
        try await receiveUntil("session.created", deadline: deadline)
        try await sendSessionUpdate(language: language)
        try await receiveUntil("session.updated", deadline: deadline)

        transition(to: .ready)
        sendQueue.append(contentsOf: startupAudio)
        startupAudio.removeAll(keepingCapacity: false)
        startupAudioBytes = 0
        drainAudioQueue()
        transition(to: .streaming)
        receiveMessages()
    }

    private func sendSessionUpdate(language: TranscriptionLanguage) async throws {
        var transcription: [String: Any] = [
            "model": settingsStore.openAIRealtimeTranscriptionModel,
            "delay": "minimal",
            "prompt": language.speechInstruction
        ]
        if let hint = language.openAIRealtimeLanguageHint { transcription["language"] = hint }

        try await sendEvent([
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": transcription,
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ])
    }

    private func receiveUntil(_ expectedType: String, deadline: ContinuousClock.Instant) async throws {
        while ContinuousClock().now < deadline {
            let remaining = ContinuousClock().now.duration(to: deadline)
            let message = try await receiveWithTimeout(remaining)
            let event = try decode(message)
            if event.type == expectedType { return }
            handle(event)
        }
        throw RealtimeTranscriptionFailure.handshakeTimeout
    }

    private func receiveWithTimeout(_ timeout: Duration) async throws -> RealtimeSocketMessage {
        guard let transport else { throw RealtimeTranscriptionFailure.transportError }
        return try await withThrowingTaskGroup(of: RealtimeSocketMessage.self) { group in
            group.addTask { try await transport.receive() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw RealtimeTranscriptionFailure.handshakeTimeout
            }
            guard let first = try await group.next() else { throw RealtimeTranscriptionFailure.transportError }
            group.cancelAll()
            return first
        }
    }

    private func receiveMessages() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let transport = self.transport else { return }
                do {
                    self.handle(try self.decode(await transport.receive()))
                    if self.receivedCompleted { return }
                } catch is CancellationError {
                    return
                } catch {
                    if self.state != .completed { self.fail(.transportError) }
                    return
                }
            }
        }
    }

    private func handle(_ event: OpenAIRealtimeServerEvent) {
        switch event.type {
        case "conversation.item.input_audio_transcription.delta":
            guard let delta = event.delta, !delta.isEmpty else { return }
            accumulator.appendDelta(delta, itemID: event.itemID)
            currentText = accumulator.text
            if firstDeltaAt == nil {
                firstDeltaAt = Date()
                recordTiming("first_delta")
            }
            updateHandler?(currentText, false)
        case "conversation.item.input_audio_transcription.completed":
            accumulator.complete(event.transcript ?? "", itemID: event.itemID)
            currentText = accumulator.text
            receivedCompleted = true
            updateHandler?(currentText, true)
        case "conversation.item.input_audio_transcription.failed", "error":
            Logger.speechToText.error("OpenAI realtime server error: \(event.error?.message ?? "unknown", privacy: .public)")
            fail(.serverError)
        default:
            break
        }
    }

    private func drainAudioQueue() {
        guard audioDrainTask == nil else { return }
        audioDrainTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.sendQueue.isEmpty {
                let chunk = self.sendQueue.removeFirst()
                do {
                    try await self.sendEvent([
                        "type": "input_audio_buffer.append",
                        "audio": chunk.base64EncodedString()
                    ])
                } catch {
                    self.fail(.transportError)
                    return
                }
            }
            self.audioDrainTask = nil
        }
    }

    private func waitForAudioDrain() async {
        while audioDrainTask != nil { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func sendEvent(_ event: [String: Any]) async throws {
        guard let transport else { throw RealtimeTranscriptionFailure.transportError }
        let data = try JSONSerialization.data(withJSONObject: event)
        guard let text = String(data: data, encoding: .utf8) else { throw RealtimeTranscriptionFailure.transportError }
        try await transport.send(text: text)
    }

    private func decode(_ message: RealtimeSocketMessage) throws -> OpenAIRealtimeServerEvent {
        let data: Data
        switch message {
        case .text(let text): data = Data(text.utf8)
        case .data(let messageData): data = messageData
        }
        return try JSONDecoder().decode(OpenAIRealtimeServerEvent.self, from: data)
    }

    private func transition(to newState: RealtimeTranscriptionState) {
        state = newState
        Task { await RealtimeDiagnostics.shared.record("state", fields: ["value": "\(newState)"]) }
        switch newState {
        case .connecting:
            updateHandler?(L10n.Recording.realtimeConnecting, false)
        case .ready:
            recordTiming("handshake")
            if currentText.isEmpty {
                updateHandler?(L10n.Recording.realtimeListening, false)
            }
        case .finalizing:
            recordTiming("finalize")
        case .failed(let failure) where failure != .cancelled:
            updateHandler?(L10n.Recording.realtimeUnavailableWhileRecording, false)
        default:
            break
        }
    }

    private func fail(_ failure: RealtimeTranscriptionFailure) {
        guard state != .completed, !receivedCompleted else { return }
        transition(to: .failed(failure))
        Task { await RealtimeDiagnostics.shared.record("fallback", fields: ["reason": failure.rawValue]) }
        closeTransport()
    }

    private func cancel(setCancelledState: Bool) {
        startTask?.cancel()
        startTask = nil
        audioDrainTask?.cancel()
        audioDrainTask = nil
        if setCancelledState, state != .idle, state != .completed {
            transition(to: .failed(.cancelled))
        }
        closeTransport()
        startupAudio.removeAll()
        startupAudioBytes = 0
        sendQueue.removeAll()
        updateHandler = nil
        if !setCancelledState || state == .completed { state = .idle }
    }

    private func closeTransport() {
        receiveTask?.cancel()
        receiveTask = nil
        transport?.close()
        transport = nil
    }

    private func recordTiming(_ event: String) {
        guard let startedAt else { return }
        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        Task { await RealtimeDiagnostics.shared.record(event, fields: ["milliseconds": "\(milliseconds)"]) }
    }

    private func recordCompletion() {
        recordTiming("completed")
        Task {
            await RealtimeDiagnostics.shared.record(
                "result",
                fields: ["model": settingsStore.openAIRealtimeTranscriptionModel, "fallback": "false"]
            )
        }
    }
}
