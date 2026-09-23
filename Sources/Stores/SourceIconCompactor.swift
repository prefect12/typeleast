import AppKit
import CryptoKit
import Foundation
import SwiftData
import os.log

/// Shrinks source-app icons that earlier versions stored at full 1024px (~600KB per record).
/// Those blobs made every history fetch — including the one at launch — read hundreds of MB.
internal enum SourceIconCompactor {
    static let completedDefaultsKey = "sourceIconCompaction.v1.completed"
    static let oversizedIconBytes = 32 * 1024

    /// Runs once per install, off the main thread. Returns the number of records rewritten.
    @discardableResult
    static func compactIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) async -> Int {
        guard !defaults.bool(forKey: completedDefaultsKey) else { return 0 }
        let result = await Task.detached(priority: .utility) { () -> Result<Int, Error> in
            Result { try compact(container: container) }
        }.value

        switch result {
        case .success(let count):
            defaults.set(true, forKey: completedDefaultsKey)
            Logger.dataManager.info("Compacted \(count) source app icons")
            return count
        case .failure(let error):
            // Left unmarked so the next launch retries; already-compacted records are skipped.
            Logger.dataManager.error("Source icon compaction failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    static func compact(container: ModelContainer, batchSize: Int = 50) throws -> Int {
        var resizedByDigest: [SHA256.Digest: Data?] = [:]
        var offset = 0
        var compacted = 0

        while true {
            // A fresh context per batch keeps the multi-hundred-MB blobs from accumulating in memory.
            let context = ModelContext(container)
            context.autosaveEnabled = false
            var descriptor = FetchDescriptor<TranscriptionRecord>(sortBy: [SortDescriptor(\.date)])
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try context.fetch(descriptor)
            guard !batch.isEmpty else { break }

            for record in batch {
                guard let iconData = record.sourceAppIconData, iconData.count > oversizedIconBytes else { continue }
                let digest = SHA256.hash(data: iconData)
                let resized = resizedByDigest[digest] ?? SourceAppInfo.pngData(from: NSImage(data: iconData))
                resizedByDigest[digest] = resized
                record.sourceAppIconData = resized
                compacted += 1
            }
            if context.hasChanges { try context.save() }
            offset += batch.count
        }
        return compacted
    }
}
