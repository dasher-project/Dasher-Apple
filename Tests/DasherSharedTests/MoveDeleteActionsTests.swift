import XCTest
@testable import DasherShared

/// RFC 0021 amendment: Move/Delete parse, keystroke mapping, editor-mode
/// caret moves and deletion ranges.
final class MoveDeleteActionsTests: XCTestCase {

    // MARK: - Parse

    func testParseKnownDistances() {
        for dist in ["char", "word", "sentence", "paragraph", "all"] {
            XCTAssertNotNil(MoveDeleteActions.parse(dist: dist, forward: "yes"), dist)
            XCTAssertNotNil(MoveDeleteActions.parse(dist: dist, forward: "no"), dist)
        }
    }

    func testParseUnknownValuesReturnNil() {
        XCTAssertNil(MoveDeleteActions.parse(dist: "page", forward: "yes"))
        XCTAssertNil(MoveDeleteActions.parse(dist: nil, forward: "yes"))
        XCTAssertNil(MoveDeleteActions.parse(dist: "word", forward: nil))
        XCTAssertNil(MoveDeleteActions.parse(dist: "word", forward: "maybe"))
        XCTAssertNil(MoveDeleteActions.parse(dist: "", forward: "yes"))
    }

    // MARK: - Editor caret moves

    private let text = "Hello world. Second sentence here.\n\nThird paragraph."

    func testMoveCharBothDirections() {
        let units = Array(text.utf16)
        let mid = 5 // after "Hello"
        let back = MoveDeleteActions.moveCaret(text: text, caret: mid, dist: .char, dir: .backward)
        let fwd = MoveDeleteActions.moveCaret(text: text, caret: mid, dist: .char, dir: .forward)
        XCTAssertEqual(back, mid - 1)
        XCTAssertEqual(fwd, mid + 1)
        XCTAssertEqual(units[mid - 1], UInt16(ASCII: "o".utf16.first!))
    }

    func testMoveWordBoundaries() {
        // caret mid-word "Hello| world" — backward word move goes to 0
        XCTAssertEqual(MoveDeleteActions.moveCaret(text: text, caret: 3, dist: .word, dir: .backward), 0)
        // caret at start — forward word move lands at the start of the next
        // word (shared wordBound semantics: skips the trailing space)
        XCTAssertEqual(MoveDeleteActions.moveCaret(text: text, caret: 0, dist: .word, dir: .forward), 6)
    }

    func testMoveParagraph() {
        // Shared paragraphBound semantics: forward stops ON the newline
        // ending the current paragraph; backward from a paragraph start
        // steps one separator at a time (chained, like select).
        let nl1 = text.range(of: "\n")!.lowerBound.utf16Offset(in: text)
        let thirdStart = text.range(of: "Third")!.lowerBound.utf16Offset(in: text)
        XCTAssertEqual(
            MoveDeleteActions.moveCaret(text: text, caret: 10, dist: .paragraph, dir: .forward),
            nl1)
        XCTAssertEqual(
            MoveDeleteActions.moveCaret(text: text, caret: thirdStart, dist: .paragraph, dir: .backward),
            thirdStart - 1)
    }

    func testMoveSentenceForwardFromStart() {
        // From 0, forward sentence lands after ". " following the first sentence.
        let secondStart = text.range(of: "Second")!.lowerBound.utf16Offset(in: text)
        XCTAssertEqual(
            MoveDeleteActions.moveCaret(text: text, caret: 0, dist: .sentence, dir: .forward),
            secondStart)
    }

    func testMoveSentenceBackwardChainsFromJustAfterTerminator() {
        // Caret just after ". " (at the S of Second) — backward goes to 0,
        // not to the same spot.
        let secondStart = text.range(of: "Second")!.lowerBound.utf16Offset(in: text)
        XCTAssertEqual(
            MoveDeleteActions.moveCaret(text: text, caret: secondStart, dist: .sentence, dir: .backward),
            0)
    }

    func testMoveAllClampsToDocumentEdges() {
        XCTAssertEqual(MoveDeleteActions.moveCaret(text: text, caret: 10, dist: .all, dir: .backward), 0)
        XCTAssertEqual(MoveDeleteActions.moveCaret(text: text, caret: 10, dist: .all, dir: .forward), text.utf16.count)
    }

    func testMoveClampsAtEdges() {
        XCTAssertEqual(MoveDeleteActions.moveCaret(text: text, caret: 0, dist: .char, dir: .backward), 0)
        XCTAssertEqual(MoveDeleteActions.moveCaret(text: text, caret: text.utf16.count, dist: .char, dir: .forward), text.utf16.count)
    }

    // MARK: - Editor deletion

    func testDeleteCharBackward() {
        let (result, caret) = MoveDeleteActions.deleteRange(text: "Hello", caret: 5, dist: .char, dir: .backward)
        XCTAssertEqual(result, "Hell")
        XCTAssertEqual(caret, 4)
    }

