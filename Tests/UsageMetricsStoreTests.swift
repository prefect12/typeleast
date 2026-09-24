import XCTest
import SwiftData
@testable import Typeleast

@MainActor
final class UsageMetricsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: UsageMetricsStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "UsageMetricsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = UsageMetricsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    func testRecordSessionAccumulatesTotals() {
        XCTAssertEqual(store.snapshot.totalSessions, 0)

        store.recordSession(duration: 30, wordCount: 120, characterCount: 600)

        XCTAssertEqual(store.snapshot.totalSessions, 1)
        XCTAssertEqual(store.snapshot.totalWords, 120)
        XCTAssertEqual(store.snapshot.totalCharacters, 600)
        XCTAssertEqual(store.snapshot.totalDuration, 30, accuracy: 0.1)
        XCTAssertGreaterThan(store.snapshot.wordsPerMinute, 0)
        XCTAssertGreaterThan(store.snapshot.keystrokesSaved, 0)
    }

    func testResetClearsSnapshot() {
        store.recordSession(duration: 10, wordCount: 50, characterCount: 250)
        store.reset()

        XCTAssertEqual(store.snapshot.totalSessions, 0)
        XCTAssertEqual(store.snapshot.totalWords, 0)
        XCTAssertEqual(store.snapshot.totalDuration, 0)
        XCTAssertEqual(store.snapshot.keystrokesSaved, 0)
    }

    func testEstimatedWordCount() {
        let text = "Don't stop 42 times -- seriously!"
        let count = UsageMetricsStore.estimatedWordCount(for: text)
        XCTAssertEqual(count, 5)

        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: ""), 0)
    }

    func testBootstrapLoadsHistoryWhenEmpty() async {
        let mockDataManager = TestDataManager()
        mockDataManager.isHistoryEnabled = true

        let record = TranscriptionRecord(
            text: "Hello world",
            provider: .openai,
            duration: 12,
            modelUsed: nil,
            wordCount: 2
        )
        mockDataManager.records = [record]

        await store.bootstrapIfNeeded(dataManager: mockDataManager)

        XCTAssertEqual(store.snapshot.totalSessions, 1)
        XCTAssertEqual(store.snapshot.totalWords, 2)
        XCTAssertEqual(store.snapshot.totalDuration, 12, accuracy: 0.1)
    }

    func testBootstrapSkipsWhenCountersPresent() async {
        store.recordSession(duration: 5, wordCount: 10, characterCount: 50)

        let mockDataManager = TestDataManager()
        mockDataManager.isHistoryEnabled = true
        mockDataManager.records = [
            TranscriptionRecord(text: "ignored", provider: .openai, duration: 30, modelUsed: nil, wordCount: 5)
        ]

        await store.bootstrapIfNeeded(dataManager: mockDataManager)

        XCTAssertEqual(store.snapshot.totalSessions, 1)
        XCTAssertEqual(store.snapshot.totalWords, 10)
    }

    func testBootstrapKeepsAggregateWhenNoRecordsExist() async {
        store.recordSession(duration: 5, wordCount: 10, characterCount: 50)

        let mockDataManager = TestDataManager()
        mockDataManager.isHistoryEnabled = true

        await store.bootstrapIfNeeded(dataManager: mockDataManager)

        XCTAssertEqual(store.snapshot.totalSessions, 1)
        XCTAssertEqual(store.snapshot.totalWords, 10)
        XCTAssertEqual(store.snapshot.totalCharacters, 50)
    }

    func testModelUsageBreakdownGroupsDurationAndCostByModel() {
        let openAIRecord = TranscriptionRecord(
            text: "hello world",
            provider: .openai,
            duration: 60,
            modelUsed: "gpt-4o-transcribe",
            wordCount: 2,
            characterCount: 11,
            transcriptionTime: 4
        )
        let miMoRecord = TranscriptionRecord(
            text: "voice note",
            provider: .mimo,
            duration: 3600,
            modelUsed: "mimo-v2.5-asr",
            wordCount: 2,
            characterCount: 10,
            transcriptionTime: 12
        )
        let localRecord = TranscriptionRecord(
            text: "offline",
            provider: .local,
            duration: 30,
            modelUsed: "base",
            wordCount: 1,
            characterCount: 7,
            transcriptionTime: 1
        )

        let stats = UsageMetricsStore.modelUsageBreakdown(from: [openAIRecord, miMoRecord, localRecord])

        let openAIStats = stats.first { $0.modelName == "gpt-4o-transcribe" }
        XCTAssertEqual(openAIStats?.sessions, 1)
        XCTAssertEqual(openAIStats?.recordingDuration ?? -1, 60, accuracy: 0.01)
        XCTAssertEqual(openAIStats?.estimatedCostUSD ?? -1, 0.006, accuracy: 0.000001)

        let miMoStats = stats.first { $0.modelName == "mimo-v2.5-asr" }
        XCTAssertEqual(miMoStats?.estimatedCostUSD ?? -1, 0.074, accuracy: 0.000001)

        let localStats = stats.first { $0.modelName == "base" }
        XCTAssertEqual(localStats?.estimatedCostUSD ?? -1, 0, accuracy: 0.000001)
    }

    func testGeminiCostEstimateUsesAudioAndOutputTokenApproximation() {
        let record = TranscriptionRecord(
            text: String(repeating: "a", count: 200),
            provider: .gemini,
            duration: 60,
            modelUsed: SpeechToTextService.geminiTranscriptionModel,
            wordCount: 1,
            characterCount: 200
        )

        let cost = UsageCostEstimator.estimatedCostUSD(for: record)

        XCTAssertEqual(cost ?? -1, 0.000596, accuracy: 0.000001)
    }

}

@MainActor
private final class TestDataManager: DataManagerProtocol {
    var isHistoryEnabled: Bool = true
    var retentionPeriod: RetentionPeriod = .oneMonth
    var sharedModelContainer: ModelContainer? { nil }

    var records: [TranscriptionRecord] = []

    func initialize() throws {}

    func saveTranscription(_ record: TranscriptionRecord) async throws {
        records.append(record)
    }

    func fetchAllRecords() async throws -> [TranscriptionRecord] {
        records
    }

    func fetchRecords(matching searchQuery: String) async throws -> [TranscriptionRecord] {
        records
    }

    func fetchRecords(matching searchQuery: String, limit: Int?, offset: Int?) async throws -> [TranscriptionRecord] {
        records
    }

    func deleteRecord(_ record: TranscriptionRecord) async throws {
        records.removeAll { $0.id == record.id }
    }

    func deleteAllRecords() async throws {
        records.removeAll()
    }

    func updateTiming(for recordID: UUID, pasteTime: TimeInterval?, endToEndTime: TimeInterval?) async throws {
        guard let record = records.first(where: { $0.id == recordID }) else { return }
        record.pasteTime = pasteTime
        record.endToEndTime = endToEndTime
    }

    func cleanupExpiredRecords() async throws {}

    func saveTranscriptionQuietly(_ record: TranscriptionRecord) async {
        records.append(record)
    }

    func fetchAllRecordsQuietly() async -> [TranscriptionRecord] {
        records
    }

    func cleanupExpiredRecordsQuietly() async {}
}
