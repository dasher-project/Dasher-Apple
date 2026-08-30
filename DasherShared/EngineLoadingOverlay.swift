import SwiftUI

/// RFC 0018-style loading state (mirrors Dasher-Android): the engine boots on
/// a background task while the UI appears immediately; this overlay covers the
/// canvas until the first frame is available. The 300 ms grace avoids flashing
/// it on warm starts, where bootstrap typically completes with the first
/// render anyway. When `errorMessage` is set (engine creation failed) an
/// error state shows instead — the canvas must never silently appear dead.
public struct EngineLoadingOverlay: View {
    private let isReady: Bool
    private let errorMessage: String?
    @State private var pastGrace = false

    public init(isReady: Bool, errorMessage: String? = nil) {
        self.isReady = isReady
        self.errorMessage = errorMessage
    }

    public var body: some View {
        Group {
            if let errorMessage {
                errorState(errorMessage)
            } else if pastGrace && !isReady {
                loadingState
            }
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                pastGrace = true
            }
        }
        .animation(.easeInOut(duration: 0.15), value: pastGrace)
    }

    private var loadingState: some View {
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

    private func errorState(_ message: String) -> some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundColor(.orange)
                Text("Dasher could not start")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text("Please try reinstalling, or report this in a GitHub issue.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .transition(.opacity)
    }
}
