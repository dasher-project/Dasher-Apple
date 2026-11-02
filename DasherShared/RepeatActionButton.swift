import SwiftUI

/// Press-and-hold repeating button for the editing keys strip (`⌫`, `←`, `→`).
///
/// Mirrors `Dasher-Windows` `WireEditingKeyRepeat`:
/// - Fires `onPressStart` and `action` immediately on press-down (so telemetry
///   records one activation per press gesture, not per repeat tick).
/// - After `initialDelayMs` (default 350 ms), repeats `action` every
///   `repeatIntervalMs` (90 ms for Backspace, 120 ms for Left/Right arrows)
///   until released or removed from the view hierarchy.
public struct RepeatActionButton<Label: View>: View {
    private let initialDelayMs: Int
    private let repeatIntervalMs: Int
    private let onPressStart: () -> Void
    private let action: () -> Void
    private let label: () -> Label

    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?
    @GestureState private var isGestureActive = false

    public init(
        initialDelayMs: Int = 350,
        repeatIntervalMs: Int,
        onPressStart: @escaping () -> Void = {},
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.initialDelayMs = initialDelayMs
        self.repeatIntervalMs = repeatIntervalMs
        self.onPressStart = onPressStart
        self.action = action
        self.label = label
    }

    public var body: some View {
        label()
            .opacity(isPressed ? 0.6 : 1.0)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isGestureActive) { _, state, _ in
                        state = true
                    }
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onPressStart()
                        action()
                        let delayNs = UInt64(max(1, initialDelayMs)) * 1_000_000
                        let intervalNs = UInt64(max(1, repeatIntervalMs)) * 1_000_000
                        repeatTask?.cancel()
                        repeatTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: delayNs)
                            while !Task.isCancelled && isPressed {
                                action()
                                try? await Task.sleep(nanoseconds: intervalNs)
                            }
                        }
                    }
                    .onEnded { _ in
                        stopRepeat()
                    }
            )
            .onChange(of: isGestureActive) { _, active in
                if !active && isPressed {
                    stopRepeat()
                }
            }
            .onDisappear {
                stopRepeat()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onPressStart()
                action()
            }
    }

    private func stopRepeat() {
        isPressed = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}
