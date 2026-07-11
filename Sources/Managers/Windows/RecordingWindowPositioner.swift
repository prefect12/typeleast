import AppKit
import ApplicationServices

internal enum RecordingWindowPositioner {
    private static var hasRequestedAccessibilityPermission = false

    static func position(_ window: NSWindow) {
        requestAccessibilityPermissionIfNeeded()

        let windowSize = window.frame.size
        let focusContext = preferredAccessibilityContext()
        let visibleFrame = screenForCurrentContext(
            caretRect: focusContext.caretRect,
            focusedElementRect: focusContext.focusedElementRect,
            focusedWindowRect: focusContext.focusedWindowRect
        )?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let preferredOrigin = preferredOrigin(
            windowSize: windowSize,
            caretRect: focusContext.caretRect,
            focusedElementRect: focusContext.focusedElementRect,
            focusedWindowRect: focusContext.focusedWindowRect,
            visibleFrame: visibleFrame
        )
        window.setFrameOrigin(preferredOrigin)
    }

    private static func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted(),
              !hasRequestedAccessibilityPermission,
              NSClassFromString("XCTestCase") == nil else {
            return
        }

        hasRequestedAccessibilityPermission = true
        let checkOptionPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptionPrompt: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    private static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    static func preferredOrigin(
        windowSize: CGSize,
        caretRect: CGRect?,
        focusedElementRect: CGRect? = nil,
        focusedWindowRect: CGRect? = nil,
        visibleFrame: CGRect
    ) -> CGPoint {
        let padding = LayoutMetrics.RecordingWindow.edgePadding

        let rawOrigin: CGPoint
        if let caretRect = validRect(caretRect) {
            rawOrigin = originNearCaret(caretRect, windowSize: windowSize, visibleFrame: visibleFrame)
        } else if let focusedElementRect = validTextElementRect(focusedElementRect, visibleFrame: visibleFrame) {
            rawOrigin = originNearFocusedElement(focusedElementRect, windowSize: windowSize, visibleFrame: visibleFrame)
        } else if let focusedWindowRect = validRect(focusedWindowRect) {
            rawOrigin = originInLowerWindowArea(focusedWindowRect, windowSize: windowSize, visibleFrame: visibleFrame)
        } else {
            rawOrigin = originInLowerWindowArea(visibleFrame, windowSize: windowSize, visibleFrame: visibleFrame)
        }

        return clampedOrigin(rawOrigin, windowSize: windowSize, visibleFrame: visibleFrame, padding: padding)
    }

    private static func originNearCaret(
        _ caretRect: CGRect,
        windowSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let gap = LayoutMetrics.RecordingWindow.caretGap
        let padding = LayoutMetrics.RecordingWindow.edgePadding
        let below = caretRect.minY - gap - windowSize.height
        let above = caretRect.maxY + gap
        let y = below >= visibleFrame.minY + padding ? below : above
        return CGPoint(x: caretRect.minX, y: y)
    }

    private static func originNearFocusedElement(
        _ elementRect: CGRect,
        windowSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let gap = LayoutMetrics.RecordingWindow.caretGap
        let padding = LayoutMetrics.RecordingWindow.edgePadding
        let above = elementRect.maxY + gap
        let below = elementRect.minY - gap - windowSize.height
        let y = above + windowSize.height <= visibleFrame.maxY - padding ? above : below
        return CGPoint(x: elementRect.minX, y: y)
    }

    private static func originInLowerWindowArea(
        _ windowRect: CGRect,
        windowSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let clampedWindow = windowRect.intersection(visibleFrame)
        let baseRect = clampedWindow.isNull || clampedWindow.isEmpty ? visibleFrame : clampedWindow
        let lowerInputBandOffset = min(max(baseRect.height * 0.08, 64), 120)
        return CGPoint(
            x: baseRect.midX - windowSize.width / 2,
            y: baseRect.minY + lowerInputBandOffset
        )
    }

