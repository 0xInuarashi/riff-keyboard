import Foundation

/// Saved tone and optional writing samples for the Personalization Smart Mode.
public struct PersonalizationProfile: Codable, Equatable, Sendable {
    public enum Tone: String, CaseIterable, Codable, Sendable {
        case superCasual, casual, standard, excited, formal, relaxed, custom

        fileprivate var instruction: String {
            switch self {
            case .superCasual:
                return "Lowercase ordinary words. Use light punctuation and omit final periods in statements. Keep question marks and apostrophes."
            case .casual:
                return "Use ordinary capitalization and conversational commas. Use one exclamation mark only when the original sounds enthusiastic."
            case .standard:
                return "Keep the original transcript."
            case .excited:
                return "Use ordinary capitalization. End an enthusiastic statement with one exclamation mark. Keep questions as questions."
            case .formal:
                return "Use standard sentence capitalization, commas, and periods. Avoid exclamation marks and ellipses."
            case .relaxed:
                return "Use ordinary capitalization and calm punctuation. Use a comma or an ellipsis for a natural pause. Avoid exclamation marks."
            case .custom:
                return "Use the capitalization and punctuation style of the writing samples."
            }
        }
    }

    public struct Substitution: Codable, Equatable, Hashable, Sendable {
        public let spoken: String
        public let written: String

        public init(spoken: String, written: String) {
            self.spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
            self.written = written.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        fileprivate var isValid: Bool {
            [spoken, written].allSatisfy {
                !$0.isEmpty && $0.count <= 64 &&
                    $0.contains(where: \.isLetter) &&
                    $0.allSatisfy { $0.isLetter || " '-’".contains($0) }
            } && spoken.caseInsensitiveCompare(written) != .orderedSame
        }
    }

    public static let maximumSubstitutions = 24
    private static let protectedText = #"(?i)(?:[a-z][a-z0-9+.-]*://|www\.)[^\s]+|[^\s@]+@[^\s@]+\.[^\s@]+|(?:[\p{L}\p{N}-]+\.)+[a-z]{2,}(?![\p{L}\p{N}])|(?<![\p{L}\p{N}])[@#][\p{L}\p{N}_]+"#
    public static let maximumSampleBytes = 12_000
    public let tone: Tone
    public let samples: String
    private let vocabulary: [Substitution]?
    public var substitutions: [Substitution] { vocabulary ?? [] }

