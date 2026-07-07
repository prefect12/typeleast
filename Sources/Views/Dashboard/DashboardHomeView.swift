import SwiftUI
import SwiftData
import Charts
import AppKit

private struct BreakdownRow: Identifiable, Equatable {
    let label: String
    let words: Int
    let characters: Int
    let sessions: Int
    let recordingDuration: TimeInterval
    let processingDuration: TimeInterval
    let processingSamples: Int

    var id: String { label }

    var averageProcessingTime: TimeInterval {
        guard processingSamples > 0 else { return 0 }
        return processingDuration / Double(processingSamples)
    }
}

private struct DailyTranscriptionSummary: Identifiable, Equatable {
    let date: Date
    let words: Int
    let characters: Int
    let sessions: Int
    let recordingDuration: TimeInterval
    let processingDuration: TimeInterval
    let processingSamples: Int

    var id: Date { date }

    var averageWordsPerSession: Double {
        guard sessions > 0 else { return 0 }
        return Double(words) / Double(sessions)
    }

    var averageWPM: Double {
        guard recordingDuration > 0 else { return 0 }
        return Double(words) / (recordingDuration / 60.0)
    }

    var averageProcessingTime: TimeInterval {
        guard processingSamples > 0 else { return 0 }
        return processingDuration / Double(processingSamples)
    }

    var activityScore: Double {
        Double(words)
            + Double(characters) / 12.0
            + Double(sessions) * 80.0
            + recordingDuration / 3.0
            + processingDuration / 3.0
    }

    static func empty(date: Date) -> DailyTranscriptionSummary {
        DailyTranscriptionSummary(
            date: date,
            words: 0,
            characters: 0,
            sessions: 0,
            recordingDuration: 0,
            processingDuration: 0,
            processingSamples: 0
        )
    }
}

private struct DashboardAggregate {
    private static let estimatedTypingWordsPerMinute: Double = 45.0

    let words: Int
    let characters: Int
    let sessions: Int
    let activeDays: Int
    let recordingDuration: TimeInterval
    let processingDuration: TimeInterval
    let processingSamples: Int
    let peakDailyWords: Int

    var averageWPM: Double {
        guard recordingDuration > 0 else { return 0 }
        return Double(words) / (recordingDuration / 60.0)
    }

    var averageProcessingTime: TimeInterval {
        guard processingSamples > 0 else { return 0 }
        return processingDuration / Double(processingSamples)
    }

    var estimatedTimeSaved: TimeInterval {
        let typingMinutes = Double(words) / Self.estimatedTypingWordsPerMinute
        return max(0, typingMinutes * 60.0 - recordingDuration)
    }
}

private struct ActivityDataPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    let sessions: Int
    let characters: Int
    let recordingDuration: TimeInterval
    let processingDuration: TimeInterval

    var id: Date { date }
}

enum ActivityCalendarLayout {
    static func generateWeeks(
        activeDates: some Sequence<Date>,
        today: Date = Date(),
        calendar: Calendar = .current,
        minimumActivityDays: Int
    ) -> [[Date]] {
        let today = calendar.startOfDay(for: today)
        let activeDates = activeDates.map { calendar.startOfDay(for: $0) }
        let earliestDate = activeDates.min()
        let minimumStartDate = calendar.date(
            byAdding: .day,
            value: -(minimumActivityDays - 1),
            to: today
        ) ?? today
        let startDate = min(earliestDate ?? minimumStartDate, minimumStartDate)

        guard let firstWeekStart = startOfWeek(containing: startDate, calendar: calendar),
              let lastWeekStart = startOfWeek(containing: today, calendar: calendar) else {
            return []
        }

        var weeks: [[Date]] = []
        var weekStart = firstWeekStart
        while weekStart <= lastWeekStart {
            var week: [Date] = []
            for dayIndex in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: dayIndex, to: weekStart) else {
                    continue
                }
                let day = calendar.startOfDay(for: date)
                guard day <= today else {
                    break
                }
                week.append(day)
            }
            weeks.append(week)

            guard let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                break
            }
            weekStart = nextWeekStart
        }
        return weeks
    }

    static func startOfWeek(containing date: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        let daysFromSunday = calendar.component(.weekday, from: day) - 1
        return calendar.date(byAdding: .day, value: -daysFromSunday, to: day)
    }
}

internal struct DashboardHomeView: View {
    private static let minimumActivityDays = 53 * 7

    @Binding var selectedNav: DashboardNavItem
    @State private var metricsStore = UsageMetricsStore.shared
    @State private var sourceStore = SourceUsageStore.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var recentRecords: [TranscriptionRecord] = []
    @State private var dailySummaries: [Date: DailyTranscriptionSummary] = [:]
    @State private var selectedDate: Date?
    @State private var hoveredTrendPoint: ActivityDataPoint?
    @State private var trendHoverLocation: CGPoint?

