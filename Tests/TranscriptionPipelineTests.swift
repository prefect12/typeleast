import AppKit
import XCTest
@testable import Typeleast

@MainActor
final class TranscriptionPipelineTests: XCTestCase {
    private var usageDefaultsSuite: String!
    private var sourceDefaultsSuite: String!
    private var audioURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        usageDefaultsSuite = "TranscriptionPipelineTests.usage.\(UUID().uuidString)"
        sourceDefaultsSuite = "TranscriptionPipelineTests.source.\(UUID().uuidString)"
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionPipelineTests-\(UUID().uuidString).wav")
        try Data([0x00, 0x01, 0x02]).write(to: audioURL)
        NSPasteboard.general.clearContents()
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
            sourceUsageStore: sourceStore
        )

        let result = try await pipeline.run(
            TranscriptionPipelineRequest(
                audioURL: audioURL,
                provider: .openai,
                whisperModel: nil,
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
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello Typeleast")
        XCTAssertEqual(speechService.requests.map(\.provider), [.openai])
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
            sourceUsageStore: sourceStore
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
            sourceUsageStore: sourceStore
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
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Streamed Typeleast text")
        XCTAssertEqual(usageStore.snapshot.totalSessions, 1)
        XCTAssertEqual(sourceStore.allSources().first?.bundleIdentifier, "com.example.chat")

        let records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Streamed Typeleast text")
        XCTAssertEqual(records.first?.asrTime ?? 0, 0.42, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(records.first?.transcriptionTime ?? 0, 0.42)
    }
}

private final class FakeRawTranscriptionService: RawTranscriptionServicing {
    struct CapturedRequest {
        let audioURL: URL
        let provider: TranscriptionProvider
        let model: WhisperModel?
    }

    private let text: String
    private(set) var requests: [CapturedRequest] = []

    init(text: String) {
        self.text = text
    }

    func transcribeRaw(audioURL: URL, provider: TranscriptionProvider, model: WhisperModel?) async throws -> String {
        requests.append(CapturedRequest(audioURL: audioURL, provider: provider, model: model))
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
