import SwiftUI

/// RFC 0018-style loading state (mirrors Dasher-Android): the engine boots on
/// a background task while the UI appears immediately; this overlay covers the
/// canvas until the first frame is available. The 300 ms grace avoids flashing
/// it on warm starts, where bootstrap typically completes with the first
/// render anyway.
public struct EngineLoadingOverlay: View {
    private let isReady: Bool
    @State private var pastGrace = false

    public init(isReady: Bool) {
        self.isReady = isReady
    }

    public var body: some View {
        Group {
            if pastGrace && !isReady {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing Dasher…")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                pastGrace = true
            }
        }
        .animation(.easeInOut(duration: 0.15), value: pastGrace)
        .allowsHitTesting(!isReady)
    }
}
