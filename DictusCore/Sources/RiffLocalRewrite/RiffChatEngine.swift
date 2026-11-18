import DictusCore
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct ChatMessage: Identifiable, Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public let id = UUID()
    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct ChatReply: Sendable {
    public let text: String
    public let reachedLimit: Bool
}

public enum RiffChatEngine {
    public enum Backend: Sendable {
        case apple
        case downloaded(LocalRewriteModel)
    }

    public enum Failure: Error {
        case modelUnavailable
        case messageTooLong
    }

    private static let instructions = """
        You are Riff, a helpful conversational assistant. Answer the user's latest message directly.
        Use earlier turns when relevant. Keep replies concise and say when you are unsure.
        """

    public static func reply(to messages: [ChatMessage], using backend: Backend) async throws -> ChatReply {
        switch backend {
        case .apple:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                return try await appleReply(to: messages)
            }
            #endif
            throw Failure.modelUnavailable
        case .downloaded(let model):
            guard model.isInstalled, let file = model.fileURL else { throw Failure.modelUnavailable }
            return try await localReply(to: messages, model: model, file: file)
        }
    }

    static func localReply(to messages: [ChatMessage], model: LocalRewriteModel, file: URL) async throws -> ChatReply {
        let prompts = historyCandidates(messages).map {
            ChatML.prompt(instructions: instructions, messages: $0, suppressesThinking: model.suppressesThinking)
        }
        do {
            return try await LlamaSession.shared.generate(prompts: prompts, file: file, mode: .chat)
        } catch LocalInferenceError.contextOverflow {
            throw Failure.messageTooLong
        }
    }

    /// Keep the newest user message intact and drop older complete turns first.
    /// A stopped or failed generation has no answer and does not enter the context.
    static func historyCandidates(_ messages: [ChatMessage]) -> [[ChatMessage]] {
        guard let latest = messages.last, latest.role == .user else { return [] }
        let earlier = messages.dropLast()
        let exchanges = zip(earlier, earlier.dropFirst())
            .filter { $0.0.role == .user && $0.1.role == .assistant }
            .suffix(6)
        return (0...exchanges.count).map { omitted in
            exchanges.dropFirst(omitted).flatMap { [$0.0, $0.1] } + [latest]
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func appleReply(to messages: [ChatMessage]) async throws -> ChatReply {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { throw Failure.modelUnavailable }
        let replyLimit = 512
        for candidate in historyCandidates(messages) {
            guard let current = candidate.last else { continue }
            let entries = appleEntries(for: candidate)
            if #available(iOS 26.4, macOS 26.4, *) {
                let tokens = try await model.tokenCount(for: entries)
                guard tokens + replyLimit < model.contextSize else { continue }
            } else {
                // Reserve space for the reply and Apple's template on iOS 26.0–26.3.
                let bytes = candidate.reduce(instructions.utf8.count) { $0 + $1.text.utf8.count + 32 }
                guard bytes < 3_400 else { continue }
            }
            let session = LanguageModelSession(model: model, transcript: Transcript(entries: entries.dropLast()))
            let response = try await session.respond(to: current.text, options: GenerationOptions(
                maximumResponseTokens: replyLimit
            ))
            return ChatReply(text: response.content, reachedLimit: false)
        }
        throw Failure.messageTooLong
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func appleEntries(for messages: [ChatMessage]) -> [Transcript.Entry] {
        let system = Transcript.Entry.instructions(.init(
            segments: [.text(.init(content: instructions))], toolDefinitions: []
        ))
        return [system] + messages.map { message in
            let segment = Transcript.Segment.text(.init(content: message.text))
            switch message.role {
            case .user: return .prompt(.init(segments: [segment]))
            case .assistant: return .response(.init(assetIDs: [], segments: [segment]))
            }
        }
    }
    #endif
}

enum ChatML {
    static func prompt(instructions: String, messages: [ChatMessage], suppressesThinking: Bool) -> String {
        var prompt = "<|im_start|>system\n\(instructions)<|im_end|>\n"
        for message in messages {
            let text = message.text.replacingOccurrences(of: "<|", with: "<\u{200B}|")
            prompt += "<|im_start|>\(message.role.rawValue)\n\(text)<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n"
        if suppressesThinking { prompt += "<think>\n\n</think>\n\n" }
        return prompt
    }
}
