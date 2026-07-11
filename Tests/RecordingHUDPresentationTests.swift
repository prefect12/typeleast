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

        XCTAssertGreaterThanOrEqual(glassSize.width, 400)
        XCTAssertGreaterThanOrEqual(auraSize.width, 400)
        XCTAssertGreaterThanOrEqual(candidateSize.width, 400)
        XCTAssertGreaterThan(auraSize.width, glassSize.width)
        XCTAssertLessThan(candidateSize.height, glassSize.height)

        XCTAssertGreaterThan(
            RecordingHUDPresentation.cornerRadius(for: .siriAura, usesRealtimeLayout: true),
            RecordingHUDPresentation.cornerRadius(for: .appleGlass, usesRealtimeLayout: true)
        )
    }
}
