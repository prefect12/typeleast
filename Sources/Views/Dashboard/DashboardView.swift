import SwiftUI
import AppKit

// MARK: - Dashboard Theme
internal enum DashboardTheme {
    // Sidebar - branded shell inspired by the older custom dashboard.
    static let sidebarBg = adaptive(light: rgb(0xF3, 0xED, 0xE3), dark: rgb(0x25, 0x25, 0x23))
    static let sidebarText = adaptive(light: rgb(0x32, 0x31, 0x2D), dark: rgb(0xE8, 0xE8, 0xE2))
    static let sidebarTextMuted = adaptive(light: rgb(0x8B, 0x84, 0x78), dark: rgb(0xA6, 0xA4, 0x9D))
    static let sidebarTextFaint = adaptive(light: rgb(0xC2, 0xBA, 0xAE), dark: rgb(0x6F, 0x6D, 0x67))
    static let sidebarDivider = adaptive(light: rgb(0xD9, 0xD0, 0xC3), dark: rgb(0x3E, 0x3E, 0x39))
    static let sidebarSelection = adaptive(light: rgb(0xEF, 0xE3, 0xD7), dark: rgb(0x1F, 0x5F, 0xBF))
    static let sidebarSelectedText = adaptive(light: rgb(0x24, 0x23, 0x20), dark: .white)
    static let sidebarAccent = adaptive(light: rgb(0xCC, 0x6D, 0x58), dark: rgb(0x16, 0x8A, 0xFF))
    static let sidebarAccentSubtle = adaptive(light: rgb(0xE8, 0xD5, 0xC7), dark: rgb(0x19, 0x4D, 0x88))

    // Main content - warm light design, intentionally consistent across system appearances.
    static let pageBg = adaptive(light: rgb(0xFA, 0xF5, 0xED), dark: rgb(0x30, 0x30, 0x2F))
    static let cardBg = adaptive(light: rgb(0xFF, 0xFB, 0xF4), dark: rgb(0x1F, 0x1F, 0x1F))
    static let cardBgAlt = adaptive(light: rgb(0xF8, 0xF0, 0xE6), dark: rgb(0x1B, 0x1B, 0x1B))

    // Text
    static let ink = adaptive(light: rgb(0x25, 0x24, 0x20), dark: rgb(0xF0, 0xF0, 0xEC))
    static let inkLight = adaptive(light: rgb(0x6E, 0x68, 0x5D), dark: rgb(0xB2, 0xB0, 0xA9))
    static let inkMuted = adaptive(light: rgb(0x95, 0x8D, 0x80), dark: rgb(0x84, 0x82, 0x7B))
    static let inkFaint = adaptive(light: rgb(0xD3, 0xCA, 0xBD), dark: rgb(0x55, 0x55, 0x50))

    // Accent
    static let accent = adaptive(light: rgb(0xC5, 0x67, 0x4E), dark: rgb(0x16, 0x8A, 0xFF))
    static let accentLight = adaptive(light: rgb(0xEF, 0xD8, 0xCA), dark: rgb(0x1A, 0x4D, 0x86))
    static let accentSubtle = adaptive(light: rgb(0xF6, 0xEA, 0xDF), dark: rgb(0x24, 0x2D, 0x36))

    // Borders & Dividers
    static let rule = adaptive(light: rgb(0xDE, 0xD5, 0xC8), dark: rgb(0x45, 0x45, 0x40))
    static let ruleBold = adaptive(light: rgb(0xC9, 0xBE, 0xAF), dark: rgb(0x62, 0x62, 0x5D))

    // Provider colors (system-leaning)
    static let providerOpenAI = Color(nsColor: .systemBlue)
    static let providerMiMo = Color(nsColor: .systemCyan)
    static let providerGemini = Color(nsColor: .systemIndigo)
    static let providerLocal = Color(nsColor: .systemTeal)
    static let providerParakeet = Color(nsColor: .systemGreen)

    // Activity heatmap (system grays)
    static let heatmapEmpty = Color(nsColor: .separatorColor)
    static let heatmapLow = Color(nsColor: .quaternaryLabelColor)
    static let heatmapMedium = Color(nsColor: .tertiaryLabelColor)
    static let heatmapHigh = Color(nsColor: .secondaryLabelColor)
    static let heatmapMax = Color(nsColor: .labelColor).opacity(0.6)

    // Semantic colors - adaptive to light/dark mode
    static let success = Color(nsColor: .systemGreen)
    static let destructive = Color(nsColor: .systemRed)

    static let sidebarWidth: CGFloat = 280

    // Typography - standard macOS system fonts
    enum Fonts {
        static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // Spacing system (8pt base)
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(red: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: 1)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .accessibilityHighContrastDarkAqua,
                .darkAqua,
                .accessibilityHighContrastAqua,
                .aqua
            ])
            return match == .darkAqua || match == .accessibilityHighContrastDarkAqua ? dark : light
        })
    }
}

