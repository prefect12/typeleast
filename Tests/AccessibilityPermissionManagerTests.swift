import XCTest
@testable import Typeleast

final class AccessibilityPermissionManagerTests: XCTestCase {

    private final class Counter { var value = 0 }

    override func setUp() {
        super.setUp()
        AccessibilityPermissionRequestCoordinator.shared.resetForTesting()
        LanguageManager.shared.current = .english
    }

    override func tearDown() {
        AccessibilityPermissionRequestCoordinator.shared.resetForTesting()
        LanguageManager.shared.current = .chinese
        super.tearDown()
    }

    private func makeManager(granted: Bool, counter: Counter) -> AccessibilityPermissionManager {
        AccessibilityPermissionManager {
            counter.value += 1
            return granted
        }
    }

    func testPermissionStatusMessageReflectsPermissionState() {
        let grantedCounter = Counter()
        let grantedManager = makeManager(granted: true, counter: grantedCounter)
        XCTAssertEqual(
            grantedManager.permissionStatusMessage,
            "✅ Accessibility permission granted - SmartPaste is enabled"
        )

        let deniedCounter = Counter()
        let deniedManager = makeManager(granted: false, counter: deniedCounter)
        XCTAssertEqual(
            deniedManager.permissionStatusMessage,
            "⚠️ Accessibility permission required for SmartPaste functionality"
        )
    }

    func testPermissionStatusMessageUsesCurrentLanguage() {
        LanguageManager.shared.current = .chinese

        let grantedManager = makeManager(granted: true, counter: Counter())
        XCTAssertEqual(
            grantedManager.permissionStatusMessage,
            "✅ 辅助功能权限已授权，智能粘贴可用"
        )

        let deniedManager = makeManager(granted: false, counter: Counter())
        XCTAssertEqual(
            deniedManager.permissionStatusMessage,
            "⚠️ 智能粘贴需要辅助功能权限"
        )
    }

    func testDetailedPermissionStatusIncludesTroubleshootingWhenDenied() {
        let counter = Counter()
        let manager = makeManager(granted: false, counter: counter)

        let status = manager.detailedPermissionStatus

        XCTAssertFalse(status.isGranted)
        XCTAssertEqual(status.statusMessage, "Accessibility permission is not granted")
        XCTAssertEqual(counter.value, 1)
        XCTAssertNotNil(status.troubleshootingInfo)
        XCTAssertTrue(status.troubleshootingInfo?.contains("System Settings") ?? false)
    }

    func testDetailedPermissionStatusUsesCurrentLanguage() {
        LanguageManager.shared.current = .chinese

        let counter = Counter()
        let manager = makeManager(granted: false, counter: counter)

        let status = manager.detailedPermissionStatus

        XCTAssertFalse(status.isGranted)
        XCTAssertEqual(status.statusMessage, "辅助功能权限尚未授权")
        XCTAssertEqual(counter.value, 1)
        XCTAssertTrue(status.troubleshootingInfo?.contains("系统设置") ?? false)
        XCTAssertTrue(status.troubleshootingInfo?.contains("/Applications/Typeleast.app") ?? false)
    }

    func testRequestPermissionReturnsTrueWhenAlreadyAuthorized() {
        let counter = Counter()
        let manager = makeManager(granted: true, counter: counter)
        let expectation = expectation(description: "Completion called with granted status")

        manager.requestPermissionWithExplanation { result in
            XCTAssertEqual(result, .granted)
            XCTAssertEqual(counter.value, 1)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0.1)
    }

    func testRequestPermissionShortCircuitsInTestEnvironmentWhenDenied() {
        let counter = Counter()
        let manager = makeManager(granted: false, counter: counter)
        let expectation = expectation(description: "Completion called with denied status in test env")

        manager.requestPermissionWithExplanation { result in
            XCTAssertEqual(result, .notGranted)
            XCTAssertEqual(counter.value, 1)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0.1)
    }

    func testPermissionRequestCoordinatorCoalescesActiveRequests() {
        let coordinator = AccessibilityPermissionRequestCoordinator()
        var results: [AccessibilityPermissionRequestResult] = []

        let first = coordinator.register(permissionGranted: false) { results.append($0) }
        let second = coordinator.register(permissionGranted: false) { results.append($0) }

        XCTAssertEqual(first, .startRequest)
        XCTAssertEqual(second, .waitingForActiveRequest)
        XCTAssertTrue(results.isEmpty)

        coordinator.complete(.notGranted)

        XCTAssertEqual(results, [.notGranted, .notGranted])
    }

    func testPermissionRequestCoordinatorSuppressesRepeatedDeniedPromptsUntilGranted() {
        let coordinator = AccessibilityPermissionRequestCoordinator()
        var results: [AccessibilityPermissionRequestResult] = []

        XCTAssertEqual(
            coordinator.register(permissionGranted: false) { results.append($0) },
            .startRequest
        )
        coordinator.complete(.notGranted)

        XCTAssertEqual(
            coordinator.register(permissionGranted: false) { results.append($0) },
            .skippedRecentlyPrompted
        )
        XCTAssertEqual(results, [.notGranted, .notGranted])

        XCTAssertEqual(
            coordinator.register(permissionGranted: true) { results.append($0) },
            .alreadyGranted
        )
        XCTAssertEqual(results, [.notGranted, .notGranted, .granted])

        XCTAssertEqual(
            coordinator.register(permissionGranted: false) { results.append($0) },
            .startRequest
        )
    }
}
