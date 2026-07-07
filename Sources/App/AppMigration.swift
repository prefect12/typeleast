import Foundation
import SQLite3
import os.log

internal enum AppMigration {
    private enum Keys {
        static let userDefaultsMigrated = "migration.audioWhisper.userDefaults.v1"
        static let usageMigrated = "migration.audioWhisper.usage.v1"
        static let sourceUsageMigrated = "migration.audioWhisper.sourceUsage.v1"
        static let keychainMigrated = "migration.audioWhisper.keychain.v1"
        static let appSupportMigrated = "migration.audioWhisper.appSupport.v1"
        static let swiftDataMigrated = "migration.audioWhisper.swiftData.v1"

        static let usageTotalSessions = "usage.totalSessions"
        static let usageTotalDuration = "usage.totalDuration"
        static let usageTotalWords = "usage.totalWords"
        static let usageTotalCharacters = "usage.totalCharacters"
        static let usageLastUpdated = "usage.lastUpdated"
        static let usageDailyActivity = "usage.dailyActivity"
        static let usageImportedDevelopment = "usage.didImportDevelopmentUsage"

        static let sourceUsageStats = "sourceUsage.stats"
        static let sourceUsageImportedDevelopment = "sourceUsage.didImportDevelopmentUsage"
    }

    static func migrateIfNeeded(
        userDefaults: UserDefaults = .standard,
        keychainService: KeychainServiceProtocol = KeychainService.shared,
        fileManager: FileManager = .default
    ) {
        migrateUserDefaultsIfNeeded(userDefaults: userDefaults)
        migrateUsageIfNeeded(userDefaults: userDefaults)
        migrateSourceUsageIfNeeded(userDefaults: userDefaults)
        migrateKeychainIfNeeded(userDefaults: userDefaults, keychainService: keychainService)
        migrateApplicationSupportIfNeeded(userDefaults: userDefaults, fileManager: fileManager)
        migrateSwiftDataStoreIfNeeded(userDefaults: userDefaults, fileManager: fileManager)
    }

    static func migrateUserDefaultsIfNeeded(
        userDefaults: UserDefaults = .standard,
        legacyDomains: [String]? = nil
    ) {
        guard userDefaults.object(forKey: Keys.userDefaultsMigrated) == nil else { return }

        for domainName in legacyDomains ?? legacyPreferenceDomains {
            guard let domain = userDefaults.persistentDomain(forName: domainName) else { continue }
            for (key, value) in domain where shouldCopyPreferenceKey(key) && userDefaults.object(forKey: key) == nil {
                userDefaults.set(value, forKey: key)
            }
        }

        userDefaults.set(true, forKey: Keys.userDefaultsMigrated)
    }

    static func migrateUsageIfNeeded(
        userDefaults: UserDefaults = .standard,
        legacyDomains: [String]? = nil
    ) {
        guard userDefaults.object(forKey: Keys.usageMigrated) == nil else { return }

        let domains = legacyDomains ?? legacyUsageDomains(userDefaults: userDefaults)
        var totalSessions = userDefaults.integer(forKey: Keys.usageTotalSessions)
        var totalWords = userDefaults.integer(forKey: Keys.usageTotalWords)
        var totalCharacters = userDefaults.integer(forKey: Keys.usageTotalCharacters)
        var totalDuration = userDefaults.double(forKey: Keys.usageTotalDuration)
        var dailyActivity = intDictionary(userDefaults.dictionary(forKey: Keys.usageDailyActivity))
        var lastUpdated = userDefaults.object(forKey: Keys.usageLastUpdated) as? Date

        for domainName in domains {
            guard let domain = userDefaults.persistentDomain(forName: domainName) else { continue }
            totalSessions += intValue(domain[Keys.usageTotalSessions])
            totalWords += intValue(domain[Keys.usageTotalWords])
            totalCharacters += intValue(domain[Keys.usageTotalCharacters])
            totalDuration += doubleValue(domain[Keys.usageTotalDuration])
            dailyActivity = mergeDailyActivity(dailyActivity, intDictionary(domain[Keys.usageDailyActivity]))
            if let legacyDate = domain[Keys.usageLastUpdated] as? Date {
                lastUpdated = [lastUpdated, legacyDate].compactMap { $0 }.max()
            }
        }

        userDefaults.set(totalSessions, forKey: Keys.usageTotalSessions)
        userDefaults.set(totalWords, forKey: Keys.usageTotalWords)
        userDefaults.set(totalCharacters, forKey: Keys.usageTotalCharacters)
        userDefaults.set(totalDuration, forKey: Keys.usageTotalDuration)
        userDefaults.set(dailyActivity, forKey: Keys.usageDailyActivity)
        if let lastUpdated {
            userDefaults.set(lastUpdated, forKey: Keys.usageLastUpdated)
        }
        userDefaults.set(true, forKey: Keys.usageMigrated)
    }

