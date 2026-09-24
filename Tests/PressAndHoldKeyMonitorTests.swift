import XCTest
import AppKit
@testable import Typeleast

final class PressAndHoldKeyMonitorTests: XCTestCase {
    private var addedGlobalEvents: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = []
    private var addedLocalEvents: [(NSEvent.EventTypeMask, (NSEvent) -> NSEvent?)] = []
    private var removedEvents: [Any] = []

    override func tearDown() {
        addedGlobalEvents.removeAll()
        addedLocalEvents.removeAll()
        removedEvents.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeMonitor(
        configuration: PressAndHoldConfiguration,
        keyDownHandler: @escaping () -> Void = {},
        keyUpHandler: (() -> Void)? = nil,
        holdStartHandler: (() -> Void)? = nil,
        holdEndHandler: (() -> Void)? = nil,
        now: @escaping () -> Date = Date.init,
        doubleTapInterval: TimeInterval = 0.35,
        scheduleAfter: PressAndHoldKeyMonitor.DelayedWorkScheduler? = nil
    ) -> PressAndHoldKeyMonitor {
        let addGlobalMonitor: PressAndHoldKeyMonitor.EventMonitorFactory = { [weak self] mask, handler in
            self?.addedGlobalEvents.append((mask, handler))
            return "global-\(self?.addedGlobalEvents.count ?? 0)"
        }

        let addLocalMonitor: PressAndHoldKeyMonitor.LocalEventMonitorFactory = { [weak self] mask, handler in
            self?.addedLocalEvents.append((mask, handler))
            return "local-\(self?.addedLocalEvents.count ?? 0)"
        }

        let removeMonitor: PressAndHoldKeyMonitor.EventMonitorRemoval = { [weak self] token in
            self?.removedEvents.append(token)
        }

        return PressAndHoldKeyMonitor(
            configuration: configuration,
            keyDownHandler: keyDownHandler,
            keyUpHandler: keyUpHandler,
            holdStartHandler: holdStartHandler,
            holdEndHandler: holdEndHandler,
            addGlobalMonitor: addGlobalMonitor,
            addLocalMonitor: addLocalMonitor,
            removeMonitor: removeMonitor,
            now: now,
            doubleTapInterval: doubleTapInterval,
            scheduleAfter: scheduleAfter
        )
    }

    // MARK: - start()

    func testStartRegistersFlagMonitorForModifierKey() {
        let config = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        let monitor = makeMonitor(configuration: config)

        monitor.start()

        XCTAssertEqual(addedGlobalEvents.count, 1)
        XCTAssertEqual(addedGlobalEvents.first?.0, .flagsChanged)
        XCTAssertEqual(addedLocalEvents.count, 1)
        XCTAssertEqual(addedLocalEvents.first?.0, .flagsChanged)
    }

    // MARK: - Transitions

    func testKeyDownInvokesHandlerOnlyOnceUntilReleased() {
        let expectationDown = expectation(description: "keyDown")
        expectationDown.expectedFulfillmentCount = 2

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {
                expectationDown.fulfill()
            }
        )

        monitor.processTransition(isKeyDownEvent: true)  // first press
        monitor.processTransition(isKeyDownEvent: true)  // repeat press ignored
        monitor.processTransition(isKeyDownEvent: false) // release
        monitor.processTransition(isKeyDownEvent: true)  // second press

        wait(for: [expectationDown], timeout: 1.0)
    }

