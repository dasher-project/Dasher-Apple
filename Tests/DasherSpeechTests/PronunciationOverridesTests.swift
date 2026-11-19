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

    func testAddingAppendsLineAndReplacesExistingKeyCaseInsensitively() {
        let text = "# keep me\nbotox = bow tocks\n\n"
        let replaced = PronunciationOverrides.adding(
            PronunciationOverrides.Entry(word: "Botox", respell: "bow tocks!", ipa: nil), to: text
        )
        XCTAssertEqual(replaced, "# keep me\nBotox = bow tocks!\n")
        XCTAssertEqual(PronunciationOverrides.entries(from: replaced).count, 1)

        let added = PronunciationOverrides.adding(
            PronunciationOverrides.Entry(word: "nguyen", respell: nil, ipa: "wɪn"), to: replaced
        )
        XCTAssertEqual(PronunciationOverrides.entries(from: added), [
            PronunciationOverrides.Entry(word: "Botox", respell: "bow tocks!", ipa: nil),
            PronunciationOverrides.Entry(word: "nguyen", respell: nil, ipa: "wɪn"),
        ])
    }

    func testRemovingDeletesTheEntryLineButKeepsComments() {
        let text = "# header\nbotox = bow tocks\nnguyen = /wɪn/\n"
        let removed = PronunciationOverrides.removing(
            PronunciationOverrides.Entry(word: "botox", respell: "bow tocks", ipa: nil), from: text
        )
        XCTAssertEqual(removed, "# header\nnguyen = /wɪn/\n")
    }
}
