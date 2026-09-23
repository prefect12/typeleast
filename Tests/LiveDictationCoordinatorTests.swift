import XCTest
@testable import Typeleast

final class LiveDictationCoordinatorTests: XCTestCase {
    func testRewarmBacksOffAfterRepeatedFailuresAndIsCapped() {
        XCTAssertEqual(LiveDictationCoordinator.rewarmDelay(afterConsecutiveFailures: 0), 1)
        XCTAssertEqual(LiveDictationCoordinator.rewarmDelay(afterConsecutiveFailures: 1), 3)
        XCTAssertEqual(LiveDictationCoordinator.rewarmDelay(afterConsecutiveFailures: 3), 12)
        XCTAssertEqual(LiveDictationCoordinator.rewarmDelay(afterConsecutiveFailures: 20), 300)
    }

    func testContextualTranscriptionRunsForChineseByDefaultAndCanBeDisabled() throws {
        let suite = "LiveDictationCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(LiveDictationCoordinator.shouldUseContextualTranscription(language: .chineseEnglish, defaults: defaults))
        XCTAssertTrue(LiveDictationCoordinator.shouldUseContextualTranscription(language: .chinese, defaults: defaults))
        XCTAssertFalse(LiveDictationCoordinator.shouldUseContextualTranscription(language: .english, defaults: defaults))

        defaults.set(false, forKey: AppDefaults.Keys.contextualTranscriptionEnabled)
        XCTAssertFalse(LiveDictationCoordinator.shouldUseContextualTranscription(language: .chineseEnglish, defaults: defaults))
    }

    func testComparableTextIgnoresPunctuationSpacingAndCase() {
        XCTAssertEqual(
            LiveDictationCoordinator.comparableText("这个 Campaign 的数据怎么样？"),
            LiveDictationCoordinator.comparableText("这个campaign的数据怎么样?")
        )
        XCTAssertNotEqual(
            LiveDictationCoordinator.comparableText("这个看片的数据"),
            LiveDictationCoordinator.comparableText("这个campaign的数据")
        )
    }
}
