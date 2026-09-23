import AppKit
import XCTest
@testable import Typeleast

@MainActor
final class TranscriptionPipelineTests: XCTestCase {
    private var usageDefaultsSuite: String!
    private var sourceDefaultsSuite: String!
    private var audioURL: URL!
    private var clipboard: FakeClipboard!

    override func setUp() async throws {
        try await super.setUp()
        usageDefaultsSuite = "TranscriptionPipelineTests.usage.\(UUID().uuidString)"
        sourceDefaultsSuite = "TranscriptionPipelineTests.source.\(UUID().uuidString)"
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionPipelineTests-\(UUID().uuidString).wav")
        try Data([0x00, 0x01, 0x02]).write(to: audioURL)
        // The system pasteboard is shared by parallel test processes, so capture writes instead.
        clipboard = FakeClipboard()
    }

    override func tearDown() async throws {
        if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        if let usageDefaultsSuite {
            UserDefaults(suiteName: usageDefaultsSuite)?.removePersistentDomain(forName: usageDefaultsSuite)
        }
        if let sourceDefaultsSuite {
            UserDefaults(suiteName: sourceDefaultsSuite)?.removePersistentDomain(forName: sourceDefaultsSuite)
        }
        clipboard = nil
        audioURL = nil
        usageDefaultsSuite = nil
        sourceDefaultsSuite = nil
        try await super.tearDown()
    }

    func testRunCentralizesClipboardHistoryAndMetricsSideEffects() async throws {
        let speechService = FakeRawTranscriptionService(text: "Hello Typeleast")
        let dataManager = MockDataManager()
        let usageDefaults = try XCTUnwrap(UserDefaults(suiteName: usageDefaultsSuite))
        let sourceDefaults = try XCTUnwrap(UserDefaults(suiteName: sourceDefaultsSuite))
        let usageStore = UsageMetricsStore(defaults: usageDefaults)
        let sourceStore = SourceUsageStore(defaults: sourceDefaults)
        let settingsStore = FakeTranscriptionSettingsStore(
            provider: .openai,
            semanticCorrectionMode: .off,
            historyEnabled: true,
            openAIModel: "gpt-4o-transcribe"
        )
        let pipeline = TranscriptionPipeline(
            speechService: speechService,
            settingsStore: settingsStore,
            dataManager: dataManager,
            usageMetricsStore: usageStore,
            sourceUsageStore: sourceStore,
            clipboard: clipboard
        )

        let result = try await pipeline.run(
            TranscriptionPipelineRequest(
                audioURL: audioURL,
                provider: .openai,
                whisperModel: nil,
                openAIModelOverride: AppDefaults.highAccuracyEnglishTranscriptionModel,
                duration: 2.5,
                estimatedDuration: nil,
                sourceAppInfo: SourceAppInfo(
                    bundleIdentifier: "com.example.editor",
                    displayName: "Editor",
                    iconData: nil,
                    fallbackSymbolName: nil
                ),
                modelReadyTime: nil,
                processStart: Date()
            )
        )

        XCTAssertEqual(result.text, "Hello Typeleast")
        XCTAssertNotNil(result.savedRecordID)
        XCTAssertEqual(clipboard.contents, "Hello Typeleast")
        XCTAssertEqual(speechService.requests.map(\.provider), [.openai])
        XCTAssertEqual(
            speechService.requests.map(\.openAIModelOverride),
            [AppDefaults.highAccuracyEnglishTranscriptionModel]
        )
        XCTAssertEqual(usageStore.snapshot.totalSessions, 1)
        XCTAssertEqual(usageStore.snapshot.totalWords, 2)
        XCTAssertEqual(usageStore.snapshot.totalCharacters, 15)

        let records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Hello Typeleast")
        XCTAssertEqual(records.first?.modelUsed, "gpt-4o-transcribe")
        XCTAssertEqual(records.first?.sourceAppBundleId, "com.example.editor")

        let sourceStats = sourceStore.allSources()
        XCTAssertEqual(sourceStats.count, 1)
        XCTAssertEqual(sourceStats.first?.bundleIdentifier, "com.example.editor")
        XCTAssertEqual(sourceStats.first?.totalWords, 2)
    }

