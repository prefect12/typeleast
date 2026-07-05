import Foundation
import SwiftData

// SwiftData @Model classes handle Sendable conformance automatically:
// 1. SwiftData manages thread safety internally through its model context
// 2. All access to @Model instances should go through the model context
// 3. The framework ensures proper synchronization across threads
@Model
internal final class TranscriptionRecord {
    @Attribute(.unique) var id: UUID
    var text: String
    var date: Date
    var provider: String // TranscriptionProvider.rawValue
    var duration: TimeInterval?
    var modelUsed: String?
    var wordCount: Int = 0
    var characterCount: Int = 0
    
    // Source app tracking
    var sourceAppBundleId: String?
    var sourceAppName: String?
    var sourceAppIconData: Data?

    // Transcription processing time (how long the ASR + correction took)
    var transcriptionTime: TimeInterval?
    var modelReadyTime: TimeInterval?
    var asrTime: TimeInterval?
    var correctionTime: TimeInterval?
    var clipboardTime: TimeInterval?
    var pasteTime: TimeInterval?
    var endToEndTime: TimeInterval?

    init(
        text: String,
        provider: TranscriptionProvider,
        duration: TimeInterval? = nil,
        modelUsed: String? = nil,
        wordCount: Int = 0,
        characterCount: Int = 0,
        sourceAppBundleId: String? = nil,
        sourceAppName: String? = nil,
        sourceAppIconData: Data? = nil,
        transcriptionTime: TimeInterval? = nil,
        modelReadyTime: TimeInterval? = nil,
        asrTime: TimeInterval? = nil,
        correctionTime: TimeInterval? = nil,
        clipboardTime: TimeInterval? = nil,
        pasteTime: TimeInterval? = nil,
        endToEndTime: TimeInterval? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.provider = provider.rawValue
        self.duration = duration
        self.modelUsed = modelUsed
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.sourceAppBundleId = sourceAppBundleId
        self.sourceAppName = sourceAppName
        self.sourceAppIconData = sourceAppIconData
        self.transcriptionTime = transcriptionTime
        self.modelReadyTime = modelReadyTime
        self.asrTime = asrTime
        self.correctionTime = correctionTime
        self.clipboardTime = clipboardTime
        self.pasteTime = pasteTime
        self.endToEndTime = endToEndTime
    }
}

// MARK: - Computed Properties
internal extension TranscriptionRecord {
    /// Returns the transcription provider as an enum
    var transcriptionProvider: TranscriptionProvider? {
        return TranscriptionProvider(rawValue: provider)
    }
    
    /// Returns the WhisperModel if applicable (for local transcriptions)
    var whisperModel: WhisperModel? {
        guard let modelUsed = modelUsed else { return nil }
        return WhisperModel(rawValue: modelUsed)
    }
    
    /// Returns a formatted date string for display
    var formattedDate: String {
        return Self.displayDateFormatter.string(from: date)
    }
    
    /// Returns a formatted duration string for display
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        
        if duration < 60 {
            return duration.formatted(.number.precision(.fractionLength(1))) + "s"
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
    
    /// Returns a truncated version of the text for display in lists
    var preview: String {
        let maxLength = 100
        if text.count <= maxLength {
            return text
        }
        let truncatedText = String(text.prefix(maxLength))
        return truncatedText + "..."
    }

    var formattedTranscriptionTime: String? {
        guard let t = transcriptionTime else { return nil }
        if t < 1 {
            return String(format: "%.0fms", t * 1000)
        } else if t < 60 {
            return String(format: "%.1fs", t)
        } else {
            let minutes = Int(t / 60)
            let seconds = Int(t.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }

    var hasDetailedTiming: Bool {
        [modelReadyTime, asrTime, correctionTime, clipboardTime, pasteTime, endToEndTime]
            .contains { ($0 ?? 0) > 0 }
    }

    var wordsPerMinute: Double? {
        guard let duration = duration, duration > 0 else { return nil }
        guard wordCount > 0 else { return nil }
        return Double(wordCount) / (duration / 60.0)
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Search and Filtering
internal extension TranscriptionRecord {
    /// Returns true if the record matches the search query
    func matches(searchQuery: String) -> Bool {
        guard !searchQuery.isEmpty else { return true }
        
        let lowercaseQuery = searchQuery.lowercased()
        return text.lowercased().contains(lowercaseQuery) ||
               provider.lowercased().contains(lowercaseQuery) ||
               (modelUsed?.lowercased().contains(lowercaseQuery) ?? false)
    }
}
