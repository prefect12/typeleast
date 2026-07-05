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

    @Published var current: AppLanguage {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.key)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ""
        self.current = AppLanguage(rawValue: raw) ?? .english
    }
}
