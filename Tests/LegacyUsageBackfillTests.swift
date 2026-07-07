import XCTest
@testable import Typeleast

@MainActor
final class LegacyUsageBackfillTests: XCTestCase {
    func testBackfillsOneSummaryRecordPerDailyActivityEntry() {
        let snapshot = UsageSnapshot(
            totalSessions: 10,
            totalDuration: 100,
            totalWords: 100,
            totalCharacters: 500,
            lastUpdated: nil,
            dailyActivity: [
                "2026-07-01": 40,
                "2026-07-02": 60
            ]
        )

        let records = LegacyUsageBackfill.recordsToBackfill(
            snapshot: snapshot,
            existingRecords: []
        )

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.wordCount).reduce(0, +), 100)
        XCTAssertTrue(records.allSatisfy { $0.provider == LegacyUsageBackfill.providerRawValue })
        XCTAssertTrue(records.allSatisfy { $0.modelUsed == LegacyUsageBackfill.modelUsed })
        XCTAssertTrue(records.allSatisfy { $0.text.contains("Legacy Summary") })
    }

    func testBackfillSubtractsDetailedRecordsFromSameDay() {
        let snapshot = UsageSnapshot(
            totalSessions: 10,
            totalDuration: 100,
            totalWords: 100,
            totalCharacters: 500,
            lastUpdated: nil,
            dailyActivity: [
                "2026-07-01": 40,
                "2026-07-02": 60
            ]
        )
        let detailedRecord = TranscriptionRecord(
            text: "already saved",
            provider: .openai,
            duration: 10,
            wordCount: 10,
            characterCount: 50
        )
        detailedRecord.date = date(year: 2026, month: 7, day: 2, hour: 9)

        let records = LegacyUsageBackfill.recordsToBackfill(
            snapshot: snapshot,
            existingRecords: [detailedRecord]
        )

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.wordCount), [40, 50])
        XCTAssertEqual(records.map(\.wordCount).reduce(0, +) + detailedRecord.wordCount, 100)
    }

    func testBackfillSkipsDaysAlreadyRepresentedByLegacySummary() {
        let snapshot = UsageSnapshot(
            totalSessions: 10,
            totalDuration: 100,
            totalWords: 100,
            totalCharacters: 500,
            lastUpdated: nil,
            dailyActivity: [
                "2026-07-01": 40,
                "2026-07-02": 60
            ]
        )
        let existingSummary = TranscriptionRecord(
            text: "existing summary",
            provider: .openai,
            duration: 20,
            modelUsed: LegacyUsageBackfill.modelUsed,
            wordCount: 40,
            characterCount: 200
        )
        existingSummary.provider = LegacyUsageBackfill.providerRawValue
        existingSummary.date = date(year: 2026, month: 7, day: 1, hour: 12)

        let records = LegacyUsageBackfill.recordsToBackfill(
            snapshot: snapshot,
            existingRecords: [existingSummary]
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.wordCount, 60)
        XCTAssertFalse(records.contains { Calendar.current.isDate($0.date, inSameDayAs: existingSummary.date) })
    }

    func testBackfillsUndatedRemainderWhenTotalsExceedDailyActivity() {
        let snapshot = UsageSnapshot(
            totalSessions: 10,
            totalDuration: 100,
            totalWords: 100,
            totalCharacters: 500,
            lastUpdated: nil,
            dailyActivity: [
                "2026-07-01": 60
            ]
        )

        let records = LegacyUsageBackfill.recordsToBackfill(
            snapshot: snapshot,
            existingRecords: []
        )

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.wordCount).reduce(0, +), 100)
        XCTAssertEqual(records.filter { $0.modelUsed == LegacyUsageBackfill.undatedModelUsed }.count, 1)
        XCTAssertEqual(records.first { $0.modelUsed == LegacyUsageBackfill.undatedModelUsed }?.wordCount, 40)
    }

    func testBackfillDoesNotDuplicateExistingUndatedRemainder() {
        let snapshot = UsageSnapshot(
            totalSessions: 10,
            totalDuration: 100,
            totalWords: 100,
            totalCharacters: 500,
            lastUpdated: nil,
            dailyActivity: [
                "2026-07-01": 60
            ]
        )
        let existingRemainder = TranscriptionRecord(
            text: "existing undated summary",
            provider: .openai,
            duration: 40,
            modelUsed: LegacyUsageBackfill.undatedModelUsed,
            wordCount: 40,
            characterCount: 200
        )
        existingRemainder.provider = LegacyUsageBackfill.providerRawValue

        let records = LegacyUsageBackfill.recordsToBackfill(
            snapshot: snapshot,
            existingRecords: [existingRemainder]
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.wordCount, 60)
        XCTAssertFalse(records.contains { $0.modelUsed == LegacyUsageBackfill.undatedModelUsed })
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        )) ?? Date(timeIntervalSince1970: 0)
    }
}