    private static func clampedOrigin(
        _ origin: CGPoint,
        windowSize: CGSize,
        visibleFrame: CGRect,
        padding: CGFloat
    ) -> CGPoint {
        let minX = visibleFrame.minX + padding
        let maxX = visibleFrame.maxX - windowSize.width - padding
        let minY = visibleFrame.minY + padding
        let maxY = visibleFrame.maxY - windowSize.height - padding

        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private static func validRect(_ rect: CGRect?) -> CGRect? {
        guard let rect,
              !rect.isNull,
              !rect.isEmpty,
              rect.minX.isFinite,
              rect.minY.isFinite,
              rect.width.isFinite,
              rect.height.isFinite else {
            return nil
        }
        return rect
    }

    private static func validTextElementRect(_ rect: CGRect?, visibleFrame: CGRect) -> CGRect? {
        guard let rect = validRect(rect) else { return nil }
        let coversMostVisibleWidth = rect.width >= visibleFrame.width * 0.85
        let coversMostVisibleHeight = rect.height >= visibleFrame.height * 0.65
        return coversMostVisibleWidth && coversMostVisibleHeight ? nil : rect
    }

    private static func preferredAccessibilityContext() -> (caretRect: CGRect?, focusedElementRect: CGRect?, focusedWindowRect: CGRect?) {
        if let targetAppContext = focusedAccessibilityContext(for: WindowController.storedTargetApp),
           targetAppContext.caretRect != nil ||
            targetAppContext.focusedElementRect != nil ||
            targetAppContext.focusedWindowRect != nil {
            return targetAppContext
        }

        return focusedAccessibilityContext()
    }

    private static func focusedAccessibilityContext() -> (caretRect: CGRect?, focusedElementRect: CGRect?, focusedWindowRect: CGRect?) {
        guard AXIsProcessTrusted() else { return (nil, nil, nil) }

        let systemWideElement = AXUIElementCreateSystemWide()
        return focusedAccessibilityContext(from: systemWideElement)
    }

    private static func focusedAccessibilityContext(for app: NSRunningApplication?) -> (caretRect: CGRect?, focusedElementRect: CGRect?, focusedWindowRect: CGRect?)? {
        guard AXIsProcessTrusted(),
              let app,
              !app.isTerminated,
              app.processIdentifier > 0,
              !AppIdentity.isTypeleastBundleIdentifier(app.bundleIdentifier) else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return focusedAccessibilityContext(from: appElement)
    }

    private static func focusedAccessibilityContext(from rootElement: AXUIElement) -> (caretRect: CGRect?, focusedElementRect: CGRect?, focusedWindowRect: CGRect?) {
        let focusedWindowRect = focusedWindowFrame(from: rootElement)
        var focusedElementValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            rootElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        ) == .success,
              let focusedElement = focusedElementValue else {
            return (nil, nil, focusedWindowRect)
        }

        let element = focusedElement as! AXUIElement
        let focusedElementRect = focusedElementFrame(from: element)

        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
              let selectedRange = selectedRangeValue else {
            return (nil, focusedElementRect, focusedWindowRect)
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange,
            &boundsValue
        ) == .success,
              let boundsValue,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return (nil, focusedElementRect, focusedWindowRect)
        }

        let axBounds = boundsValue as! AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(axBounds, .cgRect, &rect) else { return (nil, focusedElementRect, focusedWindowRect) }
        return (convertAccessibilityRectToCocoa(rect), focusedElementRect, focusedWindowRect)
    }

    private static func focusedWindowFrame(from systemWideElement: AXUIElement) -> CGRect? {
        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
              let focusedWindowValue else {
            return nil
        }

        return focusedElementFrame(from: focusedWindowValue as! AXUIElement)
    }

    private static func focusedElementFrame(from element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        let rect = CGRect(origin: position, size: size)
        return convertAccessibilityRectToCocoa(rect)
    }

    private static func convertAccessibilityRectToCocoa(_ rect: CGRect) -> CGRect {
        guard let screen = screenForAccessibilityRect(rect) ?? NSScreen.main else { return rect }
        let cocoaY = screen.frame.maxY - rect.maxY + screen.frame.minY
        return CGRect(x: rect.minX, y: cocoaY, width: rect.width, height: rect.height)
    }

    private static func screenForCurrentContext(
        caretRect: CGRect?,
        focusedElementRect: CGRect?,
        focusedWindowRect: CGRect?
    ) -> NSScreen? {
        if let caretRect {
            return NSScreen.screens.first { $0.frame.intersects(caretRect) }
        }

        if let focusedElementRect {
            return NSScreen.screens.first { $0.frame.intersects(focusedElementRect) }
        }

        if let focusedWindowRect {
            return NSScreen.screens.first { $0.frame.intersects(focusedWindowRect) }
        }

        return NSScreen.main
    }

    private static func screenForAccessibilityRect(_ rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            rect.minX >= screen.frame.minX && rect.minX <= screen.frame.maxX
        }
    }
}
