import XCTest
@testable import DictusCore
@testable import RiffLocalRewrite

final class PersonalizationInferenceTests: XCTestCase {
    func testDownloadedModelFormatsWithSavedPersonalization() async throws {
        guard let folder = ProcessInfo.processInfo.environment["RIFF_REWRITE_TEST_MODELS"] else {
            throw XCTSkip("Catalog fixtures are required")
        }
        let ids = ProcessInfo.processInfo.environment["RIFF_PERSONALIZATION_TEST_MODELS"]
            .map { Set($0.split(separator: ",").map(String.init)) }
        let models = LocalRewriteModel.catalog.filter { ids?.contains($0.id) ?? true }
        XCTAssertFalse(models.isEmpty)
        for model in models {
            let file = URL(fileURLWithPath: folder).appendingPathComponent("\(model.id).gguf")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), model.id)
            let engine = LlamaRewriteEngine(model: model, file: file)
            try await verifyPersonalization(using: engine)
        }
    }

    func testAppleModelFormatsWithSavedPersonalizationWhenAvailable() async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), PolishAvailability.isAppleFMAvailable {
            try await verifyPersonalization(using: AppleFoundationModelsPolishEngine())
            return
        }
        #endif
        throw XCTSkip("Apple Intelligence is unavailable")
    }

    private func verifyPersonalization(using engine: PolishEngineProtocol) async throws {
        let suite = "PersonalizationInferenceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let inputs = [
            "Thats great! I can send the agenda before Monday.",
            "Can you send the notes? I can review them this afternoon.",
            "Please keep 1.50 and https://example.com/Agenda in the notes."
        ]
        let policy = TranscriptionLanguagePolicy(
            mode: .autoDetect, keyboardLanguage: .english, engine: .parakeet, modelIdentifier: "test"
        )
        for tone in PersonalizationProfile.Tone.allCases {
            let profile = PersonalizationProfile(tone: tone, samples: "hey, thanks!\nall good over here")
            defaults.set(try XCTUnwrap(profile.storedValue), forKey: SharedKeys.personalizationProfile)
            let mode = PersonalizationProfile.resolve(SmartModeCatalogue.personalization, defaults: defaults)
            let job = PolishJob(task: .smart(mode), promptLanguage: .english, typographyLanguage: nil)
            for input in inputs {
                let result = await PolishPipeline.transform(preprocessed: input, engine: engine, job: job)
                let formatted = try XCTUnwrap(PolishPipeline.resolvedOutput(result, preprocessed: input, job: job))
                let delivered = DictationTail.apply(formatted, policy: policy, smartMode: mode)
                let output = delivered.trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertTrue(PersonalizationFormatting.preservesWords(in: input, formatted: output), output)
                XCTAssertTrue(PersonalizationFormatting.preservesQuestions(in: input, formatted: output), output)
                switch tone {
                case .superCasual, .custom:
                    // The custom fixture samples use lowercase and include open endings.
                    XCTAssertEqual(output, PersonalizationFormatting.apply(to: output, source: input, prompt: mode.prompt))
                    XCTAssertFalse(output.hasSuffix("."), output)
                case .excited:
                    XCTAssertTrue(output.hasSuffix("!"), output)
                case .formal:
                    XCTAssertTrue(output.hasSuffix("."), output)
                    XCTAssertFalse(output.contains("!"), output)
                case .relaxed:
                    XCTAssertFalse(output.contains("!"), output)
                case .casual:
                    break
                }
                print("TONE AUDIT \(engine.identifier) \(tone.rawValue) \(result.outcome): \(output)")
            }
        }
    }
}
