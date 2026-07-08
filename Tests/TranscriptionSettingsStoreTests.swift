import XCTest
@testable import Typeleast

final class TranscriptionSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TranscriptionSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsUseAppDefaults() {
        let store = TranscriptionSettingsStore(defaults: defaults)

        XCTAssertEqual(store.transcriptionProvider, AppDefaults.defaultTranscriptionProvider)
        XCTAssertEqual(store.selectedWhisperModel, AppDefaults.defaultWhisperModel)
        XCTAssertEqual(store.selectedParakeetModel, AppDefaults.defaultParakeetModel)
        XCTAssertEqual(store.openAITranscriptionModel, AppDefaults.defaultOpenAITranscriptionModel)
        XCTAssertEqual(store.openAIRealtimeTranscriptionModel, AppDefaults.defaultOpenAIRealtimeTranscriptionModel)
        XCTAssertEqual(store.openAIRealtimeTranscriptionDelay, AppDefaults.defaultOpenAIRealtimeTranscriptionDelay)
        XCTAssertEqual(store.miMoASRModel, AppDefaults.defaultMiMoASRModel)
        XCTAssertEqual(store.transcriptionLanguage, AppDefaults.defaultTranscriptionLanguage)
        XCTAssertEqual(store.recordingHUDStyle, AppDefaults.defaultRecordingHUDStyle)
        XCTAssertEqual(store.semanticCorrectionMode, AppDefaults.defaultSemanticCorrectionMode)
        XCTAssertEqual(store.semanticCorrectionModelRepo, AppDefaults.defaultSemanticCorrectionModelRepo)
        XCTAssertEqual(store.transcriptionRetentionPeriod, .forever)
    }

    func testInvalidEnumValuesFallBackSafely() {
        defaults.set("invalid-provider", forKey: AppDefaults.Keys.transcriptionProvider)
        defaults.set("invalid-whisper", forKey: AppDefaults.Keys.selectedWhisperModel)
        defaults.set("invalid-parakeet", forKey: AppDefaults.Keys.selectedParakeetModel)
        defaults.set("invalid-language", forKey: AppDefaults.Keys.transcriptionLanguage)
        defaults.set("invalid-delay", forKey: AppDefaults.Keys.openAIRealtimeTranscriptionDelay)
        defaults.set("invalid-hud-style", forKey: AppDefaults.Keys.recordingHUDStyle)
        defaults.set("invalid-correction", forKey: AppDefaults.Keys.semanticCorrectionMode)
        defaults.set("invalid-retention", forKey: AppDefaults.Keys.transcriptionRetentionPeriod)

        let store = TranscriptionSettingsStore(defaults: defaults)

        XCTAssertEqual(store.transcriptionProvider, AppDefaults.defaultTranscriptionProvider)
        XCTAssertEqual(store.selectedWhisperModel, AppDefaults.defaultWhisperModel)
        XCTAssertEqual(store.selectedParakeetModel, AppDefaults.defaultParakeetModel)
        XCTAssertEqual(store.transcriptionLanguage, AppDefaults.defaultTranscriptionLanguage)
        XCTAssertEqual(store.openAIRealtimeTranscriptionDelay, AppDefaults.defaultOpenAIRealtimeTranscriptionDelay)
        XCTAssertEqual(store.recordingHUDStyle, AppDefaults.defaultRecordingHUDStyle)
        XCTAssertEqual(store.semanticCorrectionMode, AppDefaults.defaultSemanticCorrectionMode)
        XCTAssertEqual(store.transcriptionRetentionPeriod, .forever)
    }

    func testBlankModelStringsFallBackSafely() {
        defaults.set("   ", forKey: AppDefaults.Keys.openAITranscriptionModel)
        defaults.set("", forKey: AppDefaults.Keys.openAIRealtimeTranscriptionModel)
        defaults.set("\n\t", forKey: AppDefaults.Keys.miMoASRModel)
        defaults.set("", forKey: AppDefaults.Keys.semanticCorrectionModelRepo)

        let store = TranscriptionSettingsStore(defaults: defaults)

        XCTAssertEqual(store.openAITranscriptionModel, AppDefaults.defaultOpenAITranscriptionModel)
        XCTAssertEqual(store.openAIRealtimeTranscriptionModel, AppDefaults.defaultOpenAIRealtimeTranscriptionModel)
        XCTAssertEqual(store.miMoASRModel, AppDefaults.defaultMiMoASRModel)
        XCTAssertEqual(store.semanticCorrectionModelRepo, AppDefaults.defaultSemanticCorrectionModelRepo)
    }

    func testRetentionPeriodWritesThroughTypedStore() {
        let store = TranscriptionSettingsStore(defaults: defaults)

        store.transcriptionRetentionPeriod = .threeMonths

        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.transcriptionRetentionPeriod), RetentionPeriod.threeMonths.rawValue)
        XCTAssertEqual(store.transcriptionRetentionPeriod, .threeMonths)
    }
}
