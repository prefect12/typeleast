import Foundation
import os.log

internal enum RealtimeTranscriptionFailure: String, Error, Equatable, Sendable {
    case handshakeTimeout
    case transportError
    case serverError
    case finalTimeout
    case cancelled
}

internal enum WarmSessionEvent: Equatable, Sendable {
    case ready
    /// A warm session died or aged out while idle.
    case lost(reason: String)
    case prewarmFailed
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
    func sendPing() async throws
    func close()
}

extension RealtimeSocketTransport {
    func sendPing() async throws {}
}

internal final class URLSessionRealtimeSocketTransport: RealtimeSocketTransport, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest, session: URLSession = .shared) {
        task = session.webSocketTask(with: request)
    }

    func connect() { task.resume() }

    func send(text: String) async throws { try await task.send(.string(text)) }

    func receive() async throws -> RealtimeSocketMessage {
        // URLSessionWebSocketTask.receive() ignores Swift task cancellation and would otherwise
        // stay suspended until URLSession's 60s request timeout fires.
        let message = try await withTaskCancellationHandler {
            try await task.receive()
        } onCancel: { [task] in
            task.cancel(with: .goingAway, reason: nil)
        }
        switch message {
        case .string(let text): return .text(text)
        case .data(let data): return .data(data)
        @unknown default: throw RealtimeTranscriptionFailure.transportError
        }
    }

    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
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

/// What a realtime transcription session is configured with.
internal struct RealtimeSessionProfile {
    /// Tags this session's diagnostics events; nil keeps the original untagged event stream.
    let diagnosticsLabel: String?
    let model: @MainActor (TranscriptionSettingsReadable) -> String
    let usesMinimalDelay: Bool
    /// Refreshed right before each commit, so a reused warm session still gets current context.
    let prompt: (@MainActor () -> String?)?

    static let live = RealtimeSessionProfile(
        diagnosticsLabel: nil,
        model: { $0.openAIRealtimeTranscriptionModel },
        usesMinimalDelay: true,
        prompt: nil
    )

    static func contextual(prompt: @escaping @MainActor () -> String?) -> RealtimeSessionProfile {
        RealtimeSessionProfile(
            diagnosticsLabel: "contextual",
            model: { _ in AppDefaults.contextualTranscriptionModel },
            usesMinimalDelay: false,
            prompt: prompt
        )
    }
}

@MainActor
internal final class OpenAIRealtimeTranscriber: ObservableObject {
    typealias UpdateHandler = @MainActor (_ text: String, _ isFinal: Bool) -> Void
    typealias TransportFactory = @Sendable (URLRequest) -> any RealtimeSocketTransport
    typealias WarmSessionEventHandler = @MainActor (WarmSessionEvent) -> Void

    /// A connected, configured session waiting for the next recording.
    private struct WarmSession {
        let transport: any RealtimeSocketTransport
        let configuration: String
        let expiresAt: ContinuousClock.Instant
        var lastAliveAt: ContinuousClock.Instant
        let receiveTask: Task<Void, Never>
        var keepAliveTask: Task<Void, Never>?
    }

    @Published private(set) var currentText = ""
    @Published private(set) var state: RealtimeTranscriptionState = .idle
    var warmSessionEventHandler: WarmSessionEventHandler?

    private let keychainService: KeychainServiceProtocol
    private let settingsStore: TranscriptionSettingsReadable
    private let profile: RealtimeSessionProfile
    private let transportFactory: TransportFactory
    private let handshakeTimeout: Duration
    private let warmSessionLifetime: Duration
    private let keepAliveInterval: Duration
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
    private var lastDeltaAt: ContinuousClock.Instant?
    private var sessionGeneration = 0
    private var activeLanguage: TranscriptionLanguage = .auto
    private var warmSession: WarmSession?
    private var prewarmTask: Task<Void, Never>?
    private var prewarmConfiguration: String?
    private var isUsingWarmSession = false
    private var didRetryWarmSession = false
    private var warmReplayAudio: [Data] = []
    private var warmReplayBytes = 0
    private let maximumStartupAudioBytes = Int(RealtimeAudioPCMConverter.sampleRate * 5) * RealtimeAudioPCMConverter.bytesPerFrame

