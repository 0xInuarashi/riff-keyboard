import DictusCore
import Foundation
import llama

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
        // All six catalog models use ChatML. Escape role markers in dictated text.
        let input = raw.replacingOccurrences(of: "<|", with: "<\u{200B}|")
        let prefix = model.suppressesThinking ? "<think>\n\n</think>\n\n" : ""
        let prompt = "<|im_start|>system\n\(instructions)<|im_end|>\n"
            + "<|im_start|>user\n\(input)<|im_end|>\n<|im_start|>assistant\n\(prefix)"
        return try await LlamaSession.shared.generate(prompt: prompt, file: file)
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

private enum RewriteError: Error {
    case modelUnavailable
    case contextUnavailable
    case contextOverflow
    case generationFailed
    case incompleteOutput
    case deadline
}

/// Serializes all app-side generations and releases weight mappings after each call.
private actor LlamaSession {
    static let shared = LlamaSession()
    private let contextSize = 2_048
    private let batchSize = 128
    private let outputLimit = 384

    init() {
        llama_backend_init()
    }

    func generate(prompt: String, file: URL) throws -> String {
        let deadline = ContinuousClock.now.advanced(by: .seconds(16))
        func checkBudget() throws {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw RewriteError.deadline }
        }
        try checkBudget()

        var modelParameters = llama_model_default_params()
        modelParameters.n_gpu_layers = 0
        modelParameters.use_mmap = true
        guard let model = file.path.withCString({ llama_model_load_from_file($0, modelParameters) }) else {
            throw RewriteError.modelUnavailable
        }
        defer { llama_model_free(model) }
        try checkBudget()

        guard let vocab = llama_model_get_vocab(model) else { throw RewriteError.modelUnavailable }
        var tokens = [llama_token](repeating: 0, count: contextSize)
        guard prompt.utf8.count <= 32_768 else { throw RewriteError.contextOverflow }
        let count = prompt.withCString { text in
            tokens.withUnsafeMutableBufferPointer { buffer in
                llama_tokenize(vocab, text, Int32(prompt.utf8.count), buffer.baseAddress, Int32(buffer.count), true, true)
            }
        }
        guard count > 0, Int(count) + outputLimit <= contextSize else { throw RewriteError.contextOverflow }

        var parameters = llama_context_default_params()
        parameters.n_ctx = UInt32(contextSize)
        parameters.n_batch = UInt32(batchSize)
        parameters.n_ubatch = UInt32(batchSize)
        parameters.n_threads = 3
        parameters.n_threads_batch = 3
        parameters.offload_kqv = false
        parameters.op_offload = false
        guard let context = llama_init_from_model(model, parameters) else { throw RewriteError.contextUnavailable }
        defer { llama_free(context) }
        guard let sampler = llama_sampler_init_greedy() else { throw RewriteError.contextUnavailable }
        defer { llama_sampler_free(sampler) }

        try tokens.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { throw RewriteError.contextUnavailable }
            for offset in stride(from: 0, to: Int(count), by: batchSize) {
                try checkBudget()
                let length = min(Int(count) - offset, batchSize)
                guard llama_decode(context, llama_batch_get_one(base + offset, Int32(length))) == 0 else {
                    throw RewriteError.generationFailed
                }
            }
        }

        var output = Data()
        var piece = [CChar](repeating: 0, count: 256)
        for _ in 0..<outputLimit {
            try checkBudget()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) {
                let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw RewriteError.incompleteOutput }
                return text
            }
            let length = piece.withUnsafeMutableBufferPointer { buffer in
                llama_token_to_piece(vocab, token, buffer.baseAddress, Int32(buffer.count), 0, false)
            }
            guard length >= 0 else { throw RewriteError.generationFailed }
            output.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            let result = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            guard result == 0 else {
                throw RewriteError.generationFailed
            }
        }
        // An unfinished generation can silently cut off a dictated sentence.
        throw RewriteError.incompleteOutput
    }
}