    private let metricColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 12)
    ]

    private let detailColumns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                overviewMetrics
                activityCalendarSection
                selectedDaySection
                distributionSection
                trendSection
                recentTranscriptsSection
            }
            .padding(24)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .background(DashboardTheme.pageBg)
        .formStyle(.grouped)
        .id(languageManager.current)
        .onAppear {
            loadDashboardData()
        }
    }

    private var aggregate: DashboardAggregate {
        makeAggregate(records: recentRecords, summaries: Array(dailySummaries.values), snapshot: metricsStore.snapshot)
    }

    private var sortedSummaries: [DailyTranscriptionSummary] {
        dailySummaries.values.sorted { $0.date < $1.date }
    }

    private var selectedDay: Date {
        let calendar = Calendar.current
        if let selectedDate {
            return calendar.startOfDay(for: selectedDate)
        }
        return sortedSummaries.last(where: { $0.words > 0 })?.date
            ?? calendar.startOfDay(for: Date())
    }

    private var selectedSummary: DailyTranscriptionSummary {
        dailySummaries[selectedDay] ?? .empty(date: selectedDay)
    }

    private var selectedRecords: [TranscriptionRecord] {
        let calendar = Calendar.current
        return recentRecords.filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.date > $1.date }
    }

    private var allSourceRows: [BreakdownRow] {
        let sourceRows = makeBreakdown(sources: sourceStore.allSources())
        if !sourceRows.isEmpty {
            return sourceRows
        }
        return makeBreakdown(records: recentRecords) { record in
            record.sourceAppName?.isEmpty == false
                ? record.sourceAppName!
                : providerLabel(for: record)
        }
    }

    private var allModelRows: [BreakdownRow] {
        makeBreakdown(records: recentRecords) { record in
            if let model = record.modelUsed, !model.isEmpty {
                return model
            }
            return providerLabel(for: record)
        }
    }

    private var trendPoints: [ActivityDataPoint] {
        Array(sortedSummaries.suffix(45)).map {
            ActivityDataPoint(
                date: $0.date,
                value: Double($0.words),
                sessions: $0.sessions,
                characters: $0.characters,
                recordingDuration: $0.recordingDuration,
                processingDuration: $0.processingDuration
            )
        }
    }

    private var trendYUpperBound: Double {
        let maxValue = trendPoints.map(\.value).max() ?? 0
        return max(1, maxValue * 1.14)
    }

    private var activeWeeks: [[Date]] {
        generateActivityWeeks()
    }

    private var maxActivityValue: Double {
        max(sortedSummaries.map(\.activityScore).max() ?? 0, 1)
    }

    private var headerSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                dashboardTitle

                Spacer()

                viewAllButton
            }

            VStack(alignment: .leading, spacing: 12) {
                dashboardTitle
                viewAllButton
            }
        }
    }

    private var dashboardTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.Home.statsTitle)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(DashboardTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(L10n.Home.statsSubtitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashboardTheme.inkLight)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var viewAllButton: some View {
        Button {
            selectedNav = .transcripts
        } label: {
            Label(L10n.Home.viewAll, systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.bordered)
    }

    private var overviewMetrics: some View {
        LazyVGrid(columns: metricColumns, spacing: 12) {
            StatTile(
                title: L10n.Home.words,
                value: formatCompactNumber(aggregate.words),
                subtitle: L10n.Home.allSavedRecords,
                systemImage: "text.word.spacing",
                tint: DashboardTheme.success
            )

            StatTile(
                title: L10n.Home.sessions,
                value: formatNumber(aggregate.sessions),
                subtitle: L10n.Home.activeDaysSummary(aggregate.activeDays),
                systemImage: "waveform",
                tint: DashboardTheme.accent
            )

            StatTile(
                title: L10n.Home.timeSaved,
                value: formatDuration(aggregate.estimatedTimeSaved),
                subtitle: L10n.Home.basedOnTypingSpeed,
                systemImage: "keyboard.badge.clock",
                tint: Color(nsColor: .systemTeal)
            )

            StatTile(
                title: L10n.Home.avgTranscriptionTime,
                value: formatDurationPrecise(aggregate.averageProcessingTime),
                subtitle: L10n.Home.processingAverage,
                systemImage: "speedometer",
                tint: Color(nsColor: .systemOrange)
            )

            StatTile(
                title: L10n.Home.avgWPM,
                value: formatDecimal(aggregate.averageWPM),
                subtitle: L10n.Home.recordingBased,
                systemImage: "gauge.with.dots.needle.33percent",
                tint: Color(nsColor: .systemPurple)
            )

            StatTile(
                title: L10n.Home.peakDay,
                value: formatCompactNumber(aggregate.peakDailyWords),
                subtitle: L10n.Home.bestSingleDay,
                systemImage: "chart.line.uptrend.xyaxis",
                tint: Color(nsColor: .systemGreen)
            )
        }
    }

    private var activityCalendarSection: some View {
        StatsPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    activityCalendarTitle
                    Spacer(minLength: 18)
                }

                ActivityCalendarView(
                    weeks: activeWeeks,
                    summaries: dailySummaries,
                    selectedDate: selectedDay,
                    maxValue: maxActivityValue,
                    onSelect: { date in
                        selectedDate = Calendar.current.startOfDay(for: date)
                    }
                )

                calendarFooter
            }
        }
    }

    private var calendarFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                calendarHint
                Spacer()
                HeatLegend(tint: DashboardTheme.success)
            }

            VStack(alignment: .leading, spacing: 8) {
                calendarHint
                HeatLegend(tint: DashboardTheme.success)
            }
        }
    }

    private var calendarHint: some View {
        Text(L10n.Home.calendarHint)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(DashboardTheme.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var activityCalendarTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.Home.calendarTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(DashboardTheme.ink)
            Text(L10n.Home.calendarSubtitle)
                .font(.callout.weight(.semibold))
                .foregroundStyle(DashboardTheme.inkLight)
        }
    }

    private var selectedDaySection: some View {
        StatsPanel {
            VStack(alignment: .leading, spacing: 18) {
                selectedDayOverviewLayout

                if selectedSummary.words == 0 {
                    EmptyStatsRow(text: L10n.Home.noDataForDay)
                } else if selectedRecords.isEmpty {
                    EmptyStatsRow(text: L10n.Home.summaryCountersOnlyDay)
                } else {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.Home.modelBreakdown)
                            .font(.headline)
                        ForEach(makeBreakdown(records: selectedRecords, label: modelLabel(for:)).prefix(5)) { row in
                            BreakdownLine(
                                row: row,
                                totalWords: max(selectedSummary.words, 1),
                                tint: modelColor(for: row.label),
                                value: formatDurationPrecise(row.averageProcessingTime)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var selectedDayOverviewLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                selectedDayOverviewText
                    .frame(minWidth: 240, maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 18)

                selectedDayMetricsGrid
                    .frame(minWidth: 330, maxWidth: 520, alignment: .topLeading)
                    .layoutPriority(1)
            }

            VStack(alignment: .leading, spacing: 16) {
                selectedDayOverviewText
                selectedDayMetricsGrid
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var selectedDayOverviewText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.dayTitleFormatter.string(from: selectedDay))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DashboardTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(L10n.Home.dayOverview)
                .font(.title3.weight(.bold))
                .foregroundStyle(DashboardTheme.success)

            Text(selectedDaySummaryLine)
                .font(.callout.weight(.semibold))
                .foregroundStyle(DashboardTheme.inkLight)
                .fixedSize(horizontal: false, vertical: true)

            Text(dayContextLine)
                .font(.callout.weight(.semibold))
                .foregroundStyle(DashboardTheme.inkLight)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectedDayMetricsGrid: some View {
        LazyVGrid(columns: detailColumns, spacing: 12) {
            CompactMetricTile(title: L10n.Home.words, value: formatCompactNumber(selectedSummary.words), tint: DashboardTheme.success)
            CompactMetricTile(title: L10n.Home.characters, value: formatCompactNumber(selectedSummary.characters), tint: DashboardTheme.accent)
            CompactMetricTile(title: L10n.Home.recordingDuration, value: formatDurationPrecise(selectedSummary.recordingDuration), tint: Color(nsColor: .systemCyan))
            CompactMetricTile(title: L10n.Home.processingDuration, value: formatDurationPrecise(selectedSummary.processingDuration), tint: Color(nsColor: .systemOrange))
            CompactMetricTile(title: L10n.Home.avgWPM, value: formatDecimal(selectedSummary.averageWPM), tint: Color(nsColor: .systemPurple))
            CompactMetricTile(title: L10n.Home.avgProcessing, value: formatDurationPrecise(selectedSummary.averageProcessingTime), tint: Color(nsColor: .systemTeal))
        }
    }

    private var distributionSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                sourceDistributionPanel
                    .frame(minWidth: 280, maxWidth: .infinity, alignment: .topLeading)
                modelDistributionPanel
                    .frame(minWidth: 280, maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 14) {
                sourceDistributionPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                modelDistributionPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var sourceDistributionPanel: some View {
        BreakdownPanel(
            title: L10n.Home.sourceMix,
            rows: allSourceRows,
            totalWords: max(aggregate.words, 1),
            color: sourceColor(for:),
            valueFormatter: { row in "\(formatCompactNumber(row.words)) · \(formatCompactNumber(row.characters))" }
        )
    }

    private var modelDistributionPanel: some View {
        BreakdownPanel(
            title: L10n.Home.modelBreakdown,
            rows: allModelRows,
            totalWords: max(aggregate.words, 1),
            color: modelColor(for:),
            valueFormatter: { row in "\(formatCompactNumber(row.words)) · \(formatDurationPrecise(row.averageProcessingTime))" }
        )
    }

    private var trendSection: some View {
        StatsPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Home.trendTitle)
                            .font(.title3.weight(.bold))
                        Text(L10n.Home.trendSubtitle)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DashboardTheme.inkMuted)
                    }
                    Spacer()
                    Text(L10n.Home.words)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(DashboardTheme.success)
                }

                if trendPoints.contains(where: { $0.value > 0 }) {
                    Chart {
                        ForEach(trendPoints) { point in
                            BarMark(
                                x: .value(L10n.Home.date, point.date, unit: .day),
                                y: .value(L10n.Home.words, point.value)
                            )
                            .foregroundStyle(DashboardTheme.success.gradient)
                            .cornerRadius(3)
                        }

                        if let hoveredTrendPoint {
                            RuleMark(x: .value(L10n.Home.date, hoveredTrendPoint.date, unit: .day))
                                .foregroundStyle(DashboardTheme.inkMuted.opacity(0.55))
                                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                    .chartYScale(domain: 0...trendYUpperBound)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(Self.shortDateFormatter.string(from: date))
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let doubleValue = value.as(Double.self) {
                                    Text(formatCompactNumber(Int(doubleValue.rounded())))
                                }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    updateTrendHover(phase: phase, proxy: proxy, geometry: geometry)
                            }
                        }
                    }
                    .overlay {
                        GeometryReader { geometry in
                            if let hoveredTrendPoint, let trendHoverLocation {
                                let x = min(max(trendHoverLocation.x, 104), max(104, geometry.size.width - 104))
                                let y = min(max(trendHoverLocation.y, 72), max(72, geometry.size.height - 72))

                                TrendHoverTooltip(
                                    date: Self.trendTooltipFormatter.string(from: hoveredTrendPoint.date),
                                    words: formatCompactNumber(Int(hoveredTrendPoint.value.rounded())),
                                    characters: formatCompactNumber(hoveredTrendPoint.characters),
                                    sessions: formatNumber(hoveredTrendPoint.sessions),
                                    recordingDuration: formatDurationPrecise(hoveredTrendPoint.recordingDuration),
                                    processingDuration: formatDurationPrecise(hoveredTrendPoint.processingDuration)
                                )
                                .position(x: x, y: y)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(height: 170)
                } else {
                    EmptyStatsRow(text: L10n.Home.noTrendData)
                        .frame(height: 120)
                }
            }
        }
    }

    private var recentTranscriptsSection: some View {
        StatsPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.Home.recentTranscripts)
                        .font(.title3.weight(.bold))
                    Spacer()
                    Button(L10n.Home.viewAll) {
                        selectedNav = .transcripts
                    }
                    .buttonStyle(.borderless)
                }

                if recentRecords.isEmpty {
                    EmptyStatsRow(text: L10n.Home.noTranscripts)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(recentRecords.prefix(6).enumerated()), id: \.element.id) { index, record in
                            RecentTranscriptRow(
                                record: record,
                                providerColor: providerColor(for: providerLabel(for: record)),
                                timeFormatter: Self.timeFormatter,
                                numberFormatter: Self.integerFormatter
                            )
                            if index < min(recentRecords.count, 6) - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var dayContextLine: String {
        if selectedRecords.isEmpty, selectedSummary.words > 0 {
            return L10n.Home.summaryCountersOnlyDay
        }
        let peakShare = aggregate.peakDailyWords > 0
            ? Double(selectedSummary.words) / Double(aggregate.peakDailyWords) * 100
            : 0
        let weekWords = wordsInSelectedWeek()
        let weekShare = weekWords > 0 ? Double(selectedSummary.words) / Double(weekWords) * 100 : 0
        return L10n.Home.dayContext(
            sessions: selectedSummary.sessions,
            peakPercent: peakShare,
            weekPercent: weekShare
        )
    }

    private var selectedDaySummaryLine: String {
        [
            "\(formatCompactNumber(selectedSummary.words)) \(L10n.Home.words)",
            "\(formatNumber(selectedSummary.sessions)) \(L10n.Home.sessions)",
            "\(formatDurationPrecise(selectedSummary.recordingDuration)) \(L10n.Home.recordingDuration)",
            "\(formatDurationPrecise(selectedSummary.processingDuration)) \(L10n.Home.processingDuration)"
        ].joined(separator: " · ")
    }

    private func loadDashboardData() {
        Task {
            await metricsStore.bootstrapIfNeeded()

            let records = await DataManager.shared.fetchAllRecordsQuietly()
            await MainActor.run {
                recentRecords = records
                dailySummaries = makeDailySummaries(records: records, snapshot: metricsStore.snapshot)
                if selectedDate == nil {
                    selectedDate = dailySummaries.values
                        .filter { $0.words > 0 }
                        .map(\.date)
                        .max()
                        ?? Calendar.current.startOfDay(for: Date())
                }
            }
        }
    }

    private func updateTrendHover(phase: HoverPhase, proxy: ChartProxy, geometry: GeometryProxy) {
        switch phase {
        case .active(let location):
            guard let plotFrameAnchor = proxy.plotFrame else {
                hoveredTrendPoint = nil
                trendHoverLocation = nil
                return
            }
            let plotFrame = geometry[plotFrameAnchor]
            guard plotFrame.contains(location) else {
                hoveredTrendPoint = nil
                trendHoverLocation = nil
                return
            }

            let x = location.x - plotFrame.origin.x
            guard let hoveredDate: Date = proxy.value(atX: x) else {
                hoveredTrendPoint = nil
                trendHoverLocation = nil
                return
            }

            hoveredTrendPoint = nearestTrendPoint(to: hoveredDate)
            trendHoverLocation = location
        case .ended:
            hoveredTrendPoint = nil
            trendHoverLocation = nil
        }
    }

    private func nearestTrendPoint(to date: Date) -> ActivityDataPoint? {
        guard let nearest = trendPoints.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else {
            return nil
        }

        guard nearest.value > 0 else {
            return nil
        }

        let maxDistance = TimeInterval(18 * 60 * 60)
        return abs(nearest.date.timeIntervalSince(date)) <= maxDistance ? nearest : nil
    }
}

