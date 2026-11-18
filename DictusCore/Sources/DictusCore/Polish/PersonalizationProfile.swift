import Foundation

/// Saved tone and optional writing samples for the Personalization Smart Mode.
public struct PersonalizationProfile: Codable, Equatable, Sendable {
    public enum Tone: String, CaseIterable, Codable, Sendable {
        case superCasual, casual, excited, formal, relaxed, custom

        fileprivate var instruction: String {
            switch self {
            case .superCasual:
                return "Use lowercase for a very informal style. Keep question marks and use light punctuation."
            case .casual:
                return "Use conversational punctuation and ordinary capitalization."
            case .excited:
                return "Use ordinary capitalization and an occasional exclamation mark to show enthusiasm."
            case .formal:
                return "Use standard capitalization and punctuation:"
            case .relaxed:
                return "Use ordinary capitalization, with periods and commas for a calm tone."
            case .custom:
                return "Use the capitalization and punctuation style of the writing samples."
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
            You are a TEXT TRANSFORMATION FUNCTION. Format the dictation's capitalization and punctuation.
            Keep all words, spelling, numbers, and their order. Never add, delete, or substitute words.
            You may insert a missing apostrophe, such as thats → that's. Keep questions as questions.
            Keep numbers and links intact. Return only the formatted dictation.
            """
        let userInstruction = effectiveTone == .custom
            ? customInstruction
            : effectiveTone.instruction
        return SmartModePrompt(
            instructions: instructions + "\n" + userInstruction,
            userInstruction: userInstruction,
            outputMarker: "Formatted text:"
        )
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
        return "\(capitalization) \(punctuation)"
    }

    /// Resolve in the engine process so the saved style applies to both rewrite engines.
    static func resolve(_ mode: SmartMode, defaults: UserDefaults) -> SmartMode {
        guard mode.id == SmartModeCatalogue.personalizationIdentifier else { return mode }
        let profile = Self(storedValue: defaults.data(forKey: SharedKeys.personalizationProfile))
        return mode.replacingPrompt(profile.prompt)
    }
}
