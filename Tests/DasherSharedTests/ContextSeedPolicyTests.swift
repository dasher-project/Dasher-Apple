import XCTest
@testable import DasherShared

final class ContextSeedPolicyTests: XCTestCase {

    // MARK: - SentenceWindow Tests (ported from SentenceWindowTests.cs)

    func testMiddleOfSentenceTrimsToSentenceStart() {
        let (text, caret) = SentenceWindow.trim("Hello John. How are you to|day", caretUTF16: 26)
        XCTAssertEqual(text, "How are you to")
        XCTAssertEqual(caret, text.utf16.count)
    }

    func testCaretAtSentenceBoundaryTrimsToEmpty() {
        let (text, caret) = SentenceWindow.trim("Hello John.|", caretUTF16: 11)
        XCTAssertEqual(text, "")
        XCTAssertEqual(caret, 0)
    }

    func testNoBoundaryWithinLookbackTrimsToMax() {
        let longRun = String(repeating: "a", count: 500) + " tail"
        let (text, caret) = SentenceWindow.trim(longRun, caretUTF16: longRun.utf16.count)
        XCTAssertEqual(text.utf16.count, SentenceWindow.maxLookback)
        XCTAssertTrue(text.hasSuffix("tail"))
        XCTAssertEqual(caret, text.utf16.count)
    }

    func testNewlineSemicolonColonAndConsecutiveBoundaries() {
        let (t1, _) = SentenceWindow.trim("First line\nSecond line|", caretUTF16: 22)
        XCTAssertEqual(t1, "Second line")

        let (t2, _) = SentenceWindow.trim("one; two|", caretUTF16: 8)
        XCTAssertEqual(t2, "two")

        let (t3, _) = SentenceWindow.trim("one: two|", caretUTF16: 8)
        XCTAssertEqual(t3, "two")

        let (t4, _) = SentenceWindow.trim("Wow!!! Next|", caretUTF16: 11)
        XCTAssertEqual(t4, "Next")
    }

    func testEmptyAndStartAndClampedCaret() {
        let (e1, c1) = SentenceWindow.trim("", caretUTF16: 0)
        XCTAssertEqual(e1, "")
        XCTAssertEqual(c1, 0)

        let (e2, c2) = SentenceWindow.trim("Hello world", caretUTF16: 0)
        XCTAssertEqual(e2, "")
        XCTAssertEqual(c2, 0)

        let (e3, c3) = SentenceWindow.trim("Hello", caretUTF16: 999)
        XCTAssertEqual(e3, "Hello")
        XCTAssertEqual(c3, 5)
    }

    func testSurrogatePairAtLookbackCapAndCaretDoesNotSplit() {
        let emoji = "😀" // 2 UTF-16 units
        let text = String(repeating: "a", count: SentenceWindow.maxLookback - 1) + emoji + " tail"
        let (trimmed, _) = SentenceWindow.trim(text, caretUTF16: text.utf16.count)
        let firstUnit = trimmed.utf16.first!
        XCTAssertFalse((0xDC00...0xDFFF).contains(firstUnit), "Must not start with an orphan low surrogate")
        XCTAssertFalse(trimmed.contains("\u{FFFD}"))

        // Mid-pair caret at end of window steps back so no orphan high surrogate remains
        let endPair = "abc\(emoji)" // a=0, b=1, c=2, high=3, low=4
        let (trimmedEnd, caretEnd) = SentenceWindow.trim(endPair, caretUTF16: 4)
        XCTAssertEqual(trimmedEnd, "abc")
        XCTAssertEqual(caretEnd, 3)
    }

    func testTypingFlowAndBoundaryLockstep() {
        let target1 = "Hello John. I wanted to ask."
        let (sentence1, _) = SentenceWindow.trim(target1, caretUTF16: target1.utf16.count)
        let engine1 = "I wanted to ask."
        let (engineSentence1, _) = SentenceWindow.trim(engine1, caretUTF16: engine1.utf16.count)
        XCTAssertEqual(sentence1, "")
        XCTAssertEqual(engineSentence1, "")

        let engine2 = "I wanted to ask. N"
        let target2 = "Hello John. I wanted to ask. N"
        XCTAssertEqual(
            SentenceWindow.trim(engine2, caretUTF16: engine2.utf16.count).text,
            SentenceWindow.trim(target2, caretUTF16: target2.utf16.count).text
        )

        let engineCRLF = "hello world\nNew sent"
        let targetCRLF = "hello world\r\nNew sent"
        XCTAssertEqual(
            SentenceWindow.trim(engineCRLF, caretUTF16: engineCRLF.utf16.count).text,
            SentenceWindow.trim(targetCRLF, caretUTF16: targetCRLF.utf16.count).text
        )
    }

    // MARK: - ContextSeedPolicy Tests (ported from ContextSeedPolicyTests.cs)

