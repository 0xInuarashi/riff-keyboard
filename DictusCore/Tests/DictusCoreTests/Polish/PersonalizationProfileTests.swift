import XCTest
@testable import DictusCore

final class PersonalizationProfileTests: XCTestCase {
    func testCustomVocabularyIsApprovedStoredAndDoesNotCascade() throws {
        let samples = "dunno\ni kno"
        let draft = PersonalizationProfile(tone: .custom, samples: samples)
        let suggestions = draft.vocabularySuggestions(from: """
        [{"spoken":"don't know","written":"dunno"},{"spoken":"know","written":"kno"},
         {"spoken":"walk","written":"invented"},{"spoken":"I","written":"i"}]
        """)
        XCTAssertEqual(suggestions.map(\.written), ["dunno", "kno"])
        XCTAssertEqual(draft.applyingVocabulary(to: "I don’t know"), "I don’t know")

        let profile = PersonalizationProfile(tone: .custom, samples: samples, substitutions: suggestions)
        let saved = PersonalizationProfile(storedValue: try XCTUnwrap(profile.storedValue))
        XCTAssertEqual(saved, profile)
        XCTAssertEqual(saved.applyingVocabulary(to: "I don’t know, and I know. knowledge https://example.org/know"),
                       "I dunno, and I kno. knowledge https://example.org/know")
        XCTAssertEqual(PersonalizationProfile(tone: .casual, substitutions: suggestions)
            .applyingVocabulary(to: "I know"), "I know")
    }