    init(
        keychainService: KeychainServiceProtocol = KeychainService.shared,
        settingsStore: TranscriptionSettingsReadable = TranscriptionSettingsStore.shared,
        profile: RealtimeSessionProfile = .live,
        handshakeTimeout: Duration = .seconds(5),
        warmSessionLifetime: Duration = .seconds(300),
        keepAliveInterval: Duration = .seconds(15),
        transportFactory: @escaping TransportFactory = { URLSessionRealtimeSocketTransport(request: $0) }
    ) {
        self.keychainService = keychainService
        self.settingsStore = settingsStore
        self.profile = profile
        self.handshakeTimeout = handshakeTimeout
        self.warmSessionLifetime = warmSessionLifetime
        self.keepAliveInterval = keepAliveInterval
        self.transportFactory = transportFactory
    }

    var hasWarmSession: Bool { warmSession != nil }
    var isFinalizing: Bool { state == .finalizing }

    func start(language: TranscriptionLanguage, updateHandler: UpdateHandler? = nil) {
        cancel(setCancelledState: false)
        currentText = ""
        accumulator = RealtimeTranscriptAccumulator()
        receivedCompleted = false
        startedAt = Date()
        firstDeltaAt = nil
        lastDeltaAt = nil
        activeLanguage = language
        didRetryWarmSession = false
        self.updateHandler = updateHandler

        let configuration = sessionConfiguration(for: language)
        if let configuration, let warm = takeWarmSession(configuration: configuration) {
            adopt(warm)
            return
        }

        transition(to: .connecting)
        let pendingPrewarm = configuration != nil && prewarmConfiguration == configuration ? prewarmTask : nil
        startTask = makeStartTask(language: language, configuration: configuration, pendingPrewarm: pendingPrewarm)
    }

    /// Opens and configures a session ahead of time so the next recording streams immediately
    /// instead of paying the ~2-3s connect and session setup after the hotkey is pressed.
    func prewarm(language: TranscriptionLanguage) {
        switch state {
        case .idle, .completed, .failed: break
        case .connecting, .ready, .streaming, .finalizing: return
        }
        guard prewarmTask == nil,
              let configuration = sessionConfiguration(for: language),
              let request = try? makeSessionRequest() else { return }
        if let warmSession {
            if warmSession.configuration == configuration, isUsable(warmSession) { return }
            discardWarmSession(reason: "replaced")
        }

        let socket = transportFactory(request)
        let startedAt = ContinuousClock().now
        prewarmConfiguration = configuration
        prewarmTask = Task { [weak self] in
            guard let self else {
                socket.close()
                return
            }
            defer {
                self.prewarmTask = nil
                self.prewarmConfiguration = nil
            }
            do {
                socket.connect()
                try await self.performHandshake(on: socket, language: language)
                self.installWarmSession(socket, configuration: configuration)
                let milliseconds = Int(startedAt.duration(to: ContinuousClock().now) / .milliseconds(1))
                diagnose("prewarm", ["milliseconds": "\(milliseconds)"])
                self.warmSessionEventHandler?(.ready)
            } catch {
                socket.close()
                let reason = (error as? RealtimeTranscriptionFailure)?.rawValue ?? error.localizedDescription
                diagnose("prewarm_failed", ["reason": reason])
                self.warmSessionEventHandler?(.prewarmFailed)
            }
        }
    }

