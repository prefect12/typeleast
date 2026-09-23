import Foundation
import XCTest
@testable import Typeleast

private final class MockRealtimeSocketTransport: RealtimeSocketTransport, @unchecked Sendable {
    private enum MockFailure: Error { case disconnected }

    private let lock = NSLock()
    private var messages: [RealtimeSocketMessage]
    private let failWhenMessagesExhausted: Bool
    private let sendDelayMilliseconds: Int
    private(set) var sentTexts: [String] = []
    private(set) var didConnect = false
    private(set) var didClose = false

    init(
        messages: [RealtimeSocketMessage],
        failWhenMessagesExhausted: Bool = false,
        sendDelayMilliseconds: Int = 0
    ) {
        self.messages = messages
        self.failWhenMessagesExhausted = failWhenMessagesExhausted
        self.sendDelayMilliseconds = sendDelayMilliseconds
    }

    func connect() {
        lock.withLock { didConnect = true }
    }

    private var failsSends = false

    func send(text: String) async throws {
        if sendDelayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(sendDelayMilliseconds))
        }
        if lock.withLock({ failsSends }) { throw MockFailure.disconnected }
        lock.withLock { sentTexts.append(text) }
    }

    func failSubsequentSends() {
        lock.withLock { failsSends = true }
    }

    func receive() async throws -> RealtimeSocketMessage {
        while !Task.isCancelled {
            if let message = lock.withLock({ messages.isEmpty ? nil : messages.removeFirst() }) {
                return message
            }
            if failWhenMessagesExhausted { throw MockFailure.disconnected }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CancellationError()
    }

    func close() { lock.withLock { didClose = true } }

    func enqueue(_ message: RealtimeSocketMessage) {
        lock.withLock { messages.append(message) }
    }

    func sentEventTypes() -> [String] {
        lock.withLock {
            sentTexts.compactMap { text in
                guard let data = text.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return object["type"] as? String
            }
        }
    }

    func sentAudioPayloads() -> [String] {
        lock.withLock {
            sentTexts.compactMap { text in
                guard let data = text.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["type"] as? String == "input_audio_buffer.append" else { return nil }
                return object["audio"] as? String
            }
        }
    }
}

/// Hands out a fresh scripted transport for each connection the transcriber opens.
private final class TransportQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [MockRealtimeSocketTransport]
    private(set) var createdCount = 0

    init(_ transports: [MockRealtimeSocketTransport]) {
        pending = transports
    }

    func next() -> any RealtimeSocketTransport {
        lock.withLock {
            createdCount += 1
            return pending.removeFirst()
        }
    }
}

/// Mirrors URLSessionWebSocketTask: a pending receive ignores task cancellation and only
/// returns once the socket is closed.
private final class CancellationIgnoringSocketTransport: RealtimeSocketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingReceive: CheckedContinuation<RealtimeSocketMessage, Error>?
    private var isClosed = false

    func connect() {}

    func send(text: String) async throws {}

    func receive() async throws -> RealtimeSocketMessage {
        try await withCheckedThrowingContinuation { continuation in
            let alreadyClosed = lock.withLock { () -> Bool in
                if isClosed { return true }
                pendingReceive = continuation
                return false
            }
            if alreadyClosed { continuation.resume(throwing: URLError(.cancelled)) }
        }
    }

    func close() {
        let pending = lock.withLock { () -> CheckedContinuation<RealtimeSocketMessage, Error>? in
            isClosed = true
            defer { pendingReceive = nil }
            return pendingReceive
        }
        pending?.resume(throwing: URLError(.cancelled))
    }
}

