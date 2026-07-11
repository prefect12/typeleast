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

    func send(text: String) async throws {
        if sendDelayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(sendDelayMilliseconds))
        }
        lock.withLock { sentTexts.append(text) }
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

@MainActor
final class OpenAIRealtimeTranscriberTests: XCTestCase {
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

    func testMixedLanguageSessionDoesNotSendLanguageHint() async throws {
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
        XCTAssertFalse(sessionUpdate.contains(#""language""#))
        XCTAssertTrue(sessionUpdate.contains("gpt-realtime-whisper"))
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

    private func makeTranscriber(
        transport: MockRealtimeSocketTransport
    ) throws -> OpenAIRealtimeTranscriber {
        let keychain = MockKeychainService()
        try keychain.save("test-key", service: AppIdentity.keychainService, account: "OpenAI")
        return OpenAIRealtimeTranscriber(
            keychainService: keychain,
            transportFactory: { _ in transport }
        )
    }
}
