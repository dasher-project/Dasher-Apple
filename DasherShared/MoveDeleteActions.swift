import Foundation

/// RFC 0021 amendment (DasherCore v0.2.28): Control-mode `Move` and `Delete`
/// subtrees ride the registered-action surface — frontends call
/// `dasher_register_action(ctx, "move"/"delete", ...)` and receive the node
/// attributes verbatim. Distances: `char | word | sentence | paragraph | all`;
/// direction: `forward | no`.
public enum MoveDeleteDistance: String, Equatable, Sendable {
    case char
    case word
    case sentence
    case paragraph
    case all
}

/// Move/Delete semantics (pure, unit-testable), mirroring SelectActions:
/// - Direct mode (macOS): native movement/deletion keystrokes. Where macOS
///   has no precision keystroke (sentence), the nearest native equivalent is
///   used and the editor mode remains the exact path.
/// - Editor mode (macOS `NSTextView` / iOS `UITextView`): measured UTF-16
///   caret moves and deletion ranges with surrogate-pair safety, reusing
///   SelectActions' boundary helpers.
public enum MoveDeleteActions {

    /// Parse the custom action callback's XML attribute values (`dist`, `forward`).
    /// Unknown or missing values return `nil` (log and no-op rather than crash).
    public static func parse(dist: String?, forward: String?) -> (distance: MoveDeleteDistance, direction: SelectDirection)? {
        guard let dist, let d = MoveDeleteDistance(rawValue: dist) else { return nil }
        let dir: SelectDirection
        switch forward {
        case "yes":
            dir = .forward
        case "no":
            dir = .backward
        default:
            return nil
        }
        return (d, dir)
    }

    // MARK: - Direct mode (macOS keystrokes)

    /// Movement chord (no Shift — movement, not selection). Sentence moves
    /// approximate with word movement: macOS has no sentence-precision arrow.
    public static func moveKeystroke(dist: MoveDeleteDistance, dir: SelectDirection) -> SelectActions.SelectKeystroke {
        let back = dir == .backward
        switch dist {
        case .char:
            return SelectActions.SelectKeystroke(
                shift: false, option: false, command: false,
                keyCode: back ? SelectActions.keyCodeLeftArrow : SelectActions.keyCodeRightArrow)
        case .word, .sentence:
            return SelectActions.SelectKeystroke(
                shift: false, option: true, command: false,
                keyCode: back ? SelectActions.keyCodeLeftArrow : SelectActions.keyCodeRightArrow)
        case .paragraph:
            return SelectActions.SelectKeystroke(
                shift: false, option: true, command: false,
                keyCode: back ? SelectActions.keyCodeUpArrow : SelectActions.keyCodeDownArrow)
        case .all:
            return SelectActions.SelectKeystroke(
                shift: false, option: false, command: true,
                keyCode: back ? SelectActions.keyCodeUpArrow : SelectActions.keyCodeDownArrow)
        }
    }

    /// Deletion keystroke. Returns `nil` for `all` — deleting everything is the
    /// composite `Cmd+A` then `Delete`, which the caller sends as two chords.
    /// Sentence deletes approximate with word deletion (no sentence-precision
    /// deletion keystroke on macOS); paragraph uses the line-start/end chords
    /// (`Cmd+Delete` / `Cmd+Forward-Delete`), exact for single-line text.
    public static func deleteKeystroke(dist: MoveDeleteDistance, dir: SelectDirection) -> SelectActions.SelectKeystroke? {
        let back = dir == .backward
        let deleteKey: UInt16 = 51 // kVK_Delete (backspace)
        let forwardDeleteKey: UInt16 = 117 // kVK_ForwardDelete
        switch dist {
        case .char:
            return SelectActions.SelectKeystroke(
                shift: false, option: false, command: false,
                keyCode: back ? deleteKey : forwardDeleteKey)
        case .word, .sentence:
            return SelectActions.SelectKeystroke(
                shift: false, option: true, command: false,
                keyCode: back ? deleteKey : forwardDeleteKey)
        case .paragraph:
            return SelectActions.SelectKeystroke(
                shift: false, option: false, command: true,
                keyCode: back ? deleteKey : forwardDeleteKey)
        case .all:
            return nil
        }
    }

