import SwiftUI

/// Thin header: score on the left, Restart on the right.
struct HUDView: View {
    let score: Int
    let onRestart: () -> Void

    var body: some View {
        HStack {
            Text("Score: \(score)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .accessibilityIdentifier("scoreLabel")
            Spacer()
            Button("Restart") { onRestart() }
                .buttonStyle(.bordered)
                .tint(.white)
                .foregroundStyle(.white)
                .accessibilityIdentifier("restartButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
