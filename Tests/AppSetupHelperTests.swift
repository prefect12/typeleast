import XCTest
@testable import AudioWhisper

final class AppSetupHelperTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.audiowhisper.tests.appsetup.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCheckFirstRunNeverRequestsWelcome() {
        XCTAssertFalse(AppSetupHelper.checkFirstRun(userDefaults: defaults))
    }

    func testCheckFirstRunInitializesLaunchDefaults() {
        _ = AppSetupHelper.checkFirstRun(userDefaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.transcriptionProvider), AppDefaults.defaultTranscriptionProvider.rawValue)
        XCTAssertEqual(defaults.bool(forKey: AppDefaults.Keys.hasCompletedWelcome), true)
        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.lastWelcomeVersion), AppDefaults.currentWelcomeVersion)
    }

    func testCheckFirstRunPreservesExistingProvider() {
        defaults.set(TranscriptionProvider.openai.rawValue, forKey: AppDefaults.Keys.transcriptionProvider)

        _ = AppSetupHelper.checkFirstRun(userDefaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.transcriptionProvider), TranscriptionProvider.openai.rawValue)
        XCTAssertEqual(defaults.bool(forKey: AppDefaults.Keys.hasCompletedWelcome), true)
    }
}
