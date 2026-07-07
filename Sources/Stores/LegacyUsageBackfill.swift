import Foundation

internal enum LegacyUsageBackfill {
    static let providerRawValue = "legacySummary"
    static let modelUsed = "legacy-usage-summary-v1"
    static let undatedModelUsed = "legacy-usage-summary-v1-undated"

    static func isBackfilledRecord(_ record: TranscriptionRecord) -> Bool {
        record.provider == providerRawValue ||
            record.modelUsed == modelUsed ||
            record.modelUsed == undatedModelUsed
    }

    static func recordsToBackfill(
        snapshot: UsageSnapshot,
        existingRecords: [TranscriptionRecord],
        calendar: Calendar = .current
    ) -> [TranscriptionRecord] {
        let backfilledRecords = existingRecords.filter(isBackfilledRecord)
        let detailedRecords = existingRecords.filter { !isBackfilledRecord($0) }
        let backfilledDays = Set(
            backfilledRecords
                .filter { !isUndatedRemainderRecord($0) }
                .map { storageDayKey(for: $0.date) }
        )
        let hasUndatedRemainder = backfilledRecords.contains(where: isUndatedRemainderRecord)
        let detailedWordsByDay = wordsByDay(for: detailedRecords)

        var legacyWordsByDay: [(dayKey: String, date: Date, words: Int)] = []
        for (dayKey, words) in snapshot.dailyActivity.sorted(by: { $0.key < $1.key }) {
            guard words > 0, !backfilledDays.contains(dayKey),
                  let date = storageDayFormatter.date(from: dayKey) else { continue }

            let detailedWords = detailedWordsByDay[dayKey] ?? 0
            let legacyWords = max(0, words - detailedWords)
            guard legacyWords > 0 else { continue }

            legacyWordsByDay.append((dayKey, calendar.startOfDay(for: date), legacyWords))
        }

        let detailedWords = detailedRecords.reduce(0) { $0 + wordCount(for: $1) }
        let detailedCharacters = detailedRecords.reduce(0) { $0 + characterCount(for: $1) }
        let detailedDuration = detailedRecords.reduce(0) { $0 + ($1.duration ?? 0) }
        let existingBackfilledWords = backfilledRecords.reduce(0) { $0 + wordCount(for: $1) }
        let existingBackfilledCharacters = backfilledRecords.reduce(0) { $0 + characterCount(for: $1) }
        let existingBackfilledDuration = backfilledRecords.reduce(0) { $0 + ($1.duration ?? 0) }

        let dailyBackfillWordsTotal = legacyWordsByDay.reduce(0) { $0 + $1.words }
        let undatedRemainderWords = hasUndatedRemainder
            ? 0
            : max(0, snapshot.totalWords - detailedWords - existingBackfilledWords - dailyBackfillWordsTotal)
        let newBackfillWordsTotal = dailyBackfillWordsTotal + undatedRemainderWords
        guard newBackfillWordsTotal > 0 else { return [] }

        let denominator = max(newBackfillWordsTotal, 1)
        let legacySessionsTotal = max(0, snapshot.totalSessions - detailedRecords.count - backfilledRecords.count)
        let legacyCharactersTotal = max(0, snapshot.totalCharacters - detailedCharacters - existingBackfilledCharacters)
        let legacyDurationTotal = max(0, snapshot.totalDuration - detailedDuration - existingBackfilledDuration)

        var records = legacyWordsByDay.map { item in
            let sessions = proportionalCount(
                total: legacySessionsTotal,
                value: item.words,
                denominator: denominator,
                minimumWhenPositive: 1
            )
            let characters = proportionalCount(
                total: legacyCharactersTotal,
                value: item.words,
                denominator: denominator,
                minimumWhenPositive: item.words
            )
            let duration = proportionalDuration(
                total: legacyDurationTotal,
                value: item.words,
                denominator: denominator
            )

            let record = TranscriptionRecord(
                text: summaryText(dayKey: item.dayKey, words: item.words, sessions: sessions),
                provider: .openai,
                duration: duration > 0 ? duration : nil,
                modelUsed: modelUsed,
                wordCount: item.words,
                characterCount: characters
            )
            record.provider = providerRawValue
            record.date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: item.date) ?? item.date
            return record
        }

