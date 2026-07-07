import Foundation
import AppKit
import Observation

internal struct SourceAppInfo: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let iconData: Data?
    let fallbackSymbolName: String?
    
    static var unknown: SourceAppInfo {
        SourceAppInfo(
            bundleIdentifier: "unknown",
            displayName: "Background trigger",
            iconData: nil,
            fallbackSymbolName: "questionmark.app"
        )
    }
    
    static func from(app: NSRunningApplication) -> SourceAppInfo? {
        guard let bundleId = app.bundleIdentifier else {
            return nil
        }
        let name = app.localizedName ?? bundleId
        let iconData = SourceAppInfo.pngData(from: app.icon)
        return SourceAppInfo(
            bundleIdentifier: bundleId,
            displayName: name,
            iconData: iconData,
            fallbackSymbolName: nil
        )
    }
    
    private static func pngData(from image: NSImage?) -> Data? {
        guard let tiffData = image?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

internal struct SourceUsageStats: Codable, Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    var displayName: String
    var totalWords: Int
    var totalCharacters: Int
    var sessionCount: Int
    var lastUsed: Date
    var iconData: Data?
    var fallbackSymbolName: String?
    
    var initials: String {
        let components = displayName.split(separator: " ")
        let chars: [Character] = components.prefix(2).compactMap { $0.first }
        if chars.isEmpty, let first = displayName.first {
            return String(first)
        }
        return String(chars)
    }
    
    func nsImage(workspace: NSWorkspace = .shared) -> NSImage? {
        if let iconData, let image = NSImage(data: iconData) {
            return image
        }
        guard bundleIdentifier != SourceAppInfo.unknown.bundleIdentifier,
              let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return workspace.icon(forFile: appURL.path)
    }
}

private struct PersistedSourceUsageStats: Codable {
    let bundleIdentifier: String
    let displayName: String
    let totalWords: Int
    let totalCharacters: Int
    let sessionCount: Int
    let lastUsed: Date
    let fallbackSymbolName: String?

    init(_ stats: SourceUsageStats) {
        self.bundleIdentifier = stats.bundleIdentifier
        self.displayName = stats.displayName
        self.totalWords = stats.totalWords
        self.totalCharacters = stats.totalCharacters
        self.sessionCount = stats.sessionCount
        self.lastUsed = stats.lastUsed
        self.fallbackSymbolName = stats.fallbackSymbolName
    }

    var stats: SourceUsageStats {
        SourceUsageStats(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            totalWords: totalWords,
            totalCharacters: totalCharacters,
            sessionCount: sessionCount,
            lastUsed: lastUsed,
            iconData: nil,
            fallbackSymbolName: fallbackSymbolName
        )
    }
}

@Observable
@MainActor
internal final class SourceUsageStore {
    static let shared = SourceUsageStore()
    
    private let defaults: UserDefaults
    private let storageKey = "sourceUsage.stats"
    private let importDevelopmentKey = "sourceUsage.didImportDevelopmentUsage"
    private let developmentBundleIdentifier = AppIdentity.developmentBundleIdentifier
    private static let maxSources = 50
    private static let maxPersistedPayloadBytes = 512 * 1024
    private static let persistedIconDataField = Data(#""iconData""#.utf8)
    
    private(set) var orderedStats: [SourceUsageStats] = []
    private var statsByBundle: [String: SourceUsageStats] = [:]
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        importDevelopmentSourcesIfNeeded()
        if let data = defaults.data(forKey: storageKey) {
            if let decoded = Self.decodeStats(from: data) {
                statsByBundle = decoded
                let originalCount = statsByBundle.count
                trimIfNeeded()
                refreshOrderedStats()
                if shouldRewritePersistedPayload(data: data, originalCount: originalCount) {
                    persist()
                }
                return
            }
        }
        statsByBundle = [:]
        orderedStats = []
    }
    
    func recordUsage(for info: SourceAppInfo, words: Int, characters: Int) {
        guard words > 0 else { return }
        var existing = statsByBundle[info.bundleIdentifier] ?? SourceUsageStats(
            bundleIdentifier: info.bundleIdentifier,
            displayName: info.displayName,
            totalWords: 0,
            totalCharacters: 0,
            sessionCount: 0,
            lastUsed: Date(),
            iconData: info.iconData,
            fallbackSymbolName: info.fallbackSymbolName
        )
        existing.totalWords += words
        existing.totalCharacters += characters
        existing.sessionCount += 1
        existing.lastUsed = Date()
        if existing.displayName != info.displayName {
            existing.displayName = info.displayName
        }
        if existing.iconData == nil {
            existing.iconData = info.iconData
        }
        if existing.fallbackSymbolName == nil {
            existing.fallbackSymbolName = info.fallbackSymbolName
        }
        statsByBundle[existing.bundleIdentifier] = existing
        trimIfNeeded()
        refreshOrderedStats()
        persist()
    }
    
    func topSources(limit: Int) -> [SourceUsageStats] {
        Array(orderedStats.prefix(limit))
    }
    
    func allSources() -> [SourceUsageStats] {
        orderedStats
    }

