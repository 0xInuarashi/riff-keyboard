import Foundation

enum PersonalizationFormatting {
    enum StatementStyle: String, Codable, Equatable, Sendable {
        case open, conversational, enthusiastic, formal, relaxed
    }

    private static let sentenceMarks: Set<Character> = Set(".!?…。！？؟")
    private static let questionMarks: Set<Character> = Set("?？؟")
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

    /// Keep existing questions at the same word boundaries. A new question mark
    /// is allowed only where the transcript did not already end a statement.
    static func preservesQuestions(in original: String, formatted: String) -> Bool {
        let source = endingMarks(in: original)
        let output = endingMarks(in: formatted)
        return source.indices.allSatisfy { i in
            guard let before = source[i] else { return true }
            let after = i < output.count ? output[i] : nil
            return questionMarks.contains(before) == (after.map(questionMarks.contains) ?? false)
        }
    }

    private static func endingMarks(in text: String) -> [Character?] {
        let words = tokens(in: text)
        return words.indices.map { i in
            let next = i + 1 < words.count ? words[i + 1].startIndex : text.endIndex
            let gap = text[words[i].endIndex..<next]
            return gap.first(where: questionMarks.contains) ?? gap.first(where: sentenceMarks.contains)
        }
    }

    /// Apply the preset to ordinary words and their adjacent punctuation. Whitespace,
    /// URLs, handles, numbers and punctuation inside tokens stay as the model left them.
    static func apply(to text: String, source: String, prompt: SmartModePrompt, globalTone: PersonalizationProfile.Tone? = nil) -> String {
        let style = prompt.personalizationStatementStyle
        guard style != nil || prompt.lowercasesWords == true else { return text }
        let words = tokens(in: text)
        let originalWords = tokens(in: source)
        var result = ""
        var remainingStart = text.startIndex
        for (i, word) in words.enumerated() where isWord(word) {
            result += text[remainingStart..<word.startIndex]
            if prompt.lowercasesWords == true || globalTone == .casual {
                let lowercase = word.lowercased()
                result += globalTone == .superCasual
                    ? lowercase.filter { $0 != "'" && $0 != "’" }
                    : lowercase
            } else if i < originalWords.count {
                result += casingWithoutAddedShouting(word, original: originalWords[i])
            } else {
                result += word
            }

            let next = i + 1 < words.count ? words[i + 1].startIndex : text.endIndex
            let marks = text[word.endIndex..<next].prefix(while: sentenceMarks.contains)
            let tail = text[marks.endIndex..<next]
            let endsLine = i == words.count - 1 || tail.contains(where: \.isNewline)
            let canAddMark = endsLine && tail.allSatisfy(\.isWhitespace) &&
                word.contains { $0.isUppercase || $0.isLowercase }
            if (globalTone == .superCasual || globalTone == .casual), !marks.contains(where: questionMarks.contains) {
                result += marks.filter { !"!！.。…".contains($0) }
            } else {
                result += statementMarks(marks, style: style, endsLine: endsLine, canAddMark: canAddMark)
            }
            remainingStart = marks.endIndex
        }
        result += text[remainingStart...]
        return result
    }

    private static func casingWithoutAddedShouting(_ word: Substring, original: Substring) -> String {
        guard word.filter(\.isUppercase).count > 1,
              !word.contains(where: \.isLowercase),
              original.contains(where: \.isLowercase),
              word.lowercased().filter(\.isLetter) == original.lowercased().filter(\.isLetter),
              word.filter(\.isLetter).count == original.filter(\.isLetter).count else {
            return String(word)
        }
        // Restore the original letter case and keep the model's apostrophe edits.
        var letters = original.filter(\.isLetter).makeIterator()
        return String(word.map { $0.isLetter ? (letters.next() ?? $0) : $0 })
    }

    private static func statementMarks(
        _ marks: Substring, style: StatementStyle?, endsLine: Bool, canAddMark: Bool
    ) -> String {
        if marks.contains(where: questionMarks.contains) { return String(marks) }
        switch style {
        case .open where endsLine:
            return String(marks.drop(while: { ".…。".contains($0) }))
        case .enthusiastic where endsLine && (marks == "." || marks == "..." || marks == "…"):
            return "!"
        case .enthusiastic where marks.isEmpty && canAddMark:
            return "!"
        case .formal where !marks.isEmpty && marks.allSatisfy({ $0 == "!" }):
            return "."
        case .formal where marks.isEmpty && canAddMark:
            return "."
        case .relaxed where !marks.isEmpty && marks.allSatisfy({ $0 == "!" }):
            return endsLine ? "." : "…"
        default:
            return String(marks)
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