    // MARK: - Editor mode

    /// Editor-mode caret move over `text` (UTF-16 units): returns the new caret
    /// location. `all` jumps to document start (backward) or end (forward).
    public static func moveCaret(text: String, caret: Int, dist: MoveDeleteDistance, dir: SelectDirection) -> Int {
        let units = Array(text.utf16)
        let len = units.count
        let from = max(0, min(caret, len))
        switch dist {
        case .all:
            return dir == .backward ? 0 : len
        case .char:
            return SelectActions.stepCodePoint(units: units, from: from, dir: dir)
        case .word:
            return SelectActions.wordBound(units: units, from: from, dir: dir)
        case .sentence:
            return sentenceBound(units: units, from: from, dir: dir)
        case .paragraph:
            return SelectActions.paragraphBound(units: units, from: from, dir: dir)
        }
    }

    /// Editor-mode deletion over `text`: removes the span between the caret and
    /// the boundary implied by `(dist, dir)`, returning the new text and caret.
    /// `all` clears the document (both directions).
    public static func deleteRange(text: String, caret: Int, dist: MoveDeleteDistance, dir: SelectDirection)
        -> (text: String, caret: Int) {
        let units = Array(text.utf16)
        let len = units.count
        let from = max(0, min(caret, len))

        var start: Int
        var end: Int
        if dist == .all {
            start = 0
            end = len
        } else {
            let boundary: Int
            switch dist {
            case .char:
                boundary = SelectActions.stepCodePoint(units: units, from: from, dir: dir)
            case .word:
                boundary = SelectActions.wordBound(units: units, from: from, dir: dir)
            case .sentence:
                boundary = sentenceBound(units: units, from: from, dir: dir)
            case .paragraph:
                boundary = SelectActions.paragraphBound(units: units, from: from, dir: dir)
            case .all:
                boundary = from // unreachable: handled above
            }
            start = min(from, boundary)
            end = max(from, boundary)
            if start == end {
                return (text, from) // nothing to delete at the document edge
            }
        }

        // Remove the UTF-16 range [start, end), preserving unpaired surrogates
        // by construction (bounds are code-point snapped).
        var resultUnits = Array(text.utf16)
        resultUnits.removeSubrange(start..<end)
        let result = String(decoding: resultUnits, as: UTF16.self)
        return (result, start)
    }

    // MARK: - Sentence boundary (UTF-16)

    private static func isTerminator(_ unit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return scalar == "." || scalar == "!" || scalar == "?" || scalar == "…"
    }

    /// Sentence boundary over `text` units. Forward: after the next terminator
    /// (plus trailing whitespace). Backward: before the start of the sentence
    /// containing the caret — if the caret sits immediately after a terminator's
    /// trailing whitespace the previous sentence is chained, mirroring the
    /// paragraph helper's chain behaviour.
    internal static func sentenceBound(units: [UInt16], from: Int, dir: SelectDirection) -> Int {
        let len = units.count
        var i = max(0, min(from, len))

        if dir == .forward {
            var j = i
            while j < len && !isTerminator(units[j]) { j += 1 }
            guard j < len else { return len }
            j += 1 // past the terminator
            while j < len && (units[j] == 0x20 || units[j] == 0x000A || units[j] == 0x000D) { j += 1 }
            return min(j, len)
        } else {
            // Chain over the whitespace following a terminator at the caret
            // (caret just after "sentence. ") so repeated moves keep stepping.
            var j = i
            while j > 0 && (units[j - 1] == 0x20 || units[j - 1] == 0x000A || units[j - 1] == 0x000D) { j -= 1 }
            if j > 0 && isTerminator(units[j - 1]) { i = j - 1 }
            // Scan back to the previous terminator, then to the start of text
            // after its trailing whitespace.
            var k = i
            while k > 0 && !isTerminator(units[k - 1]) { k -= 1 }
            guard k > 0 else { return 0 }
            var target = k
            while target < i && (units[target] == 0x20 || units[target] == 0x000A || units[target] == 0x000D) { target += 1 }
            return max(target, 0)
        }
    }
}
