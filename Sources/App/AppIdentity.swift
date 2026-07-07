import Foundation

internal enum AppIdentity {
    static let displayName = "Typeleast"

    static let packageName = "Typeleast"
    static let executableName = "Typeleast"
    static let appBundleName = "Typeleast.app"
    static let releaseArchiveName = "Typeleast.zip"

    static let bundleIdentifier = "com.typeleast.app"
    static let developmentBundleIdentifier = "com.typeleast-dev.app"

    static let keychainService = "Typeleast"

    static let appSupportDirectoryName = "Typeleast"

    static let recordingWindowTitle = "Typeleast Recording"
    static let dashboardWindowTitle = "Typeleast Dashboard"
    static let welcomeWindowTitle = "Welcome to Typeleast"

    static let swiftDataStoreName = "Typeleast.store"

    static let appSupportOverrideEnvironmentKey = "TYPELEAST_APP_SUPPORT_DIR"

    static func applicationSupportBaseDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let override = environment[appSupportOverrideEnvironmentKey], !override.isEmpty {
            return try ensureDirectory(URL(fileURLWithPath: override, isDirectory: true), fileManager: fileManager)
        }
        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    static func applicationSupportDirectory(fileManager: FileManager = .default, create: Bool = true) throws -> URL {
        let url = try applicationSupportBaseDirectory(fileManager: fileManager)
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        if create {
            return try ensureDirectory(url, fileManager: fileManager)
        }
        return url
    }

    static func swiftDataStoreURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(swiftDataStoreName, isDirectory: false)
    }

    private static func ensureDirectory(_ url: URL, fileManager: FileManager) throws -> URL {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
}
