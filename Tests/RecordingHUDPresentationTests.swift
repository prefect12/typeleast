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

    func testRealtimeHUDStylesKeepReadableButDistinctShapes() {
        let glassSize = LayoutMetrics.RecordingWindow.realtimeSize(for: .appleGlass)
        let auraSize = LayoutMetrics.RecordingWindow.realtimeSize(for: .siriAura)
        let candidateSize = LayoutMetrics.RecordingWindow.realtimeSize(for: .candidateBar)

        XCTAssertEqual(glassSize, CGSize(width: 420, height: 82))
        XCTAssertEqual(auraSize, CGSize(width: 348, height: 64))
        XCTAssertEqual(candidateSize, CGSize(width: 420, height: 68))
        XCTAssertLessThan(auraSize.width, glassSize.width)
        XCTAssertLessThan(candidateSize.height, glassSize.height)
        XCTAssertLessThan(auraSize.width * auraSize.height, 430 * 82 * 0.65)

        XCTAssertGreaterThan(
            RecordingHUDPresentation.cornerRadius(for: .siriAura, usesRealtimeLayout: true),
            RecordingHUDPresentation.cornerRadius(for: .appleGlass, usesRealtimeLayout: true)
        )
    }
}
