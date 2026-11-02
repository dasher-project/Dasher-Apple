import Foundation

/// RFC 0021: Control-mode `Select` subtree distances (`char | word | paragraph | all`).
public enum SelectDistance: String, Equatable, Sendable {
    case char
    case word
    case paragraph
    case all
}

/// RFC 0021: Control-mode `Select` subtree directions (`backward | forward`).
public enum SelectDirection: Equatable, Sendable {
    case backward
    case forward
}

/// RFC 0021 select-action semantics (pure, unit-testable):
/// - Direct mode (macOS): native Apple selection keystrokes (`Shift+Arrow`,
///   `Shift+Opt+Arrow`, `Shift+Opt+Up/Down`, `Cmd+A`) so the target app's own
///   selection, Copy, Cut, and Delete act on it natively.
/// - Editor mode (macOS `NSTextView` / iOS `UITextView`): measured UTF-16
///   selection bounds with an active-end state machine and surrogate-pair safety.
public enum SelectActions {

    /// macOS virtual key codes (`Carbon.HIToolbox.Events`).
    public static let keyCodeA: UInt16 = 0           // kVK_ANSI_A (0x00)
    public static let keyCodeLeftArrow: UInt16 = 123 // kVK_LeftArrow (0x7B)
    public static let keyCodeRightArrow: UInt16 = 124 // kVK_RightArrow (0x7C)
    public static let keyCodeDownArrow: UInt16 = 125 // kVK_DownArrow (0x7D)
    public static let keyCodeUpArrow: UInt16 = 126   // kVK_UpArrow (0x7E)

    /// Direct-mode macOS keystroke chord description for a `(SelectDistance, SelectDirection)` pair.
    ///
    /// Note per RFC 0021: paragraph uses `Shift+Option+Up/Down` (`option: true, shift: true, command: false`).
    /// Never use `Shift+Command+Up/Down`, which selects to document start/end on macOS.
    public struct SelectKeystroke: Equatable, Sendable {
        public let shift: Bool
        public let option: Bool
        public let command: Bool
        public let keyCode: UInt16

        public init(shift: Bool, option: Bool, command: Bool, keyCode: UInt16) {
            self.shift = shift
            self.option = option
            self.command = command
            self.keyCode = keyCode
        }
    }

    /// Returns the macOS Direct Mode selection keystroke for `(dist, dir)`.
    public static func keystroke(dist: SelectDistance, dir: SelectDirection) -> SelectKeystroke {
        switch dist {
        case .char:
            return SelectKeystroke(
                shift: true,
                option: false,
                command: false,
                keyCode: dir == .backward ? keyCodeLeftArrow : keyCodeRightArrow
            )
        case .word:
            return SelectKeystroke(
                shift: true,
                option: true,
                command: false,
                keyCode: dir == .backward ? keyCodeLeftArrow : keyCodeRightArrow
            )
        case .paragraph:
            return SelectKeystroke(
                shift: true,
                option: true,
                command: false,
                keyCode: dir == .backward ? keyCodeUpArrow : keyCodeDownArrow
            )
        case .all:
            return SelectKeystroke(
                shift: false,
                option: false,
                command: true,
                keyCode: keyCodeA
            )
        }
    }

