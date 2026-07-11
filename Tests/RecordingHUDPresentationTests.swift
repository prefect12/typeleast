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

    func testStreamingTestHUDHasStableReadableSize() {
        XCTAssertGreaterThanOrEqual(LayoutMetrics.RecordingWindow.streamingTestSize.width, 400)
        XCTAssertGreaterThanOrEqual(LayoutMetrics.RecordingWindow.streamingTestSize.height, 72)
    }
}