    func testSentenceMatchWithBoundarySpanningBufferSkips() {
        let d = ContextSeedPolicy.decide(
            engineFullText: "Hello world. The",
            targetFullText: "Hello world. The",
            targetCaretUTF16: 16
        )
        XCTAssertEqual(d.action, .skip)
    }

    func testMidSentenceMatchSkips() {
        let d = ContextSeedPolicy.decide(
            engineFullText: "Hello wor",
            targetFullText: "Hello wor",
            targetCaretUTF16: 9
        )
        XCTAssertEqual(d.action, .skip)
    }

    func testStaleReadLaggingAcrossSentenceBoundarySkips() {
        let d = ContextSeedPolicy.decide(
            engineFullText: "Hello world.",
            targetFullText: "Hello world",
            targetCaretUTF16: 11
        )
        XCTAssertEqual(d.action, .skip)
    }

    func testStaleReadWithEarlierTargetTextSkips() {
        let d = ContextSeedPolicy.decide(
            engineFullText: "Hello world.",
            targetFullText: "Earlier sentence. Hello world",
            targetCaretUTF16: 30
        )
        XCTAssertEqual(d.action, .skip)
    }

    func testUnrelatedNewFieldIsNotReadAsLag() {
        let d = ContextSeedPolicy.decide(
            engineFullText: "a test.",
            targetFullText: "Banana",
            targetCaretUTF16: 6
        )
        XCTAssertEqual(d.action, .seed)
        XCTAssertEqual(d.text, "Banana")
    }

    func testShortSentencePeriodLagSkips() {
        let d = ContextSeedPolicy.decide(
            engineFullText: "Hello.",
            targetFullText: "Hello",
            targetCaretUTF16: 5
        )
        XCTAssertEqual(d.action, .skip)
    }

    func testLagComparisonAnchorsAtCaretNotReadEnd() {
        let d = ContextSeedPolicy.decide(
            engineFullText: "Hello world.",
            targetFullText: "Hello world Remaining text",
            targetCaretUTF16: 11
        )
        XCTAssertEqual(d.action, .skip)
    }

    func testMidDocumentCRLFReadLagSkips() {
        let d = ContextSeedPolicy.decide(
            engineFullText: "Hello.",
            targetFullText: "Earlier\r\nHello Remaining",
            targetCaretUTF16: 14
        )
        XCTAssertEqual(d.action, .skip)
    }

    func testStaleReadWithEarlierTargetTextCatchesUpToSkip() {
        let d = ContextSeedPolicy.decide(
            engineFullText: "Hello world.",
            targetFullText: "Earlier sentence. Hello world.",
            targetCaretUTF16: 31
        )
        XCTAssertEqual(d.action, .skip)
    }

    func testStaleReadLaggingNewlineCrossesCRLFDifference() {
        let d = ContextSeedPolicy.decide(
            engineFullText: "Hello world.\nThe",
            targetFullText: "Hello world.\r\n",
            targetCaretUTF16: 14
        )
        XCTAssertEqual(d.action, .skip)
    }

    func testLagAtCapSkipsAndOnePastCapReSeeds() {
        let target = "Hello world."
        let engineAtCap = target + String(repeating: "x", count: ContextSeedPolicy.maxLagChars)
        let d1 = ContextSeedPolicy.decide(
            engineFullText: engineAtCap,
            targetFullText: target,
            targetCaretUTF16: target.utf16.count
        )
        XCTAssertEqual(d1.action, .skip)

        let enginePastCap = target + String(repeating: "x", count: ContextSeedPolicy.maxLagChars + 1)
        let d2 = ContextSeedPolicy.decide(
            engineFullText: enginePastCap,
            targetFullText: target,
            targetCaretUTF16: target.utf16.count
        )
        XCTAssertEqual(d2.action, .seed)
    }

    func testDivergentTextsWithLagWithinCapStillReSeed() {
        let engine = "Hello world. " + String(repeating: "x", count: ContextSeedPolicy.maxLagChars + 5)
        let d = ContextSeedPolicy.decide(
            engineFullText: engine,
            targetFullText: "A completely different target",
            targetCaretUTF16: 29
        )
        XCTAssertEqual(d.action, .seed)
    }

    func testEmptySentenceAtBoundaryAndEngineAheadWithinSentenceSkip() {
        let d1 = ContextSeedPolicy.decide(
            engineFullText: "Hello world.",
            targetFullText: "Hello world.",
            targetCaretUTF16: 12
        )
        XCTAssertEqual(d1.action, .skip)

        let d2 = ContextSeedPolicy.decide(
            engineFullText: "Xyz. The quick",
            targetFullText: "Abc. The",
            targetCaretUTF16: 8
        )
        XCTAssertEqual(d2.action, .skip)
    }

