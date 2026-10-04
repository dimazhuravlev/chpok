import UIKit
import BubbleShooterCore

/// Maps `GameEvent`s and button taps to short tactile feedback. Shared
/// across the app (`.shared`) so both the game scene and the SwiftUI chrome
/// (HUD, game-over screen) drive the same generators. `prepareForShot()`
/// primes the pop generator right before a shot, when a pop is likely within
/// the next ~0.5-1s, and again when a cluster matches (the bridge wave is
/// long). A match is voiced by its bridges, one pop each (spec 43): the merge
/// effect calls `bubblePopped()` as every bridge appears, so `handle(_:)`
/// only voices bubbles that fall off as hanging. New events get a haptic by
/// adding one line to `handle(_:)`.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private let pop = UIImpactFeedbackGenerator(style: .light)
    /// Separate generator for deliberate button taps ("new game", "restart")
    /// — `.medium`, heavier than the bubble-pop's `.light`, so a button press
    /// reads as a distinct, deliberate action instead of blending into the
    /// in-game pop feedback.
    private let button = UIImpactFeedbackGenerator(style: .medium)

    func prepareForShot() {
        pop.prepare()
    }

    func prepareForButton() {
        button.prepare()
    }

    func bubblePopped() {
        pop.impactOccurred(intensity: 0.5)
    }

    func buttonTapped() {
        button.impactOccurred(intensity: 1.0)
    }

    /// A match is voiced by the bridges of its merge effect, not by the
    /// per-bubble `.removed` events, so only hanging bubbles pop here; the
    /// match itself just primes the generator for the long bridge wave.
    func handle(_ event: GameEvent) {
        switch event {
        case .clusterMatched:
            pop.prepare()
        case let .removed(_, _, _, _, reason) where reason == .hanging:
            bubblePopped()
        default:
            break
        }
    }
}
