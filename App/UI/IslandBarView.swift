import SwiftUI

/// The row in place of the status bar, which the app hides (spec 71):
/// `settings` in the left ear of the Dynamic Island, opening the palette-sets
/// sheet, and `restart` in the right one. Each is centered in its ear and, vertically, on
/// the island, the way the clock and the battery are.
///
/// It is as tall as the top safe area, which on a phone with an island or a
/// notch stays the status bar's height with the status bar gone. A phone with
/// neither loses that safe area with the status bar, so the row keeps
/// `minHeight` there and its buttons sit either side of the lives instead.
struct IslandBarView: View {
    let onSettings: () -> Void
    let onRestart: () -> Void
    /// Black on a light palette background, white on a dark one.
    var foreground: Color = .white

    /// Width of the Dynamic Island, the gap between the two ears.
    static let islandWidth: CGFloat = 126
    static let minHeight: CGFloat = 44
    private static let fontSize: CGFloat = 22
    /// Centered in its ear each label looks pushed out to the screen edge;
    /// this brings both toward the island, by eye.
    private static let towardIsland: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            button("settings", id: "settingsButton", nudge: Self.towardIsland, action: onSettings)
            Color.clear.frame(width: Self.islandWidth)
            button("restart", id: "restartButton", nudge: -Self.towardIsland, action: onRestart)
        }
        .frame(maxWidth: .infinity)
    }

    private func button(_ title: String, id: String, nudge: CGFloat = 0, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.buttonTapped()
            action()
        } label: {
            // The whole ear is the tap area: from the screen edge to the
            // island and the full height of the row, not just the text.
            Text(verbatim: title)
                .font(.appSemiBold(Self.fontSize))
                .foregroundStyle(foreground)
                .offset(x: nudge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