    func discardWarmSession() { discardWarmSession(reason: "requested") }

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
            rememberForWarmSessionReplay(data)
            sendQueue.append(data)
            drainAudioQueue()
        case .idle, .finalizing, .completed, .failed:
            break
        }
    }

    /// Commits the buffered audio and waits for the final transcript.
    ///
    /// Gives up after `timeout` unless the server is still streaming deltas, in which case it keeps
    /// waiting (up to `maximumTimeout`) instead of discarding a transcript that is about to complete
    /// and re-uploading the whole recording for batch transcription.
    func finish(
        timeout: Duration = .milliseconds(2_500),
        maximumTimeout: Duration = .seconds(5),
        progressWindow: Duration = .seconds(1)
    ) async -> String? {
        let generation = sessionGeneration
        await startTask?.value
        guard sessionGeneration == generation else { return nil }
        startTask = nil
        guard state == .ready || state == .streaming else { return nil }

        transition(to: .finalizing)
        await waitForAudioDrain()
        guard sessionGeneration == generation else { return nil }
        do {
            if profile.prompt != nil, let transport {
                // Events on one socket are applied in order, so the commit below is transcribed
                // with this context even though the session may have been prewarmed long ago.
                try await sendSessionUpdate(language: activeLanguage, on: transport)
            }
            try await sendEvent(["type": "input_audio_buffer.commit"])
        } catch {
            guard sessionGeneration == generation else { return nil }
            fail(.transportError)
            return nil
        }

        let clock = ContinuousClock()
        let commitAt = clock.now
        while true {
            // A newer recording took over this transcriber; its state is no longer ours to judge.
            guard sessionGeneration == generation else { return nil }
            if receivedCompleted {
                // An empty completed transcript is the server saying "no speech", not a failure:
                // return "" right away instead of timing out into a fallback that may invent text.
                transition(to: .completed)
                recordCompletion()
                closeTransport()
                return SpeechToTextService.cleanTranscriptionText(currentText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if case .failed = state { return nil }

            let now = clock.now
            let waited = commitAt.duration(to: now)
            let isStillTranscribing = lastDeltaAt.map { $0.duration(to: now) < progressWindow } ?? false
            if waited >= maximumTimeout || (waited >= timeout && !isStillTranscribing) { break }
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

    // MARK: - Session setup

    private func makeStartTask(
        language: TranscriptionLanguage,
        configuration: String?,
        pendingPrewarm: Task<Void, Never>?
    ) -> Task<Void, Never> {
        let generation = sessionGeneration
        return Task { [weak self] in
            guard let self else { return }
            do {
                if let pendingPrewarm {
                    // A prewarm is already mid-handshake; finishing it beats starting over.
                    await pendingPrewarm.value
                    guard self.sessionGeneration == generation else { return }
                    if let configuration, let warm = self.takeWarmSession(configuration: configuration) {
                        self.adopt(warm)
                        return
                    }
                }
                try await self.establishSession(language: language, generation: generation)
            } catch {
                guard self.sessionGeneration == generation else { return }
                if let failure = error as? RealtimeTranscriptionFailure {
                    self.fail(failure)
                } else {
                    Logger.speechToText.error("OpenAI realtime start failed: \(error.localizedDescription, privacy: .public)")
                    self.fail(.transportError)
                }
            }
        }
    }

    private func establishSession(language: TranscriptionLanguage, generation: Int) async throws {
        let socket = transportFactory(try makeSessionRequest())
        transport = socket
        socket.connect()
        try await performHandshake(on: socket, language: language)
        guard sessionGeneration == generation, transport === socket else {
            socket.close()
            return
        }

        receiveTask = startReceiveLoop(on: socket)
        beginStreaming()
    }

    private func adopt(_ warm: WarmSession) {
        transport = warm.transport
        receiveTask = warm.receiveTask
        isUsingWarmSession = true
        diagnose("warm_session_adopted")
        beginStreaming()
    }

    private func beginStreaming() {
        transition(to: .ready)
        sendQueue.append(contentsOf: startupAudio)
        startupAudio.forEach(rememberForWarmSessionReplay)
        startupAudio.removeAll(keepingCapacity: false)
        startupAudioBytes = 0
        drainAudioQueue()
        transition(to: .streaming)
    }

    private func makeSessionRequest() throws -> URLRequest {
        guard let apiKey = keychainService.getQuietly(service: AppIdentity.keychainService, account: "OpenAI") else {
            throw SpeechToTextError.apiKeyMissing("OpenAI")
        }
        var request = URLRequest(url: try Self.transcriptionSessionURL())
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Identifies everything baked into a session at setup, so a warm session is only reused
    /// when it matches the current model, language and API key.
    private func sessionConfiguration(for language: TranscriptionLanguage) -> String? {
        guard let apiKey = keychainService.getQuietly(service: AppIdentity.keychainService, account: "OpenAI") else {
            return nil
        }
        return [
            profile.model(settingsStore),
            language.openAIRealtimeLanguageHint ?? "",
            String(apiKey.hashValue)
        ].joined(separator: "|")
    }

    private func performHandshake(on socket: any RealtimeSocketTransport, language: TranscriptionLanguage) async throws {
        let deadline = ContinuousClock().now.advanced(by: handshakeTimeout)
        try await receiveUntil("session.created", on: socket, deadline: deadline)
        try await sendSessionUpdate(language: language, on: socket)
        try await receiveUntil("session.updated", on: socket, deadline: deadline)
    }

    private func sendSessionUpdate(language: TranscriptionLanguage, on socket: any RealtimeSocketTransport) async throws {
        var transcription: [String: Any] = ["model": profile.model(settingsStore)]
        if profile.usesMinimalDelay { transcription["delay"] = "minimal" }
        if let hint = language.openAIRealtimeLanguageHint { transcription["language"] = hint }
        if let prompt = profile.prompt?(), !prompt.isEmpty { transcription["prompt"] = prompt }

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
        ], on: socket)
    }

    private func receiveUntil(
        _ expectedType: String,
        on socket: any RealtimeSocketTransport,
        deadline: ContinuousClock.Instant
    ) async throws {
        while ContinuousClock().now < deadline {
            let remaining = ContinuousClock().now.duration(to: deadline)
            let message = try await receiveWithTimeout(remaining, on: socket)
            let event = try decode(message)
            if event.type == expectedType { return }
            if event.type == "error" {
                Logger.speechToText.error("OpenAI realtime handshake error: \(event.error?.message ?? "unknown", privacy: .public)")
                throw RealtimeTranscriptionFailure.serverError
            }
        }
        throw RealtimeTranscriptionFailure.handshakeTimeout
    }

    private func receiveWithTimeout(
        _ timeout: Duration,
        on socket: any RealtimeSocketTransport
    ) async throws -> RealtimeSocketMessage {
        let deadline = ContinuousClock().now.advanced(by: timeout)
        do {
            return try await withThrowingTaskGroup(of: RealtimeSocketMessage.self) { group in
                group.addTask { try await socket.receive() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    // The group waits for every child before rethrowing, so unblock the pending
                    // receive now instead of relying on the transport honouring cancellation.
                    socket.close()
                    throw RealtimeTranscriptionFailure.handshakeTimeout
                }
                guard let first = try await group.next() else { throw RealtimeTranscriptionFailure.transportError }
                group.cancelAll()
                return first
            }
        } catch {
            // Closing the socket on timeout makes the receive fail too; report the root cause.
            if ContinuousClock().now >= deadline { throw RealtimeTranscriptionFailure.handshakeTimeout }
            throw error
        }
    }

    // MARK: - Warm sessions

    private func installWarmSession(_ socket: any RealtimeSocketTransport, configuration: String) {
        let now = ContinuousClock().now
        warmSession = WarmSession(
            transport: socket,
            configuration: configuration,
            expiresAt: now.advanced(by: warmSessionLifetime),
            lastAliveAt: now,
            receiveTask: startReceiveLoop(on: socket),
            keepAliveTask: nil
        )
        warmSession?.keepAliveTask = startKeepAlive(for: socket)
    }

    private func takeWarmSession(configuration: String) -> WarmSession? {
        guard let warm = warmSession else { return nil }
        guard warm.configuration == configuration, isUsable(warm) else {
            discardWarmSession(reason: warm.configuration == configuration ? "stale" : "configuration_changed")
            return nil
        }
        warm.keepAliveTask?.cancel()
        warmSession = nil
        return warm
    }

    /// A socket that has not answered a ping recently (for example across sleep, which
    /// ContinuousClock counts) is treated as dead rather than risking a failed recording.
    private func isUsable(_ warm: WarmSession) -> Bool {
        let now = ContinuousClock().now
        return now < warm.expiresAt && warm.lastAliveAt.duration(to: now) < keepAliveInterval * 2 + .seconds(10)
    }

    private func startKeepAlive(for socket: any RealtimeSocketTransport) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.keepAliveInterval ?? .seconds(15))
                guard !Task.isCancelled,
                      let self,
                      let warm = self.warmSession,
                      warm.transport === socket else { return }
                guard ContinuousClock().now < warm.expiresAt else {
                    self.discardWarmSession(reason: "expired")
                    return
                }
                // Ping off the loop so a pong that never arrives can't stall the expiry checks.
                Task { [weak self] in
                    do {
                        try await socket.sendPing()
                        guard let self, self.warmSession?.transport === socket else { return }
                        self.warmSession?.lastAliveAt = ContinuousClock().now
                    } catch {
                        self?.discardWarmSession(ifUsing: socket, reason: "ping_failed")
                    }
                }
            }
        }
    }

    private func discardWarmSession(ifUsing socket: any RealtimeSocketTransport, reason: String) {
        guard warmSession?.transport === socket else { return }
        discardWarmSession(reason: reason)
    }

    private func discardWarmSession(reason: String) {
        guard let warm = warmSession else { return }
        warmSession = nil
        warm.keepAliveTask?.cancel()
        warm.receiveTask.cancel()
        warm.transport.close()
        diagnose("warm_session_discarded", ["reason": reason])
        // Discards made while starting or replacing a session are followed by a fresh prewarm anyway.
        if Self.idleLossReasons.contains(reason) {
            warmSessionEventHandler?(.lost(reason: reason))
        }
    }

    private static let idleLossReasons: Set<String> = ["expired", "ping_failed", "disconnected", "server_error"]

    private func rememberForWarmSessionReplay(_ data: Data) {
        guard isUsingWarmSession, firstDeltaAt == nil else { return }
        warmReplayBytes += data.count
        if warmReplayBytes <= maximumStartupAudioBytes { warmReplayAudio.append(data) }
    }

    /// A reused socket can have died quietly since its last ping. If it fails before producing
    /// any transcript, reconnect once and replay the audio instead of falling back to batch.
    private func retryWarmSessionIfPossible(after failure: RealtimeTranscriptionFailure) -> Bool {
        guard isUsingWarmSession,
              !didRetryWarmSession,
              firstDeltaAt == nil,
              failure == .transportError || failure == .serverError,
              state == .ready || state == .streaming,
              warmReplayBytes <= maximumStartupAudioBytes else { return false }

        didRetryWarmSession = true
        isUsingWarmSession = false
        audioDrainTask?.cancel()
        audioDrainTask = nil
        closeTransport()
        sendQueue.removeAll()
        startupAudio = warmReplayAudio
        startupAudioBytes = warmReplayBytes
        warmReplayAudio.removeAll()
        warmReplayBytes = 0
        diagnose("warm_session_retry", ["reason": failure.rawValue])
        sessionGeneration += 1
        transition(to: .connecting)
        startTask = makeStartTask(language: activeLanguage, configuration: nil, pendingPrewarm: nil)
        return true
    }

    // MARK: - Streaming

    private func startReceiveLoop(on socket: any RealtimeSocketTransport) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                let message: RealtimeSocketMessage
                do {
                    message = try await socket.receive()
                } catch {
                    self?.socketDidFail(socket)
                    return
                }
                guard let self else { return }
                guard let event = try? self.decode(message) else {
                    self.socketDidFail(socket)
                    return
                }
                guard self.route(event, from: socket) else { return }
            }
        }
    }

    /// Returns whether the socket's receive loop should keep reading.
    private func route(_ event: OpenAIRealtimeServerEvent, from socket: any RealtimeSocketTransport) -> Bool {
        if let transport, transport === socket {
            handle(event)
            return !receivedCompleted
        }
        if warmSession?.transport === socket {
            guard event.type == "error" else { return true }
            discardWarmSession(reason: "server_error")
            return false
        }
        return false
    }

    private func socketDidFail(_ socket: any RealtimeSocketTransport) {
        if let transport, transport === socket {
            if state != .completed { fail(.transportError) }
        } else {
            discardWarmSession(ifUsing: socket, reason: "disconnected")
        }
    }

    private func handle(_ event: OpenAIRealtimeServerEvent) {
        switch event.type {
        case "conversation.item.input_audio_transcription.delta":
            guard let delta = event.delta, !delta.isEmpty else { return }
            accumulator.appendDelta(delta, itemID: event.itemID)
            currentText = accumulator.text
            lastDeltaAt = ContinuousClock().now
            if firstDeltaAt == nil {
                firstDeltaAt = Date()
                warmReplayAudio.removeAll()
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
                    guard !Task.isCancelled else { return }
                    self.fail(.transportError)
                    return
                }
            }
            guard !Task.isCancelled else { return }
            self.audioDrainTask = nil
        }
    }

    private func waitForAudioDrain() async {
        while audioDrainTask != nil { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func sendEvent(_ event: [String: Any]) async throws {
        guard let transport else { throw RealtimeTranscriptionFailure.transportError }
        try await sendEvent(event, on: transport)
    }

    private func sendEvent(_ event: [String: Any], on socket: any RealtimeSocketTransport) async throws {
        let data = try JSONSerialization.data(withJSONObject: event)
        guard let text = String(data: data, encoding: .utf8) else { throw RealtimeTranscriptionFailure.transportError }
        try await socket.send(text: text)
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
        diagnose("state", ["value": "\(newState)"])
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
        if case .failed = state { return }
        if retryWarmSessionIfPossible(after: failure) { return }
        transition(to: .failed(failure))
        diagnose("fallback", ["reason": failure.rawValue])
        closeTransport()
    }

    private func cancel(setCancelledState: Bool) {
        sessionGeneration += 1
        startTask?.cancel()
        startTask = nil
        audioDrainTask?.cancel()
        audioDrainTask = nil
        switch state {
        case .connecting, .ready, .streaming, .finalizing:
            if setCancelledState { transition(to: .failed(.cancelled)) }
        case .idle, .completed, .failed:
            break
        }
        closeTransport()
        startupAudio.removeAll()
        startupAudioBytes = 0
        sendQueue.removeAll()
        isUsingWarmSession = false
        warmReplayAudio.removeAll()
        warmReplayBytes = 0
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
        diagnose(event, ["milliseconds": "\(milliseconds)"])
    }

    private func recordCompletion() {
        recordTiming("completed")
        diagnose("result", ["model": profile.model(settingsStore), "fallback": "false"])
    }

    private func diagnose(_ event: String, _ fields: [String: String] = [:]) {
        var fields = fields
        if let label = profile.diagnosticsLabel { fields["session"] = label }
        Task { await RealtimeDiagnostics.shared.record(event, fields: fields) }
    }
}
