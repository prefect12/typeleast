import SwiftUI
import Charts

internal enum TimingStage: String, CaseIterable, Identifiable {
    case recording
    case modelReady
    case asr
    case correction
    case legacyProcessing
    case untrackedProcessing
    case clipboard
    case paste

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: return L10n.Timing.recording
        case .modelReady: return L10n.Timing.modelReady
        case .asr: return L10n.Timing.asr
        case .correction: return L10n.Timing.correction
        case .legacyProcessing: return L10n.Timing.legacyProcessing
        case .untrackedProcessing: return L10n.Timing.untrackedProcessing
        case .clipboard: return L10n.Timing.clipboard
        case .paste: return L10n.Timing.paste
        }
    }

    var color: Color {
        switch self {
        case .recording: return Color(nsColor: .systemCyan)
        case .modelReady: return Color(nsColor: .systemIndigo)
        case .asr: return DashboardTheme.success
        case .correction: return Color(nsColor: .systemPurple)
        case .legacyProcessing: return Color(nsColor: .systemOrange)
        case .untrackedProcessing: return Color(nsColor: .systemYellow)
        case .clipboard: return DashboardTheme.accent
        case .paste: return Color(nsColor: .systemRed)
        }
    }

    var canSummarizeAsBottleneck: Bool {
        self != .legacyProcessing
    }
}

private struct TimingSegment: Identifiable {
    let id: String
    let recordID: UUID
    let chartKey: String
    let runLabel: String
    let stage: TimingStage
    let seconds: TimeInterval
}

private struct TimingRun: Identifiable {
    let record: TranscriptionRecord
    let index: Int

    var id: UUID { record.id }

    var runLabel: String {
        "#\(index + 1) · \(Self.shortFormatter.string(from: record.date))"
    }

    var chartKey: String {
        String(format: "%05d", index + 1)
    }

    var chartLabel: String {
        "\(index + 1)"
    }

    var detailLine: String {
        let provider = L10n.Provider.displayName(for: record.provider)
        let source = record.sourceAppName?.isEmpty == false ? record.sourceAppName! : "-"
        return "\(provider) · \(source)"
    }

    func segments(includeRecording: Bool) -> [TimingSegment] {
        var output: [TimingSegment] = []

        if includeRecording, let duration = record.duration, duration > 0 {
            output.append(segment(.recording, duration))
        }

        if record.hasDetailedTiming {
            appendPositive(record.modelReadyTime, stage: .modelReady, to: &output)
            appendPositive(record.asrTime, stage: .asr, to: &output)
            appendPositive(record.correctionTime, stage: .correction, to: &output)

            let knownProcessing = [record.modelReadyTime, record.asrTime, record.correctionTime]
                .compactMap { $0 }
                .reduce(0, +)
            if let total = record.transcriptionTime {
                let remaining = max(0, total - knownProcessing)
                appendPositive(remaining > 0.05 ? remaining : nil, stage: .untrackedProcessing, to: &output)
            }

            appendPositive(record.clipboardTime, stage: .clipboard, to: &output)
            appendPositive(record.pasteTime, stage: .paste, to: &output)
        } else if let total = record.transcriptionTime, total > 0 {
            output.append(segment(.legacyProcessing, total))
        }

        return output
    }

    func visibleTotal(includeRecording: Bool) -> TimeInterval {
        segments(includeRecording: includeRecording).reduce(0) { $0 + $1.seconds }
    }

    func processingTotal() -> TimeInterval {
        segments(includeRecording: false).reduce(0) { $0 + $1.seconds }
    }

    private func appendPositive(_ value: TimeInterval?, stage: TimingStage, to output: inout [TimingSegment]) {
        guard let value, value > 0 else { return }
        output.append(segment(stage, value))
    }

    private func segment(_ stage: TimingStage, _ seconds: TimeInterval) -> TimingSegment {
        TimingSegment(
            id: "\(record.id.uuidString)-\(stage.rawValue)",
            recordID: record.id,
            chartKey: chartKey,
            runLabel: runLabel,
            stage: stage,
            seconds: seconds
        )
    }

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
}

internal struct DashboardTimingAnalysisView: View {
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var records: [TranscriptionRecord] = []
    @State private var includeRecording = false
    @State private var recordLimit = 50
    @State private var hoveredRunID: UUID?
    @State private var timingHoverLocation: CGPoint?

    private var runs: [TimingRun] {
        let source = recordLimit == 0 ? records : Array(records.prefix(recordLimit))
        return source.enumerated()
            .map { TimingRun(record: $0.element, index: $0.offset) }
            .filter { !$0.segments(includeRecording: true).isEmpty }
    }

