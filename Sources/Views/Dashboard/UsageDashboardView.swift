import SwiftUI

internal struct UsageDashboardView: View {
    @State private var metricsStore = UsageMetricsStore.shared
    @State private var modelStats: [ModelUsageStats] = []
    @State private var isRebuilding = false
    @State private var rebuildError: String?
    @State private var showResetConfirmation = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        let snapshot = metricsStore.snapshot

        VStack(alignment: .leading, spacing: 16) {
            heroCard(snapshot: snapshot)

            if snapshot.totalSessions == 0 {
                Text("Start a recording to see your usage stats.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    UsageMetricCard(
                        title: "Sessions Recorded",
                        value: formatNumber(snapshot.totalSessions),
                        subtitle: "Sessions completed",
                        iconName: "waveform.circle.fill",
                        accentColor: .purple
                    )

                    UsageMetricCard(
                        title: "Words Dictated",
                        value: formatNumber(snapshot.totalWords),
                        subtitle: "Words generated",
                        iconName: "text.book.closed.fill",
                        accentColor: .blue
                    )

                    UsageMetricCard(
                        title: "Words Per Minute",
                        value: formatDecimal(snapshot.wordsPerMinute),
                        subtitle: "Dictation velocity",
                        iconName: "speedometer",
                        accentColor: .orange
                    )

                    UsageMetricCard(
                        title: "Keystrokes Saved",
                        value: formatNumber(snapshot.keystrokesSaved),
                        subtitle: "Fewer characters typed",
                        iconName: "keyboard.fill",
                        accentColor: .green
                    )

                    UsageMetricCard(
                        title: "Estimated API Cost",
                        value: formatCurrency(totalKnownCostUSD),
                        subtitle: unknownCostCount > 0 ? "\(unknownCostCount) model groups unknown" : "Known model rates",
                        iconName: "creditcard.fill",
                        accentColor: .teal
                    )
                }

                modelUsageSection
            }

            if let error = rebuildError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button {
                    DashboardWindowManager.shared.showDashboardWindow()
                } label: {
                    Label("Open Dashboard", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.borderedProminent)
                
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset Stats", systemImage: "arrow.counterclockwise")
                }

                if DataManager.shared.isHistoryEnabled {
                    Button {
                        Task { await rebuildFromHistory() }
                    } label: {
                        if isRebuilding {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Rebuilding…")
                            }
                        } else {
                            Label("Rebuild", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .disabled(isRebuilding)
                }
            }
            .buttonStyle(.bordered)
        }
        .confirmationDialog(
            "Reset Usage Stats?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                metricsStore.reset()
                SourceUsageStore.shared.reset()
                modelStats = []
            }
        } message: {
            Text("This clears the aggregated usage counters and source stats. Your transcription history remains untouched.")
        }
        .task {
            await loadModelStats()
        }
    }

    private var totalKnownCostUSD: Double {
        modelStats.compactMap(\.estimatedCostUSD).reduce(0, +)
    }

    private var unknownCostCount: Int {
        modelStats.filter { $0.estimatedCostUSD == nil }.count
    }

    private func heroCard(snapshot: UsageSnapshot) -> some View {
        let gradient = LinearGradient(
            gradient: Gradient(colors: [Color.blue, Color.purple]),
            startPoint: .leading,
            endPoint: .trailing
        )
        let emptyGradient = LinearGradient(
            gradient: Gradient(colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.2)]),
            startPoint: .leading,
            endPoint: .trailing
        )

        return Group {
            if snapshot.totalSessions == 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Usage stats will appear here after your first session.")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Record once to begin tracking your time saved and words dictated.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(emptyGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You have saved \(formatDuration(snapshot.estimatedTimeSaved)) with Typeleast")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Dictated \(formatNumber(snapshot.totalWords)) words across \(formatNumber(snapshot.totalSessions)) sessions.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(gradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func rebuildFromHistory() async {
        guard !isRebuilding else { return }
        isRebuilding = true
        rebuildError = nil
        defer { isRebuilding = false }

        let records = await DataManager.shared.fetchAllRecordsQuietly()
        if records.isEmpty {
            rebuildError = "No saved sessions found in history."
            return
        }
        metricsStore.rebuild(using: records)
        modelStats = UsageMetricsStore.modelUsageBreakdown(from: records)
    }

    private func loadModelStats() async {
        guard DataManager.shared.isHistoryEnabled else { return }
        let records = await DataManager.shared.fetchAllRecordsQuietly()
        modelStats = UsageMetricsStore.modelUsageBreakdown(from: records)
    }

    private func formatNumber(_ value: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formatDecimal(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0.0" }
        return Self.decimalFormatter.string(from: NSNumber(value: value)) ?? "0.0"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0 seconds" }
        let seconds = Int(interval.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        var components: [String] = []
        if hours > 0 {
            components.append("\(hours) " + (hours == 1 ? "hour" : "hours"))
        }
        if minutes > 0 {
            components.append("\(minutes) " + (minutes == 1 ? "minute" : "minutes"))
        }
        if remainingSeconds > 0 || components.isEmpty {
            components.append("\(remainingSeconds) " + (remainingSeconds == 1 ? "second" : "seconds"))
        }
        if components.count == 1 {
            return components.first!
        } else if components.count == 2 {
            return components.joined(separator: ", ")
        } else {
            return "\(components[0]), \(components[1]) and \(components[2])"
        }
    }

    private func formatDurationShort(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0s" }
        if interval < 60 {
            return String(format: "%.0fs", interval)
        }
        if interval < 3600 {
            let minutes = Int(interval / 60)
            let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }

    private func formatCurrency(_ value: Double?) -> String {
        guard let value else { return "Unknown" }
        if value > 0, value < 0.01 {
            return "<$0.01"
        }
        return Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private var modelUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Model Usage")
                    .font(.headline)
                Spacer()
                Text("Estimated from saved history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if modelStats.isEmpty {
                Text("No model-level history yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(modelStats.prefix(8)) { stats in
                        ModelUsageRow(
                            stats: stats,
                            duration: formatDurationShort(stats.recordingDuration),
                            averageProcessing: formatDurationShort(stats.averageProcessingTime),
                            cost: formatCurrency(stats.estimatedCostUSD)
                        )
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()
}

private struct ModelUsageRow: View {
    let stats: ModelUsageStats
    let duration: String
    let averageProcessing: String
    let cost: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stats.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(stats.provider.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

            usageColumn(title: "Runs", value: "\(stats.sessions)")
            usageColumn(title: "Audio", value: duration)
            usageColumn(title: "Avg", value: averageProcessing)
            usageColumn(title: "Cost", value: cost)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func usageColumn(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 72, alignment: .trailing)
    }
}

private struct UsageMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let iconName: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(accentColor.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}
