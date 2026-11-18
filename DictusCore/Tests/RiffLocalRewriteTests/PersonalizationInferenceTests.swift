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
        var rewrites: Set<String> = []
        for profile in profiles {
            defaults.set(try XCTUnwrap(profile.storedValue), forKey: SharedKeys.personalizationProfile)
            let mode = PersonalizationProfile.resolve(SmartModeCatalogue.personalization, defaults: defaults)
            let job = PolishJob(task: .smart(mode), promptLanguage: .english, typographyLanguage: .english)
            let result = await PolishPipeline.transform(preprocessed: dictation, engine: engine, job: job)
            let output = try XCTUnwrap(result.engineOutput)
            XCTAssertEqual(result.outcome, .success, output)
            XCTAssertTrue(output.localizedCaseInsensitiveContains("Friday"), output)
            XCTAssertTrue(output.localizedCaseInsensitiveContains("Monday"), output)
            XCTAssertFalse(output.localizedCaseInsensitiveContains("invoice"), output)
            XCTAssertFalse(output.localizedCaseInsensitiveContains("print job"), output)
            rewrites.insert(output)
            print("\(engine.identifier) Personalization \(profile.tone.rawValue): \(output)")
        }
        XCTAssertEqual(rewrites.count, 2)
    }
}
