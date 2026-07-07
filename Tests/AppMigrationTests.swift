import XCTest
import SQLite3
@testable import Typeleast

final class AppMigrationTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var legacyDomainName: String!
    private var legacyDevDomainName: String!
    private var defaults: UserDefaults!
    private var keychain: MockKeychainService!
    private var tempRoot: URL!
    private var originalAppSupportOverride: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "com.typeleast.tests.migration.\(UUID().uuidString)"
        legacyDomainName = "\(defaultsSuiteName!).legacy"
        legacyDevDomainName = "\(defaultsSuiteName!).legacy-dev"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: legacyDomainName)
        defaults.removePersistentDomain(forName: legacyDevDomainName)
        keychain = MockKeychainService()

        originalAppSupportOverride = ProcessInfo.processInfo.environment[AppIdentity.appSupportOverrideEnvironmentKey]
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("AppMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        setenv(AppIdentity.appSupportOverrideEnvironmentKey, tempRoot.path, 1)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: legacyDomainName)
        defaults.removePersistentDomain(forName: legacyDevDomainName)
        defaults = nil
        keychain = nil
        if let originalAppSupportOverride {
            setenv(AppIdentity.appSupportOverrideEnvironmentKey, originalAppSupportOverride, 1)
        } else {
            unsetenv(AppIdentity.appSupportOverrideEnvironmentKey)
        }
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    func testUserDefaultsMigrationCopiesMissingValuesWithoutOverwritingCurrentValues() {
        defaults.set("openai", forKey: AppDefaults.Keys.transcriptionProvider, inDomain: legacyDomainName)
        defaults.set("gemini", forKey: AppDefaults.Keys.transcriptionProvider)
        defaults.set(true, forKey: AppDefaults.Keys.enableSmartPaste, inDomain: legacyDomainName)

        AppMigration.migrateUserDefaultsIfNeeded(userDefaults: defaults, legacyDomains: [legacyDomainName])

        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.transcriptionProvider), "gemini")
        XCTAssertEqual(defaults.object(forKey: AppDefaults.Keys.enableSmartPaste) as? Bool, true)
    }

    func testUserDefaultsMigrationPrefersLegacyProductionOverLegacyDevelopment() {
        defaults.set("openai", forKey: AppDefaults.Keys.transcriptionProvider, inDomain: legacyDomainName)
        defaults.set("gemini", forKey: AppDefaults.Keys.transcriptionProvider, inDomain: legacyDevDomainName)

        AppMigration.migrateUserDefaultsIfNeeded(userDefaults: defaults, legacyDomains: [legacyDomainName, legacyDevDomainName])

        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.transcriptionProvider), "openai")
    }

    func testUsageMigrationMergesProductionAndDevelopmentWhenProductionDidNotImportDev() {
        defaults.set(2, forKey: "usage.totalSessions", inDomain: legacyDomainName)
        defaults.set(10, forKey: "usage.totalWords", inDomain: legacyDomainName)
        defaults.set(["2026-07-01": 10], forKey: "usage.dailyActivity", inDomain: legacyDomainName)
        defaults.set(3, forKey: "usage.totalSessions", inDomain: legacyDevDomainName)
        defaults.set(5, forKey: "usage.totalWords", inDomain: legacyDevDomainName)
        defaults.set(["2026-07-01": 1, "2026-07-02": 4], forKey: "usage.dailyActivity", inDomain: legacyDevDomainName)

        AppMigration.migrateUsageIfNeeded(userDefaults: defaults, legacyDomains: [legacyDevDomainName, legacyDomainName])

        XCTAssertEqual(defaults.integer(forKey: "usage.totalSessions"), 5)
        XCTAssertEqual(defaults.integer(forKey: "usage.totalWords"), 15)
        XCTAssertEqual(defaults.dictionary(forKey: "usage.dailyActivity") as? [String: Int], [
            "2026-07-01": 11,
            "2026-07-02": 4
        ])
    }

    func testSourceUsageMigrationMergesStatsByBundleIdentifier() throws {
        let current = SourceUsageStats(
            bundleIdentifier: "com.example.app",
            displayName: "Current",
            totalWords: 3,
            totalCharacters: 12,
            sessionCount: 1,
            lastUsed: Date(timeIntervalSince1970: 10),
            iconData: nil,
            fallbackSymbolName: "doc.text"
        )
        let legacy = SourceUsageStats(
            bundleIdentifier: "com.example.app",
            displayName: "Legacy",
            totalWords: 7,
            totalCharacters: 20,
            sessionCount: 2,
            lastUsed: Date(timeIntervalSince1970: 20),
            iconData: nil,
            fallbackSymbolName: "text.cursor"
        )
        defaults.set(try encodeSourceUsage(["com.example.app": current]), forKey: "sourceUsage.stats")
        defaults.set(try encodeSourceUsage(["com.example.app": legacy]), forKey: "sourceUsage.stats", inDomain: legacyDomainName)

        AppMigration.migrateSourceUsageIfNeeded(userDefaults: defaults, legacyDomains: [legacyDomainName])

        let decoded = try decodeSourceUsage(defaults.data(forKey: "sourceUsage.stats"))
        XCTAssertEqual(decoded["com.example.app"]?.totalWords, 10)
        XCTAssertEqual(decoded["com.example.app"]?.totalCharacters, 32)
        XCTAssertEqual(decoded["com.example.app"]?.sessionCount, 3)
        XCTAssertEqual(decoded["com.example.app"]?.displayName, "Current")
        XCTAssertEqual(decoded["com.example.app"]?.lastUsed, Date(timeIntervalSince1970: 20))
    }

    func testKeychainMigrationCopiesLegacyKeysOnlyWhenTypeleastKeyIsMissing() {
        keychain.saveQuietly("legacy-openai", service: AppIdentity.legacyKeychainService, account: "OpenAI")
        keychain.saveQuietly("current-gemini", service: AppIdentity.keychainService, account: "Gemini")
        keychain.saveQuietly("legacy-gemini", service: AppIdentity.legacyKeychainService, account: "Gemini")

        AppMigration.migrateKeychainIfNeeded(userDefaults: defaults, keychainService: keychain)

        XCTAssertEqual(keychain.getQuietly(service: AppIdentity.keychainService, account: "OpenAI"), "legacy-openai")
        XCTAssertEqual(keychain.getQuietly(service: AppIdentity.keychainService, account: "Gemini"), "current-gemini")
    }

    func testApplicationSupportMigrationCopiesOnlyLightweightFiles() throws {
        let legacy = tempRoot.appendingPathComponent(AppIdentity.legacyAppSupportDirectoryName, isDirectory: true)
        let prompts = legacy.appendingPathComponent("prompts", isDirectory: true)
        let legacyVenv = legacy.appendingPathComponent("python_project/.venv", isDirectory: true)
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyVenv, withIntermediateDirectories: true)
        try #"{"categories":[]}"#.write(to: legacy.appendingPathComponent("categories.json"), atomically: true, encoding: .utf8)
        try "prompt".write(to: prompts.appendingPathComponent("local_mlx_prompt.txt"), atomically: true, encoding: .utf8)
        try "do-not-copy".write(to: legacyVenv.appendingPathComponent("marker"), atomically: true, encoding: .utf8)

        AppMigration.migrateApplicationSupportIfNeeded(userDefaults: defaults)

        let target = tempRoot.appendingPathComponent(AppIdentity.appSupportDirectoryName, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("categories.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("prompts/local_mlx_prompt.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("python_project/.venv/marker").path))
    }

    func testSwiftDataMigrationCopiesDefaultStoreFamilyIntoTypeleastDirectory() throws {
        let source = tempRoot.appendingPathComponent(AppIdentity.legacySwiftDataStoreName)
        try Data("store".utf8).write(to: source)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: source.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: source.path + "-shm"))

        AppMigration.migrateSwiftDataStoreIfNeeded(userDefaults: defaults)

        let target = try AppIdentity.swiftDataStoreURL()
        XCTAssertEqual(try String(contentsOf: target), "store")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: target.path + "-wal")), "wal")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: target.path + "-shm")), "shm")
    }

    func testSwiftDataMigrationReplacesEmptyTargetWhenLegacyHasTranscriptionRecords() throws {
        let source = tempRoot.appendingPathComponent(AppIdentity.legacySwiftDataStoreName)
        try createTranscriptionStore(at: source, recordCount: 2)

        let target = try AppIdentity.swiftDataStoreURL()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try createTranscriptionStore(at: target, recordCount: 0)

        AppMigration.migrateSwiftDataStoreIfNeeded(userDefaults: defaults)

        XCTAssertEqual(try transcriptionRecordCount(in: target), 2)
    }

    func testSwiftDataMigrationDoesNotReplaceTargetThatAlreadyHasRecords() throws {
        let source = tempRoot.appendingPathComponent(AppIdentity.legacySwiftDataStoreName)
        try createTranscriptionStore(at: source, recordCount: 2)

        let target = try AppIdentity.swiftDataStoreURL()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try createTranscriptionStore(at: target, recordCount: 1)

        AppMigration.migrateSwiftDataStoreIfNeeded(userDefaults: defaults)

        XCTAssertEqual(try transcriptionRecordCount(in: target), 1)
    }
}

