import XCTest
import SwiftData
@testable import Typeleast

@MainActor
final class TimingAnalysisStoreTests: XCTestCase {
    private var store: TimingAnalysisStore!
    private var dataManager: CountingTimingDataManager!

    override func setUp() {
        super.setUp()
        store = TimingAnalysisStore()
        dataManager = CountingTimingDataManager()
    }

    override func tearDown() {
        store = nil
        dataManager = nil
        super.tearDown()
    }

    func testLoadIfNeededCachesRecordsUntilInvalidated() async {
        dataManager.records = [
            TranscriptionRecord(text: "first", provider: .openai, duration: 1, modelUsed: nil)
        ]

        await store.loadIfNeeded(dataManager: dataManager)

        XCTAssertEqual(dataManager.fetchCount, 1)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertTrue(store.hasLoaded)

        dataManager.records.append(
            TranscriptionRecord(text: "second", provider: .openai, duration: 1, modelUsed: nil)
        )

        await store.loadIfNeeded(dataManager: dataManager)

        XCTAssertEqual(dataManager.fetchCount, 1)
        XCTAssertEqual(store.records.count, 1)

        let previousToken = store.reloadToken
        store.invalidate()

        XCTAssertFalse(store.hasLoaded)
        XCTAssertEqual(store.reloadToken, previousToken + 1)

        await store.loadIfNeeded(dataManager: dataManager)

        XCTAssertEqual(dataManager.fetchCount, 2)
        XCTAssertEqual(store.records.count, 2)
    }

    func testLoadIfNeededReusesRecordsWhenCachedLimitCoversRequest() async {
        dataManager.records = (0..<60).map { index in
            TranscriptionRecord(text: "record \(index)", provider: .openai, duration: 1, modelUsed: nil)
        }

        await store.loadIfNeeded(recordLimit: 50, dataManager: dataManager)

        XCTAssertEqual(dataManager.fetchCount, 1)
        XCTAssertEqual(dataManager.lastLimit, 50)
        XCTAssertEqual(store.records.count, 50)

        await store.loadIfNeeded(recordLimit: 20, dataManager: dataManager)

        XCTAssertEqual(dataManager.fetchCount, 1)
        XCTAssertEqual(store.records.count, 50)
    }

    func testLoadIfNeededReloadsWhenRequestNeedsMoreRecords() async {
        dataManager.records = (0..<80).map { index in
            TranscriptionRecord(text: "record \(index)", provider: .openai, duration: 1, modelUsed: nil)
        }

        await store.loadIfNeeded(recordLimit: 20, dataManager: dataManager)
        await store.loadIfNeeded(recordLimit: 50, dataManager: dataManager)

        XCTAssertEqual(dataManager.fetchCount, 2)
        XCTAssertEqual(dataManager.lastLimit, 50)
        XCTAssertEqual(store.records.count, 50)
    }
}

@MainActor
private final class CountingTimingDataManager: DataManagerProtocol {
    var isHistoryEnabled = true
    var retentionPeriod: RetentionPeriod = .oneMonth
    var sharedModelContainer: ModelContainer? { nil }
    var records: [TranscriptionRecord] = []
    private(set) var fetchCount = 0
    private(set) var lastLimit: Int?

    func initialize() throws {}

    func saveTranscription(_ record: TranscriptionRecord) async throws {
        records.append(record)
    }

    func fetchAllRecords() async throws -> [TranscriptionRecord] {
        fetchCount += 1
        return records
    }

    func fetchRecords(matching searchQuery: String) async throws -> [TranscriptionRecord] {
        records
    }

    func fetchRecords(matching searchQuery: String, limit: Int?, offset: Int?) async throws -> [TranscriptionRecord] {
        fetchCount += 1
        lastLimit = limit
        if let limit {
            return Array(records.prefix(limit))
        }
        return records
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
        fetchCount += 1
        return records
    }

    func cleanupExpiredRecordsQuietly() async {}
}
