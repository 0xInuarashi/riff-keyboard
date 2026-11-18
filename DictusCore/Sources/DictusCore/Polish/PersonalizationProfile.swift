import Foundation

/// Saved tone and optional writing samples for the Personalization Smart Mode.
public struct PersonalizationProfile: Codable, Equatable, Sendable {
    public enum Tone: String, CaseIterable, Codable, Sendable {
        case superCasual, casual, excited, formal, relaxed, custom

        fileprivate var instruction: String {
            switch self {
            case .superCasual:
                return "Rewrite this passage in a very informal tone, with short sentences and natural contractions."
            case .casual:
                return "Rewrite this passage in a friendly, conversational tone."
            case .excited:
                return "Rewrite this passage in an upbeat, enthusiastic tone without overstating anything."
            case .formal:
                return "Rewrite this passage in a formal, professional tone."
            case .relaxed:
                return "Rewrite this passage in a calm, easygoing tone."
            case .custom:
                return "Rewrite this passage to match the user's writing style."
            }
        }
    }

    public static let maximumSampleBytes = 12_000
    public let tone: Tone
    public let samples: String

    public init(tone: Tone = .casual, samples: String = "") {
        self.tone = tone
        self.samples = samples.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(storedValue: Data?) {
        if let storedValue,
           let profile = try? JSONDecoder().decode(Self.self, from: storedValue),
           profile.isValid {
            self.init(tone: profile.tone, samples: profile.samples)
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

    var prompt: SmartModePrompt {
        let effectiveTone = isValid ? tone : .casual
        let instructions = """
            You are a TEXT TRANSFORMATION FUNCTION. Rewrite the dictation in the requested tone.
            Keep its language, meaning, speaker, recipient, facts, names, dates, and numbers.
            Return only the rewritten dictation.
            """
        let userInstruction = effectiveTone == .custom
            ? customInstruction
            : effectiveTone.instruction
        return SmartModePrompt(
            instructions: instructions + "\n" + userInstruction,
            userInstruction: userInstruction,
            outputMarker: "Rewritten text:"
        )
    }

    /// The model gets style cues rather than the example messages themselves. This
    /// keeps small models from copying a sample's names or subject into the rewrite.
    private var customInstruction: String {
        let messages = samples.split(whereSeparator: \.isNewline)
        let initials = messages.compactMap { $0.first(where: \.isLetter) }
        let lowercase = initials.filter(\.isLowercase).count * 2 > initials.count
        let words = samples.split(whereSeparator: \.isWhitespace)
        let sentenceCount = samples.split { $0.isNewline || ".!?。！？".contains($0) }.count
        let shortSentences = words.count <= 12 * max(1, sentenceCount)
        let normalized = samples.lowercased().replacingOccurrences(of: "’", with: "'")
        let usesContractions = ["n't", "'m", "'re", "'ve", "'ll"].contains { normalized.contains($0) }
        let enthusiastic = samples.filter { $0 == "!" || $0 == "！" }.count * 2 >= max(1, sentenceCount)

        let register = lowercase || usesContractions ? "casual, conversational" : "composed, professional"
        let pace = shortSentences ? "shorter sentences" : "complete, connected sentences"
        let contractionStyle = lowercase || usesContractions ? "natural contractions and " : ""
        let emphasis = enthusiastic ? " Use occasional exclamation marks when appropriate." : ""
        return "Rewrite this passage in \(register) language with \(contractionStyle)\(pace).\(emphasis)"
    }

    /// Resolve in the engine process so the saved style applies to both rewrite engines.
    static func resolve(_ mode: SmartMode, defaults: UserDefaults) -> SmartMode {
        guard mode.id == SmartModeCatalogue.personalizationIdentifier else { return mode }
        let profile = Self(storedValue: defaults.data(forKey: SharedKeys.personalizationProfile))
        return mode.replacingPrompt(profile.prompt)
    }
}