    func testRunSkipsHistoryWhenDisabledButKeepsUsageMetrics() async throws {
        let speechService = FakeRawTranscriptionService(text: "No history")
        let dataManager = MockDataManager()
        dataManager.isHistoryEnabled = false
        let usageDefaults = try XCTUnwrap(UserDefaults(suiteName: usageDefaultsSuite))
        let sourceDefaults = try XCTUnwrap(UserDefaults(suiteName: sourceDefaultsSuite))
        let usageStore = UsageMetricsStore(defaults: usageDefaults)
        let sourceStore = SourceUsageStore(defaults: sourceDefaults)
        let settingsStore = FakeTranscriptionSettingsStore(
            provider: .gemini,
            semanticCorrectionMode: .off,
            historyEnabled: false
        )
        let pipeline = TranscriptionPipeline(
            speechService: speechService,
            settingsStore: settingsStore,
            dataManager: dataManager,
            usageMetricsStore: usageStore,
            sourceUsageStore: sourceStore,
            clipboard: clipboard
        )

        let result = try await pipeline.run(
            TranscriptionPipelineRequest(
                audioURL: audioURL,
                provider: .gemini,
                whisperModel: nil,
                duration: nil,
                estimatedDuration: 1.0,
                sourceAppInfo: .unknown,
                modelReadyTime: nil,
                processStart: Date()
            )
        )

        XCTAssertNil(result.savedRecordID)
        let records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.count, 0)
        XCTAssertEqual(usageStore.snapshot.totalSessions, 1)
        XCTAssertEqual(sourceStore.allSources().first?.bundleIdentifier, SourceAppInfo.unknown.bundleIdentifier)
    }

    func testRunPretranscribedSkipsSpeechServiceButKeepsSideEffects() async throws {
        let speechService = FakeRawTranscriptionService(text: "Should not run")
        let dataManager = MockDataManager()
        let usageDefaults = try XCTUnwrap(UserDefaults(suiteName: usageDefaultsSuite))
        let sourceDefaults = try XCTUnwrap(UserDefaults(suiteName: sourceDefaultsSuite))
        let usageStore = UsageMetricsStore(defaults: usageDefaults)
        let sourceStore = SourceUsageStore(defaults: sourceDefaults)
        let settingsStore = FakeTranscriptionSettingsStore(
            provider: .openai,
            semanticCorrectionMode: .off,
            historyEnabled: true,
            openAIModel: "gpt-4o-transcribe"
        )
        let pipeline = TranscriptionPipeline(
            speechService: speechService,
            settingsStore: settingsStore,
            dataManager: dataManager,
            usageMetricsStore: usageStore,
            sourceUsageStore: sourceStore,
            clipboard: clipboard
        )

        let result = try await pipeline.runPretranscribed(
            TranscriptionPipelineRequest(
                audioURL: audioURL,
                provider: .openai,
                whisperModel: nil,
                duration: 1.5,
                estimatedDuration: nil,
                sourceAppInfo: SourceAppInfo(
                    bundleIdentifier: "com.example.chat",
                    displayName: "Chat",
                    iconData: nil,
                    fallbackSymbolName: nil
                ),
                modelReadyTime: nil,
                processStart: Date()
            ),
            rawText: "  Streamed Typeleast text  ",
            asrTime: 0.42
        )

        XCTAssertEqual(result.text, "Streamed Typeleast text")
        XCTAssertTrue(speechService.requests.isEmpty)
        XCTAssertEqual(clipboard.contents, "Streamed Typeleast text")
        XCTAssertEqual(usageStore.snapshot.totalSessions, 1)
        XCTAssertEqual(sourceStore.allSources().first?.bundleIdentifier, "com.example.chat")

        let records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Streamed Typeleast text")
        XCTAssertEqual(records.first?.asrTime ?? 0, 0.42, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(records.first?.transcriptionTime ?? 0, 0.42)
    }
}

