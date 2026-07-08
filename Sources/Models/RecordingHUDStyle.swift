import Foundation

internal enum RecordingHUDStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case appleGlass
    case siriAura
    case candidateBar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleGlass:
            return L10n.RecordingSettings.hudStyleAppleGlass
        case .siriAura:
            return L10n.RecordingSettings.hudStyleSiriAura
        case .candidateBar:
            return L10n.RecordingSettings.hudStyleCandidateBar
        }
    }
}