    func testDeleteCharForward() {
        let (result, caret) = MoveDeleteActions.deleteRange(text: "Hello", caret: 0, dist: .char, dir: .forward)
        XCTAssertEqual(result, "ello")
        XCTAssertEqual(caret, 0)
    }

    func testDeleteWordBackward() {
        let (result, caret) = MoveDeleteActions.deleteRange(text: "Hello world", caret: 11, dist: .word, dir: .backward)
        XCTAssertEqual(result, "Hello ")
        XCTAssertEqual(caret, 6)
    }

    func testDeleteSentenceBackward() {
        // Caret at the end of the second sentence: the whole sentence is
        // behind the caret and the range [sentenceStart, caret) is removed.
        let caret33 = 33 // end of "here."
        let (result, caret) = MoveDeleteActions.deleteRange(text: text, caret: caret33, dist: .sentence, dir: .backward)
        XCTAssertTrue(result.hasPrefix("Hello world."))
        XCTAssertFalse(result.contains("Second sentence"))
        XCTAssertEqual(caret, "Hello world. ".utf16.count)
    }

    func testDeleteAllClearsBothDirections() {
        for dir in [SelectDirection.backward, .forward] {
            let (result, caret) = MoveDeleteActions.deleteRange(text: "Hello", caret: 2, dist: .all, dir: dir)
            XCTAssertEqual(result, "")
            XCTAssertEqual(caret, 0)
        }
    }

    func testDeleteAtDocumentEdgeIsNoOp() {
        // backward at caret 0 / forward at end — nothing to remove
        let (resultBack, caretBack) = MoveDeleteActions.deleteRange(text: "Hello", caret: 0, dist: .char, dir: .backward)
        XCTAssertEqual(resultBack, "Hello")
        XCTAssertEqual(caretBack, 0)
        let (resultFwd, caretFwd) = MoveDeleteActions.deleteRange(text: "Hello", caret: 5, dist: .char, dir: .forward)
        XCTAssertEqual(resultFwd, "Hello")
        XCTAssertEqual(caretFwd, 5)
    }

    func testDeleteEmptyTextIsNoOp() {
        let (result, caret) = MoveDeleteActions.deleteRange(text: "", caret: 0, dist: .word, dir: .backward)
        XCTAssertEqual(result, "")
        XCTAssertEqual(caret, 0)
    }

    // MARK: - Surrogate pairs

    func testDeleteRespectsSurrogatePairs() {
        // 😀 is a surrogate pair (2 UTF-16 units)
        let s = "a😀b"
        let units = Array(s.utf16)
        XCTAssertEqual(units.count, 4)
        // caret after the emoji (index 3): backward char delete removes both units
        let (result, caret) = MoveDeleteActions.deleteRange(text: s, caret: 3, dist: .char, dir: .backward)
        XCTAssertEqual(result, "ab")
        XCTAssertEqual(caret, 1)
        // caret before the emoji (index 1): forward char delete removes both units
        let (result2, caret2) = MoveDeleteActions.deleteRange(text: s, caret: 1, dist: .char, dir: .forward)
        XCTAssertEqual(result2, "ab")
        XCTAssertEqual(caret2, 1)
    }

    func testMoveCharRespectsSurrogatePairs() {
        let s = "a😀b"
        XCTAssertEqual(MoveDeleteActions.moveCaret(text: s, caret: 1, dist: .char, dir: .forward), 3)
        XCTAssertEqual(MoveDeleteActions.moveCaret(text: s, caret: 3, dist: .char, dir: .backward), 1)
    }

    // MARK: - Direct-mode chord mapping

    func testDeleteAllReturnsNilCompositeChord() {
        XCTAssertNil(MoveDeleteActions.deleteKeystroke(dist: .all, dir: .backward))
        XCTAssertNil(MoveDeleteActions.deleteKeystroke(dist: .all, dir: .forward))
    }

    func testMoveKeystrokesAreMovementChordsWithoutShift() {
        for dist in [MoveDeleteDistance.char, .word, .sentence, .paragraph, .all] {
            for dir in [SelectDirection.backward, .forward] {
                let ks = MoveDeleteActions.moveKeystroke(dist: dist, dir: dir)
                XCTAssertFalse(ks.shift, "\(dist) \(dir)")
            }
        }
    }

    func testDeleteKeystrokeCharUsesDeleteAndForwardDelete() {
        XCTAssertEqual(MoveDeleteActions.deleteKeystroke(dist: .char, dir: .backward)?.keyCode, 51)
        XCTAssertEqual(MoveDeleteActions.deleteKeystroke(dist: .char, dir: .forward)?.keyCode, 117)
    }
}

private extension UInt16 {
    init(ASCII character: UInt16) { self = character }
}
