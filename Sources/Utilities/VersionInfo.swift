import Foundation

struct VersionInfo {
    static let version = "2.1.2"
    static let gitHash = "fcf29020283ee3e45b44102f1d831aeaaea669ee"
    static let buildDate = "2026-07-07"
    
    static var displayVersion: String {
        if gitHash != "dev-build" && gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            return "\(version) (\(shortHash))"
        }
        return version
    }
    
    static var fullVersionInfo: String {
        var info = "Typeleast \(version)"
        if gitHash != "dev-build" && gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            info += " • \(shortHash)"
        }
        if !buildDate.isEmpty {
            info += " • \(buildDate)"
        }
        return info
    }
}