// MARK: - Activity Calendar

private struct ActivityDayHitTarget: NSViewRepresentable {
    let isEnabled: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let onPress: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.setButtonType(.momentaryChange)
        button.target = context.coordinator
        button.action = #selector(Coordinator.press(_:))
        configure(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        configure(button)
    }

    private func configure(_ button: NSButton) {
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityValue(accessibilityValue)
    }

    final class Coordinator: NSObject {
        var parent: ActivityDayHitTarget

        init(_ parent: ActivityDayHitTarget) {
            self.parent = parent
        }

        @objc func press(_ sender: NSButton) {
            guard parent.isEnabled else {
                return
            }
            parent.onPress()
        }
    }
}

private struct ActivityCalendarView: View {
    let weeks: [[Date]]
    let summaries: [Date: DailyTranscriptionSummary]
    let selectedDate: Date
    let maxValue: Double
    let onSelect: (Date) -> Void

    private let cellSize: CGFloat = 14
    private let hitSize: CGFloat = 22
    private let cellGap: CGFloat = 2

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: cellGap) {
                ForEach(Array(L10n.Weekday.short.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DashboardTheme.inkMuted)
                        .frame(width: 18, height: hitSize)
                }
            }
            .padding(.top, 2)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: cellGap) {
                            ForEach(weeks.indices, id: \.self) { weekIndex in
                                VStack(spacing: cellGap) {
                                    ForEach(weeks[weekIndex], id: \.self) { date in
                                        dayCell(for: date)
                                    }
                                }
                                .id(weekIndex)
                            }
                        }

                        HStack(alignment: .top, spacing: cellGap) {
                            ForEach(weeks.indices, id: \.self) { weekIndex in
                                Text(monthLabel(for: weekIndex))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(DashboardTheme.inkMuted)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: hitSize, alignment: .leading)
                            }
                        }
                        .frame(height: 16, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    scrollToLatestWeek(using: proxy)
                }
                .onChange(of: weeks.count) { _, _ in
                    scrollToLatestWeek(using: proxy)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        let summary = summaries[day] ?? .empty(date: day)
        let value = summary.activityScore
        let isFuture = day > today
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let accessibilityTitle = Self.tooltipFormatter.string(from: day)
        let accessibilityValue = activitySummaryText(for: summary)

        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color(for: value, future: isFuture))
                .frame(width: cellSize, height: cellSize)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.primary.opacity(0.92), lineWidth: 2)
                            .padding(-2)
                    }
                }

            ActivityDayHitTarget(
                isEnabled: !isFuture,
                accessibilityLabel: accessibilityTitle,
                accessibilityValue: accessibilityValue
            ) {
                onSelect(day)
            }
            .frame(width: hitSize, height: hitSize)
        }
        .frame(width: hitSize, height: hitSize)
        .contentShape(Rectangle())
        .help(accessibilityTitle + " · " + accessibilityValue)
    }

    private func color(for value: Double, future: Bool) -> Color {
        guard !future else {
            return DashboardTheme.inkFaint.opacity(0.10)
        }
        guard value > 0 else {
            return DashboardTheme.inkFaint.opacity(0.22)
        }
        let intensity = min(max(value / maxValue, 0.14), 1.0)
        return DashboardTheme.success.opacity(0.18 + 0.72 * intensity)
    }

    private func monthLabel(for weekIndex: Int) -> String {
        guard weeks.indices.contains(weekIndex),
              let firstDay = weeks[weekIndex].first else {
            return ""
        }
        let calendar = Calendar.current
        if weekIndex == 0 {
            if weeks.indices.contains(1),
               let nextFirstDay = weeks[1].first,
               calendar.component(.month, from: firstDay) != calendar.component(.month, from: nextFirstDay) {
                return ""
            }
            return Self.monthFormatter.string(from: firstDay)
        }
        guard let previousFirstDay = weeks[weekIndex - 1].first else {
            return ""
        }
        return calendar.component(.month, from: firstDay) != calendar.component(.month, from: previousFirstDay)
            ? Self.monthFormatter.string(from: firstDay)
            : ""
    }

    private func scrollToLatestWeek(using proxy: ScrollViewProxy) {
        guard let lastWeekIndex = weeks.indices.last else {
            return
        }
        DispatchQueue.main.async {
            proxy.scrollTo(lastWeekIndex, anchor: .trailing)
        }
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private static let tooltipFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private static let dayIdentifierFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func activitySummaryText(for summary: DailyTranscriptionSummary) -> String {
        guard summary.words > 0 || summary.sessions > 0 else {
            return L10n.Home.noDataForDay
        }
        return [
            "\(formatCompactNumber(summary.words)) \(L10n.Home.words)",
            "\(formatNumber(summary.sessions)) \(L10n.Home.sessions)",
            "\(formatDurationPrecise(summary.recordingDuration)) \(L10n.Home.recordingDuration)",
            "\(formatDurationPrecise(summary.processingDuration)) \(L10n.Home.processingDuration)"
        ].joined(separator: " · ")
    }

    private func formatNumber(_ value: Int) -> String {
        Self.integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatCompactNumber(_ value: Int) -> String {
        if L10n.isChinese {
            if value >= 100_000_000 {
                return String(format: "%.2f亿", Double(value) / 100_000_000)
            }
            if value >= 10_000 {
                return String(format: "%.1f万", Double(value) / 10_000)
            }
            return formatNumber(value)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return formatNumber(value)
    }

    private func formatDurationPrecise(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "0s" }
        let totalSeconds = Int(interval.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

// MARK: - Small Views

private struct StatsPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.rule.opacity(0.75), lineWidth: 1)
        )
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardTheme.inkLight)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DashboardTheme.ink)
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(DashboardTheme.inkMuted)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardTheme.cardBgAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.rule.opacity(0.55), lineWidth: 1)
        )
    }
}

