import SwiftUI

/// Header: the row of lives dots, centered (spec 71). 32pt tall, 16pt below
/// the top safe area (see `.fable/specs/20-figma-layout.md`). No score (spec
/// 68), nor on the game-over screen since spec 90. Restart, and `settings` for
/// the palette sets, are up in place of the status bar (`IslandBarView`).
struct HUDView: View {
    let livesLeft: Int
    let maxLives: Int
    /// Black on a light palette background, white on a dark one.
    var foreground: Color = .white

    var body: some View {
        LivesIndicatorView(livesLeft: livesLeft, maxLives: maxLives, foreground: foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .padding(.top, 16)
    }
}

/// Row of `maxLives` 10pt dots, `spacing: 2` (58pt total for 5), full
/// foreground color (white, or black on a light palette) for remaining lives
/// and 20% opacity for lost ones.
private struct LivesIndicatorView: View {
    let livesLeft: Int
    let maxLives: Int
    let foreground: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(maxLives, 0), id: \.self) { i in
                Circle()
                    .fill(foreground.opacity(i < livesLeft ? 1.0 : 0.2))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("livesIndicator")
        .accessibilityLabel(Text(verbatim: "lives"))
        .accessibilityValue(Text(verbatim: "\(livesLeft) of \(maxLives)"))
    }
}
