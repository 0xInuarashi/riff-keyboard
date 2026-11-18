import XCTest
@testable import DictusCore

final class PersonalizationProfileTests: XCTestCase {
    func testAllSixTonesRoundTripAndUseDistinctInstructions() throws {
        let tones = PersonalizationProfile.Tone.allCases
        XCTAssertEqual(tones.count, 6)
        var instructions = Set<String>()
        for tone in tones {
            let profile = PersonalizationProfile(tone: tone, samples: "Thanks, sounds good!")
            let saved = try XCTUnwrap(profile.storedValue)
            XCTAssertEqual(PersonalizationProfile(storedValue: saved), profile)
            instructions.insert(profile.prompt.instructions)
            XCTAssertEqual(profile.prompt.userInstruction.contains("Thanks, sounds good!"), tone == .custom)
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
        XCTAssertTrue(resolved.prompt.userInstruction.contains(samples.debugDescription))
        XCTAssertFalse(base.prompt.userInstruction.contains("works for me!"))
        XCTAssertEqual(PersonalizationProfile.resolve(SmartModeCatalogue.message, defaults: defaults),
                       SmartModeCatalogue.message)
    }
}
