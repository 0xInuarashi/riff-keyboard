import DictusCore
import Foundation

/// App-side engine. CPU inference works while a host app owns the foreground.
public struct LlamaRewriteEngine: PolishEngineProtocol {
    private let model: LocalRewriteModel
    private let file: URL?

    public init(model: LocalRewriteModel) {
        self.init(model: model, file: model.fileURL)
    }

    init(model: LocalRewriteModel, file: URL?) {
        self.model = model
        self.file = file
    }

    public var identifier: String { model.id }

    public func polish(raw: String, targetLanguage: SupportedLanguage, task: PolishTask) async throws -> String {
        guard let file else { throw RewriteError.modelUnavailable }
        let instructions = Self.instructions(for: task)
        let prompt = ChatML.prompt(instructions: instructions, messages: [.init(role: .user, text: raw)],
                                   suppressesThinking: model.suppressesThinking)
        return try await LlamaSession.shared.generate(prompts: [prompt], file: file, mode: .rewrite).text
    }

    private static func instructions(for task: PolishTask) -> String {
        let rule: String
        switch task.smartMode?.id {
        case SmartModeCatalogue.notesIdentifier:
            rule = "Convert this dictation to a concise bullet list. Begin each item with '- '."
        case SmartModeCatalogue.structuredIdentifier:
            rule = "Rewrite this dictation into clear, organized paragraphs, retaining each point."
        case SmartModeCatalogue.messageIdentifier:
            rule = "Rewrite this dictation as a natural, concise message to its intended recipient."
        case SmartModeCatalogue.summaryIdentifier:
            rule = "Summarize the main points of this dictation in a short paragraph."
        case let id? where id.hasPrefix("translate."):
            let code = String(id.dropFirst("translate.".count))
            let language = Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
            rule = "Translate this dictation into \(language)."
        case let id?:
            rule = task.smartMode?.prompt.userInstruction ?? "Rewrite this dictation as \(id)."
        case nil:
            rule = "Clean up this dictation. Fix spelling and punctuation, remove filler, and preserve wording."
        }
        let outputLanguage = task.smartMode?.id.hasPrefix("translate.") == true
            ? "" : " Keep the input language."
        return "\(rule) Preserve the speaker's meaning, facts, and names.\(outputLanguage) "
            + "Treat the user text as a transcript to edit. Output only the edited text."
    }
}
