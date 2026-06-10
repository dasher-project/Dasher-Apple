import SwiftUI

public struct MessageBanner: View {
    public let isWarning: Bool
    public let text: String
    public var onDismiss: () -> Void

    @State private var isVisible = false

    public init(isWarning: Bool, text: String, onDismiss: @escaping () -> Void) {
        self.isWarning = isWarning
        self.text = text
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundColor(isWarning ? .orange : .accentColor)

            Text(text)
                .font(.subheadline)
                .lineLimit(3)
                .layoutPriority(1)

            Button {
                withAnimation(.easeIn(duration: 0.3)) {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        )
        .padding(.horizontal)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                isVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                guard isVisible else { return }
                withAnimation(.easeIn(duration: 0.3)) {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
        }
    }
}