    static func migrateSourceUsageIfNeeded(
        userDefaults: UserDefaults = .standard,
        legacyDomains: [String]? = nil
    ) {
        guard userDefaults.object(forKey: Keys.sourceUsageMigrated) == nil else { return }

        var merged = sourceUsageStats(from: userDefaults.data(forKey: Keys.sourceUsageStats))
        for domainName in legacyDomains ?? legacySourceUsageDomains(userDefaults: userDefaults) {
            guard let domain = userDefaults.persistentDomain(forName: domainName),
                  let data = domain[Keys.sourceUsageStats] as? Data else { continue }
            merged = mergeSourceUsage(merged, sourceUsageStats(from: data))
        }

        if let data = encodeSourceUsageStats(merged) {
            userDefaults.set(data, forKey: Keys.sourceUsageStats)
        }
        userDefaults.set(true, forKey: Keys.sourceUsageMigrated)
    }

    static func migrateKeychainIfNeeded(
        userDefaults: UserDefaults = .standard,
        keychainService: KeychainServiceProtocol = KeychainService.shared
    ) {
        guard userDefaults.object(forKey: Keys.keychainMigrated) == nil else { return }

        for account in ["OpenAI", "Gemini"] {
            guard keychainService.getQuietly(service: AppIdentity.keychainService, account: account) == nil,
                  let legacyKey = keychainService.getQuietly(service: AppIdentity.legacyKeychainService, account: account),
                  !legacyKey.isEmpty else { continue }
            keychainService.saveQuietly(legacyKey, service: AppIdentity.keychainService, account: account)
        }

        userDefaults.set(true, forKey: Keys.keychainMigrated)
    }

    static func migrateApplicationSupportIfNeeded(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard userDefaults.object(forKey: Keys.appSupportMigrated) == nil else { return }

        do {
            let source = try AppIdentity.legacyApplicationSupportDirectory(fileManager: fileManager)
            let target = try AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            copyFileIfMissing(name: "categories.json", from: source, to: target, fileManager: fileManager)
            copyDirectoryContentsIfMissing(name: "prompts", from: source, to: target, fileManager: fileManager)
        } catch {
            Logger.app.error("Failed to migrate application support files: \(error.localizedDescription)")
        }

        userDefaults.set(true, forKey: Keys.appSupportMigrated)
    }

    static func migrateSwiftDataStoreIfNeeded(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard userDefaults.object(forKey: Keys.swiftDataMigrated) == nil else { return }

        do {
            let target = try AppIdentity.swiftDataStoreURL(fileManager: fileManager)
            let candidates = try legacySwiftDataCandidates(fileManager: fileManager)

            if fileManager.fileExists(atPath: target.path),
               let targetRecordCount = transcriptionRecordCount(in: target, fileManager: fileManager),
               targetRecordCount > 0 {
                userDefaults.set(true, forKey: Keys.swiftDataMigrated)
                return
            }

            let source = candidates.first { candidate in
                fileManager.fileExists(atPath: candidate.path) &&
                    (transcriptionRecordCount(in: candidate, fileManager: fileManager) ?? 1) > 0
            }

            if let source {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try copyStoreFamily(from: source, to: target, fileManager: fileManager, replacingExisting: true)
            }
        } catch {
            Logger.dataManager.error("Failed to migrate SwiftData store: \(error.localizedDescription)")
        }

        userDefaults.set(true, forKey: Keys.swiftDataMigrated)
    }
}

private extension AppMigration {
    static var legacyPreferenceDomains: [String] {
        [
            AppIdentity.legacyBundleIdentifier,
            AppIdentity.legacyDevelopmentBundleIdentifier
        ]
    }

    static func shouldCopyPreferenceKey(_ key: String) -> Bool {
        if key.hasPrefix("NS") { return false }
        if key.hasPrefix("usage.") { return false }
        if key.hasPrefix("sourceUsage.") { return false }
        if key.hasPrefix("migration.") { return false }
        return true
    }

    static func legacyUsageDomains(userDefaults: UserDefaults) -> [String] {
        guard let production = userDefaults.persistentDomain(forName: AppIdentity.legacyBundleIdentifier),
              boolValue(production[Keys.usageImportedDevelopment]) else {
            return legacyPreferenceDomains
        }
        return [AppIdentity.legacyBundleIdentifier]
    }