    func testOlderProfilesLoadWithoutVocabulary() {
        let profile = PersonalizationProfile(storedValue: Data(#"{"tone":"custom","samples":"dunno"}"#.utf8))
        XCTAssertEqual(profile.tone, .custom)
        XCTAssertTrue(profile.substitutions.isEmpty)
    }

    func testAllSixTonesRoundTripAndUseDistinctInstructions() throws {
        let tones = PersonalizationProfile.Tone.allCases
        XCTAssertEqual(tones.count, 6)
        var instructions = Set<String>()
        for tone in tones {
            let profile = PersonalizationProfile(tone: tone, samples: "thanks, sounds good!")
            let saved = try XCTUnwrap(profile.storedValue)
            XCTAssertEqual(PersonalizationProfile(storedValue: saved), profile)
            instructions.insert(profile.prompt.instructions)
            XCTAssertFalse(profile.prompt.userInstruction.contains("thanks, sounds good!"))
        }
        XCTAssertEqual(instructions.count, 6)
    }

    func testInvalidCustomSamplesCannotBeSaved() {
        XCTAssertNil(PersonalizationProfile(tone: .custom, samples: "  \n").storedValue)
        let large = String(repeating: "é", count: PersonalizationProfile.maximumSampleBytes)
        XCTAssertNil(PersonalizationProfile(tone: .custom, samples: large).storedValue)
        XCTAssertEqual(PersonalizationProfile(storedValue: Data("bad".utf8)).tone, .casual)
    }

    func testResolverReadsSavedStyleWithoutPuttingSamplesInTheCatalogue() throws {
        let suite = "PersonalizationProfileTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let samples = "yeah, let’s do it\nworks for me!"
        let profile = PersonalizationProfile(tone: .custom, samples: samples)
        defaults.set(try XCTUnwrap(profile.storedValue), forKey: SharedKeys.personalizationProfile)
        let base = SmartModeCatalogue.personalization.pinned(true)
        let resolved = PersonalizationProfile.resolve(base, defaults: defaults)

        XCTAssertEqual(resolved.id, base.id)
        XCTAssertEqual(resolved.contract, base.contract)
        XCTAssertTrue(resolved.isPinned)
        XCTAssertTrue(resolved.prompt.userInstruction.contains("lowercase"))
        XCTAssertFalse(resolved.prompt.userInstruction.contains("works for me!"))
        XCTAssertFalse(base.prompt.userInstruction.contains("works for me!"))
        XCTAssertEqual(PersonalizationProfile.resolve(SmartModeCatalogue.message, defaults: defaults),
                       SmartModeCatalogue.message)
    }

    func testCustomSamplesChangeStyleCuesWithoutPassingThroughTheirText() {
        let informal = PersonalizationProfile(tone: .custom, samples: "hey! got a sec?\nthanks!")
        let formal = PersonalizationProfile(tone: .custom, samples: """
            I would appreciate confirmation when you have finished reviewing the invoice.
            Please let me know if I can provide any further information.
            """)
        XCTAssertTrue(informal.prompt.userInstruction.contains("lowercase"))
        XCTAssertTrue(formal.prompt.userInstruction.contains("ordinary capitalization"))
        XCTAssertFalse(formal.prompt.userInstruction.contains("invoice"))
    }

    func testWordSubstitutionFallsBackToTheTranscript() async {
        let input = "I can send the agenda before Monday."
        let job = PolishJob(task: .smart(SmartModeCatalogue.personalization),
                            promptLanguage: .english, typographyLanguage: .english)
        let engine = FixedToneEngine(output: "I’ll send the agenda before Monday.")
        let result = await PolishPipeline.transform(preprocessed: input, engine: engine, job: job)
        XCTAssertEqual(result.rejectedCheck, .changedWords)
        XCTAssertEqual(PolishPipeline.resolvedOutput(result, preprocessed: input, job: job), input)
    }

    func testCapitalizationPunctuationAndMissingApostropheAreAllowed() async {
        let input = "thats great i can send the agenda"
        let formatted = "That’s great! I can send the agenda."
        let job = PolishJob(task: .smart(SmartModeCatalogue.personalization),
                            promptLanguage: .english, typographyLanguage: .english)
        let result = await PolishPipeline.transform(
            preprocessed: input, engine: FixedToneEngine(output: formatted), job: job
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(PolishPipeline.resolvedOutput(result, preprocessed: input, job: job), formatted)
    }

    func testSuperCasualLowercasesAcceptedOutputAndFallbackWithoutChangingLinks() async {
        let profile = PersonalizationProfile(tone: .superCasual)
        let mode = SmartModeCatalogue.personalization.replacingPrompt(profile.prompt)
        let job = PolishJob(task: .smart(mode), promptLanguage: .english, typographyLanguage: nil)
        let input = "Thats Great!\nI can send https://example.com/Agenda."
        let result = await PolishPipeline.transform(
            preprocessed: input,
            engine: FixedToneEngine(output: "That's great!\nI can send https://example.com/Agenda."),
            job: job
        )
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(
            PolishPipeline.resolvedOutput(result, preprocessed: input, job: job),
            "that's great!\ni can send https://example.com/Agenda."
        )

        let rejected = await PolishPipeline.transform(
            preprocessed: input,
            engine: FixedToneEngine(output: "That's great!\nI will send https://example.com/Agenda."),
            job: job
        )
        XCTAssertEqual(rejected.rejectedCheck, .changedWords)
        XCTAssertEqual(
            PolishPipeline.resolvedOutput(rejected, preprocessed: input, job: job),
            "thats great!\ni can send https://example.com/Agenda."
        )
    }

    func testAllTonesFormatModelAndFallbackPunctuation() async throws {
        let input = "Thats great! I can send the agenda."
        let modelOutput = "THAT’S great! I CAN send the agenda."
        let policy = TranscriptionLanguagePolicy(
            mode: .autoDetect, keyboardLanguage: .english, engine: .parakeet, modelIdentifier: "test"
        )
        let expected: [(PersonalizationProfile.Tone, String, String)] = [
            (.superCasual, "that’s great! i can send the agenda", "thats great! i can send the agenda"),
            (.casual, "That’s great! I can send the agenda.", "Thats great! I can send the agenda."),
            (.excited, "That’s great! I can send the agenda!", "Thats great! I can send the agenda!"),
            (.formal, "That’s great. I can send the agenda.", "Thats great. I can send the agenda."),
            (.relaxed, "That’s great… I can send the agenda.", "Thats great… I can send the agenda."),
            (.custom, "that’s great! i can send the agenda", "thats great! i can send the agenda")
        ]
        for (tone, accepted, fallback) in expected {
            let profile = PersonalizationProfile(tone: tone, samples: "hey, thanks!\nall good")
            let mode = SmartModeCatalogue.personalization.replacingPrompt(profile.prompt)
            let decoded = try JSONDecoder().decode(SmartMode.self, from: JSONEncoder().encode(mode))
            let job = PolishJob(task: .smart(decoded), promptLanguage: .english, typographyLanguage: nil)
            let reply = await PolishPipeline.transform(
                preprocessed: input, engine: FixedToneEngine(output: modelOutput), job: job
            )
            XCTAssertEqual(reply.outcome, .success, tone.rawValue)
            let formatted = try XCTUnwrap(PolishPipeline.resolvedOutput(reply, preprocessed: input, job: job))
            XCTAssertEqual(DictationTail.apply(formatted, policy: policy, smartMode: decoded), accepted + " ", tone.rawValue)
            let rejected = await PolishPipeline.transform(
                preprocessed: input, engine: FixedToneEngine(output: "I will send the agenda."), job: job
            )
            XCTAssertEqual(rejected.rejectedCheck, .changedWords, tone.rawValue)
            let recovered = try XCTUnwrap(PolishPipeline.resolvedOutput(rejected, preprocessed: input, job: job))
            XCTAssertEqual(DictationTail.apply(recovered, policy: policy, smartMode: decoded), fallback + " ", tone.rawValue)
        }
    }

    func testEveryExplicitQuestionBoundaryIsPreserved() {
        XCTAssertFalse(PersonalizationFormatting.preservesQuestions(
            in: "Can you send it? Is it ready?", formatted: "Can you send it. Is it ready?"
        ))
        XCTAssertTrue(PersonalizationFormatting.preservesQuestions(
            in: "Can you send it? Is it ready", formatted: "can you send it? is it ready?"
        ))
    }

    func testWordOrderBoundariesSpellingAndSignificantSymbolsArePreserved() {
        let cases = [
            ("Call me Monday", "Monday, call me."),
            ("I can send it", "I can send it today."),
            ("Um I can send it", "I can send it."),
            ("That's cool", "That is cool."),
            ("We’ll send it", "Well send it."),
            ("art work", "artwork"),
            ("Pay 1.50", "Pay 150."),
            ("Use .5", "Use 5."),
            ("Send it to a@b.com", "Send it to a@c.com."),
            ("Keep C++", "Keep C."),
            ("ça marche", "ca marche")
        ]
        for (original, formatted) in cases {
            XCTAssertFalse(PersonalizationFormatting.preservesWords(in: original, formatted: formatted), formatted)
        }
    }

    func testQuestionLossFallsBackToTheTranscript() async {
        let input = "Can we move the meeting to Monday?"
        let job = PolishJob(
            task: .smart(SmartModeCatalogue.personalization),
            promptLanguage: .english,
            typographyLanguage: .english
        )
        let result = await PolishPipeline.transform(preprocessed: input, engine: FixedToneEngine(output: "We can move the meeting to Monday."), job: job)
        XCTAssertEqual(result.rejectedCheck, .lostQuestion)
        XCTAssertEqual(PolishPipeline.resolvedOutput(result, preprocessed: input, job: job), input)
    }
}

private struct FixedToneEngine: PolishEngineProtocol {
    let identifier = "fixed-tone-test"
    let output: String

    func polish(raw: String, targetLanguage: SupportedLanguage, task: PolishTask) async throws -> String {
        output
    }
}
