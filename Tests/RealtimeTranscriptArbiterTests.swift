import XCTest
@testable import Typeleast

@MainActor
final class RealtimeTranscriptArbiterTests: XCTestCase {
    private func result(_ text: String?, after milliseconds: Int) -> Task<String?, Never> {
        Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            return text
        }
    }

    func testContextualArrivingFirstWinsImmediately() async {
        let decision = await RealtimeTranscriptArbiter.decide(
            live: result("live", after: 300),
            contextual: result("contextual", after: 10),
            grace: .seconds(1)
        )
        XCTAssertEqual(decision, .init(text: "contextual", source: .contextual))
    }

    func testContextualWithinGraceAfterLiveWins() async {
        let decision = await RealtimeTranscriptArbiter.decide(
            live: result("live", after: 10),
            contextual: result("contextual", after: 80),
            grace: .milliseconds(500)
        )
        XCTAssertEqual(decision, .init(text: "contextual", source: .contextual))
    }

    func testLiveIsUsedWhenContextualMissesGrace() async {
        let startedAt = ContinuousClock().now
        let decision = await RealtimeTranscriptArbiter.decide(
            live: result("live", after: 10),
            contextual: result("contextual", after: 2_000),
            grace: .milliseconds(100)
        )
        XCTAssertEqual(decision, .init(text: "live", source: .live))
        XCTAssertLessThan(startedAt.duration(to: ContinuousClock().now), .milliseconds(1_000))
    }

    func testFailedContextualFallsBackToLiveWithoutWaitingForGrace() async {
        let startedAt = ContinuousClock().now
        let decision = await RealtimeTranscriptArbiter.decide(
            live: result("live", after: 50),
            contextual: result(nil, after: 10),
            grace: .seconds(5)
        )
        XCTAssertEqual(decision, .init(text: "live", source: .live))
        XCTAssertLessThan(startedAt.duration(to: ContinuousClock().now), .seconds(1))
    }

    func testFailedLiveWaitsForContextual() async {
        let decision = await RealtimeTranscriptArbiter.decide(
            live: result(nil, after: 10),
            contextual: result("contextual", after: 150),
            grace: .milliseconds(20)
        )
        XCTAssertEqual(decision, .init(text: "contextual", source: .contextual))
    }

    func testBothFailingYieldsNoTranscript() async {
        let decision = await RealtimeTranscriptArbiter.decide(
            live: result(nil, after: 10),
            contextual: result(nil, after: 30),
            grace: .seconds(1)
        )
        XCTAssertEqual(decision, .init(text: nil, source: nil))
    }

    func testWithoutContextualSessionUsesLive() async {
        let decision = await RealtimeTranscriptArbiter.decide(
            live: result("live", after: 10),
            contextual: nil,
            grace: .seconds(1)
        )
        XCTAssertEqual(decision, .init(text: "live", source: .live))
    }

    func testNoSpeechFromLiveStandsWhenContextualHasNothing() async {
        let decision = await RealtimeTranscriptArbiter.decide(
            live: result("", after: 10),
            contextual: result(nil, after: 30),
            grace: .seconds(1)
        )
        XCTAssertEqual(decision, .init(text: "", source: .live))
    }
}
