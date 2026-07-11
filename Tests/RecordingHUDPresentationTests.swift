import XCTest
@testable import Typeleast

final class RecordingHUDPresentationTests: XCTestCase {
    func testShortTextIsDisplayedWithoutModification() {
        XCTAssertEqual(RecordingHUDPresentation.latestText("正在聆听"), "正在聆听")
    }

    func testLongTranscriptKeepsLatestCharactersVisible() {
        let transcript = String(repeating: "前", count: 80) + String(repeating: "后", count: 80)
        let visible = RecordingHUDPresentation.latestText(transcript, limit: 100)

        XCTAssertTrue(visible.hasPrefix("…"))
        XCTAssertTrue(visible.hasSuffix(String(repeating: "后", count: 80)))
        XCTAssertEqual(visible.count, 101)
    }

    func testStreamingTestHUDStylesKeepReadableButDistinctShapes() {
        let glassSize = LayoutMetrics.RecordingWindow.streamingTestSize(for: .appleGlass)
        let auraSize = LayoutMetrics.RecordingWindow.streamingTestSize(for: .siriAura)
        let candidateSize = LayoutMetrics.RecordingWindow.streamingTestSize(for: .candidateBar)

        XCTAssertGreaterThanOrEqual(glassSize.width, 400)
        XCTAssertGreaterThanOrEqual(auraSize.width, 400)
        XCTAssertGreaterThanOrEqual(candidateSize.width, 400)
        XCTAssertGreaterThan(auraSize.width, glassSize.width)
        XCTAssertLessThan(candidateSize.height, glassSize.height)

        XCTAssertGreaterThan(
            RecordingHUDPresentation.cornerRadius(for: .siriAura, isStreamingTest: true),
            RecordingHUDPresentation.cornerRadius(for: .appleGlass, isStreamingTest: true)
        )
    }
}
