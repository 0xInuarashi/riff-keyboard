import DictusCore
import XCTest
@testable import RiffLocalRewrite

final class LocalRewriteTests: XCTestCase {
    func testCatalogContainsSixCompactPinnedModels() {
        let models = LocalRewriteModel.catalog
        XCTAssertEqual(models.count, 6)
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        for model in models {
            XCTAssertLessThan(model.bytes, 550_000_000)
            XCTAssertEqual(model.sha256.count, 64)
            XCTAssertEqual(model.url.scheme, "https")
            XCTAssertEqual(model.url.host, "huggingface.co")
            XCTAssertEqual(model.url.pathExtension, "gguf")
        }
    }

    func testDownloadsGenerateThroughTheProductionPipeline() async throws {
        guard let path = ProcessInfo.processInfo.environment["RIFF_REWRITE_TEST_MODELS"] else {
            throw XCTSkip("Set RIFF_REWRITE_TEST_MODELS to a directory of catalog GGUFs named by model ID")
        }
        let folder = URL(fileURLWithPath: path)
        let raw = "Can you send the budget on Friday and book the main room for Monday morning?"
        let job = PolishJob(task: .natural, promptLanguage: .english, typographyLanguage: .english)
        for model in LocalRewriteModel.catalog {
            let file = folder.appendingPathComponent("\(model.id).gguf")
            let engine = LlamaRewriteEngine(model: model, file: file)
            let result = await PolishPipeline.transform(preprocessed: raw, engine: engine, job: job)
            print("\(model.id) \(result.outcome.rawValue) \(result.engineMs) ms")
            XCTAssertNotEqual(result.outcome, .engineFailed, model.id)
            XCTAssertNotNil(result.engineOutput, model.id)
        }
    }

    func testLocalModelRewritesAList() async throws {
        guard let path = ProcessInfo.processInfo.environment["RIFF_REWRITE_TEST_MODELS"] else {
            throw XCTSkip("Catalog fixtures are required")
        }
        let model = try XCTUnwrap(LocalRewriteModel.catalog.first { $0.id == "qwen25-05b" })
        let mode = try XCTUnwrap(SmartModeCatalogue.mode(withIdentifier: SmartModeCatalogue.notesIdentifier))
        let engine = LlamaRewriteEngine(model: model, file: URL(fileURLWithPath: path)
            .appendingPathComponent("\(model.id).gguf"))
        let raw = "We need to send the report on Friday and book the conference room for Monday morning."
        let result = await PolishPipeline.transform(
            preprocessed: raw, engine: engine,
            job: PolishJob(task: .smart(mode), promptLanguage: .english, typographyLanguage: .english)
        )
        XCTAssertEqual(result.outcome, .success, result.engineOutput ?? "No output")
        let output = try XCTUnwrap(result.engineOutput)
        XCTAssertTrue(output.contains("Friday"))
        XCTAssertTrue(output.contains("Monday"))
        XCTAssertGreaterThanOrEqual(output.split(separator: "\n").count, 2)
    }

    func testAppSideResultRoundTripsWithoutLosingRefusalOrDocument() throws {
        let result = LocalRewriteHandoff(
            outcome: PolishOutcome(failure: SmartModeFailure(
                modeIdentifier: "translate.en", modeDisplayName: "English",
                outcome: "engineFailed", reason: "model-failed"
            )),
            documentIdentifier: "original-field"
        )
        let read = try JSONDecoder().decode(LocalRewriteHandoff.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(read.outcome, result.outcome)
        XCTAssertEqual(read.documentIdentifier, "original-field")
    }
}
