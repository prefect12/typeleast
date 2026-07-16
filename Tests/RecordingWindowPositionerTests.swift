import XCTest
@testable import Typeleast

final class RecordingWindowPositionerTests: XCTestCase {
    private let windowSize = LayoutMetrics.RecordingWindow.size
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testStreamingTestNeverAutomaticallyOpensAccessibilitySettings() {
        XCTAssertFalse(RecordingWindowPositioner.shouldRequestAccessibilityPermission(
            isTrusted: false,
            hasRequested: false,
            isTestEnvironment: false,
            isStreamingTest: true
        ))
    }

    func testProductionNeverAutomaticallyOpensAccessibilitySettings() {
        XCTAssertFalse(RecordingWindowPositioner.shouldRequestAccessibilityPermission(
            isTrusted: false,
            hasRequested: false,
            isTestEnvironment: false,
            isStreamingTest: false
        ))
        XCTAssertFalse(RecordingWindowPositioner.shouldRequestAccessibilityPermission(
            isTrusted: false,
            hasRequested: true,
            isTestEnvironment: false,
            isStreamingTest: false
        ))
    }

    func testPreferredOriginUsesCaretBelowWhenThereIsRoom() {
        let caret = CGRect(x: 420, y: 300, width: 2, height: 20)

        let origin = RecordingWindowPositioner.preferredOrigin(
            windowSize: windowSize,
            caretRect: caret,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 420)
        XCTAssertEqual(origin.y, 244)
    }

    func testPreferredOriginMovesAboveCaretNearBottomEdge() {
        let caret = CGRect(x: 420, y: 50, width: 2, height: 20)

        let origin = RecordingWindowPositioner.preferredOrigin(
            windowSize: windowSize,
            caretRect: caret,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 420)
        XCTAssertEqual(origin.y, 78)
    }

    func testPreferredOriginClampsToVisibleFrameAtRightEdge() {
        let caret = CGRect(x: 1160, y: 300, width: 2, height: 20)

        let origin = RecordingWindowPositioner.preferredOrigin(
            windowSize: windowSize,
            caretRect: caret,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 1008)
        XCTAssertEqual(origin.y, 244)
    }

    func testPreferredOriginUsesFocusedElementWithoutCaret() {
        let origin = RecordingWindowPositioner.preferredOrigin(
            windowSize: windowSize,
            caretRect: nil,
            focusedElementRect: CGRect(x: 760, y: 120, width: 320, height: 80),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 760)
        XCTAssertEqual(origin.y, 208)
    }

    func testPreferredOriginUsesLowerWindowAreaWithoutCaretOrFocusedElement() {
        let origin = RecordingWindowPositioner.preferredOrigin(
            windowSize: windowSize,
            caretRect: nil,
            focusedElementRect: nil,
            focusedWindowRect: CGRect(x: 200, y: 100, width: 800, height: 600),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 510)
        XCTAssertEqual(origin.y, 164)
    }

    func testPreferredOriginUsesLowerScreenAreaWithoutAnyAccessibilityContext() {
        let origin = RecordingWindowPositioner.preferredOrigin(
            windowSize: windowSize,
            caretRect: nil,
            focusedElementRect: nil,
            focusedWindowRect: nil,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 510)
        XCTAssertEqual(origin.y, 64)
    }

    func testPreferredOriginClampsLargeWindowAtRightEdge() {
        let caret = CGRect(x: 1160, y: 300, width: 2, height: 20)

        let origin = RecordingWindowPositioner.preferredOrigin(
            windowSize: LayoutMetrics.RecordingWindow.maximumSize,
            caretRect: caret,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 828)
        XCTAssertEqual(origin.y, 188)
    }

    func testPreferredOriginUsesWideInputElementWhenItIsNotFullHeight() {
        let origin = RecordingWindowPositioner.preferredOrigin(
            windowSize: windowSize,
            caretRect: nil,
            focusedElementRect: CGRect(x: 120, y: 90, width: 980, height: 120),
            focusedWindowRect: CGRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 120)
        XCTAssertEqual(origin.y, 218)
    }

    func testPreferredOriginIgnoresFullPageElementAndUsesLowerWindowArea() {
        let origin = RecordingWindowPositioner.preferredOrigin(
            windowSize: windowSize,
            caretRect: nil,
            focusedElementRect: CGRect(x: 0, y: 0, width: 1150, height: 760),
            focusedWindowRect: CGRect(x: 200, y: 100, width: 800, height: 600),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 510)
        XCTAssertEqual(origin.y, 164)
    }
}
