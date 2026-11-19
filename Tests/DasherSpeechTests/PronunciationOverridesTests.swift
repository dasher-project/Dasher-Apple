import XCTest
@testable import DasherSpeech

final class PronunciationOverridesTests: XCTestCase {
    func testParsesRespellAndIPAEntries() {
        let text = """
        # a comment
        botox = bow tocks
        nguyen = /wɪn/
        san rafael = san rah fah el
        not an entry
        """
        XCTAssertEqual(PronunciationOverrides.entries(from: text), [
            PronunciationOverrides.Entry(word: "botox", respell: "bow tocks", ipa: nil),
            PronunciationOverrides.Entry(word: "nguyen", respell: nil, ipa: "wɪn"),
            PronunciationOverrides.Entry(word: "san rafael", respell: "san rah fah el", ipa: nil),
        ])
    }

    func testRespellMatchesWholeWordsCaseInsensitively() {
        let entries = [PronunciationOverrides.Entry(word: "botox", respell: "bow tocks", ipa: nil)]
        XCTAssertEqual(
            PronunciationOverrides.applyingRespells(to: "Botox, and (BOTOX) but never botax or elbow", entries: entries),
            "bow tocks, and (bow tocks) but never botax or elbow"
        )
    }

    func testLongestKeyWins() {
        let entries = [
            PronunciationOverrides.Entry(word: "rafael", respell: "rah fah EL", ipa: nil),
            PronunciationOverrides.Entry(word: "san rafael", respell: "san rah fah el", ipa: nil),
        ]
        XCTAssertEqual(
            PronunciationOverrides.applyingRespells(to: "visit san rafael, then rafael alone", entries: entries),
            "visit san rah fah el, then rah fah EL alone"
        )
    }

    func testIPAOnlyEntriesDoNotSubstitute() {
        let entries = [PronunciationOverrides.Entry(word: "nguyen", respell: nil, ipa: "wɪn")]
        XCTAssertEqual(
            PronunciationOverrides.applyingRespells(to: "mr nguyen", entries: entries),
            "mr nguyen"
        )
    }

    func testStarterTextParsesToNoEntries() {
        XCTAssertTrue(PronunciationOverrides.entries(from: PronunciationOverrides.starterText).isEmpty)
    }
}
