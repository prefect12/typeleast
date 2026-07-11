import SwiftUI
import AppKit

internal enum RecordingHUDPresentation {
    static let maximumVisibleCharacters = 150

    static func latestText(_ text: String, limit: Int = maximumVisibleCharacters) -> String {
        guard text.count > limit else { return text }
        return "…" + String(text.suffix(limit))
    }

    static func cornerRadius(for style: RecordingHUDStyle, usesRealtimeLayout: Bool) -> CGFloat {
        guard usesRealtimeLayout else {
            return style == .candidateBar ? 14 : LayoutMetrics.RecordingWindow.cornerRadius
        }
        switch style {
        case .appleGlass: return 18
        case .siriAura: return 34
        case .candidateBar: return 14
        }
    }
}

/// Recording control view - standard macOS look and feel
internal struct WaveformRecordingView: View {
    let status: AppStatus
    let audioLevel: Float
    let streamingDraftText: String
    let onTap: () -> Void
    @AppStorage(AppDefaults.Keys.recordingHUDStyle) private var recordingHUDStyle = AppDefaults.defaultRecordingHUDStyle
    @State private var indicatorPulse = false
    @State private var auraPhase = false

    var body: some View {
        ZStack {
            backgroundLayer
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusRow
                .frame(width: rowContentWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            if !isProcessing {
                onTap()
            }
        }
        .help(buttonHelp)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(buttonHelp)
        .frame(width: windowSize.width, height: windowSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(edgeGlowLayer)
        .overlay(borderLayer)
        .onAppear {
            indicatorPulse = true
            auraPhase = true
            resizeRecordingWindow(to: windowSize)
        }
        .onChange(of: statusText) { _, _ in
            if !usesRealtimePresentation {
                resizeRecordingWindow(to: windowSize)
            }
        }
        .onChange(of: recordingHUDStyle) { _, _ in
            resizeRecordingWindow(to: windowSize)
        }
    }

    private var statusRow: some View {
        HStack(alignment: .center, spacing: 10) {
            statusIndicator
                .frame(width: leadingIndicatorWidth, height: indicatorHeight, alignment: .center)

            statusLabel

            if AppIdentity.isStreamingTest {
                Text("TEST")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.gradient, in: Capsule())
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var statusLabel: some View {
        let label = Text(visibleStatusText)
            .font(.system(size: fontSize, weight: textWeight))
            .foregroundStyle(textColor)
            .lineLimit(recordingHUDStyle == .candidateBar && usesRealtimePresentation ? 2 : (usesRealtimePresentation ? 3 : 4))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

        if usesRealtimePresentation {
            label.frame(width: textWidth, alignment: .leading)
        } else {
            label.frame(maxWidth: textWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        ZStack(alignment: .leading) {
            VisualEffectView(
                material: visualEffectMaterial,
                blendingMode: .behindWindow,
                appearanceName: .aqua
            )

            backgroundTint

            switch recordingHUDStyle {
            case .appleGlass:
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.42),
                        Color(red: 0.88, green: 0.94, blue: 1.0).opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if isRecording {
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.blue.opacity(0.06), Color.clear],
                        startPoint: auraPhase ? .topLeading : .bottomLeading,
                        endPoint: auraPhase ? .bottomTrailing : .topTrailing
                    )
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: auraPhase)
                }
            case .siriAura:
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.88),
                                    Color(red: 0.35, green: 0.72, blue: 1.0).opacity(0.52),
                                    Color(red: 0.96, green: 0.36, blue: 0.86).opacity(0.38),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: 58
                            )
                        )
                        .frame(width: 148 + CGFloat(audioLevel) * 54, height: 148 + CGFloat(audioLevel) * 54)
                        .blur(radius: 17 + CGFloat(audioLevel) * 5)
                        .opacity(isRecording ? 1 : 0.58)
                        .scaleEffect(auraPhase ? 1.08 : 0.92)
                        .offset(x: -50 + (auraPhase ? 10 : -2))
                        .animation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true), value: auraPhase)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.54),
                            Color(red: 0.90, green: 0.96, blue: 1.0).opacity(0.30),
                            Color(red: 1.0, green: 0.90, blue: 0.98).opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            case .candidateBar:
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.76),
                        Color(red: 0.97, green: 0.98, blue: 1.0).opacity(0.48)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if isRecording {
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.62, blue: 1.0).opacity(0.10),
                            Color(red: 0.95, green: 0.32, blue: 0.82).opacity(0.10),
                            Color.clear
                        ],
                        startPoint: auraPhase ? .leading : .trailing,
                        endPoint: auraPhase ? .trailing : .leading
                    )
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: auraPhase)
                }
            }
        }
    }

    @ViewBuilder
    private var borderLayer: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch recordingHUDStyle {
        case .appleGlass:
            shape
                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                .overlay(shape.strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
        case .siriAura:
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(red: 0.24, green: 0.63, blue: 1.0).opacity(0.46),
                            Color(red: 0.95, green: 0.31, blue: 0.82).opacity(0.34),
                            Color.white.opacity(0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        case .candidateBar:
            shape
                .strokeBorder(Color.black.opacity(0.11), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var edgeGlowLayer: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if isRecording {
            switch recordingHUDStyle {
            case .appleGlass:
                shape
                    .strokeBorder(Color.white.opacity(auraPhase ? 0.82 : 0.52), lineWidth: 1.1)
                    .animation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true), value: auraPhase)
            case .siriAura:
                shape
                    .strokeBorder(siriLinearGradient.opacity(auraPhase ? 0.96 : 0.56), lineWidth: 1.8)
                    .shadow(color: Color(red: 0.36, green: 0.66, blue: 1.0).opacity(auraPhase ? 0.38 : 0.14), radius: 12)
                    .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true), value: auraPhase)
            case .candidateBar:
                shape
                    .strokeBorder(Color(red: 0.25, green: 0.58, blue: 1.0).opacity(auraPhase ? 0.42 : 0.18), lineWidth: 1)
                    .animation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true), value: auraPhase)
            }
        } else if isProcessing || isDownloadingModel {
            shape
                .strokeBorder(indicatorTint.opacity(auraPhase ? 0.48 : 0.18), lineWidth: 1.1)
                .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: auraPhase)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isRecording {
            recordingIndicator
        } else if isProcessing || isDownloadingModel {
            ProgressView()
                .controlSize(.small)
                .tint(indicatorTint)
        } else if let icon = status.icon {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(status.color)
        } else {
            standbyIndicator
        }
    }

    @ViewBuilder
    private var recordingIndicator: some View {
        switch recordingHUDStyle {
        case .appleGlass:
            ZStack {
                Circle()
                    .fill(siriGradient)
                    .frame(width: 24, height: 24)
                    .blur(radius: 7)
                    .opacity(0.30 + Double(audioLevel) * 0.28)
                    .scaleEffect(indicatorPulse ? 1.18 : 0.82)
                Circle()
                    .fill(siriGradient)
                    .frame(width: 9 + CGFloat(audioLevel) * 4, height: 9 + CGFloat(audioLevel) * 4)
                    .shadow(color: Color(red: 0.96, green: 0.31, blue: 0.32).opacity(0.45), radius: 5)
            }
            .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: indicatorPulse)
        case .siriAura:
            ZStack {
                Circle()
                    .fill(siriGradient)
                    .frame(width: 28 + CGFloat(audioLevel) * 10, height: 28 + CGFloat(audioLevel) * 10)
                    .blur(radius: 8)
                    .opacity(indicatorPulse ? 0.76 : 0.30)
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 11, height: 11)
                Circle()
                    .fill(siriGradient)
                    .frame(width: 8 + CGFloat(audioLevel) * 3, height: 8 + CGFloat(audioLevel) * 3)
            }
            .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true), value: indicatorPulse)
        case .candidateBar:
            MiniSiriWaveform(isAnimating: indicatorPulse, audioLevel: audioLevel)
        }
    }

    @ViewBuilder
    private var standbyIndicator: some View {
        switch recordingHUDStyle {
        case .candidateBar:
            MiniSiriWaveform(isAnimating: false, audioLevel: 0)
                .opacity(0.55)
        default:
            Circle()
                .fill(Color(red: 0.26, green: 0.61, blue: 1.0).opacity(0.78))
                .frame(width: 7, height: 7)
        }
    }

    private var windowSize: CGSize {
        if usesRealtimePresentation {
            return LayoutMetrics.RecordingWindow.realtimeSize(for: recordingHUDStyle)
        }
        let contentSize = measuredTextSize()

        return clampedWindowSize(
            CGSize(
                width: contentSize.width + leadingIndicatorWidth + horizontalPadding * 2,
                height: contentSize.height + verticalPadding * 2
            )
        )
    }

    private var textWidth: CGFloat {
        rowContentWidth
            - leadingIndicatorWidth
            - (AppIdentity.isStreamingTest ? 54 : 0)
            - (AppIdentity.isStreamingTest ? 20 : 10)
    }

    private var rowContentWidth: CGFloat {
        windowSize.width - horizontalPadding * 2
    }

    private var leadingIndicatorWidth: CGFloat {
        switch recordingHUDStyle {
        case .appleGlass:
            return 18
        case .siriAura:
            return 22
        case .candidateBar:
            return 28
        }
    }

    private var indicatorHeight: CGFloat {
        switch recordingHUDStyle {
        case .siriAura:
            return 30
        case .candidateBar:
            return 20
        default:
            return 24
        }
    }

    private func measuredTextSize() -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize, weight: nsTextWeight)
        let maxTextWidth = LayoutMetrics.RecordingWindow.maximumSize.width
            - horizontalPadding * 2
            - leadingIndicatorWidth
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let rect = NSString(string: visibleStatusText).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private func clampedWindowSize(_ size: CGSize) -> CGSize {
        let minimum = minimumSize
        let maximum = LayoutMetrics.RecordingWindow.maximumSize
        return CGSize(
            width: min(max(size.width, minimum.width), maximum.width),
            height: min(max(size.height, minimum.height), maximum.height)
        )
    }

    private func resizeRecordingWindow(to size: CGSize) {
        guard let window = NSApp.windows.first(where: { $0.title == AppIdentity.recordingWindowTitle }) else {
            return
        }

        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(frame, display: true)
        RecordingWindowPositioner.position(window)
    }

    private var statusText: String {
        switch status {
        case .recording:
            let draft = streamingDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !draft.isEmpty {
                return draft
            }
            return usesRealtimePresentation ? L10n.Recording.realtimeListening : "Recording…"
        case .processing(let message):
            return message
        case .downloadingModel(let message):
            return message
        case .success:
            return AppStatus.successMessage(smartPasteEnabled: smartPasteEnabled)
        case .ready:
            return "Ready to record"
        case .permissionRequired:
            return "Microphone access required"
        case .error(let message):
            return message
        }
    }

    private var visibleStatusText: String {
        guard usesRealtimePresentation else { return statusText }
        return RecordingHUDPresentation.latestText(statusText)
    }

    private var buttonTitle: String {
        switch status {
        case .recording:
            return "Stop Recording"
        case .processing:
            return "Processing…"
        case .downloadingModel:
            return "Start Recording"
        case .success:
            return AppStatus.successButtonHelp(smartPasteEnabled: smartPasteEnabled)
        case .permissionRequired:
            return "Grant Permission"
        case .error:
            return "Try Again"
        case .ready:
            return "Start Recording"
        }
    }

    private var isRecording: Bool {
        if case .recording = status { return true }
        return false
    }

    private var isProcessing: Bool {
        if case .processing = status { return true }
        return false
    }

    private var isDownloadingModel: Bool {
        if case .downloadingModel = status { return true }
        return false
    }

    private var buttonHelp: String {
        switch status {
        case .recording:
            return "Stop recording"
        case .processing:
            return "Processing"
        case .downloadingModel:
            return "Start recording"
        case .success:
            return AppStatus.successButtonHelp(smartPasteEnabled: smartPasteEnabled)
        case .permissionRequired:
            return "Grant microphone permission"
        case .error:
            return "Try again"
        case .ready:
            return "Start recording"
        }
    }

    private var smartPasteEnabled: Bool {
        TranscriptionSettingsStore.shared.isSmartPasteEnabled
    }

    private var minimumSize: CGSize {
        switch recordingHUDStyle {
        case .candidateBar:
            return CGSize(width: 172, height: 44)
        default:
            return LayoutMetrics.RecordingWindow.minimumSize
        }
    }

    private var horizontalPadding: CGFloat {
        switch recordingHUDStyle {
        case .candidateBar:
            return 14
        default:
            return LayoutMetrics.RecordingWindow.horizontalPadding
        }
    }

    private var verticalPadding: CGFloat {
        switch recordingHUDStyle {
        case .candidateBar:
            return 12
        default:
            return LayoutMetrics.RecordingWindow.verticalPadding
        }
    }

    private var cornerRadius: CGFloat {
        RecordingHUDPresentation.cornerRadius(
            for: recordingHUDStyle,
            usesRealtimeLayout: usesRealtimePresentation
        )
    }

    private var usesRealtimePresentation: Bool {
        AppIdentity.isStreamingTest
            || TranscriptionSettingsStore.shared.transcriptionProvider == .openAIRealtime
    }

    private var fontSize: CGFloat {
        switch recordingHUDStyle {
        case .candidateBar:
            return 14
        default:
            return 15
        }
    }

    private var textWeight: Font.Weight {
        switch recordingHUDStyle {
        case .candidateBar:
            return .medium
        default:
            return .semibold
        }
    }

    private var nsTextWeight: NSFont.Weight {
        switch recordingHUDStyle {
        case .candidateBar:
            return .medium
        default:
            return .semibold
        }
    }

    private var textColor: Color {
        switch recordingHUDStyle {
        case .candidateBar:
            return Color.black.opacity(0.82)
        default:
            return Color.black.opacity(0.86)
        }
    }

    private var backgroundTint: Color {
        switch recordingHUDStyle {
        case .appleGlass:
            return Color.white.opacity(0.50)
        case .siriAura:
            return Color.white.opacity(0.44)
        case .candidateBar:
            return Color.white.opacity(0.68)
        }
    }

    private var visualEffectMaterial: NSVisualEffectView.Material {
        switch recordingHUDStyle {
        case .candidateBar:
            return .popover
        default:
            return .hudWindow
        }
    }

    private var indicatorTint: Color {
        switch recordingHUDStyle {
        case .appleGlass:
            return Color(red: 0.24, green: 0.55, blue: 1.0)
        case .siriAura:
            return Color(red: 0.65, green: 0.28, blue: 0.96)
        case .candidateBar:
            return Color(red: 0.20, green: 0.50, blue: 0.88)
        }
    }

    private var siriGradient: AngularGradient {
        AngularGradient(
            colors: [
                Color(red: 0.20, green: 0.60, blue: 1.0),
                Color(red: 0.67, green: 0.34, blue: 1.0),
                Color(red: 1.0, green: 0.35, blue: 0.78),
                Color(red: 1.0, green: 0.45, blue: 0.22),
                Color(red: 0.20, green: 0.60, blue: 1.0)
            ],
            center: .center
        )
    }

    private var siriLinearGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.60, blue: 1.0),
                Color(red: 0.67, green: 0.34, blue: 1.0),
                Color(red: 1.0, green: 0.35, blue: 0.78),
                Color(red: 1.0, green: 0.45, blue: 0.22)
            ],
            startPoint: auraPhase ? .topLeading : .bottomLeading,
            endPoint: auraPhase ? .bottomTrailing : .topTrailing
        )
    }
}