    func testTrailingWhitespaceAndInvisibleCharsSkip() {
        let d1 = ContextSeedPolicy.decide(
            engineFullText: "Hello world. The",
            targetFullText: "Hello world. The ",
            targetCaretUTF16: 17
        )
        XCTAssertEqual(d1.action, .skip)

        let d2 = ContextSeedPolicy.decide(
            engineFullText: "Hi heide I",
            targetFullText: "Hi\u{00A0}heide I",
            targetCaretUTF16: 10
        )
        XCTAssertEqual(d2.action, .skip)
    }

    func testGenuineContextChangesSeed() {
        let d1 = ContextSeedPolicy.decide(
            engineFullText: "Hello world. The",
            targetFullText: "A different sentence entirely",
            targetCaretUTF16: 29
        )
        XCTAssertEqual(d1.action, .seed)
        XCTAssertEqual(d1.text, "A different sentence entirely")
        XCTAssertEqual(d1.caretUTF16, 29)

        let d2 = ContextSeedPolicy.decide(
            engineFullText: "old context",
            targetFullText: "",
            targetCaretUTF16: 0
        )
        XCTAssertEqual(d2.action, .seed)
        XCTAssertEqual(d2.text, "")
        XCTAssertEqual(d2.caretUTF16, 0)

        let d3 = ContextSeedPolicy.decide(
            engineFullText: "Hello world. The",
            targetFullText: "Hello world. The quick brown",
            targetCaretUTF16: 28
        )
        XCTAssertEqual(d3.action, .seed)
        XCTAssertEqual(d3.text, "The quick brown")
        XCTAssertEqual(d3.caretUTF16, 15)

        let d4 = ContextSeedPolicy.decide(
            engineFullText: "",
            targetFullText: "H\u{00A0}i there\u{200B}",
            targetCaretUTF16: 11
        )
        XCTAssertEqual(d4.action, .seed)
        XCTAssertEqual(d4.text, "H i there")
    }

    func testRepeatedIdenticalSentencesAndCaretClickedBackToBoundary() {
        let d1 = ContextSeedPolicy.decide(
            engineFullText: "Hi. Hi.",
            targetFullText: "Hi. Hi.",
            targetCaretUTF16: 4
        )
        XCTAssertEqual(d1.action, .skip)

        let d2 = ContextSeedPolicy.decide(
            engineFullText: "Hello world. The",
            targetFullText: "Hello world. The",
            targetCaretUTF16: 13
        )
        XCTAssertEqual(d2.action, .seed)
        XCTAssertEqual(d2.text, "")
        XCTAssertEqual(d2.caretUTF16, 0)
    }

    func testParagraphMarkMirrorAndExternalTextAfterParagraph() {
        let d1 = ContextSeedPolicy.decide(
            engineFullText: "Hello my name is Willy!\n",
            targetFullText: "Hello my name is Willy!\r\n",
            targetCaretUTF16: 23
        )
        XCTAssertEqual(d1.action, .skip)

        let d2 = ContextSeedPolicy.decide(
            engineFullText: "Hello my name is Willy!\n",
            targetFullText: "Hello my name is Willy!",
            targetCaretUTF16: 23
        )
        XCTAssertEqual(d2.action, .skip)

        let before = ContextSeedPolicy.decide(
            engineFullText: "Hello my name is Willy\n",
            targetFullText: "Earlier text. Hello my name is Willy\n",
            targetCaretUTF16: 36
        )
        XCTAssertEqual(before.action, .skip)

        let after = ContextSeedPolicy.decide(
            engineFullText: "Hello my name is Willy\n",
            targetFullText: "Earlier text. Hello my name is Willy\n",
            targetCaretUTF16: 37
        )
        XCTAssertEqual(after.action, .skip)

        let external = ContextSeedPolicy.decide(
            engineFullText: "Hello my name is Willy!\n",
            targetFullText: "Hello my name is Willy!\r\nHello my &nail,",
            targetCaretUTF16: 34
        )
        XCTAssertEqual(external.action, .seed)

        let bareNewline = ContextSeedPolicy.decide(
            engineFullText: "\n",
            targetFullText: "Banana",
            targetCaretUTF16: 6
        )
        XCTAssertEqual(bareNewline.action, .seed)
    }

    func testMidSurrogateCaretSnapsCleanlyInDecide() {
        // "Hi 😀" is 5 UTF-16 code units ("Hi " = 3, "😀" = 2).
        // If targetCaretUTF16 = 4 (mid-emoji low surrogate) while engine has "Hi 😀",
        // snapping clampedCaret back to 3 makes targetToCaret = "Hi " (lagging by 2 units),
        // which cleanly skips without producing U+FFFD replacement characters.
        let decision = ContextSeedPolicy.decide(
            engineFullText: "Hi 😀",
            targetFullText: "Hi 😀",
            targetCaretUTF16: 4
        )
        XCTAssertEqual(decision.action, .skip)
        XCTAssertFalse(decision.text.contains("\u{FFFD}"))
    }
}
