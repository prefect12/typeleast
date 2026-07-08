import AppKit
import SwiftUI

internal class ChromelessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

internal struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var appearanceName: NSAppearance.Name?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.state = .active
        effectView.material = material
        effectView.blendingMode = blendingMode
        if let appearanceName {
            effectView.appearance = NSAppearance(named: appearanceName)
        }
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = LayoutMetrics.RecordingWindow.cornerRadius
        effectView.layer?.masksToBounds = true
        return effectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = appearanceName.flatMap { NSAppearance(named: $0) }
    }
}

internal class RecordingWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