    func testKeyUpInvokesHandlerWhenConfigured() {
        let expectationUp = expectation(description: "keyUp")

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: {
                expectationUp.fulfill()
            }
        )

        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)

        wait(for: [expectationUp], timeout: 1.0)
    }

    func testKeyUpHandlerNotCalledWhenNeverPressed() {
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: {
                XCTFail("Key up should not fire without prior key down")
            }
        )

        monitor.processTransition(isKeyDownEvent: false)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    func testDoubleTapModeDoesNotInvokeHandlerOnSinglePress() {
        let expectationDown = expectation(description: "keyDown")
        expectationDown.isInverted = true

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .doubleTapToggle),
            keyDownHandler: {
                expectationDown.fulfill()
            }
        )

        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)

        wait(for: [expectationDown], timeout: 0.1)
    }

    func testDoubleTapModeInvokesHandlerOnSecondPressWithinInterval() {
        var currentTime = Date(timeIntervalSinceReferenceDate: 100)
        let expectationDown = expectation(description: "keyDown")

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .doubleTapToggle),
            keyDownHandler: {
                expectationDown.fulfill()
            },
            now: { currentTime },
            doubleTapInterval: 0.35
        )

        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)
        currentTime = currentTime.addingTimeInterval(0.2)
        monitor.processTransition(isKeyDownEvent: true)

        wait(for: [expectationDown], timeout: 1.0)
    }

    func testDoubleTapModeIgnoresSecondPressAfterInterval() {
        var currentTime = Date(timeIntervalSinceReferenceDate: 100)
        let expectationDown = expectation(description: "keyDown")
        expectationDown.isInverted = true

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .doubleTapToggle),
            keyDownHandler: {
                expectationDown.fulfill()
            },
            now: { currentTime },
            doubleTapInterval: 0.35
        )

        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)
        currentTime = currentTime.addingTimeInterval(0.5)
        monitor.processTransition(isKeyDownEvent: true)

        wait(for: [expectationDown], timeout: 0.1)
    }

    func testDoubleTapModeHoldStartsAndReleaseStops() {
        var pendingWork: [() -> Void] = []
        let holdStarted = expectation(description: "holdStart")
        let holdEnded = expectation(description: "holdEnd")
        let toggled = expectation(description: "toggle")
        toggled.isInverted = true

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .doubleTapToggle),
            keyDownHandler: { toggled.fulfill() },
            holdStartHandler: { holdStarted.fulfill() },
            holdEndHandler: { holdEnded.fulfill() },
            scheduleAfter: { _, work in pendingWork.append(work) }
        )

        monitor.processTransition(isKeyDownEvent: true)
        pendingWork.forEach { $0() }
        wait(for: [holdStarted], timeout: 1.0)

        monitor.processTransition(isKeyDownEvent: false)
        wait(for: [holdEnded], timeout: 1.0)
        wait(for: [toggled], timeout: 0.1)
    }

    func testDoubleTapModeQuickTapDoesNotStartHold() {
        var pendingWork: [() -> Void] = []
        let holdStarted = expectation(description: "holdStart")
        holdStarted.isInverted = true

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .doubleTapToggle),
            holdStartHandler: { holdStarted.fulfill() },
            scheduleAfter: { _, work in pendingWork.append(work) }
        )

        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)
        pendingWork.forEach { $0() }

        wait(for: [holdStarted], timeout: 0.1)
    }

    func testDoubleTapModeReleasedHoldDoesNotCountAsFirstTap() {
        var currentTime = Date(timeIntervalSinceReferenceDate: 100)
        var pendingWork: [() -> Void] = []
        let holdStarted = expectation(description: "holdStart")
        let toggled = expectation(description: "toggle")
        toggled.isInverted = true

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .doubleTapToggle),
            keyDownHandler: { toggled.fulfill() },
            holdStartHandler: { holdStarted.fulfill() },
            holdEndHandler: {},
            now: { currentTime },
            scheduleAfter: { _, work in pendingWork.append(work) }
        )

        monitor.processTransition(isKeyDownEvent: true)
        pendingWork.removeFirst()()
        wait(for: [holdStarted], timeout: 1.0)
        monitor.processTransition(isKeyDownEvent: false)

        currentTime = currentTime.addingTimeInterval(0.1)
        monitor.processTransition(isKeyDownEvent: true)

        wait(for: [toggled], timeout: 0.1)
    }

    // MARK: - stop()

    func testStopRemovesRegisteredMonitors() {
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        )

        monitor.start()
        monitor.stop()

        XCTAssertEqual(removedEvents.count, 2)
    }
}