    static func legacySourceUsageDomains(userDefaults: UserDefaults) -> [String] {
        guard let production = userDefaults.persistentDomain(forName: AppIdentity.legacyBundleIdentifier),
              boolValue(production[Keys.sourceUsageImportedDevelopment]) else {
            return legacyPreferenceDomains
        }
        return [AppIdentity.legacyBundleIdentifier]
    }

    static func intDictionary(_ value: Any?) -> [String: Int] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        return dictionary.reduce(into: [:]) { result, entry in
            result[entry.key] = intValue(entry.value)
        }
    }

    static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    static func doubleValue(_ value: Any?) -> Double {
        if let double = value as? Double { return double }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return string == "1" || string.lowercased() == "true" }
        return false
    }

    static func mergeDailyActivity(_ lhs: [String: Int], _ rhs: [String: Int]) -> [String: Int] {
        var merged = lhs
        for (day, count) in rhs {
            merged[day, default: 0] += count
        }
        return merged
    }

    static func sourceUsageStats(from data: Data?) -> [String: SourceUsageStats] {
        guard let data else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: SourceUsageStats].self, from: data)) ?? [:]
    }

    static func encodeSourceUsageStats(_ stats: [String: SourceUsageStats]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(stats)
    }

    static func mergeSourceUsage(
        _ current: [String: SourceUsageStats],
        _ legacy: [String: SourceUsageStats]
    ) -> [String: SourceUsageStats] {
        var merged = current
        for (bundleIdentifier, legacyStat) in legacy {
            if let currentStat = merged[bundleIdentifier] {
                merged[bundleIdentifier] = SourceUsageStats(
                    bundleIdentifier: bundleIdentifier,
                    displayName: currentStat.displayName.isEmpty ? legacyStat.displayName : currentStat.displayName,
                    totalWords: currentStat.totalWords + legacyStat.totalWords,
                    totalCharacters: currentStat.totalCharacters + legacyStat.totalCharacters,
                    sessionCount: currentStat.sessionCount + legacyStat.sessionCount,
                    lastUsed: max(currentStat.lastUsed, legacyStat.lastUsed),
                    iconData: currentStat.iconData ?? legacyStat.iconData,
                    fallbackSymbolName: currentStat.fallbackSymbolName ?? legacyStat.fallbackSymbolName
                )
            } else {
                merged[bundleIdentifier] = legacyStat
            }
        }
        return merged
    }

    static func copyFileIfMissing(name: String, from source: URL, to target: URL, fileManager: FileManager) {
        let sourceURL = source.appendingPathComponent(name)
        let targetURL = target.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: sourceURL.path),
              !fileManager.fileExists(atPath: targetURL.path) else { return }
        try? fileManager.copyItem(at: sourceURL, to: targetURL)
    }

    static func copyDirectoryContentsIfMissing(name: String, from source: URL, to target: URL, fileManager: FileManager) {
        let sourceURL = source.appendingPathComponent(name, isDirectory: true)
        let targetURL = target.appendingPathComponent(name, isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil) else { return }
        try? fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
        for file in files {
            let destination = targetURL.appendingPathComponent(file.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.copyItem(at: file, to: destination)
        }
    }

    static func legacySwiftDataCandidates(fileManager: FileManager) throws -> [URL] {
        let base = try AppIdentity.applicationSupportBaseDirectory(fileManager: fileManager)
        let legacySupport = try AppIdentity.legacyApplicationSupportDirectory(fileManager: fileManager)
        return [
            base.appendingPathComponent(AppIdentity.legacySwiftDataStoreName),
            base.appendingPathComponent("AudioWhisper.store"),
            legacySupport.appendingPathComponent("AudioWhisper.store")
        ]
    }

    static func copyStoreFamily(
        from source: URL,
        to target: URL,
        fileManager: FileManager,
        replacingExisting: Bool = false
    ) throws {
        for suffix in ["", "-wal", "-shm"] {
            let sourceURL = URL(fileURLWithPath: source.path + suffix)
            let targetURL = URL(fileURLWithPath: target.path + suffix)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            if fileManager.fileExists(atPath: targetURL.path) {
                guard replacingExisting else { continue }
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }
    }

    static func transcriptionRecordCount(in storeURL: URL, fileManager: FileManager) -> Int? {
        let fileSize = (try? storeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileManager.fileExists(atPath: storeURL.path),
              fileSize > 0,
              isSQLiteStore(storeURL) else {
            return nil
        }

        var database: OpaquePointer?
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storeURL.path, &database, openFlags, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM ZTRANSCRIPTIONRECORD"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    static func isSQLiteStore(_ storeURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: storeURL) else { return false }
        defer { try? handle.close() }

        let header = handle.readData(ofLength: 16)
        return String(data: header, encoding: .ascii) == "SQLite format 3\u{0000}"
    }
}
