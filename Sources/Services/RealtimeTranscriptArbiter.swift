import Foundation

/// Picks between the realtime transcript and the contextual (more accurate) one.
///
/// The contextual result wins whenever it is available in time: immediately if it lands first,
/// or within `grace` after the realtime result. Each model occasionally stalls for 10s+ while the
/// other does not, so this also trims tail latency: whichever usable result comes first bounds it.
@MainActor
internal final class RealtimeTranscriptArbiter {
    enum Source: String, Equatable, Sendable {
        case contextual
        case live
    }

    struct Decision: Equatable {
        var text: String?
        var source: Source?
    }

    static func decide(
        live: Task<String?, Never>,
        contextual: Task<String?, Never>?,
        grace: Duration
    ) async -> Decision {
        guard let contextual else {
            let text = await live.value
            return Decision(text: text, source: text == nil ? nil : .live)
        }
        let arbiter = RealtimeTranscriptArbiter(grace: grace)
        return await withCheckedContinuation { continuation in
            arbiter.continuation = continuation
            Task { @MainActor in arbiter.liveFinished(await live.value) }
            Task { @MainActor in arbiter.contextualFinished(await contextual.value) }
        }
    }

    private let grace: Duration
    private var continuation: CheckedContinuation<Decision, Never>?
    // Outer optional: still pending. Inner optional: finished without a transcript.
    private var liveResult: String??
    private var contextualResult: String??
    private var graceTask: Task<Void, Never>?

    private init(grace: Duration) {
        self.grace = grace
    }

    private func liveFinished(_ text: String?) {
        liveResult = .some(text)
        evaluate()
    }

    private func contextualFinished(_ text: String?) {
        contextualResult = .some(text)
        evaluate()
    }

    private func evaluate() {
        if case .some(.some(let text)) = contextualResult {
            resolve(Decision(text: text, source: .contextual))
            return
        }
        guard let liveResult else { return }
        guard let liveText = liveResult else {
            if contextualResult != nil { resolve(Decision(text: nil, source: nil)) }
            return
        }
        if contextualResult != nil {
            resolve(Decision(text: liveText, source: .live))
            return
        }
        guard graceTask == nil else { return }
        let grace = grace
        graceTask = Task { @MainActor in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled else { return }
            self.resolve(Decision(text: liveText, source: .live))
        }
    }

    private func resolve(_ decision: Decision) {
        graceTask?.cancel()
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: decision)
    }
}
