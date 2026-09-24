import Foundation

/// Chat apps (WeChat, Feishu, …) read more naturally without sentence-ending periods.
/// Question and exclamation marks are kept; ellipses and decimals are left untouched.
internal enum ChatPunctuationFormatter {
    static let chatCategoryId = "chat"

    static func removingSentencePeriods(from text: String) -> String {
        text
            .components(separatedBy: "\n")
            .map(formatLine)
            .joined(separator: "\n")
    }

    private static func formatLine(_ line: String) -> String {
        // A full-width period between sentences becomes a space, e.g. "好的。明天见。" → "好的 明天见".
        var result = line
            .components(separatedBy: "。")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }

        while let last = result.last, isTrailingPeriod(last, in: result) {
            result.removeLast()
            result = String(result.reversed().drop(while: { $0 == " " }).reversed())
        }
        return result
    }

    private static func isTrailingPeriod(_ character: Character, in text: String) -> Bool {
        switch character {
        case "。", "．":
            return true
        case ".":
            // Keep "..." and similar ellipses.
            return !text.dropLast().hasSuffix(".")
        default:
            return false
        }
    }
}
