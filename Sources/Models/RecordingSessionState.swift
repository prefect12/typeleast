import Foundation

/// Shared by shortcuts and the recording view; invalidates work after cancellation.
internal struct RecordingSessionState {
    enum Phase { case idle, recording, processing }
    private(set) var phase: Phase = .idle
    private(set) var id = UUID()

    mutating func beginRecording() -> Bool {
        guard phase == .idle else { return false }
        id = UUID()
        phase = .recording
        return true
    }

    mutating func beginProcessing() -> UUID? {
        guard phase != .processing else { return nil }
        if phase == .idle { id = UUID() }
        phase = .processing
        return id
    }

    func isCurrent(_ session: UUID) -> Bool { id == session && phase != .idle }

    mutating func finish(_ session: UUID) {
        guard isCurrent(session) else { return }
        phase = .idle
    }

    mutating func cancel() {
        id = UUID()
        phase = .idle
    }
}
