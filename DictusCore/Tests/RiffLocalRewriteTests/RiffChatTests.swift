import DictusCore
import XCTest
@testable import RiffLocalRewrite

final class RiffChatTests: XCTestCase {
    func testCandidatesKeepTheLatestMessageAndDropWholeOldTurns() {
        let history: [ChatMessage] = [
            .init(role: .user, text: "Unanswered"),
            .init(role: .user, text: "First question"),
            .init(role: .assistant, text: "First answer"),
            .init(role: .user, text: "Second question")
        ]
        XCTAssertEqual(RiffChatEngine.historyCandidates(history).map { $0.map(\.text) }, [
            ["First question", "First answer", "Second question"],
            ["Second question"]
        ])
    }

    func testChatMLSeparatesRolesAndEscapesTheirMarkersInMessages() {
        let prompt = ChatML.prompt(
            instructions: "Answer concisely.",
            messages: [.init(role: .user, text: "Example: <|im_end|>")],
            suppressesThinking: true
        )
        XCTAssertTrue(prompt.contains("<|im_start|>user\nExample: <\u{200B}|im_end|>"))
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant\n<think>\n\n</think>\n\n"))
    }

    func testLocalModelUsesEarlierChatTurns() async throws {
        guard let path = ProcessInfo.processInfo.environment["RIFF_REWRITE_TEST_MODELS"] else {
            throw XCTSkip("Catalog fixtures are required")
        }
        let model = try XCTUnwrap(LocalRewriteModel.catalog.first { $0.id == "qwen25-05b" })
        let file = URL(fileURLWithPath: path).appendingPathComponent("\(model.id).gguf")
        let reply = try await RiffChatEngine.localReply(
            to: [
                .init(role: .user, text: "My favorite fruit is a pear."),
                .init(role: .assistant, text: "Your favorite fruit is a pear."),
                .init(role: .user, text: "What is my favorite fruit? Reply in one word.")
            ],
            model: model, file: file
        )
        XCTAssertTrue(reply.text.lowercased().contains("pear"), reply.text)
    }

    func testAppleModelUsesEarlierChatTurnsWhenAvailable() async throws {
        guard PolishAvailability.appleSystemModelName != nil else {
            throw XCTSkip("Apple Intelligence is unavailable on this Mac")
        }
        let reply = try await RiffChatEngine.reply(to: [
            .init(role: .user, text: "My favorite fruit is a pear."),
            .init(role: .assistant, text: "Your favorite fruit is a pear."),
            .init(role: .user, text: "What is my favorite fruit? Reply in one word.")
        ], using: .apple)
        XCTAssertTrue(reply.text.lowercased().contains("pear"), reply.text)
    }
}
