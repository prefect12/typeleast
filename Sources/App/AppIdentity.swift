import Foundation

internal enum AppIdentity {
    #if TYPELEAST_STREAMING_TEST
    static let isStreamingTest = true
    static let displayName = "Typeleast Streaming Test"
    static let bundleIdentifier = "com.typeleast.streaming-test"
    static let appBundleName = "Typeleast Streaming Test.app"
    static let releaseArchiveName = "TypeleastStreamingTest.zip"
    static let keychainService = "Typeleast Streaming Test"
    static let appSupportDirectoryName = "TypeleastStreamingTest"
    static let swiftDataStoreName = "TypeleastStreamingTest.store"
    #else
    static let isStreamingTest = false
    static let displayName = "Typeleast"
    static let bundleIdentifier = productionBundleIdentifier
    static let appBundleName = "Typeleast.app"
    static let releaseArchiveName = "Typeleast.zip"
    static let keychainService = productionKeychainService
    static let appSupportDirectoryName = "Typeleast"
    static let swiftDataStoreName = "Typeleast.store"
    #endif

    static let packageName = "Typeleast"
    static let executableName = "Typeleast"

    static let productionBundleIdentifier = "com.typeleast.app"
    static let streamingTestBundleIdentifier = "com.typeleast.streaming-test"
    static let developmentBundleIdentifier = "com.typeleast-dev.app"

    static let productionKeychainService = "Typeleast"
    static let streamingTestKeychainService = "Typeleast Streaming Test"

    static var recordingWindowTitle: String { "\(displayName) Recording" }
    static var dashboardWindowTitle: String { "\(displayName) Dashboard" }
    static var welcomeWindowTitle: String { "Welcome to \(displayName)" }

    static let appSupportOverrideEnvironmentKey = "TYPELEAST_APP_SUPPORT_DIR"

    static func isTypeleastBundleIdentifier(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return identifier == productionBundleIdentifier
            || identifier == streamingTestBundleIdentifier
            || identifier == developmentBundleIdentifier
    }

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