    func rebuild(using records: [TranscriptionRecord]) {
        guard !records.isEmpty else { return }

        statsByBundle = [:]

        for record in records {
            guard let bundleIdentifier = record.sourceAppBundleId, !bundleIdentifier.isEmpty else {
                continue
            }

            let words = record.wordCount > 0 ? record.wordCount : UsageMetricsStore.estimatedWordCount(for: record.text)
            guard words > 0 else { continue }

            let characters = record.characterCount > 0 ? record.characterCount : record.text.count
            let displayName = record.sourceAppName?.isEmpty == false ? record.sourceAppName! : bundleIdentifier
            var stat = statsByBundle[bundleIdentifier] ?? SourceUsageStats(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                totalWords: 0,
                totalCharacters: 0,
                sessionCount: 0,
                lastUsed: record.date,
                iconData: record.sourceAppIconData,
                fallbackSymbolName: nil
            )

            stat.displayName = stat.displayName.isEmpty ? displayName : stat.displayName
            stat.totalWords += words
            stat.totalCharacters += characters
            stat.sessionCount += 1
            stat.lastUsed = max(stat.lastUsed, record.date)
            if stat.iconData == nil {
                stat.iconData = record.sourceAppIconData
            }
            statsByBundle[bundleIdentifier] = stat
        }

        trimIfNeeded()
        refreshOrderedStats()
        persist()
    }
    
    private func trimIfNeeded() {
        guard statsByBundle.count > Self.maxSources else { return }
        let candidates = statsByBundle.values.sorted(by: Self.defaultSort).dropFirst(Self.maxSources)
        for stat in candidates {
            statsByBundle[stat.bundleIdentifier] = nil
        }
    }

    private func persist() {
        if let data = Self.encodeStats(statsByBundle) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func importDevelopmentSourcesIfNeeded() {
        guard defaults === UserDefaults.standard else { return }
        guard defaults.object(forKey: importDevelopmentKey) == nil else { return }
        guard let developmentDomain = defaults.persistentDomain(forName: developmentBundleIdentifier),
              let developmentData = developmentDomain[storageKey] as? Data else {
            return
        }

        guard let developmentStats = Self.decodeStats(from: developmentData) else {
            return
        }

        var mergedStats: [String: SourceUsageStats] = [:]
        if let currentData = defaults.data(forKey: storageKey),
           let currentStats = Self.decodeStats(from: currentData) {
            mergedStats = currentStats
        }

        for (bundleIdentifier, developmentStat) in developmentStats {
            if let currentStat = mergedStats[bundleIdentifier] {
                mergedStats[bundleIdentifier] = SourceUsageStats(
                    bundleIdentifier: bundleIdentifier,
                    displayName: currentStat.displayName.isEmpty ? developmentStat.displayName : currentStat.displayName,
                    totalWords: currentStat.totalWords + developmentStat.totalWords,
                    totalCharacters: currentStat.totalCharacters + developmentStat.totalCharacters,
                    sessionCount: currentStat.sessionCount + developmentStat.sessionCount,
                    lastUsed: max(currentStat.lastUsed, developmentStat.lastUsed),
                    iconData: currentStat.iconData ?? developmentStat.iconData,
                    fallbackSymbolName: currentStat.fallbackSymbolName ?? developmentStat.fallbackSymbolName
                )
            } else {
                mergedStats[bundleIdentifier] = developmentStat
            }
        }

        mergedStats = Self.trimmed(mergedStats)
        if let data = Self.encodeStats(mergedStats) {
            defaults.set(data, forKey: storageKey)
            defaults.set(true, forKey: importDevelopmentKey)
        }
    }
    
    private func refreshOrderedStats() {
        orderedStats = statsByBundle.values.sorted(by: Self.defaultSort)
    }

    private func shouldRewritePersistedPayload(data: Data, originalCount: Int) -> Bool {
        data.count > Self.maxPersistedPayloadBytes ||
            data.range(of: Self.persistedIconDataField) != nil ||
            statsByBundle.count != originalCount
    }

    private static func decodeStats(from data: Data) -> [String: SourceUsageStats]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let persisted = try? decoder.decode([String: PersistedSourceUsageStats].self, from: data) {
            return persisted.mapValues(\.stats)
        }
        if let decodedStats = try? decoder.decode([String: SourceUsageStats].self, from: data) {
            return decodedStats.mapValues { stat in
                var lightweight = stat
                lightweight.iconData = nil
                return lightweight
            }
        }
        return nil
    }

    private static func encodeStats(_ stats: [String: SourceUsageStats]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(stats.mapValues(PersistedSourceUsageStats.init))
    }

    private static func trimmed(_ stats: [String: SourceUsageStats]) -> [String: SourceUsageStats] {
        guard stats.count > maxSources else { return stats }
        let keep = Set(stats.values.sorted(by: defaultSort).prefix(maxSources).map(\.bundleIdentifier))
        return stats.filter { keep.contains($0.key) }
    }

    private static func defaultSort(lhs: SourceUsageStats, rhs: SourceUsageStats) -> Bool {
        if lhs.totalWords == rhs.totalWords {
            return lhs.lastUsed > rhs.lastUsed
        }
        return lhs.totalWords > rhs.totalWords
    }

    /// Clears all persisted source usage stats.
    func reset() {
        statsByBundle = [:]
        orderedStats = []
        defaults.removeObject(forKey: storageKey)
    }

    func resetForTesting() {
        reset()
    }
}
