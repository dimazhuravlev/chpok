import UIKit
import BubbleShooterCore

/// Maps `GameEvent`s and button taps to short tactile feedback. Shared
/// across the app (`.shared`) so both the game scene and the SwiftUI chrome
/// (HUD, game-over screen) drive the same generators. `prepareForShot()`
/// primes the pop generator right before a shot, when a pop is likely within
/// the next ~0.5-1s. New events get a haptic by adding one line to
/// `handle(_:)`.
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
        pop.impactOccurred(intensity: 0.7)
    }

    func buttonTapped() {
        button.impactOccurred(intensity: 1.0)
    }

    func handle(_ event: GameEvent) {
        switch event {
        case .removed:
            bubblePopped()
        default:
            break
        }
    }
}
