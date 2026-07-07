import Foundation
import Combine

/// Supported app languages
internal enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

/// Manages app language preference and notifies views of changes.
internal final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private static let key = "appLanguage"
    internal static let defaultLanguage: AppLanguage = .chinese
    private let defaults: UserDefaults

    @Published var current: AppLanguage {
        didSet {
            defaults.set(current.rawValue, forKey: Self.key)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.current = Self.initialLanguage(defaults: defaults)
    }

    internal static func initialLanguage(defaults: UserDefaults = .standard) -> AppLanguage {
        let raw = defaults.string(forKey: Self.key) ?? ""
        return AppLanguage(rawValue: raw) ?? defaultLanguage
    }
}
