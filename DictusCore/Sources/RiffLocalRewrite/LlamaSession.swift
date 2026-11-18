import Foundation
import llama

enum LocalInferenceError: Error {
    case modelUnavailable
    case contextUnavailable
    case contextOverflow
    case generationFailed
    case incompleteOutput
    case deadline
}

/// Serializes all app-side generations and releases weight mappings after each call.
actor LlamaSession {
    static let shared = LlamaSession()
    private let contextSize = 2_048
    private let batchSize = 128
    private let outputLimit = 384

    init() {
        llama_backend_init()
    }

    enum Mode: Equatable {
        case rewrite
        case chat
    }

    func generate(prompts: [String], file: URL, mode: Mode) throws -> ChatReply {
        let deadline = ContinuousClock.now.advanced(by: .seconds(mode == .chat ? 45 : 20))
        func checkBudget() throws {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw LocalInferenceError.deadline }
        }
        try checkBudget()

        var modelParameters = llama_model_default_params()
        modelParameters.n_gpu_layers = 0
        modelParameters.use_mmap = true
        // A nil list asks llama.cpp to discover GPU devices, even with zero GPU layers.
        var cpuOnly: [OpaquePointer?] = [nil]
        let loaded = cpuOnly.withUnsafeMutableBufferPointer { devices in
            modelParameters.devices = devices.baseAddress
            return file.path.withCString { llama_model_load_from_file($0, modelParameters) }
        }
        guard let model = loaded else {
            throw LocalInferenceError.modelUnavailable
        }
        defer { llama_model_free(model) }
        try checkBudget()

        guard let vocab = llama_model_get_vocab(model) else { throw LocalInferenceError.modelUnavailable }
        var tokens = try fittingTokens(prompts, vocabulary: vocab)

        var parameters = llama_context_default_params()
        parameters.n_ctx = UInt32(contextSize)
        parameters.n_batch = UInt32(batchSize)
        parameters.n_ubatch = UInt32(batchSize)
        parameters.n_threads = 3
        parameters.n_threads_batch = 3
        parameters.offload_kqv = false
        parameters.op_offload = false
        guard let context = llama_init_from_model(model, parameters) else { throw LocalInferenceError.contextUnavailable }
        defer { llama_free(context) }
        guard let sampler = llama_sampler_init_greedy() else { throw LocalInferenceError.contextUnavailable }
        defer { llama_sampler_free(sampler) }

        try tokens.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { throw LocalInferenceError.contextUnavailable }
            for offset in stride(from: 0, to: buffer.count, by: batchSize) {
                try checkBudget()
                let length = min(buffer.count - offset, batchSize)
                guard llama_decode(context, llama_batch_get_one(base + offset, Int32(length))) == 0 else {
                    throw LocalInferenceError.generationFailed
                }
            }
        }

        var output = Data()
        var piece = [CChar](repeating: 0, count: 256)
        for _ in 0..<outputLimit {
            try checkBudget()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) {
                return try reply(from: output)
            }
            let length = piece.withUnsafeMutableBufferPointer { buffer in
                llama_token_to_piece(vocab, token, buffer.baseAddress, Int32(buffer.count), 0, false)
            }
            guard length >= 0 else { throw LocalInferenceError.generationFailed }
            output.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            let result = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            guard result == 0 else {
                throw LocalInferenceError.generationFailed
            }
        }
        if mode == .chat { return try reply(from: output, reachedLimit: true) }
        // An unfinished generation can silently cut off a dictated sentence.
        throw LocalInferenceError.incompleteOutput
    }

    private func fittingTokens(_ prompts: [String], vocabulary: OpaquePointer) throws -> [llama_token] {
        var tokens = [llama_token](repeating: 0, count: contextSize)
        for prompt in prompts where prompt.utf8.count <= 32_768 {
            let count = prompt.withCString { text in
                tokens.withUnsafeMutableBufferPointer { buffer in
                    llama_tokenize(vocabulary, text, Int32(prompt.utf8.count), buffer.baseAddress,
                                   Int32(buffer.count), true, true)
                }
            }
            if count > 0, Int(count) + outputLimit <= contextSize {
                return Array(tokens.prefix(Int(count)))
            }
        }
        throw LocalInferenceError.contextOverflow
    }

    private func reply(from data: Data, reachedLimit: Bool = false) throws -> ChatReply {
        // A token-limited chat can stop in the middle of a UTF-8 scalar. Trim at
        // most its trailing bytes while keeping invalid bytes out of a rewrite.
        let candidates = reachedLimit ? 0...min(3, data.count) : 0...0
        for trailingBytes in candidates {
            if let text = String(data: data.dropLast(trailingBytes), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return ChatReply(text: text, reachedLimit: reachedLimit)
            }
        }
        throw LocalInferenceError.incompleteOutput
    }
}