    private var visibleRuns: [TimingRun] {
        runs.filter { !$0.segments(includeRecording: includeRecording).isEmpty }
    }

    private var chartSegments: [TimingSegment] {
        visibleRuns.flatMap { $0.segments(includeRecording: includeRecording) }
    }

    private var hoveredRun: TimingRun? {
        guard let hoveredRunID else { return nil }
        return visibleRuns.first { $0.id == hoveredRunID }
    }

    private var chartWidth: CGFloat {
        max(900, CGFloat(visibleRuns.count) * 36)
    }

    private var chartYUpperBound: Double {
        let maxTotal = visibleRuns
            .map { $0.visibleTotal(includeRecording: includeRecording) }
            .max() ?? 0
        return max(1, maxTotal * 1.16)
    }

    private var xAxisVisibleKeys: [String] {
        guard !visibleRuns.isEmpty else { return [] }
        let maxLabels = 18
        let interval = max(1, Int(ceil(Double(visibleRuns.count) / Double(maxLabels))))

        return visibleRuns.enumerated().compactMap { offset, run in
            if offset == 0 || offset == visibleRuns.count - 1 || offset % interval == 0 {
                return run.chartKey
            }
            return nil
        }
    }

    private var stageTotals: [(stage: TimingStage, seconds: TimeInterval)] {
        TimingStage.allCases.compactMap { stage in
            let total = chartSegments
                .filter { $0.stage == stage }
                .reduce(0) { $0 + $1.seconds }
            return total > 0 ? (stage, total) : nil
        }
        .sorted { $0.seconds > $1.seconds }
    }

    private var bottleneckStageTotals: [(stage: TimingStage, seconds: TimeInterval)] {
        Self.bottleneckStageTotals(from: stageTotals)
    }

    static func bottleneckStageTotals(
        from totals: [(stage: TimingStage, seconds: TimeInterval)]
    ) -> [(stage: TimingStage, seconds: TimeInterval)] {
        totals.filter { $0.stage.canSummarizeAsBottleneck }
    }

    private var averageProcessing: TimeInterval {
        guard !runs.isEmpty else { return 0 }
        return runs.reduce(0) { $0 + $1.processingTotal() } / Double(runs.count)
    }

    private var slowestRun: TimingRun? {
        visibleRuns.max { $0.visibleTotal(includeRecording: includeRecording) < $1.visibleTotal(includeRecording: includeRecording) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                controls
                summaryGrid
                breakdownChart
                stageDistribution
                detailRows
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DashboardTheme.pageBg)
        .id(languageManager.current)
        .task {
            await loadRecords()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.Timing.title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(DashboardTheme.ink)

            Text(L10n.Timing.subtitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashboardTheme.inkLight)
        }
    }

    private var controls: some View {
        TimingPanel {
            HStack(spacing: 18) {
                Toggle(L10n.Timing.includeRecording, isOn: $includeRecording)
                    .toggleStyle(.switch)
                    .tint(DashboardTheme.accent)

                Spacer()

                Picker(L10n.Timing.recordLimit, selection: $recordLimit) {
                    Text(L10n.Timing.latestRecords(20)).tag(20)
                    Text(L10n.Timing.latestRecords(50)).tag(50)
                    Text(L10n.Timing.latestRecords(100)).tag(100)
                    Text(L10n.Timing.allRecords).tag(0)
                }
                .frame(width: 180)
            }
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            TimingStatTile(title: L10n.Timing.analyzedRuns, value: "\(visibleRuns.count)", tint: DashboardTheme.accent)
            TimingStatTile(title: L10n.Timing.averageProcessing, value: formatDuration(averageProcessing), tint: DashboardTheme.success)
            TimingStatTile(title: L10n.Timing.slowestRun, value: slowestRun.map { formatDuration($0.visibleTotal(includeRecording: includeRecording)) } ?? "0s", tint: Color(nsColor: .systemRed))
            if let bottleneck = bottleneckStageTotals.first {
                TimingStatTile(title: L10n.Timing.slowestStage, value: bottleneck.stage.title, tint: bottleneck.stage.color)
            }
        }
    }

