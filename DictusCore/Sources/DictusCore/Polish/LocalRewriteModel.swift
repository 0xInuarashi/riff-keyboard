import Foundation

/// A pinned, downloadable GGUF for app-side Smart Mode generation.
public struct LocalRewriteModel: Identifiable, Sendable, Equatable {
    public static let apple = "apple"
    public static let preferenceKey = "dictus.rewriteModel"

    public let id: String
    public let name: String
    public let bytes: Int
    public let sha256: String
    public let url: URL
    public let suppressesThinking: Bool

    private init(_ id: String, _ name: String, _ repository: String, _ revision: String,
                 _ filename: String, _ bytes: Int, _ sha256: String, suppressesThinking: Bool = false) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.sha256 = sha256
        self.suppressesThinking = suppressesThinking
        var source = URLComponents()
        source.scheme = "https"
        source.host = "huggingface.co"
        source.path = "/\(repository)/resolve/\(revision)/\(filename)"
        guard let url = source.url else { preconditionFailure("Invalid model repository URL") }
        self.url = url
    }

    public static let catalog: [Self] = [
        .init("qwen25-05b", "Qwen2.5 0.5B Instruct", "Qwen/Qwen2.5-0.5B-Instruct-GGUF",
              "9217f5db79a29953eb74d5343926648285ec7e67", "qwen2.5-0.5b-instruct-q4_k_m.gguf",
              491_400_032, "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"),
        .init("smollm2-135m", "SmolLM2 135M Instruct", "bartowski/SmolLM2-135M-Instruct-GGUF",
              "09816acd5d99df7be770d85ea30822623dab342c", "SmolLM2-135M-Instruct-Q4_K_M.gguf",
              105_454_432, "2e8040ceae7815abe0dcb3540b9995eaa1fa0d2ca9e797d0a635ae4433c68c2d"),
        .init("smollm2-360m", "SmolLM2 360M Instruct", "bartowski/SmolLM2-360M-Instruct-GGUF",
              "7be6f65f1db715fe5dc5a4634c0d459b4eed42ec", "SmolLM2-360M-Instruct-Q4_K_M.gguf",
              270_590_880, "2fa3f013dcdd7b99f9b237717fa0b12d75bbb89984cc1274be1471a465bac9c2"),
        .init("qwen2-05b", "Qwen2 0.5B Instruct", "bartowski/Qwen2-0.5B-Instruct-GGUF",
              "a641934b5ba7a4b798fdc6aaf1138ce156ae7da1", "Qwen2-0.5B-Instruct-Q4_K_M.gguf",
              397_805_248, "ca7490f00135c413e0827cbc27333985f937188c19caa2321365644211a3ed4a"),
        .init("qwen3-06b", "Qwen3 0.6B", "bartowski/Qwen_Qwen3-0.6B-GGUF",
              "60b85c0e3d8fe0f6474f406922a26d12aca4550d", "Qwen_Qwen3-0.6B-Q4_K_M.gguf",
              484_220_320, "9acfc1e001311f34b4252001b626f2e466d592a42065f66571bff3790d4e1b14",
              suppressesThinking: true),
        .init("qwen35-08b", "Qwen3.5 0.8B", "unsloth/Qwen3.5-0.8B-GGUF",
              "6ab461498e2023f6e3c1baea90a8f0fe38ab64d0", "Qwen3.5-0.8B-Q4_K_M.gguf",
              532_517_120, "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517",
              suppressesThinking: true)
    ]

    public var fileURL: URL? {
        AppGroup.containerURL?
            .appendingPathComponent("LocalRewriteModels", isDirectory: true)
            .appendingPathComponent("\(id).gguf")
    }

    public var isInstalled: Bool {
        guard let fileURL else { return false }
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        return values?.isRegularFile == true && values?.fileSize == bytes
    }

    public static var selected: Self? {
        let preference = AppGroup.defaults.string(forKey: preferenceKey)
        return catalog.first { $0.id == preference && $0.isInstalled }
    }
}
