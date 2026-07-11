import Foundation

internal actor RealtimeDiagnostics {
    static let shared = RealtimeDiagnostics()

    func record(_ event: String, fields: [String: String] = [:]) {
        guard AppIdentity.isStreamingTest,
              let directory = try? AppIdentity.applicationSupportDirectory() else { return }

        var payload = fields
        payload["event"] = event
        payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
        payload["bundle_id"] = AppIdentity.bundleIdentifier
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }

        let url = directory.appendingPathComponent("realtime-diagnostics.jsonl")
        var line = data
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            return
        }
    }
}
