import XCTest
@testable import AudioWhisper

final class DashboardTimingAnalysisViewTests: XCTestCase {
    func testBottleneckStageTotalsExcludeLegacyProcessing() {
        let totals: [(stage: TimingStage, seconds: TimeInterval)] = [
            (.legacyProcessing, 120),
            (.asr, 8),
            (.paste, 3)
        ]

        let bottlenecks = DashboardTimingAnalysisView.bottleneckStageTotals(from: totals)

        XCTAssertEqual(bottlenecks.map(\.stage), [.asr, .paste])
    }

    func testBottleneckStageTotalsEmptyForLegacyOnlyRecords() {
        let totals: [(stage: TimingStage, seconds: TimeInterval)] = [
            (.legacyProcessing, 120)
        ]

        let bottlenecks = DashboardTimingAnalysisView.bottleneckStageTotals(from: totals)

        XCTAssertTrue(bottlenecks.isEmpty)
    }
}
