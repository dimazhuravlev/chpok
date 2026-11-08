import SwiftUI

/// A set's app icon, drawn in place for the sets carousel (spec 75): the
/// design `scripts/make-app-icon.py` draws for the home screen — a circle of
/// the set's icon circle color on its icon background color, `circleRatio`
/// of the icon wide. The colors are the set's as the board shows them on the
/// background picked by the slider (spec 80, `BackgroundAdaptation`): on
/// black, the home-screen icon's own. The alternate icons can't be read back
/// from the asset catalog, so they're drawn rather than loaded. The circle
/// gets the bubbles' glass (`BubbleNode`), the look iOS 26 gives it on the
/// home screen.
struct AppIconView: View {
    let set: PaletteSet
    let size: CGFloat
    /// The set's six colors on the current background (`set.colors` on
    /// black).
    let colors: [UInt32]

    /// `CIRCLE_DIAMETER` over `FINAL_SIZE` in `make-app-icon.py`.
    static let circleRatio: CGFloat = 672.0 / 1024
    /// Corner, continuous: a little rounder than the home screen's 0.2237
    /// (spec 82).
    static let cornerRatio: CGFloat = 0.27

    var body: some View {
        let diameter = size * Self.circleRatio
        RoundedRectangle(cornerRadius: size * Self.cornerRatio, style: .continuous)
            .fill(Self.color(colors[set.icon.background]))
            .overlay {
                Circle()
                    .fill(Self.color(colors[set.icon.circle]))
                    // Lighter at the top, darker at the bottom.
                    .overlay {
                        Circle().fill(LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.14), location: 0),
                                .init(color: .clear, location: 0.5),
                                .init(color: .black.opacity(0.12), location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        ))
                    }
                    // A thin light rim, brightest at the top.
                    .overlay {
                        Circle().strokeBorder(LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.6), location: 0),
                                .init(color: .white.opacity(0.12), location: 0.5),
                                .init(color: .white.opacity(0.28), location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        ), lineWidth: max(1, diameter / 30))
                    }
                    .frame(width: diameter, height: diameter)
            }
            .frame(width: size, height: size)
    }

    /// As the board shows it (`Palette.display`).
    private static func color(_ hex: UInt32) -> Color {
        Color(uiColor: Palette.display(hex))
    }
}
