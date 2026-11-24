// DictusCore/Tests/DictusCoreTests/DictationTailTests.swift
// Tests for the trailing separator (#361): the rule moved into the keyboard with
// polish, and now has two callers in two processes.

import XCTest
@testable import DictusCore

final class DictationTailTests: XCTestCase {

    private func policy(
        mode: TranscriptionLanguageMode,
        engine: SpeechEngine = .whisperKit
    ) -> TranscriptionLanguagePolicy {
        TranscriptionLanguagePolicy(
            mode: mode,
            keyboardLanguage: .french,
            engine: engine,
            modelIdentifier: "openai_whisper-small"
        )
    }

    // MARK: - The historical separator

    func testUnpunctuatedTextGetsASpace() {
        let out = DictationTail.apply("bonjour tout le monde", policy: policy(mode: .followKeyboard))
        XCTAssertEqual(out, "bonjour tout le monde ")
    }

    func testTextEndingInAFullStopGetsOnlyASpace() {
        let out = DictationTail.apply("Bonjour.", policy: policy(mode: .followKeyboard))
        XCTAssertEqual(out, "Bonjour. ")
    }

    func testEveryTerminatorCountsAsPunctuated() {
        for terminator in [".", "!", "?", "…"] {
            let out = DictationTail.apply("Bonjour\(terminator)", policy: policy(mode: .followKeyboard))
            XCTAssertEqual(out, "Bonjour\(terminator) ", "terminator \(terminator)")
        }
    }

    func testExplicitModeKeepsTheSeparator() {
        let out = DictationTail.apply("hello", policy: policy(mode: .explicit(.english)))
        XCTAssertEqual(out, "hello ")
    }

    func testEmptyTextStaysEmpty() {
        XCTAssertEqual(DictationTail.apply("", policy: policy(mode: .followKeyboard)), "")
    }

    // MARK: - Whisper auto-detect inserts as-is

    func testWhisperAutoDetectIsLeftAlone() {
        let out = DictationTail.apply("你好。", policy: policy(mode: .autoDetect))
        XCTAssertEqual(out, "你好。", "coercing Western punctuation onto CJK corrupts it")
    }

    func testParakeetAutoDetectKeepsTheSeparator() {
        // The setting is Whisper-only-effective: Parakeet auto-detects natively and
        // ignores it, so its flows stay byte-identical to the pre-#226 behaviour.
        let out = DictationTail.apply("bonjour", policy: policy(mode: .autoDetect, engine: .parakeet))
        XCTAssertEqual(out, "bonjour ")
    }

    func testPersonalizationKeepsItsOwnPunctuationOnBothSpeechEngines() {
        let mode = SmartModeCatalogue.personalization
        for engine in [SpeechEngine.parakeet, .whisperKit] {
            let policy = policy(mode: .explicit(.english), engine: engine)
            XCTAssertEqual(DictationTail.apply("sounds good", policy: policy, smartMode: mode), "sounds good ")
            XCTAssertEqual(DictationTail.apply("sounds good?", policy: policy, smartMode: mode), "sounds good? ")
            XCTAssertEqual(DictationTail.apply("你好。", policy: policy, smartMode: mode), "你好。 ")
            XCTAssertEqual(DictationTail.apply("sounds good ", policy: policy, smartMode: mode), "sounds good ")
            XCTAssertEqual(DictationTail.apply("", policy: policy, smartMode: mode), "")
        }
    }
    func testRiffTwoFiveTonesKeepTheSameWords() throws {
        let policy = policy(mode: .autoDetect, engine: .parakeet)
        let input = "That’s great. I can send it."
        let cases: [(PersonalizationProfile.Tone, String)] = [
            (.superCasual, "thats great i can send it "),
            (.casual, "that’s great i can send it "),
            (.standard, "That’s great. I can send it. "),
            (.formal, "That’s great. I can send it. "),
            (.excited, "That’s great. I can send it! "),
        ]
        for (tone, expected) in cases {
            let saved = try XCTUnwrap(PersonalizationProfile(tone: tone).storedValue)
            XCTAssertEqual(DictationTail.apply(input, policy: policy, personalization: saved), expected, tone.rawValue)
        }
    }

    func testSavedToneAppliesWithAndWithoutASmartMode() throws {
        let input = "That’s great! I can send https://example.com/Agenda before 1.50."
        let policy = policy(mode: .autoDetect, engine: .parakeet)
        let superCasual = try XCTUnwrap(PersonalizationProfile(tone: .superCasual).storedValue)
        let casual = try XCTUnwrap(PersonalizationProfile(tone: .casual).storedValue)
        for mode in [nil, SmartModeCatalogue.message] {
            XCTAssertEqual(
                DictationTail.apply(input, policy: policy, smartMode: mode, personalization: superCasual),
                "thats great i can send https://example.com/Agenda before 1.50. "
            )
            XCTAssertEqual(
                DictationTail.apply("That’s great, I can send it.", policy: policy,
                                    smartMode: mode, personalization: casual),
                "that’s great, i can send it "
            )
            XCTAssertEqual(
                DictationTail.apply("Can I send it?", policy: policy, smartMode: mode, personalization: superCasual),
                "can i send it? "
            )
        }
    }
}
