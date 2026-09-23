import Foundation

/// Builds the prompt for the contextual transcription session from the user's own dictation
/// history: the English terms they mix into Chinese sentences, plus their last few sentences.
///
/// Measured on real recordings, this context fixed misheard jargon such as "campaign" (heard as
/// 看片) that neither the realtime model nor the same model without context got right.
@MainActor
internal final class DictationContextProvider {
    static let shared = DictationContextProvider()

    static let termsRefreshInterval: TimeInterval = 60 * 60
    static let historyLimit = 400
    static let recentTranscriptLimit = 3
    static let recentCharacterLimit = 300

    private(set) var terms: [String] = []
    private(set) var recentTranscripts: [String] = []
    private var termsRefreshedAt: Date?

    var prompt: String? { Self.prompt(terms: terms, recentTranscripts: recentTranscripts) }

    func refreshIfNeeded(dataManager: DataManagerProtocol = DataManager.shared, now: Date = Date()) async {
        if let termsRefreshedAt, now.timeIntervalSince(termsRefreshedAt) < Self.termsRefreshInterval { return }
        termsRefreshedAt = now
        guard let records = try? await dataManager.fetchRecords(
            matching: "",
            limit: Self.historyLimit,
            offset: nil
        ) else { return }
        let newestFirst = records.map(\.text)
        terms = Self.frequentMixedInTerms(in: newestFirst)
        if recentTranscripts.isEmpty {
            recentTranscripts = Array(newestFirst.prefix(Self.recentTranscriptLimit).reversed())
        }
    }

    func recordTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentTranscripts.append(trimmed)
        if recentTranscripts.count > Self.recentTranscriptLimit {
            recentTranscripts.removeFirst(recentTranscripts.count - Self.recentTranscriptLimit)
        }
    }

    /// English words that show up inside Chinese sentences are the speaker's jargon; plain English
    /// dictation is skipped so everyday words don't crowd the list.
    nonisolated static func frequentMixedInTerms(
        in transcripts: [String],
        limit: Int = 25,
        minimumCount: Int = 2
    ) -> [String] {
        var counts: [String: Int] = [:]
        var spellings: [String: [String: Int]] = [:]
        for transcript in transcripts where hanCharacterCount(in: transcript) >= 4 {
            for word in latinWords(in: transcript) {
                let key = word.lowercased()
                counts[key, default: 0] += 1
                spellings[key, default: [:]][word, default: 0] += 1
            }
        }
        return counts
            .filter { $0.value >= minimumCount }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .compactMap { entry in
                spellings[entry.key]?.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
            }
    }

    nonisolated static func prompt(terms: [String], recentTranscripts: [String]) -> String? {
        let recent = recentTranscripts
            .map { $0.replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: " ")
            .suffix(recentCharacterLimit)
        guard !terms.isEmpty || !recent.isEmpty else { return nil }

        var prompt = "说话人主要讲中文，常夹杂英文技术词，英文词请保留英文原样。"
        if !terms.isEmpty { prompt += "说话人常用的词：\(terms.joined(separator: ", "))。" }
        if !recent.isEmpty { prompt += "说话人之前刚说过：\(recent)" }
        return prompt
    }

    private nonisolated static func hanCharacterCount(in text: String) -> Int {
        text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
    }

    private nonisolated static func latinWords(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in text {
            let isWordCharacter = character.isASCII && (character.isLetter || character.isNumber || "+#-".contains(character))
            if isWordCharacter, !(current.isEmpty && !character.isLetter) {
                current.append(character)
            } else {
                if current.count >= 2 { words.append(current) }
                current = ""
            }
        }
        if current.count >= 2 { words.append(current) }
        return words
    }
}
