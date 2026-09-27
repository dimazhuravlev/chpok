import SwiftUI

/// Header per the Figma layout: score on the left, a row of lives dots
/// centered on the screen, Restart on the right. 32pt tall, 16pt below the
/// top safe area, 16pt side insets (see `.fable/specs/20-figma-layout.md`).
struct HUDView: View {
    let score: Int
    let livesLeft: Int
    let maxLives: Int
    let onRestart: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Text(verbatim: String(score))
                    .font(.pretendardSemiBold(32))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("scoreLabel")
                Spacer()
                Button("restart") {
                    Haptics.shared.buttonTapped()
                    onRestart()
                }
                .font(.pretendardSemiBold(32))
                .tint(.white)
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .accessibilityIdentifier("restartButton")
            }
            .padding(.horizontal, 16)

            LivesIndicatorView(livesLeft: livesLeft, maxLives: maxLives)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .padding(.top, 16)
    }
}

/// Row of `maxLives` 10pt dots, `spacing: 2` (58pt total for 5), full white
/// for remaining lives and white-at-20%-opacity for lost ones. Centered on
/// the screen (the parent `ZStack`'s default alignment), independent of the
/// score/restart text widths on either side.
private struct LivesIndicatorView: View {
    let livesLeft: Int
    let maxLives: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(maxLives, 0), id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i < livesLeft ? 1.0 : 0.2))
                    .frame(width: 10, height: 10)
            }
        }
    }
}
