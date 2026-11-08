import SwiftUI

/// The background slider (spec 73): a thick capsule with a capsule inside it,
/// `inset` in from its edge, that grows from the left end to the value — a
/// disc at 0, the whole inside at 1. The inner capsule shows the range,
/// `stops`, pinned to the track rather than to itself, so its right end is
/// always the color the value picks.
///
/// Only the inner capsule can be taken, and only dragged (spec 77): a press
/// on the empty track moves nothing, and a tap on the capsule doesn't move it
/// either — both only nudge it, below.
/// Taken anywhere along it, it moves by as much as the finger does, without
/// jumping to the finger first.
///
/// Alive under the finger: a press anywhere on it reaches the inner capsule a
/// little further right, `nudgeDistance`, and lets it back when the finger
/// lifts or starts to drag (spec 88) — less where there's less room, not at
/// all at 1; it swells a little while held; the inner capsule trails the
/// finger on a quick spring; dragged past an end the whole capsule
/// stretches after the finger, rubber-banded, thinning as it does, and
/// springs back with a wobble when let go.
/// Haptics: a soft bump as it's taken, a tick at each of `detents`, a firmer
/// knock at either end, a soft bump as a stretched one springs back.
struct CapsuleSlider: View {
    @Binding var value: Double
    /// Colors along the range, spread evenly from 0 to 1.
    let stops: [Color]
    /// Values that tick as the inner capsule passes them.
    var detents: [Double] = []
    /// Called when the finger lifts, and after a VoiceOver step.
    var onEditingEnded: () -> Void = {}

    static let height: CGFloat = 56
    static let inset: CGFloat = 6
    /// Swell while held.
    private static let heldScale: CGFloat = 1.03
    /// Longest stretch past an end, points; finger travel past the end that
    /// gets about two thirds of it.
    private static let maxStretch: CGFloat = 22
    private static let stretchReach: CGFloat = 70
    /// Thinning per point of stretch, in capsule heights: keeps it looking
    /// like the same amount of jelly pulled longer.
    private static let thinning: CGFloat = 0.5
    /// The inner capsule following the finger.
    private static let follow = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.8)
    /// The stretch springing back on release, with a wobble.
    private static let springBack = Animation.spring(response: 0.5, dampingFraction: 0.45)
    private static let swell = Animation.spring(response: 0.3, dampingFraction: 0.6)
    /// How far a press reaches the inner capsule on, and the finger travel
    /// after which a drag takes over from it.
    private static let nudgeDistance: CGFloat = 8
    private static let nudgeDragOver: CGFloat = 4
    private static let nudgeSpring = Animation.spring(response: 0.3, dampingFraction: 0.75)
    private static let space = "capsuleSlider"

    @State private var isHeld = false
    /// The press in progress; `nil` between presses.
    @State private var press: Press?
    /// How much further the inner capsule reaches than the value, points:
    /// the press nudge.
    @State private var nudge: CGFloat = 0
    /// Signed stretch past an end, points: negative past the left one.
    @State private var stretch: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let inner = CGSize(width: max(0, width - 2 * Self.inset), height: Self.height - 2 * Self.inset)
            let fill = min(inner.width, inner.height + max(0, inner.width - inner.height) * value + nudge)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
                    .frame(width: inner.width, height: inner.height)
                    .mask(alignment: .leading) { Capsule().frame(width: fill) }
                    // A hairline keeps the dark end apart from a dark track;
                    // faint, just enough for that (spec 84).
                    .overlay(alignment: .leading) {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                            .frame(width: fill)
                    }
                    .padding(Self.inset)
            }
            .scaleEffect(
                x: 1 + abs(stretch) / max(width, 1),
                y: 1 - Self.thinning * abs(stretch) / Self.height,
                anchor: stretch < 0 ? .trailing : .leading
            )
            .scaleEffect(isHeld ? Self.heldScale : 1)
            .contentShape(Capsule())
            .gesture(drag(width: width, inner: inner))
        }
        .coordinateSpace(name: Self.space)
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "background"))
        .accessibilityValue(Text(verbatim: "\(Int((value * 100).rounded()))%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: return
            }
            onEditingEnded()
        }
    }

    /// Where a press began on the slider, and the value then if it took the
    /// inner capsule (`grabbed`; `nil` for one that began off it, which
    /// moves nothing). Told from the last press by where it began, so one
    /// the system cancelled — `onEnded` never hears of that — is let go of
    /// when the next comes. (Not a `@GestureState`: in the icon carousel
    /// one reset itself in the middle of drags.)
    private struct Press {
        let location: CGPoint
        let grabbed: Double?
    }

    private func drag(width: CGFloat, inner: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { gesture in
                let span = max(1, inner.width - inner.height)
                if press?.location != gesture.startLocation {
                    if press != nil { release() }
                    begin(at: gesture.startLocation, inner: inner, span: span)
                }
                guard let grabbed = press?.grabbed else { return }
                if nudge != 0, abs(gesture.translation.width) > Self.nudgeDragOver {
                    withAnimation(Self.follow) { nudge = 0 }
                }
                // Where the finger has taken the capsule's end, in points
                // along the track past the start; past either end it pulls
                // the stretch instead.
                let along = CGFloat(grabbed) * span + gesture.translation.width
                let past = along < 0 ? along : max(0, along - span)
                let newValue = min(1, max(0, Double(along / span)))
                tick(from: value, to: newValue)
                withAnimation(Self.follow) {
                    value = newValue
                    stretch = Self.rubberBand(past)
                }
            }
            .onEnded { _ in release() }
    }

    /// A finger comes down: the inner capsule reaches on a little, and if
    /// the press is on it — give or take the inset around it — it's taken.
    private func begin(at location: CGPoint, inner: CGSize, span: CGFloat) {
        let fillEnd = Self.inset + inner.height + span * value
        let onCapsule = location.x <= fillEnd + Self.inset
        press = Press(location: location, grabbed: onCapsule ? value : nil)
        withAnimation(Self.nudgeSpring) {
            nudge = min(Self.nudgeDistance, span * (1 - value))
        }
        guard onCapsule else { return }
        Haptics.shared.sliderGrabbed()
        withAnimation(Self.swell) { isHeld = true }
    }

    /// The finger is off: the nudge goes back; a stretched capsule springs
    /// back, and a held one is let go and its value saved.
    private func release() {
        let wasHeld = press?.grabbed != nil
        press = nil
        withAnimation(Self.nudgeSpring) { nudge = 0 }
        guard wasHeld else { return }
        if stretch != 0 { Haptics.shared.sliderSprangBack() }
        withAnimation(Self.springBack) { stretch = 0 }
        withAnimation(Self.swell) { isHeld = false }
        onEditingEnded()
    }

    /// A knock on reaching an end, else a tick on passing a detent.
    private func tick(from old: Double, to new: Double) {
        guard old != new else { return }
        if new == 0 || new == 1 {
            Haptics.shared.sliderReachedEnd()
        } else if detents.contains(where: { (old < $0) != (new < $0) }) {
            Haptics.shared.sliderTicked()
        }
    }

    /// Finger travel past an end, signed, to the stretch it pulls: all of it
    /// at first, less and less, never more than `maxStretch`.
    private static func rubberBand(_ past: CGFloat) -> CGFloat {
        let pulled = maxStretch * (1 - exp(-abs(past) / stretchReach))
        return past < 0 ? -pulled : pulled
    }
}
