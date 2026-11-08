import SwiftUI

/// The sets' app icons in a row that goes round without end (specs 75, 79,
/// 83), each in its set's colors on the current background (spec 80,
/// `AppIconView`). The icon that rests in the middle, inside a ring that
/// stays put, is the set in play: picked as it gets there, so the board
/// behind the sheet repaints live as the icons go by. Drag it, or tap an
/// icon to bring it to the middle. Opens on the selected set.
///
/// Not a scroll view: the row is one number, `position` — which icon is in
/// the middle, in icons, fractional between them — and only the icons
/// around it are drawn. Icon `k` (any whole number) shows set `k` modulo the
/// set count, so the row has no ends, and the row opens exactly on the
/// selected set (a long repeated scroll view did not: lazy layout landed it
/// a few icons off). A drag moves `position` with the finger; letting go
/// carries on by the drag's momentum and settles on a whole icon with a
/// spring.
struct IconCarousel: View {
    @ObservedObject private var store = PaletteStore.shared

    static let iconSize: CGFloat = 72
    static let iconSpacing: CGFloat = 22
    private static let step = iconSize + iconSpacing
    /// Icons away from the middle shrink and fade by up to this much, all of
    /// it one icon out.
    private static let sideShrink: CGFloat = 0.22
    private static let sideFade: Double = 0.4
    /// Icons drawn either side of the middle: enough to fill out to the
    /// sheet's sides and a little past them.
    private static let reach = 3
    /// The furthest a fling carries on past where the finger let go, icons.
    private static let maxFling: Double = 6
    /// Gap between the middle icon and the ring around the middle.
    private static let ringGap: CGFloat = 5
    private static let settle = Animation.spring(response: 0.45, dampingFraction: 0.86)
    /// Finger travel within which a press is a tap.
    private static let tapSlop: CGFloat = 8

    /// Every set's adaptation, built once: the icons recolor on every
    /// slider step.
    private static let adaptations = Dictionary(
        uniqueKeysWithValues: PaletteSet.all.map { ($0.id, BackgroundAdaptation(palette: $0.colors)) }
    )

    /// Which icon is in the middle, in icons.
    @State private var position: Double
    /// The icon whose set was last picked.
    @State private var picked: Int
    /// The drag in progress: where on screen it began, and `position` then.
    /// A drag is told from the last by where it began, so one the system
    /// cancelled — `onEnded` never hears of that — leaves nothing behind.
    /// (Not a `@GestureState`: that one reset itself over and over in the
    /// middle of a drag, each time restarting the count from where the row
    /// had got to, so the row ran several icons ahead of the finger.)
    @State private var dragStart: (location: CGPoint, position: Double)?

    init() {
        let index = PaletteSet.all.firstIndex { $0.id == PaletteStore.shared.selectedSetId } ?? 0
        _position = State(initialValue: Double(index))
        _picked = State(initialValue: index)
    }

    var body: some View {
        GeometryReader { geo in
            Strip(
                position: position,
                picked: picked,
                colors: { set in
                    Self.adaptations[set.id]?.colors(lightness: store.backgroundLightness) ?? set.colors
                },
                onTap: bring
            )
            .contentShape(Rectangle())
            .gesture(drag(width: geo.size.width))
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.iconSize + 2 * (Self.ringGap + 2))
        .overlay { ring.allowsHitTesting(false) }
    }

    /// The one gesture of the row, drags and taps alike (spec 89). It starts
    /// on the touch, so the row moves with the finger's first point of
    /// travel; a tap of its own on each icon held a drag back until the tap
    /// gave up, about ten points in, and the row then caught up with a jump.
    /// A press that hardly moves is a tap on the icon under it.
    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragStart?.location != gesture.startLocation {
                    dragStart = (gesture.startLocation, position)
                }
                guard let start = dragStart?.position else { return }
                position = start - Double(gesture.translation.width / Self.step)
                pick(Int(position.rounded()))
            }
            .onEnded { gesture in
                dragStart = nil
                if abs(gesture.translation.width) < Self.tapSlop, abs(gesture.translation.height) < Self.tapSlop {
                    let across = Double((gesture.location.x - width / 2) / Self.step)
                    bring(Int((position + across).rounded()))
                    return
                }
                // The row is already where the finger left it; the drag's
                // momentum carries it on by the rest of the predicted travel.
                let momentum = Double(
                    (gesture.predictedEndTranslation.width - gesture.translation.width) / Self.step
                )
                settle(at: (position - min(Self.maxFling, max(-Self.maxFling, momentum))).rounded())
            }
    }

    private func settle(at target: Double) {
        withAnimation(Self.settle) { position = target }
        pick(Int(target))
    }

    /// Brings icon `k` to the middle.
    private func bring(_ k: Int) {
        settle(at: Double(k))
    }

    /// Plays icon `k`'s set, with a tick, unless it already is.
    private func pick(_ k: Int) {
        guard k != picked else { return }
        picked = k
        let set = Self.set(at: k)
        guard set.id != store.selectedSetId else { return }
        Haptics.shared.selectionChanged()
        store.apply(set)
    }

    static func set(at k: Int) -> PaletteSet {
        let count = PaletteSet.all.count
        return PaletteSet.all[(k % count + count) % count]
    }

    /// Marks the middle, where the set in play rests.
    private var ring: some View {
        let side = Self.iconSize + 2 * Self.ringGap
        return RoundedRectangle(
            cornerRadius: Self.iconSize * AppIconView.cornerRatio + Self.ringGap, style: .continuous
        )
        .strokeBorder(Color.primary, lineWidth: 2)
        .frame(width: side, height: side)
    }

    /// The icons around `position`, laid out from it. Animatable by
    /// `position`, so a settle redraws the whole row at every step of the
    /// spring — icons coming into view on the way included — rather than
    /// only moving the icons that were already drawn.
    private struct Strip: View, Animatable {
        var position: Double
        let picked: Int
        let colors: (PaletteSet) -> [UInt32]
        /// For VoiceOver; a tap on screen goes through the row's gesture.
        let onTap: (Int) -> Void

        var animatableData: Double {
            get { position }
            set { position = newValue }
        }

        var body: some View {
            let middle = Int(position.rounded())
            // Placed by `position`, not shifted by `offset`: an offset only
            // moves the drawing, leaving every icon's frame — what taps and
            // accessibility go by — piled up in the middle.
            GeometryReader { geo in
                ForEach((middle - IconCarousel.reach)...(middle + IconCarousel.reach), id: \.self) { k in
                    icon(k)
                        .position(
                            x: geo.size.width / 2 + CGFloat(Double(k) - position) * IconCarousel.step,
                            y: geo.size.height / 2
                        )
                }
            }
        }

        private func icon(_ k: Int) -> some View {
            let set = IconCarousel.set(at: k)
            let offset = Double(k) - position
            let away = min(1, abs(offset))
            return AppIconView(set: set, size: IconCarousel.iconSize, colors: colors(set))
                .scaleEffect(1 - IconCarousel.sideShrink * away)
                .opacity(1 - IconCarousel.sideFade * away)
                .accessibilityElement()
                .accessibilityIdentifier("paletteSet.\(set.id)")
                .accessibilityLabel(Text(verbatim: set.name))
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(k == picked ? .isSelected : [])
                .accessibilityAction { onTap(k) }
        }
    }
}