/// Refinement tests share the pipeline fakes above but need no clipboard assertions, so they
/// capture clipboard writes with a throwaway fake.
@MainActor
final class TranscriptionPipelineRefiningTests: XCTestCase {
    private var usageDefaultsSuite: String!
    private var sourceDefaultsSuite: String!
    private var audioURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        usageDefaultsSuite = "TranscriptionPipelineRefiningTests.usage.\(UUID().uuidString)"
        sourceDefaultsSuite = "TranscriptionPipelineRefiningTests.source.\(UUID().uuidString)"
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionPipelineRefiningTests-\(UUID().uuidString).wav")
        try Data([0x00, 0x01, 0x02]).write(to: audioURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: audioURL)
        UserDefaults(suiteName: usageDefaultsSuite)?.removePersistentDomain(forName: usageDefaultsSuite)
        UserDefaults(suiteName: sourceDefaultsSuite)?.removePersistentDomain(forName: sourceDefaultsSuite)
        audioURL = nil
        usageDefaultsSuite = nil
        sourceDefaultsSuite = nil
        try await super.tearDown()
    }

    func testRunRefiningUsesBatchTextWhenItArrivesInTime() async throws {
        let speechService = ScriptedRawTranscriptionService(behavior: .text("Refined campaign text"))
        let dataManager = MockDataManager()
        let pipeline = try makePipeline(speechService: speechService, dataManager: dataManager)
        let request = makeRequest(provider: .openai, modelOverride: "gpt-4o-transcribe")

        let refinement = pipeline.startRawTranscription(
            audioURL: audioURL,
            provider: .openai,
            openAIModelOverride: "gpt-4o-transcribe"
        )
        let result = try await pipeline.runRefining(
            request,
            refinement: refinement,
            fallbackRequest: request.with(provider: .openAIRealtime),
            fallbackText: "realtime 康佩恩 text",
            fallbackASRTime: 0.3,
            timeout: 2
        )

        XCTAssertEqual(result.text, "Refined campaign text")
        XCTAssertEqual(speechService.requestedModelOverrides, ["gpt-4o-transcribe"])
        let records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.first?.provider, TranscriptionProvider.openai.rawValue)
        XCTAssertEqual(records.first?.modelUsed, "gpt-4o-transcribe")
    }

    func testRunRefiningFallsBackToStreamedTextWithoutWaitingForSlowBatch() async throws {
        let speechService = ScriptedRawTranscriptionService(behavior: .hang)
        let dataManager = MockDataManager()
        let pipeline = try makePipeline(speechService: speechService, dataManager: dataManager)
        let request = makeRequest(provider: .openai, modelOverride: "gpt-4o-transcribe")

        let startedAt = Date()
        let result = try await pipeline.runRefining(
            request,
            refinement: pipeline.startRawTranscription(audioURL: audioURL, provider: .openai),
            fallbackRequest: request.with(provider: .openAIRealtime),
            fallbackText: "realtime text",
            fallbackASRTime: 0.3,
            timeout: 0.1
        )

        XCTAssertEqual(result.text, "realtime text")
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        let records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.first?.provider, TranscriptionProvider.openAIRealtime.rawValue)
        XCTAssertEqual(records.first?.asrTime ?? 0, 0.3, accuracy: 0.001)
    }

    func testRunRefiningFallsBackToStreamedTextWhenBatchFails() async throws {
        let speechService = ScriptedRawTranscriptionService(behavior: .failure)
        let pipeline = try makePipeline(speechService: speechService, dataManager: MockDataManager())
        let request = makeRequest(provider: .openai, modelOverride: nil)

        let result = try await pipeline.runRefining(
            request,
            refinement: pipeline.startRawTranscription(audioURL: audioURL, provider: .openai),
            fallbackRequest: request.with(provider: .openAIRealtime),
            fallbackText: "realtime text",
            fallbackASRTime: 0.3,
            timeout: 2
        )

        XCTAssertEqual(result.text, "realtime text")
    }

    func testRunRefiningCapsExtraWaitOnceStreamedTextIsReady() async throws {
        let speechService = ScriptedRawTranscriptionService(behavior: .delayedText("Refined text", .milliseconds(600)))
        let pipeline = try makePipeline(speechService: speechService, dataManager: MockDataManager())
        let request = makeRequest(provider: .openai, modelOverride: "gpt-4o-transcribe")

        let startedAt = Date()
        let result = try await pipeline.runRefining(
            request,
            refinement: pipeline.startRawTranscription(audioURL: audioURL, provider: .openai),
            fallbackRequest: request.with(provider: .openAIRealtime),
            fallbackText: "realtime text",
            fallbackASRTime: 0.3,
            timeout: 5,
            maximumExtraWait: 0.1
        )

        XCTAssertEqual(result.text, "realtime text")
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
    }

    func testRunRefiningUsesBatchTextArrivingWithinExtraWait() async throws {
        let speechService = ScriptedRawTranscriptionService(behavior: .delayedText("Refined text", .milliseconds(50)))
        let pipeline = try makePipeline(speechService: speechService, dataManager: MockDataManager())
        let request = makeRequest(provider: .openai, modelOverride: "gpt-4o-transcribe")

        let result = try await pipeline.runRefining(
            request,
            refinement: pipeline.startRawTranscription(audioURL: audioURL, provider: .openai),
            fallbackRequest: request.with(provider: .openAIRealtime),
            fallbackText: "realtime text",
            fallbackASRTime: 0.3,
            timeout: 5,
            maximumExtraWait: 2
        )

        XCTAssertEqual(result.text, "Refined text")
    }

    func testRunPrestartedFinishesEarlyStartedTranscription() async throws {
        let speechService = ScriptedRawTranscriptionService(behavior: .text("Batch text"))
        let dataManager = MockDataManager()
        let pipeline = try makePipeline(speechService: speechService, dataManager: dataManager)

        let prestarted = pipeline.startRawTranscription(audioURL: audioURL, provider: .openai)
        let result = try await pipeline.run(makeRequest(provider: .openai, modelOverride: nil), prestarted: prestarted)

        XCTAssertEqual(result.text, "Batch text")
        XCTAssertEqual(speechService.requestedModelOverrides.count, 1)
    }

    func testRefinementTimeoutScalesWithAudioDurationAndIsCapped() {
        XCTAssertEqual(TranscriptionPipeline.refinementTimeout(forAudioDuration: nil), 3, accuracy: 0.001)
        XCTAssertEqual(TranscriptionPipeline.refinementTimeout(forAudioDuration: 10), 4, accuracy: 0.001)
        XCTAssertEqual(TranscriptionPipeline.refinementTimeout(forAudioDuration: 120), 6, accuracy: 0.001)
    }

    private func makePipeline(
        speechService: RawTranscriptionServicing,
        dataManager: MockDataManager
    ) throws -> TranscriptionPipeline {
        TranscriptionPipeline(
            speechService: speechService,
            settingsStore: FakeTranscriptionSettingsStore(
                provider: .openAIRealtime,
                semanticCorrectionMode: .off,
                historyEnabled: true,
                openAIModel: "gpt-4o-mini-transcribe"
            ),
            dataManager: dataManager,
            usageMetricsStore: UsageMetricsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: usageDefaultsSuite))),
            sourceUsageStore: SourceUsageStore(defaults: try XCTUnwrap(UserDefaults(suiteName: sourceDefaultsSuite))),
            clipboard: FakeClipboard()
        )
    }

    private func makeRequest(provider: TranscriptionProvider, modelOverride: String?) -> TranscriptionPipelineRequest {
        TranscriptionPipelineRequest(
            audioURL: audioURL,
            provider: provider,
            whisperModel: nil,
            openAIModelOverride: modelOverride,
            duration: 4,
            estimatedDuration: nil,
            sourceAppInfo: .unknown,
            modelReadyTime: nil,
            processStart: Date()
        )
    }
}

