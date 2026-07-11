import XCTest
@testable import Typeleast

final class AppDefaultsTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var productionDomainName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "com.typeleast.tests.appdefaults.\(UUID().uuidString)"
        productionDomainName = "\(defaultsSuiteName!).production"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: productionDomainName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: productionDomainName)
        defaults = nil
        productionDomainName = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testMigrateHistoryPreferencesCopiesProductionSettingsForDevBuild() {
        defaults.set(true, forKey: AppDefaults.Keys.transcriptionHistoryEnabled, inDomain: productionDomainName)
        defaults.set(RetentionPeriod.threeMonths.rawValue, forKey: AppDefaults.Keys.transcriptionRetentionPeriod, inDomain: productionDomainName)

        AppDefaults.migrateHistoryPreferencesIfNeeded(
            currentBundleIdentifier: "com.typeleast-dev.app",
            userDefaults: defaults,
            sourceBundleIdentifier: productionDomainName
        )

        XCTAssertEqual(defaults.object(forKey: AppDefaults.Keys.transcriptionHistoryEnabled) as? Bool, true)
        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.transcriptionRetentionPeriod), RetentionPeriod.threeMonths.rawValue)
    }

    func testMigrateHistoryPreferencesDoesNotOverrideExistingDevSettings() {
        defaults.set(false, forKey: AppDefaults.Keys.transcriptionHistoryEnabled)
        defaults.set(RetentionPeriod.forever.rawValue, forKey: AppDefaults.Keys.transcriptionRetentionPeriod)
        defaults.set(true, forKey: AppDefaults.Keys.transcriptionHistoryEnabled, inDomain: productionDomainName)
        defaults.set(RetentionPeriod.oneWeek.rawValue, forKey: AppDefaults.Keys.transcriptionRetentionPeriod, inDomain: productionDomainName)

        AppDefaults.migrateHistoryPreferencesIfNeeded(
            currentBundleIdentifier: "com.typeleast-dev.app",
            userDefaults: defaults,
            sourceBundleIdentifier: productionDomainName
        )

        XCTAssertEqual(defaults.object(forKey: AppDefaults.Keys.transcriptionHistoryEnabled) as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.transcriptionRetentionPeriod), RetentionPeriod.forever.rawValue)
    }

    func testStreamingTestCopiesOpenAIKeyWithoutChangingProductionItem() throws {
        let keychain = MockKeychainService()
        try keychain.save("production-key", service: AppIdentity.productionKeychainService, account: "OpenAI")

        AppDefaults.copyProductionOpenAIKeyToStreamingTestIfNeeded(
            keychain: keychain,
            defaults: defaults,
            isStreamingTest: true,
            destinationService: AppIdentity.streamingTestKeychainService
        )

        XCTAssertEqual(
            try keychain.get(service: AppIdentity.streamingTestKeychainService, account: "OpenAI"),
            "production-key"
        )
        XCTAssertEqual(
            try keychain.get(service: AppIdentity.productionKeychainService, account: "OpenAI"),
            "production-key"
        )
    }

    func testStreamingTestDefaultsAreIsolatedAndDeterministic() {
        AppDefaults.configureStreamingTestDefaultsIfNeeded(
            defaults: defaults,
            isStreamingTest: true
        )

        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.transcriptionProvider), "openaiRealtime")
        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.transcriptionLanguage), "zh-en")
        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.globalHotkey), "⌃⌥Space")
        XCTAssertEqual(defaults.bool(forKey: AppDefaults.Keys.startAtLogin), false)
        XCTAssertEqual(defaults.bool(forKey: AppDefaults.Keys.pressAndHoldEnabled), false)
        XCTAssertEqual(defaults.bool(forKey: AppDefaults.Keys.enableStreamingTranscription), true)
    }
}

private extension UserDefaults {
    func set(_ value: Any, forKey key: String, inDomain domainName: String) {
        var domain = persistentDomain(forName: domainName) ?? [:]
        domain[key] = value
        setPersistentDomain(domain, forName: domainName)
    }
}
