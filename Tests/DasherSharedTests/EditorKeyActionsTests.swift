import XCTest
@testable import DasherShared

final class EditorKeyActionsTests: XCTestCase {

    private let emoji = "😀" // U+1F600 (2 UTF-16 code units: 0xD83D, 0xDE00)

    func testBackspaceDeletesOneBMPCharacter() {
        let (text, caret) = EditorKeyActions.backspace(text: "abc", caretUTF16: 3)
        XCTAssertEqual(text, "ab")
        XCTAssertEqual(caret, 2)
    }

    func testBackspaceDeletesWholeSurrogatePair() {
        let (text, caret) = EditorKeyActions.backspace(text: "a\(emoji)b", caretUTF16: 3)
        XCTAssertEqual(text, "ab")
        XCTAssertEqual(caret, 1)
    }

    func testBackspaceAtStartIsNoOp() {
        let (text, caret) = EditorKeyActions.backspace(text: "abc", caretUTF16: 0)
        XCTAssertEqual(text, "abc")
        XCTAssertEqual(caret, 0)
    }

    func testBackspaceOnEmptyTextIsNoOp() {
        let (text, caret) = EditorKeyActions.backspace(text: "", caretUTF16: 0)
        XCTAssertEqual(text, "")
        XCTAssertEqual(caret, 0)
    }

    func testBackspaceClampsOutOfRangeCaret() {
        let (text, caret) = EditorKeyActions.backspace(text: "ab", caretUTF16: 99)
        XCTAssertEqual(text, "a")
        XCTAssertEqual(caret, 1)
    }

    func testBackspaceWithMidPairCaretDeletesWholePair() {
        // If a retained caret index sits between the high and low surrogate halves,
        // deleting one unit would leave an orphaned half-surrogate (U+FFFD corruption).
        let (text, caret) = EditorKeyActions.backspace(text: emoji, caretUTF16: 1)
        XCTAssertEqual(text, "")
        XCTAssertEqual(caret, 0)
    }

    func testBackspaceDeletesActiveSelectionAndExpandsStraddledSurrogates() {
        let (text, caret) = EditorKeyActions.backspace(text: "hello world", selectionStart: 2, selectionEnd: 9)
        XCTAssertEqual(text, "held")
        XCTAssertEqual(caret, 2)

        // Selection endpoints straddling surrogate pairs at both ends:
        // "a😀b😀c" -> indices: a=0, emoji1=(1,2), b=3, emoji2=(4,5), c=6
        let sample = "a\(emoji)b\(emoji)c"
        let (text2, caret2) = EditorKeyActions.backspace(text: sample, selectionStart: 2, selectionEnd: 5)
        XCTAssertEqual(text2, "ac")
        XCTAssertEqual(caret2, 1)
    }

    func testMoveCaretLeftSkipsOverLowSurrogate() {
        let text = "a\(emoji)b" // a=0, high=1, low=2, b=3
        XCTAssertEqual(EditorKeyActions.moveCaret(text: text, caretUTF16: 3, delta: -1), 1)
    }

    func testMoveCaretRightSkipsOverLowSurrogate() {
        let text = "a\(emoji)b" // a=0, high=1, low=2, b=3
        XCTAssertEqual(EditorKeyActions.moveCaret(text: text, caretUTF16: 1, delta: 1), 3)
    }

    func testMoveCaretBMPMovesOneUnit() {
        XCTAssertEqual(EditorKeyActions.moveCaret(text: "abc", caretUTF16: 3, delta: -1), 2)
        XCTAssertEqual(EditorKeyActions.moveCaret(text: "abc", caretUTF16: 2, delta: 1), 3)
    }

    func testMoveCaretClampsAtBothEnds() {
        XCTAssertEqual(EditorKeyActions.moveCaret(text: "abc", caretUTF16: 0, delta: -1), 0)
        XCTAssertEqual(EditorKeyActions.moveCaret(text: "abc", caretUTF16: 3, delta: 1), 3)
    }

