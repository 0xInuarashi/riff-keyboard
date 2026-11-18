import Foundation

enum PersonalizationFormatting {
    private static let surroundingPunctuation: Set<Character> = Set(".,!?;:…—“”\"«»‘¿¡。！？、，；：؟،؛")

    static func preservesWords(in original: String, formatted: String) -> Bool {
        let source = tokens(in: original)
        let edited = tokens(in: formatted)
        guard source.count == edited.count else { return false }

        return zip(source, edited).allSatisfy { before, after in
            // Keep links, handles, numbers with internal punctuation, and other
            // symbols literal. Casing and apostrophe edits apply to words only.
            guard isWord(before), isWord(after) else { return before == after }
            let normalizedBefore = normalizedWord(before)
            let normalizedAfter = normalizedWord(after)
            if normalizedBefore == normalizedAfter { return true }
            return !normalizedBefore.contains("'") &&
                normalizedAfter.filter { $0 == "'" }.count == 1 &&
                normalizedAfter.filter { $0 != "'" } == normalizedBefore
        }
    }

    private static func tokens(in text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace).compactMap { token in
            // A period or comma before a digit can be a decimal separator.
            let end = token.lastIndex { !surroundingPunctuation.contains($0) }
            guard let end else { return nil }
            var start = token.startIndex
            while start < end, surroundingPunctuation.contains(token[start]) {
                let next = token.index(after: start)
                if ".,".contains(token[start]), token[next].isNumber { break }
                start = next
            }
            return token[start...end]
        }
    }

    private static func isWord(_ token: Substring) -> Bool {
        token.first?.isLetter == true && token.last?.isLetter == true &&
            token.allSatisfy { $0.isLetter || $0 == "'" || $0 == "’" }
    }

    private static func normalizedWord(_ token: Substring) -> String {
        token.lowercased().replacingOccurrences(of: "’", with: "'")
    }
}
