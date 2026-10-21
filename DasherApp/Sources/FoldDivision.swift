import SwiftUI

/// iPhone Duo fold support (HIG "Designing for iPhone Duo").
///
/// When the device is partially open (or closed) the hinge reports a
/// `ReservedRegion` of kind `.division` — a band of the display that content
/// must not cross. Dasher's layouts already offer a draggable divider
/// between the steering canvas and the writing area; when a fold is active
/// along the same axis, the divider snaps to the fold so each pane sits
/// entirely on its own side (HIG: arrange content into separate sections on
/// each side of a division). When the device is flat — division inactive —
/// the draggable fraction rules again. A layout whose axis doesn't match
/// the fold direction keeps its geometry; the user can pick a matching
/// layout from the toolbar instead (small adjustments, no rearrangement).
///
/// Snap behaviour only applies in regular-width environments (the unfolded
/// inner display). The compact outer display keeps today's layout
/// untouched.
///
/// Everything new-API is gated on the iOS 27.1 SDK (`#if compiler(>=6.4)`)
/// and `@available(iOS 27.1, *)` (the ReservedRegion API is annotated
/// `anyAppleOS 27.1` in the SDK); older toolchains compile the fallback
/// path, which never reports a fold.
enum FoldDivision {

    /// Pane widths for a side-by-side (HStack) layout: leading canvas-or-
    /// text width and trailing width. With an active vertical fold the
    /// divider snaps to the fold band; otherwise the draggable fraction
    /// applies.
    static func horizontal(fold: CGRect?, total: CGFloat,
                           fraction: CGFloat, minPane: CGFloat = 120)
        -> (leading: CGFloat, trailing: CGFloat) {
        if let f = fold, f.height > f.width, total > 0 {
            let leading = max(minPane, min(total - minPane, f.minX))
            let trailing = max(minPane, total - f.maxX)
            if leading + trailing <= total {
                return (leading, total - leading)
            }
        }
        return (total * (1 - fraction), total * fraction)
    }

    /// Pane heights for a stacked (VStack) layout: top height and bottom
    /// height. With an active horizontal fold (device folded like a laptop)
    /// the divider snaps to the fold band; otherwise the draggable fraction
    /// applies.
    static func vertical(fold: CGRect?, total: CGFloat,
                         fraction: CGFloat, minPane: CGFloat = 120)
        -> (top: CGFloat, bottom: CGFloat) {
        if let f = fold, f.width > f.height, total > 0 {
            let top = max(minPane, min(total - minPane, f.minY))
            let bottom = max(minPane, total - f.maxY)
            if top + bottom <= total {
                return (top, total - top)
            }
        }
        return (total * (1 - fraction), total * fraction)
    }
}

/// Invisible background view that reports the first active division region
/// (the iPhone Duo hinge fold) in the coordinate space of the view it is
/// attached to. Reports nil on older OSes/SDKs and whenever no division is
/// active (device fully open).
struct FoldDivisionReader: View {
    var onChange: (CGRect?) -> Void

    var body: some View {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            FoldDivisionReader27(onChange: onChange)
        } else {
            Color.clear.onAppear { onChange(nil) }
        }
        #else
        Color.clear
        #endif
    }
}

#if compiler(>=6.4)
@available(iOS 27.1, *)
private struct FoldDivisionReader27: View {
    var onChange: (CGRect?) -> Void

    var body: some View {
        GeometryReader { proxy in
            // iPhone Duo has one fold; inactive while fully open.
            let frame = proxy.reservedRegions(kind: .division).first?.frame
            Color.clear
                .onAppear { onChange(frame) }
                .onChange(of: frame) { _, new in onChange(new) }
        }
    }
}
#endif
