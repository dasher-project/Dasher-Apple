import XCTest
@testable import DasherShared

final class SelectActionsTests: XCTestCase {

    // MARK: - Parse

    func testParseAcceptsAllDocumentedPairs() {
        let pairs: [(String, String, SelectDistance, SelectDirection)] = [
            ("char", "yes", .char, .forward),
            ("char", "no", .char, .backward),
            ("word", "yes", .word, .forward),
            ("word", "no", .word, .backward),
            ("paragraph", "yes", .paragraph, .forward),
            ("paragraph", "no", .paragraph, .backward),
            ("all", "yes", .all, .forward),
            ("all", "no", .all, .backward),
        ]
        for (d, f, expectedDist, expectedDir) in pairs {
            let parsed = SelectActions.parse(dist: d, forward: f)
            XCTAssertNotNil(parsed, "Expected (\(d), \(f)) to parse")
            XCTAssertEqual(parsed?.distance, expectedDist)
            XCTAssertEqual(parsed?.direction, expectedDir)
        }
    }

    func testParseRejectsUnknownAndCaseMismatchedValues() {
        XCTAssertNil(SelectActions.parse(dist: "sentence", forward: "yes"))
        XCTAssertNil(SelectActions.parse(dist: "char", forward: "maybe"))
        XCTAssertNil(SelectActions.parse(dist: nil, forward: "yes"))
        XCTAssertNil(SelectActions.parse(dist: "char", forward: nil))
        XCTAssertNil(SelectActions.parse(dist: "Char", forward: "yes"))
        XCTAssertNil(SelectActions.parse(dist: "char", forward: "Yes"))
    }

    // MARK: - Keystroke (Apple RFC 0021 table)

    func testKeystrokeCharIsShiftArrow() {
        let back = SelectActions.keystroke(dist: .char, dir: .backward)
        XCTAssertTrue(back.shift)
        XCTAssertFalse(back.option)
        XCTAssertFalse(back.command)
        XCTAssertEqual(back.keyCode, SelectActions.keyCodeLeftArrow)

        let fwd = SelectActions.keystroke(dist: .char, dir: .forward)
        XCTAssertTrue(fwd.shift)
        XCTAssertFalse(fwd.option)
        XCTAssertFalse(fwd.command)
        XCTAssertEqual(fwd.keyCode, SelectActions.keyCodeRightArrow)
    }

    func testKeystrokeWordIsShiftOptionArrow() {
        let back = SelectActions.keystroke(dist: .word, dir: .backward)
        XCTAssertTrue(back.shift)
        XCTAssertTrue(back.option)
        XCTAssertFalse(back.command)
        XCTAssertEqual(back.keyCode, SelectActions.keyCodeLeftArrow)

        let fwd = SelectActions.keystroke(dist: .word, dir: .forward)
        XCTAssertTrue(fwd.shift)
        XCTAssertTrue(fwd.option)
        XCTAssertFalse(fwd.command)
        XCTAssertEqual(fwd.keyCode, SelectActions.keyCodeRightArrow)
    }

    func testKeystrokeParagraphIsShiftOptionUpDownNeverCommand() {
        // RFC 0021 safety requirement: paragraph selection on macOS MUST use
        // Shift+Opt+Up/Down (never Shift+Cmd+Up/Down which selects to document ends).
        let back = SelectActions.keystroke(dist: .paragraph, dir: .backward)
        XCTAssertTrue(back.shift)
        XCTAssertTrue(back.option)
        XCTAssertFalse(back.command)
        XCTAssertEqual(back.keyCode, SelectActions.keyCodeUpArrow)

        let fwd = SelectActions.keystroke(dist: .paragraph, dir: .forward)
        XCTAssertTrue(fwd.shift)
        XCTAssertTrue(fwd.option)
        XCTAssertFalse(fwd.command)
        XCTAssertEqual(fwd.keyCode, SelectActions.keyCodeDownArrow)
    }

    func testKeystrokeAllIsCommandA() {
        let k = SelectActions.keystroke(dist: .all, dir: .forward)
        XCTAssertFalse(k.shift)
        XCTAssertFalse(k.option)
        XCTAssertTrue(k.command)
        XCTAssertEqual(k.keyCode, SelectActions.keyCodeA)
    }

    // MARK: - EditorBounds

