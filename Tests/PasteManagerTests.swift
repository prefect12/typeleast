import XCTest
import AppKit
@testable import Typeleast

@MainActor
final class PasteManagerTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var pasteboardName: NSPasteboard.Name!
    private var pasteboard: NSPasteboard!

    private final class StubAccessibilityPermissionManager: AccessibilityPermissionManager {
        private let requestResult: AccessibilityPermissionRequestResult

        init(permissionGranted: Bool, requestResult: AccessibilityPermissionRequestResult) {
            self.requestResult = requestResult
            super.init(permissionCheck: { permissionGranted })
        }

        override func requestPermissionWithExplanation(
            completion: @escaping (AccessibilityPermissionRequestResult) -> Void
        ) {
            completion(requestResult)
        }
    }

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "com.typeleast.tests.paste.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        pasteboardName = NSPasteboard.Name("com.typeleast.tests.paste.\(UUID().uuidString)")
        pasteboard = NSPasteboard(name: pasteboardName)
        pasteboard.clearContents()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        pasteboard.clearContents()
        pasteboard = nil
        pasteboardName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeManager(permissionGranted: Bool) -> PasteManager {
        let manager = PasteManager(
            accessibilityManager: AccessibilityPermissionManager(permissionCheck: { permissionGranted }),
            userDefaults: defaults,
            pasteboard: pasteboard
        )
        return manager
    }

    private func makeManager(accessibilityManager: AccessibilityPermissionManager) -> PasteManager {
        PasteManager(
            accessibilityManager: accessibilityManager,
            userDefaults: defaults,
            pasteboard: pasteboard
        )
    }

    // MARK: - Tests

    func testSmartPasteDisabledPostsFailureAndSkipsActivation() async throws {
        defaults.set(false, forKey: "enableSmartPaste")

        let mockApp = MockRunningApplication()
        let manager = makeManager(permissionGranted: true)

        // Set up notification expectation before calling smartPaste
        let notificationReceived = expectation(description: "PasteOperationFailed fired")
        let observer = NotificationCenter.default.addObserver(
            forName: .pasteOperationFailed,
            object: nil,
            queue: nil
        ) { _ in
            notificationReceived.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.smartPaste(into: mockApp, text: "hello world")

        await fulfillment(of: [notificationReceived], timeout: 1.0)
        XCTAssertEqual(mockApp.mockActivationCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
    }

    func testSmartPasteFailsWhenPermissionDenied() async throws {
        defaults.set(true, forKey: "enableSmartPaste")

        let mockApp = MockRunningApplication()
        let manager = makeManager(permissionGranted: false)

        let notificationReceived = expectation(description: "PasteOperationFailed fired")
        let observer = NotificationCenter.default.addObserver(
            forName: .pasteOperationFailed,
            object: nil,
            queue: nil
        ) { _ in
            notificationReceived.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.smartPaste(into: mockApp, text: "needs permission")

        await fulfillment(of: [notificationReceived], timeout: 1.0)
        XCTAssertEqual(mockApp.mockActivationCount, 0)
    }

    func testSmartPasteFailsForNilTargetApplication() async throws {
        defaults.set(true, forKey: "enableSmartPaste")

        let manager = makeManager(permissionGranted: true)

        let notificationReceived = expectation(description: "PasteOperationFailed fired")
        let observer = NotificationCenter.default.addObserver(
            forName: .pasteOperationFailed,
            object: nil,
            queue: nil
        ) { _ in
            notificationReceived.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.smartPaste(into: nil, text: "no target app")

        await fulfillment(of: [notificationReceived], timeout: 1.0)
    }

    func testSmartPasteAttemptsActivationThenFailsInsideTests() async throws {
        defaults.set(true, forKey: "enableSmartPaste")

        let mockApp = MockRunningApplication()
        let manager = makeManager(permissionGranted: true)

        let notificationReceived = expectation(description: "PasteOperationFailed fired")
        let observer = NotificationCenter.default.addObserver(
            forName: .pasteOperationFailed,
            object: nil,
            queue: nil
        ) { _ in
            notificationReceived.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.smartPaste(into: mockApp, text: "attempt paste")

        await fulfillment(of: [notificationReceived], timeout: 1.0)
        XCTAssertEqual(mockApp.mockActivationCount, 1)
    }

    func testPasteWithUserInteractionKeepsSmartPasteEnabledWhenUserDefersPermission() async throws {
        defaults.set(true, forKey: AppDefaults.Keys.enableSmartPaste)
        let manager = makeManager(
            accessibilityManager: StubAccessibilityPermissionManager(
                permissionGranted: false,
                requestResult: .userDeclined
            )
        )

        await withCheckedContinuation { continuation in
            manager.pasteWithUserInteraction { result in
                if case .success = result {
                    XCTFail("Paste should fail when permission is declined")
                }
                continuation.resume()
            }
        }

        XCTAssertTrue(defaults.bool(forKey: AppDefaults.Keys.enableSmartPaste))
    }

    func testPasteWithUserInteractionKeepsSmartPasteEnabledWhenPermissionStillPending() async throws {
        defaults.set(true, forKey: AppDefaults.Keys.enableSmartPaste)
        let manager = makeManager(
            accessibilityManager: StubAccessibilityPermissionManager(
                permissionGranted: false,
                requestResult: .notGranted
            )
        )

        await withCheckedContinuation { continuation in
            manager.pasteWithUserInteraction { result in
                if case .success = result {
                    XCTFail("Paste should fail when permission is not granted")
                }
                continuation.resume()
            }
        }

        XCTAssertTrue(defaults.bool(forKey: AppDefaults.Keys.enableSmartPaste))
    }
}
