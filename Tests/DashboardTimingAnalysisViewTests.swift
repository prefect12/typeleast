import XCTest
@testable import Typeleast

final class DashboardTimingAnalysisViewTests: XCTestCase {
    func testBottleneckStageTotalsIncludesUntrackedProcessing() {
        let totals: [(stage: TimingStage, seconds: TimeInterval)] = [
            (.untrackedProcessing, 120),
            (.asr, 8),
            (.paste, 3)
        ]

        let bottlenecks = DashboardTimingAnalysisView.bottleneckStageTotals(from: totals)

        XCTAssertEqual(bottlenecks.map(\.stage), [.untrackedProcessing, .asr, .paste])
    }
}
