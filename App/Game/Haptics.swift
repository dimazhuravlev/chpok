import UIKit
import BubbleShooterCore

/// Maps `GameEvent`s to short tactile feedback. One generator per scene;
/// `prepareForShot()` primes it right before a shot, when a pop is likely
/// within the next ~0.5-1s. New events get a haptic by adding one line to
/// `handle(_:)`.
@MainActor
final class Haptics {
    private let pop = UIImpactFeedbackGenerator(style: .light)

    func prepareForShot() {
        pop.prepare()
    }

    func bubblePopped() {
        pop.impactOccurred(intensity: 0.7)
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