        if undatedRemainderWords > 0 {
            let sessions = proportionalCount(
                total: legacySessionsTotal,
                value: undatedRemainderWords,
                denominator: denominator,
                minimumWhenPositive: 1
            )
            let characters = proportionalCount(
                total: legacyCharactersTotal,
                value: undatedRemainderWords,
                denominator: denominator,
                minimumWhenPositive: undatedRemainderWords
            )
            let duration = proportionalDuration(
                total: legacyDurationTotal,
                value: undatedRemainderWords,
                denominator: denominator
            )

            let record = TranscriptionRecord(
                text: undatedSummaryText(words: undatedRemainderWords, sessions: sessions),
                provider: .openai,
                duration: duration > 0 ? duration : nil,
                modelUsed: undatedModelUsed,
                wordCount: undatedRemainderWords,
                characterCount: characters
            )
            record.provider = providerRawValue
            record.date = undatedSummaryDate(
                dailyEntries: legacyWordsByDay,
                snapshot: snapshot,
                calendar: calendar
            )
            records.append(record)
        }

        return records
    }

    private static func isUndatedRemainderRecord(_ record: TranscriptionRecord) -> Bool {
        record.modelUsed == undatedModelUsed
    }

    private static func wordsByDay(for records: [TranscriptionRecord]) -> [String: Int] {
        records.reduce(into: [:]) { result, record in
            result[storageDayKey(for: record.date), default: 0] += wordCount(for: record)
        }
    }

    private static func storageDayKey(for date: Date) -> String {
        storageDayFormatter.string(from: date)
    }

    private static func wordCount(for record: TranscriptionRecord) -> Int {
        record.wordCount > 0 ? record.wordCount : UsageMetricsStore.estimatedWordCount(for: record.text)
    }

    private static func characterCount(for record: TranscriptionRecord) -> Int {
        record.characterCount > 0 ? record.characterCount : record.text.count
    }

    private static func proportionalCount(
        total: Int,
        value: Int,
        denominator: Int,
        minimumWhenPositive: Int
    ) -> Int {
        guard value > 0 else { return 0 }
        guard total > 0, denominator > 0 else { return minimumWhenPositive }
        let estimate = Int((Double(total) * Double(value) / Double(denominator)).rounded())
        return max(minimumWhenPositive, estimate)
    }

    private static func proportionalDuration(total: TimeInterval, value: Int, denominator: Int) -> TimeInterval {
        guard value > 0, total > 0, denominator > 0 else { return 0 }
        return total * Double(value) / Double(denominator)
    }

    private static func summaryText(dayKey: String, words: Int, sessions: Int) -> String {
        """
        旧版汇总 / Legacy Summary
        日期 / Date: \(dayKey)
        累计字数 / Words: \(words)
        估算轮次 / Estimated sessions: \(sessions)

        原始转录文本没有保存在旧版历史库中；这里恢复的是统计占位。新的转录会继续保存完整文本和耗时。
        Original transcript text was not saved in the previous history store; this is a restored aggregate placeholder. New transcriptions will save full text and timing.
        """
    }

    private static func undatedSummaryText(words: Int, sessions: Int) -> String {
        """
        未分日期旧版汇总 / Undated Legacy Summary
        日期 / Date: unavailable in old usage counters
        累计字数 / Words: \(words)
        估算轮次 / Estimated sessions: \(sessions)

        这部分旧版统计只有总量，没有保存到每天的活跃度里；这里恢复的是统计占位。
        This portion of the old usage counters only had totals, not daily activity. This is a restored aggregate placeholder.
        """
    }

    private static func undatedSummaryDate(
        dailyEntries: [(dayKey: String, date: Date, words: Int)],
        snapshot: UsageSnapshot,
        calendar: Calendar
    ) -> Date {
        if let earliestDailyDate = dailyEntries.map(\.date).min(),
           let previousDay = calendar.date(byAdding: .day, value: -1, to: earliestDailyDate) {
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: previousDay) ?? previousDay
        }

        if let earliestSnapshotDay = snapshot.dailyActivity.keys.sorted().first,
           let date = storageDayFormatter.date(from: earliestSnapshotDay),
           let previousDay = calendar.date(byAdding: .day, value: -1, to: date) {
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: previousDay) ?? previousDay
        }

        return snapshot.lastUpdated ?? Date()
    }

    private static let storageDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}
