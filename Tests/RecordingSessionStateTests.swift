import XCTest
@testable import Typeleast

final class RecordingSessionStateTests: XCTestCase {
    func testProcessingRejectsNewRecordingAndRepeatedStop() {
        var state = RecordingSessionState()
        XCTAssertTrue(state.beginRecording())
        let session = state.beginProcessing()!
        XCTAssertFalse(state.beginRecording())
        XCTAssertNil(state.beginProcessing())
        XCTAssertTrue(state.isCurrent(session))
    }

    func testCancelledLateResultCannotFinishNewSession() {
        var state = RecordingSessionState()
        XCTAssertTrue(state.beginRecording())
        let old = state.beginProcessing()!
        state.cancel()
        XCTAssertTrue(state.beginRecording())
        let next = state.id
        XCTAssertFalse(state.isCurrent(old))
        state.finish(old)
        XCTAssertEqual(state.phase, .recording)
        XCTAssertEqual(state.id, next)
    }

    func testRepeatedCancellationAndFinishAreSafe() {
        var state = RecordingSessionState()
        let session = state.beginProcessing()!
        state.finish(session)
        state.finish(session)
        XCTAssertEqual(state.phase, .idle)
        state.cancel()
        state.cancel()
        XCTAssertFalse(state.isCurrent(session))
    }
}
