import XCTest
@testable import DictusCore
@testable import RiffLocalRewrite

final class PersonalizationInferenceTests: XCTestCase {
    func testDownloadedModelFormatsWithSavedPersonalization() async throws {
        guard let folder = ProcessInfo.processInfo.environment["RIFF_REWRITE_TEST_MODELS"] else {
            throw XCTSkip("Catalog fixtures are required")
        }
        let model = try XCTUnwrap(LocalRewriteModel.catalog.first { $0.id == "qwen25-05b" })
        let file = URL(fileURLWithPath: folder).appendingPathComponent("\(model.id).gguf")
        let engine = LlamaRewriteEngine(model: model, file: file)
        try await verifyPersonalization(using: engine)
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
        let profiles = [
            PersonalizationProfile(tone: .formal),
            PersonalizationProfile(tone: .custom, samples:
                "hey! got a sec to check the invoice? all good if not.\n"
                + "just a heads-up: the print job is ready. thanks!")
        ]
        for profile in profiles {
            defaults.set(try XCTUnwrap(profile.storedValue), forKey: SharedKeys.personalizationProfile)
            let mode = PersonalizationProfile.resolve(SmartModeCatalogue.personalization, defaults: defaults)
            let job = PolishJob(task: .smart(mode), promptLanguage: .english, typographyLanguage: .english)
            let input = "thats great i can send the agenda before monday"
            let result = await PolishPipeline.transform(preprocessed: input, engine: engine, job: job)
            let output = try XCTUnwrap(PolishPipeline.resolvedOutput(result, preprocessed: input, job: job))
            XCTAssertTrue(PersonalizationFormatting.preservesWords(in: input, formatted: output), output)
            if profile.tone == .formal {
                XCTAssertEqual(result.outcome, .success, result.engineOutput ?? "No engine output")
                XCTAssertNotEqual(output, input)
            }
            print("\(engine.identifier) Personalization \(profile.tone.rawValue): \(output)")
        }
    }
}