private extension UserDefaults {
    func set(_ value: Any, forKey key: String, inDomain domainName: String) {
        var domain = persistentDomain(forName: domainName) ?? [:]
        domain[key] = value
        setPersistentDomain(domain, forName: domainName)
    }
}

private func encodeSourceUsage(_ stats: [String: SourceUsageStats]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(stats)
}

private func decodeSourceUsage(_ data: Data?) throws -> [String: SourceUsageStats] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([String: SourceUsageStats].self, from: XCTUnwrap(data))
}

private func createTranscriptionStore(at url: URL, recordCount: Int) throws {
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
    defer { sqlite3_close(database) }

    XCTAssertEqual(
        sqlite3_exec(
            database,
            "CREATE TABLE ZTRANSCRIPTIONRECORD (Z_PK INTEGER PRIMARY KEY);",
            nil,
            nil,
            nil
        ),
        SQLITE_OK
    )

    for index in 0..<recordCount {
        XCTAssertEqual(
            sqlite3_exec(
                database,
                "INSERT INTO ZTRANSCRIPTIONRECORD (Z_PK) VALUES (\(index + 1));",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
    }
}

private func transcriptionRecordCount(in url: URL) throws -> Int {
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
    defer { sqlite3_close(database) }

    var statement: OpaquePointer?
    XCTAssertEqual(
        sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM ZTRANSCRIPTIONRECORD", -1, &statement, nil),
        SQLITE_OK
    )
    defer { sqlite3_finalize(statement) }

    XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
    return Int(sqlite3_column_int64(statement, 0))
}