private final class FakeClipboard: ClipboardWriting {
    private(set) var contents: String?

    func replaceContents(with string: String) {
        contents = string
    }
}

private final class ScriptedRawTranscriptionService: RawTranscriptionServicing {
    enum Behavior {
        case text(String)
        case delayedText(String, Duration)
        case failure
        /// Never returns and ignores cancellation, like a stalled upload.
        case hang
    }

    private let behavior: Behavior
    private var stalledRequests: [CheckedContinuation<String, Never>] = []
    private(set) var requestedModelOverrides: [String?] = []

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func transcribeRaw(
        audioURL: URL,
        provider: TranscriptionProvider,
        model: WhisperModel?,
        openAIModelOverride: String?
    ) async throws -> String {
        requestedModelOverrides.append(openAIModelOverride)
        switch behavior {
        case .text(let text):
            return text
        case .delayedText(let text, let delay):
            try await Task.sleep(for: delay)
            return text
        case .failure:
            throw SpeechToTextError.transcriptionFailed("injected")
        case .hang:
            return await withCheckedContinuation { stalledRequests.append($0) }
        }
    }
}

private final class FakeRawTranscriptionService: RawTranscriptionServicing {
    struct CapturedRequest {
        let audioURL: URL
        let provider: TranscriptionProvider
        let model: WhisperModel?
        let openAIModelOverride: String?
    }

