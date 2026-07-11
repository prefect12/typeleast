import CoreGraphics

/// Centralized layout metrics to avoid scattered magic numbers.
internal enum LayoutMetrics {
    enum RecordingWindow {
        static let minimumSize = CGSize(width: 180, height: 48)
        static let maximumSize = CGSize(width: 360, height: 104)
        static func streamingTestSize(for style: RecordingHUDStyle) -> CGSize {
            switch style {
            case .appleGlass:
                return CGSize(width: 420, height: 82)
            case .siriAura:
                return CGSize(width: 430, height: 82)
            case .candidateBar:
                return CGSize(width: 420, height: 68)
            }
        }
        static let size = minimumSize
        static let cornerRadius: CGFloat = 18
        static let edgePadding: CGFloat = 12
        static let caretGap: CGFloat = 8
        static let horizontalPadding: CGFloat = 18
        static let verticalPadding: CGFloat = 14
    }
    
    enum DashboardWindow {
        static let initialSize = CGSize(width: 950, height: 700)
        static let minimumSize = CGSize(width: 800, height: 550)
        static let previewSize = CGSize(width: 900, height: 700)
        static let sidebarWidth: CGFloat = 200
    }
    
    enum TranscriptionHistory {
        static let minimumSize = CGSize(width: 700, height: 400)
        static let previewSize = CGSize(width: 700, height: 500)
    }
    
    enum Welcome {
        static let windowSize = CGSize(width: 600, height: 650)
    }
}