private struct CompactMetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(DashboardTheme.inkMuted)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardTheme.accentSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct BreakdownPanel: View {
    let title: String
    let rows: [BreakdownRow]
    let totalWords: Int
    let color: (String) -> Color
    let valueFormatter: (BreakdownRow) -> String

    var body: some View {
        StatsPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DashboardTheme.ink)

                if rows.isEmpty {
                    EmptyStatsRow(text: L10n.Home.noBreakdownData)
                } else {
                    ForEach(rows.prefix(6)) { row in
                        BreakdownLine(
                            row: row,
                            totalWords: totalWords,
                            tint: color(row.label),
                            value: valueFormatter(row)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct BreakdownLine: View {
    let row: BreakdownRow
    let totalWords: Int
    let tint: Color
    let value: String

    private var share: Double {
        guard totalWords > 0 else { return 0 }
        return Double(row.words) / Double(totalWords)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)

                Text(row.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .layoutPriority(1)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DashboardTheme.inkFaint.opacity(0.16))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, geometry.size.width * share))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct HeatLegend: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n.Home.less)
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index == 0 ? DashboardTheme.inkFaint.opacity(0.22) : tint.opacity(0.18 + Double(index) * 0.16))
                    .frame(width: 14, height: 14)
            }
            Text(L10n.Home.more)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(DashboardTheme.inkMuted)
    }
}