    private var breakdownChart: some View {
        TimingPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.Timing.runBreakdown)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DashboardTheme.ink)

                if chartSegments.isEmpty {
                    emptyState
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Chart {
                            ForEach(chartSegments) { segment in
                                BarMark(
                                    x: .value(L10n.Timing.recordDetails, segment.chartKey),
                                    y: .value(L10n.Timing.total, segment.seconds)
                                )
                                .foregroundStyle(by: .value(L10n.Timing.stageDistribution, segment.stage.title))
                                .cornerRadius(3)
                            }

                            if let hoveredRun {
                                RuleMark(x: .value(L10n.Timing.recordDetails, hoveredRun.chartKey))
                                    .foregroundStyle(DashboardTheme.inkMuted.opacity(0.55))
                                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                            }
                        }
                        .chartForegroundStyleScale(stageColorScale)
                        .chartYScale(domain: 0...chartYUpperBound)
                        .chartLegend(.hidden)
                        .chartXAxis {
                            AxisMarks(values: xAxisVisibleKeys) { value in
                                AxisGridLine()
                                    .foregroundStyle(DashboardTheme.rule.opacity(0.42))
                                AxisTick()
                                    .foregroundStyle(DashboardTheme.inkMuted.opacity(0.75))
                                AxisValueLabel {
                                    if let key = value.as(String.self) {
                                        Text(chartLabel(for: key))
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(DashboardTheme.inkLight)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                                AxisGridLine()
                                    .foregroundStyle(DashboardTheme.rule.opacity(0.55))
                                AxisValueLabel {
                                    if let seconds = value.as(Double.self) {
                                        Text(formatDuration(seconds))
                                            .font(.caption2.monospacedDigit().weight(.semibold))
                                            .foregroundStyle(DashboardTheme.inkLight)
                                    }
                                }
                            }
                        }
                        .chartPlotStyle { plotArea in
                            plotArea
                                .padding(.leading, 8)
                                .padding(.bottom, 4)
                        }
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(.clear)
                                    .contentShape(Rectangle())
                                    .onContinuousHover { phase in
                                        updateRunHover(phase: phase, proxy: proxy, geometry: geometry)
                                    }
                            }
                        }
                        .overlay {
                            GeometryReader { geometry in
                                if let hoveredRun, let timingHoverLocation {
                                    let x = min(
                                        max(timingHoverLocation.x + 124, 124),
                                        max(124, geometry.size.width - 124)
                                    )
                                    let y = min(
                                        max(timingHoverLocation.y - 112, 106),
                                        max(106, geometry.size.height - 106)
                                    )

                                    TimingRunHoverTooltip(
                                        run: hoveredRun,
                                        includeRecording: includeRecording,
                                        millisecondFormatter: formatMilliseconds
                                    )
                                    .position(x: x, y: y)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                        .frame(width: chartWidth, height: 340)
                    }
                    .frame(height: 370)
                }
            }
        }
    }

    private var stageDistribution: some View {
        TimingPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Timing.stageDistribution)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DashboardTheme.ink)

                if stageTotals.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(stageTotals.enumerated()), id: \.element.stage.id) { _, item in
                            TimingStageRow(
                                stage: item.stage,
                                seconds: item.seconds,
                                total: stageTotals.reduce(0) { $0 + $1.seconds },
                                formatter: formatDuration
                            )
                        }
                    }
                }
            }
        }
    }

    private var detailRows: some View {
        TimingPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Timing.recordDetails)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DashboardTheme.ink)

                if visibleRuns.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleRuns) { run in
                            TimingDetailRow(
                                run: run,
                                includeRecording: includeRecording,
                                durationFormatter: formatDuration
                            )
                            if run.id != visibleRuns.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.Timing.noTimingData)
                .font(.headline)
            Text(L10n.Timing.noTimingDataHint)
                .font(.subheadline)
                .foregroundStyle(DashboardTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }

    private var stageColorScale: KeyValuePairs<String, Color> {
        [
            L10n.Timing.recording: Color(nsColor: .systemCyan),
            L10n.Timing.modelReady: Color(nsColor: .systemIndigo),
            L10n.Timing.asr: DashboardTheme.success,
            L10n.Timing.correction: Color(nsColor: .systemPurple),
            L10n.Timing.legacyProcessing: Color(nsColor: .systemOrange),
            L10n.Timing.untrackedProcessing: Color(nsColor: .systemYellow),
            L10n.Timing.clipboard: DashboardTheme.accent,
            L10n.Timing.paste: Color(nsColor: .systemRed)
        ]
    }

    @MainActor
    private func loadRecords() async {
        records = await DataManager.shared.fetchAllRecordsQuietly()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0s" }
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        }
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds.truncatingRemainder(dividingBy: 60))
        if minutes < 60 {
            return "\(minutes)m \(remainder)s"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func formatMilliseconds(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 ms" }
        let milliseconds = max(1, Int((seconds * 1000).rounded()))
        let formatted = Self.integerFormatter.string(from: NSNumber(value: milliseconds)) ?? "\(milliseconds)"
        return "\(formatted) ms"
    }

    private func chartLabel(for key: String) -> String {
        visibleRuns.first { $0.chartKey == key }?.chartLabel ?? key
    }

    private func updateRunHover(phase: HoverPhase, proxy: ChartProxy, geometry: GeometryProxy) {
        switch phase {
        case .active(let location):
            guard let plotFrameAnchor = proxy.plotFrame else {
                hoveredRunID = nil
                timingHoverLocation = nil
                return
            }

            let plotFrame = geometry[plotFrameAnchor]
            guard plotFrame.contains(location) else {
                hoveredRunID = nil
                timingHoverLocation = nil
                return
            }

            let x = location.x - plotFrame.origin.x
            guard let key: String = proxy.value(atX: x),
                  let run = visibleRuns.first(where: { $0.chartKey == key }) else {
                hoveredRunID = nil
                timingHoverLocation = nil
                return
            }

            hoveredRunID = run.id
            timingHoverLocation = location
        case .ended:
            hoveredRunID = nil
            timingHoverLocation = nil
        }
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private struct TimingPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardTheme.cardBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.rule.opacity(0.75), lineWidth: 1)
        )
    }
}