private struct MiniSiriWaveform: View {
    let isAnimating: Bool
    let audioLevel: Float

    private let heights: [CGFloat] = [8, 14, 18, 12, 16]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule(style: .continuous)
                    .fill(waveGradient)
                    .frame(width: 3, height: isAnimating ? animatedHeight(height, index: index) : height * 0.72)
                    .animation(
                        .easeInOut(duration: 0.72 + Double(index) * 0.06)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 24, height: 18)
    }

    private var waveGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.58, blue: 1.0),
                Color(red: 0.76, green: 0.32, blue: 1.0),
                Color(red: 1.0, green: 0.37, blue: 0.72)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func animatedHeight(_ base: CGFloat, index: Int) -> CGFloat {
        guard isAnimating else { return base * 0.72 }
        let levelBoost = CGFloat(audioLevel) * 9
        let phaseScale: CGFloat = index.isMultiple(of: 2) ? 1.0 : 0.62
        return max(7, base * phaseScale + levelBoost)
    }
}

#Preview("Recording Window") {
    WaveformRecordingView(status: .recording, audioLevel: 0.45, streamingDraftText: "目前这个余额还是有点问题，字跟这个图标不是在同一水平", onTap: {})
        .padding(40)
        .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Recording HUD Styles") {
    VStack(spacing: 18) {
        WaveformRecordingView(status: .recording, audioLevel: 0.35, streamingDraftText: "Apple 玻璃", onTap: {})
            .environment(\.colorScheme, .light)
        WaveformRecordingView(status: .processing("准备音频..."), audioLevel: 0.15, streamingDraftText: "", onTap: {})
            .environment(\.colorScheme, .light)
        WaveformRecordingView(status: .recording, audioLevel: 0.75, streamingDraftText: "Candidate Bar Waveform", onTap: {})
            .environment(\.colorScheme, .light)
    }
    .padding(48)
    .background(Color(nsColor: .windowBackgroundColor))
}