private struct EmptyStatsRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .foregroundStyle(DashboardTheme.inkMuted)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DashboardTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }
}

private struct TrendHoverTooltip: View {
    let date: String
    let words: String
    let characters: String
    let sessions: String
    let recordingDuration: String
    let processingDuration: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date)
                .font(.caption.weight(.bold))
                .foregroundStyle(DashboardTheme.ink)

            VStack(alignment: .leading, spacing: 5) {
                tooltipRow(label: L10n.Home.words, value: words, tint: DashboardTheme.success)
                tooltipRow(label: L10n.Home.characters, value: characters, tint: DashboardTheme.accent)
                tooltipRow(label: L10n.Home.sessions, value: sessions, tint: DashboardTheme.providerGemini)
                tooltipRow(label: L10n.Home.recordingDuration, value: recordingDuration, tint: Color(nsColor: .systemCyan))
                tooltipRow(label: L10n.Home.processingDuration, value: processingDuration, tint: Color(nsColor: .systemOrange))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardTheme.cardBgAlt.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.rule.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        .frame(width: 190, alignment: .leading)
    }

    private func tooltipRow(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(label)
                .foregroundStyle(DashboardTheme.inkMuted)
            Spacer(minLength: 14)
            Text(value)
                .foregroundStyle(tint)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
    }
}