    func testColdStartCharForwardSelectsOneChar() {
        let (s, e) = SelectActions.editorBounds(
            text: "hello world",
            selectionStart: 5,
            selectionEnd: 5,
            dist: .char,
            dir: .forward,
            hadSelection: false
        )
        XCTAssertEqual(s, 5)
        XCTAssertEqual(e, 6)
    }

    func testExtendActiveEndBackwardCollapsesToAnchor() {
        let text = "hello world"
        let (s1, e1) = SelectActions.editorBounds(
            text: text,
            selectionStart: 5,
            selectionEnd: 5,
            dist: .char,
            dir: .forward,
            hadSelection: false
        )
        XCTAssertEqual(s1, 5)
        XCTAssertEqual(e1, 6)

        let (s2, e2) = SelectActions.editorBounds(
            text: text,
            selectionStart: s1,
            selectionEnd: e1,
            dist: .char,
            dir: .backward,
            hadSelection: true
        )
        XCTAssertEqual(s2, 5)
        XCTAssertEqual(e2, 5)
    }

    func testChainedBackwardSelectionAndShrinkWithNSRangeAnchorTracking() {
        // NSRange always has start <= end; anchorUTF16 preserves which end is the anchor
        // when extending backward from caret=5 -> [4,5] -> [3,5] and shrinking -> [4,5].
        let text = "hello world"
        let r1 = SelectActions.editorBounds(
            text: text,
            selectionStart: 5,
            selectionEnd: 5,
            dist: .char,
            dir: .backward,
            hadSelection: false,
            anchorUTF16: nil
        )
        XCTAssertEqual(r1.start, 4)
        XCTAssertEqual(r1.end, 5)
        XCTAssertEqual(r1.anchorUTF16, 5)

        let r2 = SelectActions.editorBounds(
            text: text,
            selectionStart: r1.start,
            selectionEnd: r1.end,
            dist: .char,
            dir: .backward,
            hadSelection: true,
            anchorUTF16: r1.anchorUTF16
        )
        XCTAssertEqual(r2.start, 3)
        XCTAssertEqual(r2.end, 5)
        XCTAssertEqual(r2.anchorUTF16, 5)

        // Now shrink forward by 1 char -> [4, 5]
        let r3 = SelectActions.editorBounds(
            text: text,
            selectionStart: r2.start,
            selectionEnd: r2.end,
            dist: .char,
            dir: .forward,
            hadSelection: true,
            anchorUTF16: r2.anchorUTF16
        )
        XCTAssertEqual(r3.start, 4)
        XCTAssertEqual(r3.end, 5)
        XCTAssertEqual(r3.anchorUTF16, 5)
    }

    func testEmptyTextIsSafeForAllDistances() {
        let distances: [SelectDistance] = [.char, .word, .paragraph, .all]
        let directions: [SelectDirection] = [.backward, .forward]
        for dist in distances {
            for dir in directions {
                let (s, e) = SelectActions.editorBounds(
                    text: "",
                    selectionStart: 0,
                    selectionEnd: 0,
                    dist: dist,
                    dir: dir,
                    hadSelection: false
                )
                XCTAssertEqual(s, 0)
                XCTAssertEqual(e, 0)
            }
        }
    }

    func testCharBackwardFromZeroAndForwardFromEndClamp() {
        let b = SelectActions.editorBounds(
            text: "abc", selectionStart: 0, selectionEnd: 0, dist: .char, dir: .backward, hadSelection: false
        )
        XCTAssertEqual(b.start, 0)
        XCTAssertEqual(b.end, 0)

        let f = SelectActions.editorBounds(
            text: "abc", selectionStart: 3, selectionEnd: 3, dist: .char, dir: .forward, hadSelection: false
        )
        XCTAssertEqual(f.start, 3)
        XCTAssertEqual(f.end, 3)
    }

    func testWordForwardAndBackward() {
        let (s1, e1) = SelectActions.editorBounds(
            text: "hello world", selectionStart: 2, selectionEnd: 2, dist: .word, dir: .forward, hadSelection: false
        )
        XCTAssertEqual(s1, 2)
        XCTAssertEqual(e1, 6)

        let (s2, e2) = SelectActions.editorBounds(
            text: "hello world", selectionStart: 8, selectionEnd: 8, dist: .word, dir: .backward, hadSelection: false
        )
        XCTAssertEqual(s2, 6)
        XCTAssertEqual(e2, 8)

        let (s3, e3) = SelectActions.editorBounds(
            text: "one", selectionStart: 3, selectionEnd: 3, dist: .word, dir: .forward, hadSelection: false
        )
        XCTAssertEqual(s3, 3)
        XCTAssertEqual(e3, 3)
    }

