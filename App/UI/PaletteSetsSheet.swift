import SwiftUI

/// Test bottom sheet with every ready-made palette set (spec 56), opened by the
/// `settings` button (spec 71) or the `-showPaletteSets` launch argument. On
/// top the background slider from black to white (spec 64), a thick capsule
/// (`CapsuleSlider`, spec 73); below it the sets' app icons in a row that goes
/// round without end (`IconCarousel`, specs 75, 79, 80, 83), whose middle icon
/// is the set in play, so the board behind the sheet repaints live as the icons
/// go by, the way it does while the slider moves. No names: the icon says it.
/// The sheet is only as tall as its content, and the board above it stays
/// undimmed, so the colors can be judged as they really look; a tap on the
/// board closes the sheet rather than playing (spec 74, `RootView`).
struct PaletteSetsSheet: View {
    @ObservedObject private var store = PaletteStore.shared

    /// The slider's range as shown, black to white through the very greys
    /// the background takes.
    private static let backgroundStops = (0...10).map { step in
        Color(uiColor: Palette.display(BackgroundAdaptation.background(lightness: Double(step) / 10)))
    }
    /// A tick every tenth of the way, and where the interface text flips
    /// between white and black.
    private static let backgroundDetents = (1...9).map { Double($0) / 10 } + [BackgroundAdaptation.polarityFlip]

    /// Around the slider: as far in from the sides as down from the top
    /// (spec 81).
    private static let sliderInset: CGFloat = 28
    /// The sheet's handle (spec 81): 40 long, a little longer than the
    /// system one (36 × 5), and a quarter as strong, so it hints rather than
    /// shows.
    private static let handleSize = CGSize(width: 40, height: 5)
    private static let handleTop: CGFloat = 5
    /// The content's own height, which the sheet's height follows.
    @State private var contentHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            CapsuleSlider(
                value: backgroundLightness,
                stops: Self.backgroundStops,
                detents: Self.backgroundDetents,
                onEditingEnded: store.saveBackground
            )
            .accessibilityIdentifier("backgroundSlider")
            .padding(.horizontal, Self.sliderInset)
            .padding(.top, Self.sliderInset)

            IconCarousel()
                .padding(.top, 32)
                .padding(.bottom, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { contentHeight = geo.size.height }
                    .onChange(of: geo.size.height) { contentHeight = $0 }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // A container, so the slider and the rest keep identifiers of
        // their own instead of all taking this one.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paletteSetsSheet")
        .presentationDetents([.height(contentHeight)])
        // Our own handle in place of the system one, which can't be styled.
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel).opacity(0.25))
                .frame(width: Self.handleSize.width, height: Self.handleSize.height)
                .padding(.top, Self.handleTop)
                .accessibilityHidden(true)
        }
        .presentationDragIndicator(.hidden)
        // All four corners alike (spec 85). By default the top ones are
        // tighter than the bottom ones, which follow the screen's own
        // corners; 52 keeps the bottom ones as they were (measured).
        .presentationCornerRadius(52)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(contentHeight)))
        .preferredColorScheme(store.isLight ? .light : .dark)
    }

    /// The slider's value; it ticks on its own (`CapsuleSlider`).
    private var backgroundLightness: Binding<Double> {
        Binding(
            get: { store.backgroundLightness },
            set: { store.setBackgroundLightness($0) }
        )
    }
}
