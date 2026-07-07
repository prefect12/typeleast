import XCTest
@testable import Typeleast

final class AppIdentityTests: XCTestCase {
    func testTypeleastIdentityConstants() {
        XCTAssertEqual(AppIdentity.displayName, "Typeleast")
        XCTAssertEqual(AppIdentity.packageName, "Typeleast")
        XCTAssertEqual(AppIdentity.executableName, "Typeleast")
        XCTAssertEqual(AppIdentity.bundleIdentifier, "com.typeleast.app")
        XCTAssertEqual(AppIdentity.developmentBundleIdentifier, "com.typeleast-dev.app")
        XCTAssertEqual(AppIdentity.keychainService, "Typeleast")
        XCTAssertEqual(AppIdentity.appSupportDirectoryName, "Typeleast")
        XCTAssertEqual(AppIdentity.releaseArchiveName, "Typeleast.zip")
    }

    func testApplicationSupportBaseDirectoryPrefersTypeleastOverride() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("TypeleastIdentityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let typeleastOverride = base.appendingPathComponent("TypeleastOverride", isDirectory: true)

        let resolved = try AppIdentity.applicationSupportBaseDirectory(
            environment: [
                AppIdentity.appSupportOverrideEnvironmentKey: typeleastOverride.path
            ]
        )

        XCTAssertEqual(resolved.path, typeleastOverride.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: typeleastOverride.path))
    }
}