    func testCharSelectionIsSurrogateSafe() {
        let emoji = "😀" // 2 UTF-16 code units
        let text = "a\(emoji)b"
        let (s1, e1) = SelectActions.editorBounds(
            text: text, selectionStart: 1, selectionEnd: 1, dist: .char, dir: .forward, hadSelection: false
        )
        XCTAssertEqual(s1, 1)
        XCTAssertEqual(e1, 3)

        let (s2, e2) = SelectActions.editorBounds(
            text: text, selectionStart: 3, selectionEnd: 3, dist: .char, dir: .backward, hadSelection: false
        )
        XCTAssertEqual(s2, 1)
        XCTAssertEqual(e2, 3)
    }

    func testParagraphBoundsLFAndCRLFAndChaining() {
        // Last paragraph selects to end
        let (sLast, eLast) = SelectActions.editorBounds(
            text: "first\nlast", selectionStart: 6, selectionEnd: 6, dist: .paragraph, dir: .forward, hadSelection: false
        )
        XCTAssertEqual(sLast, 6)
        XCTAssertEqual(eLast, 10)

        // CRLF: stops before \r
        let (sCRLF, eCRLF) = SelectActions.editorBounds(
            text: "first\r\nsecond", selectionStart: 2, selectionEnd: 2, dist: .paragraph, dir: .forward, hadSelection: false
        )
        XCTAssertEqual(sCRLF, 2)
        XCTAssertEqual(eCRLF, 5)

        // Chained forward paragraph on LF
        let lfText = "aaa\nbbb\nccc"
        let (lf1S, lf1E) = SelectActions.editorBounds(
            text: lfText, selectionStart: 1, selectionEnd: 1, dist: .paragraph, dir: .forward, hadSelection: false
        )
        XCTAssertEqual(lf1S, 1)
        XCTAssertEqual(lf1E, 3)
        let (lf2S, lf2E) = SelectActions.editorBounds(
            text: lfText, selectionStart: lf1S, selectionEnd: lf1E, dist: .paragraph, dir: .forward, hadSelection: true
        )
        XCTAssertEqual(lf2S, 1)
        XCTAssertEqual(lf2E, 7)

        // Chained forward paragraph on CRLF
        let crlfText = "aaa\r\nbbb\r\nccc"
        let (c1S, c1E) = SelectActions.editorBounds(
            text: crlfText, selectionStart: 1, selectionEnd: 1, dist: .paragraph, dir: .forward, hadSelection: false
        )
        XCTAssertEqual(c1S, 1)
        XCTAssertEqual(c1E, 3)
        let (c2S, c2E) = SelectActions.editorBounds(
            text: crlfText, selectionStart: c1S, selectionEnd: c1E, dist: .paragraph, dir: .forward, hadSelection: true
        )
        XCTAssertEqual(c2S, 1)
        XCTAssertEqual(c2E, 8)

        // Blank lines stepped one at a time
        let blankText = "a\n\nb\nc"
        let (b1S, b1E) = SelectActions.editorBounds(
            text: blankText, selectionStart: 1, selectionEnd: 1, dist: .paragraph, dir: .forward, hadSelection: false
        )
        XCTAssertEqual(b1S, 1)
        XCTAssertEqual(b1E, 2)
        let (b2S, b2E) = SelectActions.editorBounds(
            text: blankText, selectionStart: b1S, selectionEnd: b1E, dist: .paragraph, dir: .forward, hadSelection: true
        )
        XCTAssertEqual(b2S, 1)
        XCTAssertEqual(b2E, 4)

        // Paragraph backward to previous newline
        let multi = "first line\nsecond line\nthird"
        let (pBackS, pBackE) = SelectActions.editorBounds(
            text: multi, selectionStart: 15, selectionEnd: 15, dist: .paragraph, dir: .backward, hadSelection: false
        )
        XCTAssertEqual(pBackS, 11)
        XCTAssertEqual(pBackE, 15)

        // Chained backward paragraph on LF (must not stall at paragraph start)
        let b1 = SelectActions.editorBounds(
            text: lfText, selectionStart: 10, selectionEnd: 10, dist: .paragraph, dir: .backward, hadSelection: false, anchorUTF16: nil
        )
        XCTAssertEqual(b1.start, 8)
        XCTAssertEqual(b1.end, 10)
        XCTAssertEqual(b1.anchorUTF16, 10)

        let b2 = SelectActions.editorBounds(
            text: lfText, selectionStart: b1.start, selectionEnd: b1.end, dist: .paragraph, dir: .backward, hadSelection: true, anchorUTF16: b1.anchorUTF16
        )
        XCTAssertEqual(b2.start, 4)
        XCTAssertEqual(b2.end, 10)
        XCTAssertEqual(b2.anchorUTF16, 10)

        let b3 = SelectActions.editorBounds(
            text: lfText, selectionStart: b2.start, selectionEnd: b2.end, dist: .paragraph, dir: .backward, hadSelection: true, anchorUTF16: b2.anchorUTF16
        )
        XCTAssertEqual(b3.start, 0)
        XCTAssertEqual(b3.end, 10)

        // Chained backward paragraph on CRLF ("aaa\r\nbbb\r\nccc", len=13)
        let cb1 = SelectActions.editorBounds(
            text: crlfText, selectionStart: 12, selectionEnd: 12, dist: .paragraph, dir: .backward, hadSelection: false, anchorUTF16: nil
        )
        XCTAssertEqual(cb1.start, 10)
        XCTAssertEqual(cb1.end, 12)
        let cb2 = SelectActions.editorBounds(
            text: crlfText, selectionStart: cb1.start, selectionEnd: cb1.end, dist: .paragraph, dir: .backward, hadSelection: true, anchorUTF16: cb1.anchorUTF16
        )
        XCTAssertEqual(cb2.start, 5)
        XCTAssertEqual(cb2.end, 12)
        let cb3 = SelectActions.editorBounds(
            text: crlfText, selectionStart: cb2.start, selectionEnd: cb2.end, dist: .paragraph, dir: .backward, hadSelection: true, anchorUTF16: cb2.anchorUTF16
        )
        XCTAssertEqual(cb3.start, 0)
        XCTAssertEqual(cb3.end, 12)
    }

