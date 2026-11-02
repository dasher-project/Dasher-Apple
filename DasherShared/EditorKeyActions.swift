import Foundation

/// Surrogate-safe UTF-16 editing helpers for the on-screen editing keys strip
/// (`⌫`, `←`, `→`). Mirrors `Dasher.Windows.Services.EditorKeyActions`.
///
/// `NSTextView` (macOS) and `UITextView` (iOS) index selections in UTF-16 code
/// units (`NSRange`). Naive `caret - 1` or `caret + 1` arithmetic splits
/// astral-plane characters (such as emoji surrogate pairs) into orphaned half-
/// surrogates, which then round-trip through the UTF-8 engine bridge as U+FFFD
/// and corrupt the editor buffer.
public enum EditorKeyActions {

    private static func isHighSurrogate(_ unit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    private static func isLowSurrogate(_ unit: UInt16) -> Bool {
        (0xDC00...0xDFFF).contains(unit)
    }

    /// Delete one character (or full surrogate pair) before `caretUTF16` in `text`.
    /// Returns the updated text and the new UTF-16 caret offset.
    public static func backspace(text: String, caretUTF16: Int) -> (text: String, caretUTF16: Int) {
        backspace(text: text, selectionStart: caretUTF16, selectionEnd: caretUTF16)
    }

    /// Delete the active selection range `[selectionStart, selectionEnd)` if non-empty,
    /// or one character (or full surrogate pair) before the caret when `selectionStart == selectionEnd`.
    /// Surrogate pairs straddling selection boundaries are expanded so no orphaned half-surrogate remains.
    public static func backspace(
        text: String,
        selectionStart: Int,
        selectionEnd: Int
    ) -> (text: String, caretUTF16: Int) {
        let units = Array(text.utf16)
        let len = units.count
        guard len > 0 else { return ("", 0) }

        let rawLow = min(selectionStart, selectionEnd)
        let rawHigh = max(selectionStart, selectionEnd)
        var start = max(0, min(rawLow, len))
        var end = max(0, min(rawHigh, len))

        if end > start {
            // Active selection: expand if either endpoint sits between a high and low surrogate.
            if start > 0 && start < len && isLowSurrogate(units[start]) && isHighSurrogate(units[start - 1]) {
                start -= 1
            }
            if end > 0 && end < len && isLowSurrogate(units[end]) && isHighSurrogate(units[end - 1]) {
                end += 1
            }
            var remaining = units
            remaining.removeSubrange(start..<end)
            let updated = String(decoding: remaining, as: UTF16.self)
            return (updated, start)
        }

        let c = start
        guard c > 0 else { return (text, 0) }

        // Mid-pair defence: if a retained caret index sits BETWEEN the high and low
        // halves of a surrogate pair, delete the entire pair so neither half is orphaned.
        let removeStart: Int
        let removeEnd: Int
        if c < len && isLowSurrogate(units[c]) && isHighSurrogate(units[c - 1]) {
            removeStart = c - 1
            removeEnd = c + 1
        } else if c >= 2 && isLowSurrogate(units[c - 1]) && isHighSurrogate(units[c - 2]) {
            removeStart = c - 2
            removeEnd = c
        } else {
            removeStart = c - 1
            removeEnd = c
        }

        var remaining = units
        remaining.removeSubrange(removeStart..<removeEnd)
        let updated = String(decoding: remaining, as: UTF16.self)
        return (updated, removeStart)
    }

    /// Move `caretUTF16` by `delta` (`< 0` for left, `> 0` for right), stepping over
    /// full surrogate pairs and clamping to `0...text.utf16.count`.
    public static func moveCaret(text: String, caretUTF16: Int, delta: Int) -> Int {
        moveCaret(text: text, selectionStart: caretUTF16, selectionEnd: caretUTF16, delta: delta)
    }

    /// Selection-aware caret movement: if a non-empty selection is active, left (`delta < 0`)
    /// collapses to the selection start and right (`delta > 0`) collapses to the selection end
    /// (snapping outside any split surrogate pair). Otherwise moves by one character / surrogate pair.
    public static func moveCaret(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
        delta: Int
    ) -> Int {
        let units = Array(text.utf16)
        let len = units.count
        guard len > 0 else { return 0 }

        let rawLow = min(selectionStart, selectionEnd)
        let rawHigh = max(selectionStart, selectionEnd)
        let start = max(0, min(rawLow, len))
        let end = max(0, min(rawHigh, len))

        guard delta != 0 else { return end }

        if end > start {
            if delta < 0 {
                if start > 0 && start < len && isLowSurrogate(units[start]) && isHighSurrogate(units[start - 1]) {
                    return start - 1
                }
                return start
            } else {
                if end > 0 && end < len && isLowSurrogate(units[end]) && isHighSurrogate(units[end - 1]) {
                    return end + 1
                }
                return end
            }
        }

        let c = start
        if delta < 0 {
            guard c > 0 else { return 0 }
            var next = c - 1
            if next > 0 && isLowSurrogate(units[next]) && isHighSurrogate(units[next - 1]) {
                next -= 1
            }
            return next
        } else {
            guard c < len else { return len }
            var next = c + 1
            if next < len && isLowSurrogate(units[next]) && isHighSurrogate(units[next - 1]) {
                next += 1
            }
            return next
        }
    }

    /// Insert `inserted` into `existing` at `[selectionStart, selectionEnd)` (replacing any
    /// active selection and expanding endpoints that straddle a surrogate pair), returning
    /// the updated text and the new UTF-16 caret offset immediately after `inserted`.
    public static func insert(
        text inserted: String,
        into existing: String,
        selectionStart: Int,
        selectionEnd: Int
    ) -> (text: String, caretUTF16: Int) {
        let units = Array(existing.utf16)
        let len = units.count
        let rawLow = min(selectionStart, selectionEnd)
        let rawHigh = max(selectionStart, selectionEnd)
        var start = max(0, min(rawLow, len))
        var end = max(0, min(rawHigh, len))

        if start > 0 && start < len && isLowSurrogate(units[start]) && isHighSurrogate(units[start - 1]) {
            start -= 1
        }
        if end > 0 && end < len && isLowSurrogate(units[end]) && isHighSurrogate(units[end - 1]) {
            end += 1
        }

        let insertedUnits = Array(inserted.utf16)
        var updated = units
        updated.replaceSubrange(start..<end, with: insertedUnits)
        let resultText = String(decoding: updated, as: UTF16.self)
        return (resultText, start + insertedUnits.count)
    }
}

/// RFC 0019 clause 7: caps the text seeded to the engine at a trailing window of
/// `maxUTF16Units` (default 100k) UTF-16 units without splitting a surrogate pair
/// at the window boundary. Shared across macOS and iOS editor views.
public enum EditorSeedPolicy {
    public static let maxUTF16Units = 100_000

    public static func apply(
        to text: String,
        caretUTF16: Int,
        maxUnits: Int = maxUTF16Units
    ) -> (text: String, caretUTF16: Int) {
        let units = Array(text.utf16)
        let len = units.count
        guard len > maxUnits else { return (text, max(0, min(caretUTF16, len))) }

        var dropCount = len - maxUnits
        // Never slice between a high surrogate (0xD800...0xDBFF) and a low surrogate (0xDC00...0xDFFF).
        if dropCount > 0 && dropCount < len &&
           (0xDC00...0xDFFF).contains(units[dropCount]) &&
           (0xD800...0xDBFF).contains(units[dropCount - 1]) {
            dropCount += 1
        }

        let slice = Array(units[dropCount..<len])
        let windowed = String(decoding: slice, as: UTF16.self)
        let clampedCaret = max(0, min(caretUTF16, len))
        let newCaret = max(0, clampedCaret - dropCount)
        return (windowed, newCaret)
    }
}