@MainActor
final class OpenAIRealtimeTranscriberTests: XCTestCase {
    private static let sessionCreated = RealtimeSocketMessage.text(#"{"type":"session.created"}"#)
    private static let sessionUpdated = RealtimeSocketMessage.text(#"{"type":"session.updated"}"#)

    private static func delta(_ text: String) -> RealtimeSocketMessage {
        .text(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"1","delta":"\#(text)"}"#)
    }

    private static func completed(_ text: String) -> RealtimeSocketMessage {
        .text(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"1","transcript":"\#(text)"}"#)
    }

    func testAccumulatorReplacesCompletedSegmentAndPreservesOrder() {
        var accumulator = RealtimeTranscriptAccumulator()
        accumulator.appendDelta("你", itemID: "a")
        accumulator.appendDelta("好", itemID: "a")
        accumulator.appendDelta("world", itemID: "b")
        XCTAssertEqual(accumulator.text, "你好 world")

        accumulator.complete("你好。", itemID: "a")
        accumulator.complete("world!", itemID: "b")
        XCTAssertEqual(accumulator.text, "你好。 world!")
    }

    func testHandshakeBuffersAudioAndFinishCommitsOnce() async throws {
        let transport = MockRealtimeSocketTransport(
            messages: [
                .text(#"{"type":"session.created"}"#),
                .text(#"{"type":"session.updated"}"#),
                .text(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"1","delta":"中英 "}"#),
                .text(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"1","transcript":"中英 test"}"#)
            ],
            failWhenMessagesExhausted: true,
            sendDelayMilliseconds: 10
        )
        let keychain = MockKeychainService()
        try keychain.save("test-key", service: AppIdentity.keychainService, account: "OpenAI")
        let transcriber = OpenAIRealtimeTranscriber(
            keychainService: keychain,
            transportFactory: { _ in transport }
        )

        var updates: [String] = []
        transcriber.start(language: .chineseEnglish) { text, _ in updates.append(text) }
        let chunks = [
            Data(repeating: 1, count: 1_600),
            Data(repeating: 2, count: 1_600),
            Data(repeating: 3, count: 1_600)
        ]
        chunks.forEach(transcriber.appendPCM16AudioData)
        let text = await transcriber.finish()

        XCTAssertEqual(text, "中英 test")
        XCTAssertEqual(transcriber.state, .completed)
        XCTAssertEqual(transport.sentEventTypes(), [
            "session.update",
            "input_audio_buffer.append",
            "input_audio_buffer.append",
            "input_audio_buffer.append",
            "input_audio_buffer.commit"
        ])
        XCTAssertEqual(transport.sentAudioPayloads(), chunks.map { $0.base64EncodedString() })
        XCTAssertTrue(updates.contains(L10n.Recording.realtimeConnecting))
        XCTAssertTrue(updates.contains(L10n.Recording.realtimeListening))
        XCTAssertEqual(updates.last, "中英 test")
    }

    func testHandshakeTimeoutReturnsNoRealtimeFinal() async throws {
        let transport = MockRealtimeSocketTransport(messages: [])
        let keychain = MockKeychainService()
        try keychain.save("test-key", service: AppIdentity.keychainService, account: "OpenAI")
        let transcriber = OpenAIRealtimeTranscriber(
            keychainService: keychain,
            handshakeTimeout: .milliseconds(40),
            transportFactory: { _ in transport }
        )

        var updates: [String] = []
        transcriber.start(language: .auto) { text, _ in updates.append(text) }
        let text = await transcriber.finish(timeout: .milliseconds(40))

        XCTAssertNil(text)
        XCTAssertEqual(transcriber.state, .failed(.handshakeTimeout))
        XCTAssertEqual(updates.last, L10n.Recording.realtimeUnavailableWhileRecording)
    }

    func testMixedLanguageSessionUsesChineseHintWithoutUnsupportedPrompt() async throws {
        let transport = MockRealtimeSocketTransport(messages: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#)
        ])
        let keychain = MockKeychainService()
        try keychain.save("test-key", service: AppIdentity.keychainService, account: "OpenAI")
        let transcriber = OpenAIRealtimeTranscriber(
            keychainService: keychain,
            transportFactory: { _ in transport }
        )

        transcriber.start(language: .chineseEnglish)
        try await Task.sleep(for: .milliseconds(30))
        transcriber.cancel()

        let sessionUpdate = try XCTUnwrap(transport.sentTexts.first)
        XCTAssertTrue(sessionUpdate.contains(#""language":"zh""#))
        XCTAssertTrue(sessionUpdate.contains("gpt-realtime-whisper"))
        XCTAssertTrue(sessionUpdate.contains(#""delay":"minimal""#))
        XCTAssertFalse(sessionUpdate.contains(#""prompt""#))
    }

    func testServerErrorFailsRealtimePath() async throws {
        let transport = MockRealtimeSocketTransport(messages: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#),
            .text(#"{"type":"error","error":{"message":"injected"}}"#)
        ])
        let transcriber = try makeTranscriber(transport: transport)

        transcriber.start(language: .auto)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(transcriber.state, .failed(.serverError))
        XCTAssertTrue(transport.didClose)
    }

    func testDisconnectFailsRealtimePath() async throws {
        let transport = MockRealtimeSocketTransport(
            messages: [
                .text(#"{"type":"session.created"}"#),
                .text(#"{"type":"session.updated"}"#)
            ],
            failWhenMessagesExhausted: true
        )
        let transcriber = try makeTranscriber(transport: transport)

        transcriber.start(language: .auto)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(transcriber.state, .failed(.transportError))
        XCTAssertTrue(transport.didClose)
    }

    func testCancelClosesTransportAndReportsCancelled() async throws {
        let transport = MockRealtimeSocketTransport(messages: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#)
        ])
        let transcriber = try makeTranscriber(transport: transport)

        transcriber.start(language: .auto)
        try await Task.sleep(for: .milliseconds(30))
        transcriber.cancel()

        XCTAssertEqual(transcriber.state, .failed(.cancelled))
        XCTAssertTrue(transport.didClose)
    }

    func testFinalTimeoutCommitsOnceThenReturnsNil() async throws {
        let transport = MockRealtimeSocketTransport(messages: [
            .text(#"{"type":"session.created"}"#),
            .text(#"{"type":"session.updated"}"#)
        ])
        let transcriber = try makeTranscriber(transport: transport)

        transcriber.start(language: .auto)
        transcriber.appendPCM16AudioData(Data(repeating: 4, count: 2_400))
        let text = await transcriber.finish(timeout: .milliseconds(60))

        XCTAssertNil(text)
        XCTAssertEqual(transcriber.state, .failed(.finalTimeout))
        XCTAssertEqual(transport.sentEventTypes().filter { $0 == "input_audio_buffer.commit" }.count, 1)
    }

    func testHandshakeTimeoutDoesNotWaitForUncancellableSocketReceive() async throws {
        let transport = CancellationIgnoringSocketTransport()
        let transcriber = try makeTranscriber(transport: transport, handshakeTimeout: .milliseconds(50))

        let startedAt = ContinuousClock().now
        transcriber.start(language: .chineseEnglish)
        transcriber.appendPCM16AudioData(Data(repeating: 1, count: 1_600))
        let text = await transcriber.finish(timeout: .milliseconds(50))
        let elapsed = startedAt.duration(to: ContinuousClock().now)

        XCTAssertNil(text)
        XCTAssertEqual(transcriber.state, .failed(.handshakeTimeout))
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    func testFinishKeepsWaitingWhileServerIsStillStreamingDeltas() async throws {
        let transport = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let transcriber = try makeTranscriber(transport: transport)

        transcriber.start(language: .auto)
        transcriber.appendPCM16AudioData(Data(repeating: 4, count: 2_400))
        let feeder = Task {
            for index in 0..<8 {
                try await Task.sleep(for: .milliseconds(30))
                transport.enqueue(Self.delta("w\(index) "))
            }
            transport.enqueue(Self.completed("streamed final"))
        }
        let text = await transcriber.finish(
            timeout: .milliseconds(60),
            maximumTimeout: .seconds(3),
            progressWindow: .milliseconds(300)
        )
        feeder.cancel()

        XCTAssertEqual(text, "streamed final")
        XCTAssertEqual(transcriber.state, .completed)
    }

    func testFinishStopsWaitingAtMaximumTimeoutEvenWhileDeltasArrive() async throws {
        let transport = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let transcriber = try makeTranscriber(transport: transport)

        transcriber.start(language: .auto)
        transcriber.appendPCM16AudioData(Data(repeating: 4, count: 2_400))
        let feeder = Task {
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(20))
                transport.enqueue(Self.delta("more "))
            }
        }
        let startedAt = ContinuousClock().now
        let text = await transcriber.finish(
            timeout: .milliseconds(40),
            maximumTimeout: .milliseconds(250),
            progressWindow: .milliseconds(200)
        )
        let elapsed = startedAt.duration(to: ContinuousClock().now)
        feeder.cancel()

        XCTAssertNil(text)
        XCTAssertEqual(transcriber.state, .failed(.finalTimeout))
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(250))
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    func testPrewarmedSessionIsAdoptedWithoutReconnecting() async throws {
        let transport = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let queue = TransportQueue([transport])
        let transcriber = try makeTranscriber(queue: queue)

        transcriber.prewarm(language: .chineseEnglish)
        try await waitUntil { transcriber.hasWarmSession }
        var updates: [String] = []
        transcriber.start(language: .chineseEnglish) { text, _ in updates.append(text) }

        XCTAssertEqual(transcriber.state, .streaming)
        XCTAssertFalse(updates.contains(L10n.Recording.realtimeConnecting))
        let chunk = Data(repeating: 7, count: 2_400)
        transcriber.appendPCM16AudioData(chunk)
        transport.enqueue(Self.completed("warm text"))
        let text = await transcriber.finish(timeout: .seconds(1))

        XCTAssertEqual(text, "warm text")
        XCTAssertEqual(queue.createdCount, 1)
        XCTAssertEqual(transport.sentEventTypes(), ["session.update", "input_audio_buffer.append", "input_audio_buffer.commit"])
        XCTAssertEqual(transport.sentAudioPayloads(), [chunk.base64EncodedString()])
    }

    func testCancelBeforeRecordingKeepsWarmSession() async throws {
        let transport = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let transcriber = try makeTranscriber(queue: TransportQueue([transport]))

        transcriber.prewarm(language: .auto)
        try await waitUntil { transcriber.hasWarmSession }
        transcriber.cancel()

        XCTAssertTrue(transcriber.hasWarmSession)
        XCTAssertFalse(transport.didClose)
    }

    func testWarmSessionForDifferentLanguageIsReplacedByFreshSession() async throws {
        let warm = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let fresh = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let queue = TransportQueue([warm, fresh])
        let transcriber = try makeTranscriber(queue: queue)

        transcriber.prewarm(language: .english)
        try await waitUntil { transcriber.hasWarmSession }
        transcriber.start(language: .chinese)
        try await waitUntil { transcriber.state == .streaming }

        XCTAssertEqual(queue.createdCount, 2)
        XCTAssertTrue(warm.didClose)
        XCTAssertFalse(transcriber.hasWarmSession)
        XCTAssertTrue(fresh.sentTexts.first?.contains(#""language":"zh""#) ?? false)
        transcriber.cancel()
    }

    func testWarmSessionThatDisconnectsWhileIdleIsDiscarded() async throws {
        let warm = MockRealtimeSocketTransport(
            messages: [Self.sessionCreated, Self.sessionUpdated],
            failWhenMessagesExhausted: true
        )
        let fresh = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let queue = TransportQueue([warm, fresh])
        let transcriber = try makeTranscriber(queue: queue)

        transcriber.prewarm(language: .auto)
        try await waitUntil { warm.didClose }
        XCTAssertFalse(transcriber.hasWarmSession)

        transcriber.start(language: .auto)
        try await waitUntil { transcriber.state == .streaming }
        XCTAssertEqual(queue.createdCount, 2)
        transcriber.cancel()
    }

    func testExpiredWarmSessionIsNotReused() async throws {
        let warm = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let fresh = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let queue = TransportQueue([warm, fresh])
        let transcriber = try makeTranscriber(queue: queue, warmSessionLifetime: .milliseconds(50))

        transcriber.prewarm(language: .auto)
        try await waitUntil { transcriber.hasWarmSession }
        try await Task.sleep(for: .milliseconds(120))
        transcriber.start(language: .auto)
        try await waitUntil { transcriber.state == .streaming }

        XCTAssertEqual(queue.createdCount, 2)
        XCTAssertTrue(warm.didClose)
        transcriber.cancel()
    }

    func testStartDuringPrewarmHandshakeWaitsForItInsteadOfReconnecting() async throws {
        let transport = MockRealtimeSocketTransport(
            messages: [Self.sessionCreated, Self.sessionUpdated],
            sendDelayMilliseconds: 50
        )
        let queue = TransportQueue([transport])
        let transcriber = try makeTranscriber(queue: queue)

        transcriber.prewarm(language: .auto)
        transcriber.start(language: .auto)
        XCTAssertEqual(transcriber.state, .connecting)
        let chunk = Data(repeating: 3, count: 1_600)
        transcriber.appendPCM16AudioData(chunk)
        try await waitUntil { transcriber.state == .streaming }
        try await waitUntil { transport.sentAudioPayloads().count == 1 }

        XCTAssertEqual(queue.createdCount, 1)
        XCTAssertEqual(transport.sentAudioPayloads(), [chunk.base64EncodedString()])
        transcriber.cancel()
    }

    func testAdoptedWarmSessionThatFailsBeforeTranscriptReconnectsAndReplaysAudio() async throws {
        let warm = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let fresh = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let queue = TransportQueue([warm, fresh])
        let transcriber = try makeTranscriber(queue: queue)

        transcriber.prewarm(language: .auto)
        try await waitUntil { transcriber.hasWarmSession }
        warm.failSubsequentSends()
        transcriber.start(language: .auto)
        let chunks = [Data(repeating: 1, count: 1_600), Data(repeating: 2, count: 1_600)]
        chunks.forEach(transcriber.appendPCM16AudioData)
        try await waitUntil { fresh.sentAudioPayloads().count == 2 }
        fresh.enqueue(Self.completed("recovered"))
        let text = await transcriber.finish(timeout: .seconds(1))

        XCTAssertEqual(text, "recovered")
        XCTAssertEqual(queue.createdCount, 2)
        XCTAssertTrue(warm.didClose)
        XCTAssertEqual(fresh.sentAudioPayloads(), chunks.map { $0.base64EncodedString() })
    }

    func testWarmSessionEventsReportReadyAndIdleLoss() async throws {
        let warm = MockRealtimeSocketTransport(
            messages: [Self.sessionCreated, Self.sessionUpdated],
            failWhenMessagesExhausted: true
        )
        let transcriber = try makeTranscriber(queue: TransportQueue([warm]))
        var events: [WarmSessionEvent] = []
        transcriber.warmSessionEventHandler = { events.append($0) }

        transcriber.prewarm(language: .auto)
        try await waitUntil { events.count == 2 }

        XCTAssertEqual(events, [.ready, .lost(reason: "disconnected")])
    }

    func testWarmSessionEventReportsExpiry() async throws {
        let warm = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let keychain = MockKeychainService()
        try keychain.save("test-key", service: AppIdentity.keychainService, account: "OpenAI")
        let queue = TransportQueue([warm])
        let transcriber = OpenAIRealtimeTranscriber(
            keychainService: keychain,
            warmSessionLifetime: .milliseconds(30),
            keepAliveInterval: .milliseconds(20),
            transportFactory: { _ in queue.next() }
        )
        var events: [WarmSessionEvent] = []
        transcriber.warmSessionEventHandler = { events.append($0) }

        transcriber.prewarm(language: .auto)
        try await waitUntil { events.count == 2 }

        XCTAssertEqual(events, [.ready, .lost(reason: "expired")])
        XCTAssertTrue(warm.didClose)
    }

    func testWarmSessionEventReportsFailedPrewarm() async throws {
        let keychain = MockKeychainService()
        try keychain.save("test-key", service: AppIdentity.keychainService, account: "OpenAI")
        let transport = CancellationIgnoringSocketTransport()
        let transcriber = OpenAIRealtimeTranscriber(
            keychainService: keychain,
            handshakeTimeout: .milliseconds(40),
            transportFactory: { _ in transport }
        )
        var events: [WarmSessionEvent] = []
        transcriber.warmSessionEventHandler = { events.append($0) }

        transcriber.prewarm(language: .auto)
        try await waitUntil { !events.isEmpty }

        XCTAssertEqual(events, [.prewarmFailed])
        XCTAssertFalse(transcriber.hasWarmSession)
    }

    func testAdoptingWarmSessionDoesNotReportLoss() async throws {
        let warm = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let transcriber = try makeTranscriber(queue: TransportQueue([warm]))
        var events: [WarmSessionEvent] = []
        transcriber.warmSessionEventHandler = { events.append($0) }

        transcriber.prewarm(language: .auto)
        try await waitUntil { transcriber.hasWarmSession }
        transcriber.start(language: .auto)
        transcriber.cancel()

        XCTAssertEqual(events, [.ready])
    }

    func testContextualProfileRefreshesPromptRightBeforeCommit() async throws {
        let transport = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let keychain = MockKeychainService()
        try keychain.save("test-key", service: AppIdentity.keychainService, account: "OpenAI")
        var prompt = "第一版上下文"
        let transcriber = OpenAIRealtimeTranscriber(
            keychainService: keychain,
            profile: .contextual(prompt: { prompt }),
            transportFactory: { _ in transport }
        )

        transcriber.start(language: .chineseEnglish)
        try await waitUntil { transcriber.state == .streaming }
        transcriber.appendPCM16AudioData(Data(repeating: 1, count: 1_600))
        prompt = "最新上下文"
        transport.enqueue(Self.completed("这个campaign的数据"))
        let text = await transcriber.finish(timeout: .seconds(1))

        XCTAssertEqual(text, "这个campaign的数据")
        XCTAssertEqual(transport.sentEventTypes(), [
            "session.update", "input_audio_buffer.append", "session.update", "input_audio_buffer.commit"
        ])
        let updates = transport.sentTexts.filter { $0.contains("session.update") }
        XCTAssertTrue(updates[0].contains("第一版上下文"))
        XCTAssertTrue(updates[1].contains("最新上下文"))
        XCTAssertTrue(updates[1].contains(AppDefaults.contextualTranscriptionModel))
        XCTAssertFalse(updates[1].contains("delay"))
    }

    func testSupersededFinishDoesNotFailTheNextSession() async throws {
        let first = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let second = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let transcriber = try makeTranscriber(queue: TransportQueue([first, second]))

        transcriber.start(language: .auto)
        try await waitUntil { transcriber.state == .streaming }
        let supersededFinish = Task {
            await transcriber.finish(timeout: .milliseconds(150), maximumTimeout: .milliseconds(200))
        }
        try await waitUntil { transcriber.state == .finalizing }
        transcriber.start(language: .auto)
        try await waitUntil { transcriber.state == .streaming }
        let supersededResult = await supersededFinish.value
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertNil(supersededResult)
        XCTAssertEqual(transcriber.state, .streaming)
        transcriber.cancel()
    }

    func testEmptyCompletedTranscriptMeansNoSpeechAndReturnsImmediately() async throws {
        let transport = MockRealtimeSocketTransport(messages: [Self.sessionCreated, Self.sessionUpdated])
        let transcriber = try makeTranscriber(transport: transport)

        transcriber.start(language: .auto)
        transcriber.appendPCM16AudioData(Data(repeating: 0, count: 2_400))
        transport.enqueue(Self.completed(""))
        let startedAt = ContinuousClock().now
        let text = await transcriber.finish(timeout: .seconds(2))

        XCTAssertEqual(text, "")
        XCTAssertEqual(transcriber.state, .completed)
        XCTAssertLessThan(startedAt.duration(to: ContinuousClock().now), .seconds(1))
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock().now.advanced(by: timeout)
        while !condition() {
            guard ContinuousClock().now < deadline else {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeTranscriber(
        queue: TransportQueue,
        warmSessionLifetime: Duration = .seconds(600)
    ) throws -> OpenAIRealtimeTranscriber {
        let keychain = MockKeychainService()
        try keychain.save("test-key", service: AppIdentity.keychainService, account: "OpenAI")
        return OpenAIRealtimeTranscriber(
            keychainService: keychain,
            warmSessionLifetime: warmSessionLifetime,
            transportFactory: { _ in queue.next() }
        )
    }

    private func makeTranscriber(
        transport: any RealtimeSocketTransport,
        handshakeTimeout: Duration = .seconds(5)
    ) throws -> OpenAIRealtimeTranscriber {
        let keychain = MockKeychainService()
        try keychain.save("test-key", service: AppIdentity.keychainService, account: "OpenAI")
        return OpenAIRealtimeTranscriber(
            keychainService: keychain,
            handshakeTimeout: handshakeTimeout,
            transportFactory: { _ in transport }
        )
    }
}