    func testAllSelectsEverything() {
        let (s1, e1) = SelectActions.editorBounds(
            text: "some text", selectionStart: 4, selectionEnd: 4, dist: .all, dir: .forward, hadSelection: false
        )
        XCTAssertEqual(s1, 0)
        XCTAssertEqual(e1, 9)

        let (s2, e2) = SelectActions.editorBounds(
            text: "some text", selectionStart: 4, selectionEnd: 4, dist: .all, dir: .backward, hadSelection: false
        )
        XCTAssertEqual(s2, 0)
        XCTAssertEqual(e2, 9)
    }

    // MARK: - Wiring Contract Tests (mirrors Windows SelectWiringContractTests)

    func testBridgesRegisterSelectBeforeScreenSizeInBootstrap() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for relPath in ["DasherMac/Sources/DasherBridge.swift", "DasherApp/Sources/DasherBridge.swift"] {
            let fileURL = repoRoot.appendingPathComponent(relPath)
            let src = try String(contentsOf: fileURL, encoding: .utf8)
            guard let bootstrapRange = src.range(of: "func bootstrap("),
                  let regRange = src.range(of: "dasher_register_action(newCtx, \"select\"", range: bootstrapRange.lowerBound..<src.endIndex),
                  let screenRange = src.range(of: "dasher_set_screen_size(newCtx", range: bootstrapRange.lowerBound..<src.endIndex) else {
                XCTFail("Missing bootstrap / dasher_register_action / dasher_set_screen_size in \(relPath)")
                continue
            }
            XCTAssertLessThan(
                regRange.lowerBound,
                screenRange.lowerBound,
                "\(relPath) must register 'select' before dasher_set_screen_size in bootstrap()"
            )
        }
    }

    func testViewModelsWireOnCustomActionBeforeBootstrap() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for relPath in ["DasherMac/Sources/MacDasherViewModel.swift", "DasherApp/Sources/DasherViewModel.swift"] {
            let fileURL = repoRoot.appendingPathComponent(relPath)
            let src = try String(contentsOf: fileURL, encoding: .utf8)
            guard let wireRange = src.range(of: "bridge.onCustomAction ="),
                  let bootRange = src.range(of: "await bridge.bootstrap") else {
                XCTFail("Missing bridge.onCustomAction or await bridge.bootstrap in \(relPath)")
                continue
            }
            XCTAssertLessThan(
                wireRange.lowerBound,
                bootRange.lowerBound,
                "\(relPath) must wire bridge.onCustomAction before calling bridge.bootstrap()"
            )
        }
    }
}