    private let text: String
    private(set) var requests: [CapturedRequest] = []

    init(text: String) {
        self.text = text
    }

    func transcribeRaw(
        audioURL: URL,
        provider: TranscriptionProvider,
        model: WhisperModel?,
        openAIModelOverride: String?
    ) async throws -> String {
        requests.append(
            CapturedRequest(
                audioURL: audioURL,
                provider: provider,
                model: model,
                openAIModelOverride: openAIModelOverride
            )
        )
        return text
    }
}

private final class FakeTranscriptionSettingsStore: TranscriptionSettingsReadable {
    var transcriptionProvider: TranscriptionProvider
    var selectedWhisperModel: WhisperModel = .base
    var selectedParakeetModel: ParakeetModel = .v3Multilingual
    var openAITranscriptionModel: String
    var openAIRealtimeTranscriptionModel: String = AppDefaults.defaultOpenAIRealtimeTranscriptionModel
    var miMoASRModel: String = AppDefaults.defaultMiMoASRModel
    var transcriptionLanguage: TranscriptionLanguage = .auto
    var recordingHUDStyle: RecordingHUDStyle = AppDefaults.defaultRecordingHUDStyle
    var semanticCorrectionMode: SemanticCorrectionMode
    var semanticCorrectionModelRepo: String = AppDefaults.defaultSemanticCorrectionModelRepo
    var isTranscriptionHistoryEnabled: Bool
    var transcriptionRetentionPeriod: RetentionPeriod = .forever
    var isSmartPasteEnabled: Bool = false
    var isStreamingTranscriptionEnabled: Bool = true
    var maxModelStorageGB: Double = 5.0

    init(
        provider: TranscriptionProvider,
        semanticCorrectionMode: SemanticCorrectionMode,
        historyEnabled: Bool,
        openAIModel: String = AppDefaults.defaultOpenAITranscriptionModel
    ) {
        self.transcriptionProvider = provider
        self.semanticCorrectionMode = semanticCorrectionMode
        self.isTranscriptionHistoryEnabled = historyEnabled
        self.openAITranscriptionModel = openAIModel
    }
}