    public init(tone: Tone = .standard, samples: String = "", substitutions: [Substitution] = []) {
        var sources = Set<String>()
        vocabulary = Array(substitutions.filter {
            $0.isValid && sources.insert(Self.sourceKey($0.spoken)).inserted
        }.prefix(Self.maximumSubstitutions))
        self.tone = tone
        self.samples = samples.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(storedValue: Data?) {
        if let storedValue,
           let profile = try? JSONDecoder().decode(Self.self, from: storedValue),
           profile.isValid {
            self.init(tone: profile.tone, samples: profile.samples, substitutions: profile.substitutions)
        } else {
            self.init()
        }
    }

    public var isValid: Bool {
        samples.utf8.count <= Self.maximumSampleBytes &&
            (tone != .custom || !samples.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    public var storedValue: Data? {
        guard isValid else { return nil }
        return try? JSONEncoder().encode(self)
    }

    private static func sourceKey(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    /// Accept only bounded spelling and phrase suggestions that actually occur in the sample text.
    public func vocabularySuggestions(from response: String) -> [Substitution] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = trimmed.hasPrefix("```") && trimmed.hasSuffix("```")
            ? trimmed.split(separator: "\n").dropFirst().dropLast().joined(separator: "\n")
            : trimmed
        guard json.utf8.count <= 8_192,
              let proposals = try? JSONDecoder().decode([Substitution].self, from: Data(json.utf8))
        else { return [] }
        var sources = Set(substitutions.map { Self.sourceKey($0.spoken) })
        return proposals.map { Substitution(spoken: $0.spoken, written: $0.written) }.filter {
            $0.isValid && samples.range(of: Self.wholePhrase($0.written), options: [.regularExpression, .caseInsensitive]) != nil &&
                sources.insert(Self.sourceKey($0.spoken)).inserted
        }.prefix(12).map { $0 }
    }

    private static func wholePhrase(_ text: String) -> String {
        let phrase = NSRegularExpression.escapedPattern(for: sourceKey(text))
            .replacingOccurrences(of: "'", with: "['’]")
        return "(?<![\\p{L}\\p{N}_'’])(?:\(phrase))(?![\\p{L}\\p{N}_'’])"
    }

    func applyingVocabulary(to text: String) -> String {
        guard tone == .custom, !substitutions.isEmpty else { return text }
        let ordered = substitutions.sorted { $0.spoken.count > $1.spoken.count }
        let pattern = ([Self.protectedText] + ordered.map { Self.wholePhrase($0.spoken) }).joined(separator: "|")
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        let replacements = Dictionary(uniqueKeysWithValues: ordered.map { (Self.sourceKey($0.spoken), $0.written) })
        var result = text
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let original = Range(match.range, in: text),
                  let replacement = replacements[Self.sourceKey(String(text[original]))],
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    var prompt: SmartModePrompt {
        let effectiveTone = isValid ? tone : .casual
        let instructions = """
            You are a TEXT TRANSFORMATION FUNCTION. Format the dictation's capitalization and punctuation.
            Keep all words, spelling, numbers, and their order. Never add, delete, or substitute words.
            You may insert a missing apostrophe, such as thats → that's. Keep questions as questions.
            Keep numbers and links intact. Avoid all-caps emphasis. Return only the formatted dictation.
            """
        let userInstruction = effectiveTone == .custom
            ? customInstruction
            : effectiveTone.instruction
        var prompt = SmartModePrompt(
            instructions: instructions + "\n" + userInstruction,
            userInstruction: userInstruction,
            outputMarker: "Formatted text:",
            lowercasesWords: effectiveTone == .superCasual ||
                (effectiveTone == .custom && samples.contains(where: \.isLowercase) &&
                    !samples.contains(where: \.isUppercase)) ? true : nil
        )
        switch effectiveTone {
        case .superCasual: prompt.personalizationStatementStyle = .open
        case .casual: prompt.personalizationStatementStyle = .open
        case .standard: break
        case .excited: prompt.personalizationStatementStyle = .enthusiastic
        case .formal: prompt.personalizationStatementStyle = .formal
        case .relaxed: prompt.personalizationStatementStyle = .relaxed
        case .custom: prompt.personalizationStatementStyle = customStatementStyle
        }
        return prompt
    }

    private var customStatementStyle: PersonalizationFormatting.StatementStyle {
        let messages = samples.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains(where: \.isLetter) }
        let openMessages = messages.filter { message in
            message.last.map { !".!?…。！？؟".contains($0) } ?? false
        }
        return !openMessages.isEmpty && openMessages.count * 2 >= messages.count ? .open : .conversational
    }

    /// The model gets style cues rather than the example messages themselves. This
    /// keeps small models from copying a sample's names or subject into the rewrite.
    private var customInstruction: String {
        let messages = samples.split(whereSeparator: \.isNewline)
        let initials = messages.compactMap { $0.first(where: \.isLetter) }
        let lowercase = initials.filter(\.isLowercase).count * 2 > initials.count
        let sentences = samples.split { $0.isNewline || ".!?。！？".contains($0) }
        let exclamations = samples.filter { $0 == "!" || $0 == "！" }.count
        let capitalization = lowercase ? "Use lowercase sentence starts." : "Use ordinary capitalization."
        let punctuation = exclamations * 2 >= max(1, sentences.count)
            ? "Use occasional exclamation marks." : "Use light punctuation."
        let ending = customStatementStyle == .open ? " Omit final periods in statements." : ""
        return "\(capitalization) \(punctuation)\(ending)"
    }

    /// Resolve in the engine process so the saved style applies to both rewrite engines.
    static func resolve(_ mode: SmartMode, defaults: UserDefaults) -> SmartMode {
        guard mode.id == SmartModeCatalogue.personalizationIdentifier else { return mode }
        let profile = Self(storedValue: defaults.data(forKey: SharedKeys.personalizationProfile))
        return mode.replacingPrompt(profile.prompt)
    }
}