    /// Parse the custom action callback's XML attribute values (`dist`, `forward`).
    /// Unknown or missing values return `nil` (the engine validates no attributes for
    /// custom actions; unexpected values must log and no-op rather than crash).
    public static func parse(dist: String?, forward: String?) -> (distance: SelectDistance, direction: SelectDirection)? {
        guard let dist, let d = SelectDistance(rawValue: dist) else { return nil }
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

    /// Editor-mode selection bounds over `text` (UTF-16 code units, ordered `start <= end`).
    /// Mirrors `Dasher.Windows.Services.SelectActions.EditorBounds`.
    public static func editorBounds(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
        dist: SelectDistance,
        dir: SelectDirection,
        hadSelection: Bool
    ) -> (start: Int, end: Int) {
        let result = editorBounds(
            text: text,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd,
            dist: dist,
            dir: dir,
            hadSelection: hadSelection,
            anchorUTF16: nil
        )
        return (result.start, result.end)
    }

    /// Editor-mode selection bounds over `text` (UTF-16 code units) with explicit
    /// `anchorUTF16` tracking for `NSRange`-backed views (`NSTextView` / `UITextView`)
    /// where `NSRange(location, length)` always stores `location <= location + length`.
    ///
    /// - When `hadSelection` is `false` (or `selectionStart == selectionEnd`), the caret
    ///   becomes the anchor.
    /// - When `hadSelection` is `true` and `anchorUTF16` matches either endpoint of
    ///   `[selectionStart, selectionEnd]`, the opposite endpoint is the active end.
    ///   This allows chaining backward selections (`Select <= Char` repeatedly) as well
    ///   as shrinking a backward selection with `Select => Char`.
    public static func editorBounds(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
        dist: SelectDistance,
        dir: SelectDirection,
        hadSelection: Bool,
        anchorUTF16: Int?
    ) -> (start: Int, end: Int, anchorUTF16: Int) {
        let units = Array(text.utf16)
        let len = units.count

        let clampedStart = snapToCodePoint(units: units, index: max(0, min(selectionStart, len)), dir: .backward)
        let clampedEnd = snapToCodePoint(units: units, index: max(0, min(selectionEnd, len)), dir: .forward)

        if dist == .all {
            let preservedAnchor: Int
            if let explicitAnchor = anchorUTF16 {
                preservedAnchor = snapToCodePoint(units: units, index: max(0, min(explicitAnchor, len)), dir: .backward)
            } else {
                preservedAnchor = hadSelection ? clampedStart : clampedEnd
            }
            return (0, len, preservedAnchor)
        }

        let anchor: Int
        let active: Int
        if hadSelection && clampedStart != clampedEnd {
            let low = min(clampedStart, clampedEnd)
            let high = max(clampedStart, clampedEnd)
            if let explicitAnchor = anchorUTF16 {
                let snappedAnchor = snapToCodePoint(units: units, index: max(0, min(explicitAnchor, len)), dir: .backward)
                if snappedAnchor == high {
                    anchor = high
                    active = low
                } else if snappedAnchor == low {
                    anchor = low
                    active = high
                } else {
                    anchor = clampedStart
                    active = clampedEnd
                }
            } else {
                anchor = clampedStart
                active = clampedEnd
            }
        } else {
            anchor = clampedEnd
            active = anchor
        }

        let target: Int
        switch dist {
        case .char:
            target = stepCodePoint(units: units, from: active, dir: dir)
        case .word:
            target = wordBound(units: units, from: active, dir: dir)
        case .paragraph:
            target = paragraphBound(units: units, from: active, dir: dir)
        case .all:
            return (0, len, 0)
        }

        if target <= anchor {
            return (target, anchor, anchor)
        } else {
            return (anchor, target, anchor)
        }
    }

    // MARK: - Internal UTF-16 Boundary Helpers

    private static func isHighSurrogate(_ unit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    private static func isLowSurrogate(_ unit: UInt16) -> Bool {
        (0xDC00...0xDFFF).contains(unit)
    }

    private static func isUTF16Whitespace(_ unit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    /// Move by one Unicode code point, never landing on the low half of a surrogate pair.
    internal static func stepCodePoint(units: [UInt16], from: Int, dir: SelectDirection) -> Int {
        let len = units.count
        let i = snapToCodePoint(units: units, index: max(0, min(from, len)), dir: dir)
        if dir == .forward {
            guard i < len else { return len }
            let step = (isHighSurrogate(units[i]) && i + 1 < len && isLowSurrogate(units[i + 1])) ? 2 : 1
            return min(i + step, len)
        } else {
            guard i > 0 else { return 0 }
            let back = (i >= 2 && isLowSurrogate(units[i - 1]) && isHighSurrogate(units[i - 2])) ? 2 : 1
            return max(i - back, 0)
        }
    }

    /// Next/previous word boundary (skips the current run of non-whitespace then whitespace
    /// when moving forward, or whitespace then non-whitespace when moving backward).
    internal static func wordBound(units: [UInt16], from: Int, dir: SelectDirection) -> Int {
        let len = units.count
        var i = max(0, min(from, len))
        if dir == .forward {
            while i < len && !isUTF16Whitespace(units[i]) { i += 1 }
            while i < len && isUTF16Whitespace(units[i]) { i += 1 }
        } else {
            while i > 0 && isUTF16Whitespace(units[i - 1]) { i -= 1 }
            while i > 0 && !isUTF16Whitespace(units[i - 1]) { i -= 1 }
        }
        return snapToCodePoint(units: units, index: i, dir: dir)
    }

    /// Start/end of the current `\n`-delimited paragraph. A chained forward-paragraph
    /// advances past at most ONE separator (`\r\n` as a unit, or `\n`), so blank lines
    /// are stepped one at a time and selections stop before `\r` on `\r\n` text.
    internal static func paragraphBound(units: [UInt16], from: Int, dir: SelectDirection) -> Int {
        let len = units.count
        let cr: UInt16 = 0x000D // '\r'
        let lf: UInt16 = 0x000A // '\n'
        var i = max(0, min(from, len))

        if dir == .forward {
            if i < len && units[i] == cr && i + 1 < len && units[i + 1] == lf {
                i += 2
            } else if i < len && units[i] == lf {
                i += 1
            }
            var nl = -1
            for idx in i..<len where units[idx] == lf {
                nl = idx
                break
            }
            guard nl >= 0 else { return len }
            return (nl > 0 && units[nl - 1] == cr) ? (nl - 1) : nl
        } else {
            guard i > 0 else { return 0 }
            // Skip at most one preceding separator (\r\n as a unit, or \n) when
            // the active end already sits at the start of a paragraph so chained
            // backward-paragraph selections step paragraph by paragraph instead of stalling.
            if i >= 2 && units[i - 1] == lf && units[i - 2] == cr {
                i -= 2
            } else if units[i - 1] == lf {
                i -= 1
            }
            guard i > 0 else { return 0 }
            var prev = -1
            for idx in stride(from: i - 1, through: 0, by: -1) where units[idx] == lf {
                prev = idx
                break
            }
            let target = prev < 0 ? 0 : (prev + 1)
            return snapToCodePoint(units: units, index: target, dir: dir)
        }
    }

    /// Snap a UTF-16 index so it never splits a surrogate pair.
    private static func snapToCodePoint(units: [UInt16], index: Int, dir: SelectDirection) -> Int {
        let len = units.count
        if index > 0 && index < len && isLowSurrogate(units[index]) && isHighSurrogate(units[index - 1]) {
            return dir == .backward ? (index - 1) : (index + 1)
        }
        return index
    }
}
