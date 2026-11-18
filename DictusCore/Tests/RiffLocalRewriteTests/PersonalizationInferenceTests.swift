import XCTest
@testable import DictusCore
@testable import RiffLocalRewrite

final class PersonalizationInferenceTests: XCTestCase {
    private let dictation = "Hey, I can't join the meeting on Friday. Can we move it to Monday?"

    func testDownloadedModelRewritesWithSavedPersonalization() async throws {
        guard let folder = ProcessInfo.processInfo.environment["RIFF_REWRITE_TEST_MODELS"] else {
            throw XCTSkip("Catalog fixtures are required")
        }
        let model = try XCTUnwrap(LocalRewriteModel.catalog.first { $0.id == "qwen25-05b" })
        let file = URL(fileURLWithPath: folder).appendingPathComponent("\(model.id).gguf")
        let engine = LlamaRewriteEngine(model: model, file: file)
        try await verifyPersonalization(using: engine)
    }

    func testAppleModelRewritesWithSavedPersonalizationWhenAvailable() async throws {
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
            let input = profile.tone == .custom
                ? "I will be unable to attend the meeting scheduled for Friday, "
                    + "would it be possible to reschedule it to Monday? I can send the agenda before then."
                : dictation
            let result = await PolishPipeline.transform(preprocessed: input, engine: engine, job: job)
            let output = try XCTUnwrap(result.engineOutput)
            XCTAssertEqual(result.outcome, .success, output)
            XCTAssertNotEqual(output, input, "The \(profile.tone.rawValue) output should rewrite the sample.")
            XCTAssertTrue(output.localizedCaseInsensitiveContains("Friday"), output)
            XCTAssertTrue(output.localizedCaseInsensitiveContains("Monday"), output)
            XCTAssertTrue(output.contains("?"), output)
            if profile.tone == .custom {
                XCTAssertTrue(output.localizedCaseInsensitiveContains("agenda"), output)
            }
            XCTAssertFalse(output.localizedCaseInsensitiveContains("invoice"), output)
            XCTAssertFalse(output.localizedCaseInsensitiveContains("print job"), output)
            print("\(engine.identifier) Personalization \(profile.tone.rawValue): \(output)")
        }
    }
}
