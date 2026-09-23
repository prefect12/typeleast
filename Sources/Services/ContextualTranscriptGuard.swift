import Foundation

/// Rejects contextual transcripts that were likely invented from the prompt rather than heard.
///
/// Prompted Whisper-family models echo their prompt when the audio holds little or no speech:
/// a 0.6s silent recording came back as a sentence from the "recently said" context.
internal enum ContextualTranscriptGuard {
    enum Rejection: String, Equatable {
        case tooLongForAudio = "too_long_for_audio"
        case echoesRecentSpeech = "echoes_recent_speech"
    }

    /// Fast Mandarin runs about 5-6 characters per second; beyond this the text wasn't all spoken.
    static let maximumUnitsPerSecond = 8.0
    static let echoSimilarityThreshold = 0.8
    private static let minimumComparableLength = 4

    static func rejection(
        for text: String,
        audioSeconds: Double,
        recentTranscripts: [String]
    ) -> Rejection? {
        let units = spokenUnitCount(text)
        guard units > 0 else { return nil }
        if Double(units) > max(audioSeconds, 0.25) * maximumUnitsPerSecond {
            return .tooLongForAudio
        }

        let candidate = Array(LiveDictationCoordinator.comparableText(text))
        guard candidate.count >= minimumComparableLength else { return nil }
        for recent in recentTranscripts {
            let previous = Array(LiveDictationCoordinator.comparableText(recent))
            if String(previous).contains(String(candidate))
                || similarity(candidate, previous) >= echoSimilarityThreshold {
                return .echoesRecentSpeech
            }
        }
        return nil
    }

    /// Han characters plus runs of Latin letters or digits, roughly one unit per spoken syllable/word.
    static func spokenUnitCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if (0x3400...0x9FFF).contains(scalar.value) {
                count += 1
                inWord = false
            } else if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if !inWord { count += 1 }
                inWord = true
            } else {
                inWord = false
            }
        }
        return count
    }

    /// 1 minus normalized edit distance.
    static func similarity(_ lhs: [Character], _ rhs: [Character]) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 1 }
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: rhs.count)
            for (j, right) in rhs.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (left == right ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[rhs.count]) / Double(max(lhs.count, rhs.count))
    }
}