private struct RecentTranscriptRow: View {
    let record: TranscriptionRecord
    let providerColor: Color
    let timeFormatter: DateFormatter
    let numberFormatter: NumberFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                sourceIcon

                Text(record.sourceAppName ?? L10n.Provider.displayName(for: record.provider))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardTheme.inkLight)
                    .lineLimit(1)

                Text(L10n.Provider.displayName(for: record.provider))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(providerColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(providerColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                if let processing = record.formattedTranscriptionTime {
                    Text(processing)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                }

                Spacer(minLength: 8)

                Text(timeFormatter.string(from: record.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DashboardTheme.inkMuted)
            }

            Text(record.text)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(DashboardTheme.ink)

            HStack(spacing: 12) {
                Text(L10n.Home.wordsSuffix(record.wordCount > 0 ? record.wordCount : UsageMetricsStore.estimatedWordCount(for: record.text)))
                if let duration = record.formattedDuration {
                    Text(duration)
                }
                if let model = record.modelUsed, !model.isEmpty {
                    Text(model)
                        .lineLimit(1)
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(DashboardTheme.inkMuted)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let iconData = record.sourceAppIconData,
           let nsImage = NSImage(data: iconData) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(providerColor.opacity(0.16))
                .overlay {
                    Image(systemName: "text.cursor")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(providerColor)
                }
                .frame(width: 18, height: 18)
        }
    }
}

// MARK: - Data + Helpers

private extension DashboardHomeView {
    func makeDailySummaries(records: [TranscriptionRecord], snapshot: UsageSnapshot) -> [Date: DailyTranscriptionSummary] {
        let calendar = Calendar.current
        var output: [Date: DailyTranscriptionSummary] = [:]
        var detailedWordsByDay: [Date: Int] = [:]

        let grouped = Dictionary(grouping: records) { record in
            calendar.startOfDay(for: record.date)
        }

        for (day, dayRecords) in grouped {
            let words = dayRecords.reduce(0) { $0 + wordCount(for: $1) }
            let characters = dayRecords.reduce(0) { $0 + characterCount(for: $1) }
            let recordingDuration = dayRecords.reduce(0) { $0 + ($1.duration ?? 0) }
            let processingValues = dayRecords.compactMap(\.transcriptionTime).filter { $0 > 0 }
            detailedWordsByDay[day] = words
            output[day] = DailyTranscriptionSummary(
                date: day,
                words: words,
                characters: characters,
                sessions: dayRecords.count,
                recordingDuration: recordingDuration,
                processingDuration: processingValues.reduce(0, +),
                processingSamples: processingValues.count
            )
        }

        let recordWords = records.reduce(0) { $0 + wordCount(for: $1) }
        let recordCharacters = records.reduce(0) { $0 + characterCount(for: $1) }
        let recordDuration = records.reduce(0) { $0 + ($1.duration ?? 0) }
        let processingValues = records.compactMap(\.transcriptionTime).filter { $0 > 0 }
        let averageProcessingTime = processingValues.isEmpty
            ? 0
            : processingValues.reduce(0, +) / Double(processingValues.count)

        let summaryOnlyTotalWords = max(0, snapshot.totalWords - recordWords)
        let summaryOnlyTotalCharacters = max(0, snapshot.totalCharacters - recordCharacters)
        let summaryOnlyTotalSessions = max(0, snapshot.totalSessions - records.count)
        let summaryOnlyTotalDuration = max(0, snapshot.totalDuration - recordDuration)

        for (day, words) in dailyWords(from: snapshot) {
            let summaryOnlyWords = max(0, words - (detailedWordsByDay[day] ?? 0))
            guard summaryOnlyWords > 0 else { continue }

            let estimatedSessions = proportionalCount(
                total: summaryOnlyTotalSessions,
                value: summaryOnlyWords,
                denominator: summaryOnlyTotalWords,
                minimumWhenPositive: 1
            )
            let estimatedCharacters = proportionalCount(
                total: summaryOnlyTotalCharacters,
                value: summaryOnlyWords,
                denominator: summaryOnlyTotalWords,
                minimumWhenPositive: summaryOnlyWords
            )
            let estimatedRecordingDuration = proportionalDuration(
                total: summaryOnlyTotalDuration,
                value: summaryOnlyWords,
                denominator: summaryOnlyTotalWords
            )
            let estimatedProcessingDuration = averageProcessingTime * Double(estimatedSessions)

            let existing = output[day] ?? .empty(date: day)
            output[day] = DailyTranscriptionSummary(
                date: day,
                words: existing.words + summaryOnlyWords,
                characters: existing.characters + estimatedCharacters,
                sessions: existing.sessions + estimatedSessions,
                recordingDuration: existing.recordingDuration + estimatedRecordingDuration,
                processingDuration: existing.processingDuration + estimatedProcessingDuration,
                processingSamples: existing.processingSamples + (averageProcessingTime > 0 ? estimatedSessions : 0)
            )
        }

        return output
    }

    func dailyWords(from snapshot: UsageSnapshot) -> [Date: Int] {
        let formatter = Self.storageDayFormatter
        var output: [Date: Int] = [:]
        for (key, words) in snapshot.dailyActivity {
            guard let date = formatter.date(from: key) else { continue }
            let day = Calendar.current.startOfDay(for: date)
            output[day] = words
        }
        return output
    }

    func proportionalCount(total: Int, value: Int, denominator: Int, minimumWhenPositive: Int) -> Int {
        guard value > 0 else { return 0 }
        guard total > 0, denominator > 0 else { return minimumWhenPositive }
        let estimate = Int((Double(total) * Double(value) / Double(denominator)).rounded())
        return max(minimumWhenPositive, estimate)
    }

    func proportionalDuration(total: TimeInterval, value: Int, denominator: Int) -> TimeInterval {
        guard value > 0, total > 0, denominator > 0 else { return 0 }
        return total * Double(value) / Double(denominator)
    }

    func makeAggregate(records: [TranscriptionRecord], summaries: [DailyTranscriptionSummary], snapshot: UsageSnapshot) -> DashboardAggregate {
        let recordWords = records.reduce(0) { $0 + wordCount(for: $1) }
        let recordCharacters = records.reduce(0) { $0 + characterCount(for: $1) }
        let recordDuration = records.reduce(0) { $0 + ($1.duration ?? 0) }
        let processingValues = records.compactMap(\.transcriptionTime).filter { $0 > 0 }
        let hasUsageSnapshot = snapshot.totalSessions > 0 || snapshot.totalWords > 0 || !snapshot.dailyActivity.isEmpty

        return DashboardAggregate(
            words: hasUsageSnapshot ? max(snapshot.totalWords, recordWords) : recordWords,
            characters: hasUsageSnapshot ? max(snapshot.totalCharacters, recordCharacters) : recordCharacters,
            sessions: hasUsageSnapshot ? max(snapshot.totalSessions, records.count) : records.count,
            activeDays: summaries.filter { $0.words > 0 }.count,
            recordingDuration: hasUsageSnapshot ? max(snapshot.totalDuration, recordDuration) : recordDuration,
            processingDuration: processingValues.reduce(0, +),
            processingSamples: processingValues.count,
            peakDailyWords: summaries.map(\.words).max() ?? 0
        )
    }

    func makeBreakdown(records: [TranscriptionRecord], label: (TranscriptionRecord) -> String) -> [BreakdownRow] {
        var buckets: [String: BreakdownRow] = [:]
        for record in records {
            let key = label(record)
            let existing = buckets[key] ?? BreakdownRow(
                label: key,
                words: 0,
                characters: 0,
                sessions: 0,
                recordingDuration: 0,
                processingDuration: 0,
                processingSamples: 0
            )
            let processing = record.transcriptionTime ?? 0
            buckets[key] = BreakdownRow(
                label: key,
                words: existing.words + wordCount(for: record),
                characters: existing.characters + characterCount(for: record),
                sessions: existing.sessions + 1,
                recordingDuration: existing.recordingDuration + (record.duration ?? 0),
                processingDuration: existing.processingDuration + max(0, processing),
                processingSamples: existing.processingSamples + (processing > 0 ? 1 : 0)
            )
        }

        return buckets.values.sorted {
            if $0.words == $1.words {
                return $0.sessions > $1.sessions
            }
            return $0.words > $1.words
        }
    }

    func makeBreakdown(sources: [SourceUsageStats]) -> [BreakdownRow] {
        sources.map { source in
            BreakdownRow(
                label: source.displayName,
                words: source.totalWords,
                characters: source.totalCharacters,
                sessions: source.sessionCount,
                recordingDuration: 0,
                processingDuration: 0,
                processingSamples: 0
            )
        }
    }

    func generateActivityWeeks() -> [[Date]] {
        ActivityCalendarLayout.generateWeeks(
            activeDates: dailySummaries.keys,
            minimumActivityDays: Self.minimumActivityDays
        )
    }

    func startOfWeek(containing date: Date, calendar: Calendar) -> Date? {
        ActivityCalendarLayout.startOfWeek(containing: date, calendar: calendar)
    }

    func wordsInSelectedWeek() -> Int {
        let calendar = Calendar.current
        guard let weekStart = startOfWeek(containing: selectedDay, calendar: calendar),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return selectedSummary.words
        }
        return dailySummaries.values
            .filter { $0.date >= weekStart && $0.date < weekEnd }
            .reduce(0) { $0 + $1.words }
    }

    func providerLabel(for record: TranscriptionRecord) -> String {
        L10n.Provider.displayName(for: record.provider)
    }

    func modelLabel(for record: TranscriptionRecord) -> String {
        if let model = record.modelUsed, !model.isEmpty {
            return model
        }
        return providerLabel(for: record)
    }

    func providerColor(for label: String) -> Color {
        let lowered = label.lowercased()
        if lowered.contains("openai") { return DashboardTheme.providerOpenAI }
        if lowered.contains("mimo") { return DashboardTheme.providerMiMo }
        if lowered.contains("gemini") { return DashboardTheme.providerGemini }
        if lowered.contains("whisper") || lowered.contains("local") { return DashboardTheme.providerLocal }
        if lowered.contains("parakeet") { return DashboardTheme.providerParakeet }
        if lowered.contains("funasr") { return Color(nsColor: .systemOrange) }
        return DashboardTheme.accent
    }

    func sourceColor(for label: String) -> Color {
        colorFromString(label, saturation: 0.60, brightness: 0.82)
    }

    func modelColor(for label: String) -> Color {
        colorFromString(label, saturation: 0.55, brightness: 0.88)
    }

    func colorFromString(_ string: String, saturation: Double, brightness: Double) -> Color {
        let scalars = string.unicodeScalars.reduce(UInt32(0)) { partial, scalar in
            partial &+ scalar.value
        }
        let hue = Double(scalars % 360) / 360.0
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    func wordCount(for record: TranscriptionRecord) -> Int {
        if record.wordCount > 0 {
            return record.wordCount
        }
        return UsageMetricsStore.estimatedWordCount(for: record.text)
    }

    func characterCount(for record: TranscriptionRecord) -> Int {
        if record.characterCount > 0 {
            return record.characterCount
        }
        return record.text.count
    }

    func formatNumber(_ value: Int) -> String {
        Self.integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    func formatCompactNumber(_ value: Int) -> String {
        if L10n.isChinese {
            if value >= 100_000_000 {
                return String(format: "%.2f亿", Double(value) / 100_000_000)
            }
            if value >= 10_000 {
                return String(format: "%.1f万", Double(value) / 10_000)
            }
            return formatNumber(value)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return formatNumber(value)
    }

    func formatDecimal(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    func formatDuration(_ interval: TimeInterval) -> String {
        L10n.Format.duration(interval)
    }

    func formatDurationShort(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0" }
        if interval < 60 {
            return String(format: "%.0fs", interval)
        }
        if interval < 3600 {
            return "\(Int(interval / 60))m"
        }
        return "\(Int(interval / 3600))h"
    }

    func formatDurationPrecise(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0" }
        if interval < 1 {
            return String(format: "%.0fms", interval * 1000)
        }
        if interval < 60 {
            return String(format: "%.1fs", interval)
        }
        let minutes = Int(interval / 60)
        let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
        if minutes < 60 {
            return "\(minutes)m \(seconds)s"
        }
        let hours = minutes / 60
        return "\(hours)h \(minutes % 60)m"
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let storageDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M/d")
        return formatter
    }()

    private static let trendTooltipFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()
}

#Preview("Dashboard Home") {
    DashboardHomeView(selectedNav: .constant(.dashboard))
        .frame(width: 1080, height: 760)
}
