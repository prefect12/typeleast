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
        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.globalHotkey), "modifierOnly:rightCommand")
        XCTAssertEqual(defaults.bool(forKey: AppDefaults.Keys.immediateRecording), false)
        XCTAssertEqual(defaults.bool(forKey: AppDefaults.Keys.startAtLogin), false)
        XCTAssertEqual(defaults.bool(forKey: AppDefaults.Keys.pressAndHoldEnabled), true)
        XCTAssertEqual(defaults.bool(forKey: AppDefaults.Keys.enableStreamingTranscription), true)
    }

    func testStreamingTestV3MigrationRestoresRightCommandHoldMode() {
        defaults.set(true, forKey: "streamingTestDefaultsConfiguredV2")
        defaults.set("⌃⌥Space", forKey: AppDefaults.Keys.globalHotkey)
        defaults.set(true, forKey: AppDefaults.Keys.immediateRecording)
        defaults.set(false, forKey: AppDefaults.Keys.pressAndHoldEnabled)
        defaults.set(PressAndHoldKey.rightCommand.rawValue, forKey: AppDefaults.Keys.pressAndHoldKeyIdentifier)
        defaults.set(PressAndHoldMode.doubleTapToggle.rawValue, forKey: AppDefaults.Keys.pressAndHoldMode)

        AppDefaults.configureStreamingTestDefaultsIfNeeded(
            defaults: defaults,
            isStreamingTest: true
        )

        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.globalHotkey), "modifierOnly:rightCommand")
        XCTAssertFalse(defaults.bool(forKey: AppDefaults.Keys.immediateRecording))
        XCTAssertTrue(defaults.bool(forKey: AppDefaults.Keys.pressAndHoldEnabled))
        XCTAssertEqual(
            defaults.string(forKey: AppDefaults.Keys.pressAndHoldKeyIdentifier),
            PressAndHoldConfiguration.defaults.key.rawValue
        )
        XCTAssertEqual(
            defaults.string(forKey: AppDefaults.Keys.pressAndHoldMode),
            PressAndHoldMode.hold.rawValue
        )
        XCTAssertTrue(defaults.bool(forKey: "streamingTestDefaultsConfiguredV3"))
    }
}

private extension UserDefaults {
    func set(_ value: Any, forKey key: String, inDomain domainName: String) {
        var domain = persistentDomain(forName: domainName) ?? [:]
        domain[key] = value
        setPersistentDomain(domain, forName: domainName)
    }
}