    func testMoveCaretOnEmptyTextReturnsZero() {
        XCTAssertEqual(EditorKeyActions.moveCaret(text: "", caretUTF16: 5, delta: 1), 0)
    }

    func testMoveCaretCollapsesActiveSelectionSafely() {
        let sample = "a\(emoji)b" // a=0, high=1, low=2, b=3
        // Left collapses to selection start (snapping left of low surrogate if mid-pair)
        XCTAssertEqual(EditorKeyActions.moveCaret(text: sample, selectionStart: 2, selectionEnd: 4, delta: -1), 1)
        // Right collapses to selection end (snapping right of low surrogate if mid-pair)
        XCTAssertEqual(EditorKeyActions.moveCaret(text: sample, selectionStart: 0, selectionEnd: 2, delta: 1), 3)
    }

    func testConsecutiveEmojisBackspaceAndMoveCaret() {
        let pair = "\(emoji)\(emoji)" // indices: emoji1=(0,1), emoji2=(2,3), len=4
        // Backspace at boundary between two emojis (caret=2) deletes only the first emoji
        let (afterFirst, caret1) = EditorKeyActions.backspace(text: pair, caretUTF16: 2)
        XCTAssertEqual(afterFirst, emoji)
        XCTAssertEqual(caret1, 0)

        // Backspace mid-second-emoji (caret=3) deletes the second emoji cleanly
        let (afterSecond, caret2) = EditorKeyActions.backspace(text: pair, caretUTF16: 3)
        XCTAssertEqual(afterSecond, emoji)
        XCTAssertEqual(caret2, 2)

        // Selection straddling both emojis [1, 3) expands to [0, 4) and deletes both
        let (afterBoth, caret3) = EditorKeyActions.backspace(text: pair, selectionStart: 1, selectionEnd: 3)
        XCTAssertEqual(afterBoth, "")
        XCTAssertEqual(caret3, 0)

        // Move caret across consecutive emojis
        XCTAssertEqual(EditorKeyActions.moveCaret(text: pair, caretUTF16: 0, delta: 1), 2)
        XCTAssertEqual(EditorKeyActions.moveCaret(text: pair, caretUTF16: 2, delta: 1), 4)
        XCTAssertEqual(EditorKeyActions.moveCaret(text: pair, caretUTF16: 4, delta: -1), 2)
        XCTAssertEqual(EditorKeyActions.moveCaret(text: pair, caretUTF16: 2, delta: -1), 0)
    }

    func testInsertAtCaretAndReplaceSelectionSurrogateSafe() {
        let (insertedMid, caretMid) = EditorKeyActions.insert(
            text: "X",
            into: "ab",
            selectionStart: 1,
            selectionEnd: 1
        )
        XCTAssertEqual(insertedMid, "aXb")
        XCTAssertEqual(caretMid, 2)

        // Replace selection straddling surrogate pair boundaries
        let sample = "a\(emoji)b" // a=0, emoji=(1,2), b=3
        let (replaced, caretReplaced) = EditorKeyActions.insert(
            text: "YZ",
            into: sample,
            selectionStart: 2,
            selectionEnd: 3
        )
        XCTAssertEqual(replaced, "aYZb")
        XCTAssertEqual(caretReplaced, 3)
    }

    func testEditorSeedPolicySurrogateBoundarySafety() {
        // String of length 5 UTF-16 units: "a😀bc" -> a=0, high=1, low=2, b=3, c=4
        // If maxUnits = 3, naive dropCount = 5 - 3 = 2 would slice at index 2 (low surrogate!).
        // Surrogate-safe slicing advances dropCount to 3 so the window is "bc" (no U+FFFD).
        let sample = "a\(emoji)bc"
        let (windowed, newCaret) = EditorSeedPolicy.apply(to: sample, caretUTF16: 5, maxUnits: 3)
        XCTAssertEqual(windowed, "bc")
        XCTAssertEqual(newCaret, 2)
        XCTAssertFalse(windowed.contains("\u{FFFD}"))
    }
}