// MARK: - Navigation Item
internal enum DashboardNavItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case timingAnalysis
    case transcripts
    case categories
    case recording
    case providers
    case preferences
    case permissions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dashboard: return L10n.Nav.overview
        case .timingAnalysis: return L10n.Nav.timingAnalysis
        case .transcripts: return L10n.Nav.transcripts
        case .categories: return L10n.Nav.categories
        case .recording: return L10n.Nav.recording
        case .providers: return L10n.Nav.providers
        case .preferences: return L10n.Nav.preferences
        case .permissions: return L10n.Nav.permissions
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.text.square"
        case .timingAnalysis: return "chart.bar.xaxis"
        case .transcripts: return "doc.text"
        case .categories: return "folder"
        case .recording: return "waveform"
        case .providers: return "cloud"
        case .preferences: return "slider.horizontal.3"
        case .permissions: return "lock"
        }
    }
}

// MARK: - Main Dashboard View
internal struct DashboardView: View {
    @ObservedObject var selectionModel: DashboardSelectionModel

    init(selectionModel: DashboardSelectionModel = DashboardSelectionModel()) {
        self.selectionModel = selectionModel
    }

    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var metricsStore = UsageMetricsStore.shared
    private var currentNav: DashboardNavItem {
        selectionModel.selectedNav ?? .dashboard
    }

    var body: some View {
        HStack(spacing: 0) {
            DashboardSidebar(
                selectedNav: Binding(
                    get: { currentNav },
                    set: { selectionModel.selectedNav = $0 }
                ),
                totalWords: metricsStore.snapshot.totalWords
            )
            .frame(width: DashboardTheme.sidebarWidth)

            Rectangle()
                .fill(DashboardTheme.sidebarDivider)
                .frame(width: 1)

            ZStack {
                DashboardTheme.pageBg

                detailView(for: currentNav)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
        }
        .background(DashboardTheme.pageBg)
        .id(languageManager.current)
        .task {
            await metricsStore.bootstrapIfNeeded()
            let records = await DataManager.shared.fetchAllRecordsQuietly()
            SourceUsageStore.shared.rebuild(using: records)
        }
    }

    @ViewBuilder
    private func detailView(for item: DashboardNavItem) -> some View {
        switch item {
        case .dashboard:
            DashboardHomeView(selectedNav: Binding(get: { selectionModel.selectedNav ?? .dashboard }, set: { selectionModel.selectedNav = $0 }))
        case .timingAnalysis:
            DashboardTimingAnalysisView()
        case .transcripts:
            DashboardTranscriptsView()
        case .categories:
            DashboardCategoriesView()
        case .recording:
            DashboardRecordingView()
        case .providers:
            DashboardProvidersView()
        case .preferences:
            DashboardPreferencesView()
        case .permissions:
            DashboardPermissionsView()
        }
    }
}

// MARK: - Branded Sidebar

private struct DashboardSidebar: View {
    @Binding var selectedNav: DashboardNavItem
    let totalWords: Int

    private let primaryItems: [DashboardNavItem] = [
        .dashboard,
        .timingAnalysis,
        .transcripts,
        .categories
    ]

    private let settingsItems: [DashboardNavItem] = [
        .recording,
        .providers,
        .preferences,
        .permissions
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            VStack(alignment: .leading, spacing: 10) {
                navRows(primaryItems)

                SidebarDividerLabel(text: L10n.isChinese ? "设置" : "SETTINGS")
                    .padding(.top, 28)
                    .padding(.bottom, 14)

                navRows(settingsItems)
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 28)

            sidebarSummary
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
        }
        .background(DashboardTheme.sidebarBg)
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Typeleast")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(DashboardTheme.sidebarText)
                .lineLimit(1)

            Text("VOICE TO TEXT")
                .font(.system(size: 13, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(DashboardTheme.sidebarTextMuted)
        }
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
    }

    private func navRows(_ items: [DashboardNavItem]) -> some View {
        ForEach(items) { item in
            DashboardSidebarRow(
                item: item,
                isSelected: selectedNav == item
            ) {
                selectedNav = item
            }
        }
    }

    private var sidebarSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(DashboardTheme.sidebarDivider)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.isChinese ? "累计转录" : "TOTAL RECORDED")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(DashboardTheme.sidebarTextFaint)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.numberFormatter.string(from: NSNumber(value: totalWords)) ?? "\(totalWords)")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(DashboardTheme.sidebarText)
                        .monospacedDigit()

                    Text(L10n.isChinese ? "字" : "words")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DashboardTheme.sidebarTextMuted)
                }
            }
            .padding(.top, 12)
        }
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

private struct DashboardSidebarRow: View {
    let item: DashboardNavItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? DashboardTheme.sidebarSelectedText : DashboardTheme.sidebarAccent)

                Text(item.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? DashboardTheme.sidebarSelectedText : DashboardTheme.sidebarTextMuted)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? DashboardTheme.sidebarSelection : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct SidebarDividerLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(DashboardTheme.sidebarDivider)
                .frame(height: 1)

            Text(text)
                .font(.system(size: 11, weight: .bold))
                .tracking(2.2)
                .foregroundStyle(DashboardTheme.sidebarTextFaint)

            Rectangle()
                .fill(DashboardTheme.sidebarDivider)
                .frame(height: 1)
        }
        .frame(height: 20)
    }
}

// MARK: - Preview
#Preview("Dashboard") {
    DashboardView()
        .frame(width: LayoutMetrics.DashboardWindow.previewSize.width,
               height: LayoutMetrics.DashboardWindow.previewSize.height)
}