private struct TimingStatTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(DashboardTheme.inkMuted)
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .background(DashboardTheme.cardBgAlt, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.rule.opacity(0.55), lineWidth: 1)
        )
    }
}

private struct TimingStageRow: View {
    let stage: TimingStage
    let seconds: TimeInterval
    let total: TimeInterval
    let formatter: (TimeInterval) -> String

    private var share: Double {
        guard total > 0 else { return 0 }
        return seconds / total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(stage.color)
                    .frame(width: 8, height: 8)
                Text(stage.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(formatter(seconds)) · \(String(format: "%.0f%%", share * 100))")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(stage.color)
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3)
                    .fill(stage.color.opacity(0.82))
                    .frame(width: max(4, proxy.size.width * share))
            }
            .frame(height: 6)
            .background(DashboardTheme.inkFaint.opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
        }
    }
}

private struct TimingRunHoverTooltip: View {
    let run: TimingRun
    let includeRecording: Bool
    let millisecondFormatter: (TimeInterval) -> String

    private var segments: [TimingSegment] {
        run.segments(includeRecording: includeRecording)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("#\(run.chartLabel)")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(DashboardTheme.accent)
                Text(run.runLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DashboardTheme.ink)
            }

            Text(run.detailLine)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DashboardTheme.inkMuted)
                .lineLimit(1)

            Text("\(L10n.Timing.total) \(millisecondFormatter(run.visibleTotal(includeRecording: includeRecording)))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DashboardTheme.inkLight)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(segments) { segment in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(segment.stage.color)
                            .frame(width: 6, height: 6)
                        Text(segment.stage.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DashboardTheme.inkMuted)
                        Spacer(minLength: 12)
                        Text(millisecondFormatter(segment.seconds))
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(segment.stage.color)
                    }
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .frame(width: 236, alignment: .leading)
        .background(DashboardTheme.cardBgAlt, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.rule.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
    }
}

private struct TimingDetailRow: View {
    let run: TimingRun
    let includeRecording: Bool
    let durationFormatter: (TimeInterval) -> String

    private var segments: [TimingSegment] {
        run.segments(includeRecording: includeRecording)
    }

    private var transcriptText: String {
        run.record.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.runLabel)
                        .font(.headline)
                        .foregroundStyle(DashboardTheme.ink)
                    Text(run.detailLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DashboardTheme.inkLight)
                }

                Spacer()

                Text(durationFormatter(run.visibleTotal(includeRecording: includeRecording)))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(DashboardTheme.ink)
            }

            if !transcriptText.isEmpty {
                Text(transcriptText)
                    .font(.callout.weight(.medium))
                    .lineSpacing(2)
                    .foregroundStyle(DashboardTheme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        DashboardTheme.pageBg.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DashboardTheme.rule.opacity(0.65), lineWidth: 1)
                    )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(segments) { segment in
                    TimingSegmentPill(
                        segment: segment,
                        durationFormatter: durationFormatter
                    )
                }
            }

            if !run.record.hasDetailedTiming, run.record.transcriptionTime != nil {
                Text(L10n.Timing.oldRecordHint)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DashboardTheme.inkLight)
            }
        }
        .padding(.vertical, 14)
    }
}

private struct TimingSegmentPill: View {
    let segment: TimingSegment
    let durationFormatter: (TimeInterval) -> String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(segment.stage.color)
                .frame(width: 7, height: 7)

            Text(segment.stage.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(DashboardTheme.inkLight)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(durationFormatter(segment.seconds))
                .font(.caption.monospacedDigit().weight(.heavy))
                .foregroundStyle(segment.stage.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(
            segment.stage.color.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(segment.stage.color.opacity(0.24), lineWidth: 1)
        )
    }
}

#Preview("Timing Analysis") {
    DashboardTimingAnalysisView()
        .frame(width: 1100, height: 760)
}
