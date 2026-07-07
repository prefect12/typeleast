import XCTest
@testable import Typeleast

final class KeychainServiceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.typeleast.tests.keychain.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testGetPrefersMirroredCredentialWithoutKeychainPrompt() throws {
        let key = "test-api-key"
        defaults.set(
            Data(key.utf8).base64EncodedString(),
            forKey: KeychainService.mirroredCredentialDefaultsKey(service: "Typeleast", account: "OpenAI")
        )

        let service = KeychainService(userDefaults: defaults)

        XCTAssertEqual(try service.get(service: "Typeleast", account: "OpenAI"), key)
    }
}
