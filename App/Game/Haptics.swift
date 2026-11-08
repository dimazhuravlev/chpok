import UIKit
import BubbleShooterCore

/// Maps `GameEvent`s and button taps to short tactile feedback. Shared
/// across the app (`.shared`) so both the game scene and the SwiftUI chrome
/// (HUD, game-over screen) drive the same generators. `prepareForShot()`
/// primes the pop generator right before a shot, when a pop is likely within
/// the next ~0.5-1s, and again when a cluster matches (the bridge wave is
/// long). A match is voiced by the scene (spec 43, 51): in the default
/// `.pops` mode `GameScene.animateRemoval` calls `bubblePopped()` on every
/// bubble's pop, in `.bridges` the merge effect does as every bridge appears,
/// so `handle(_:)` only voices bubbles that fall off as hanging. New events get a haptic by
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

    /// Gentle tick for picking a row in the palette-sets test sheet (spec 56).
    private let selection = UISelectionFeedbackGenerator()

    /// The board going out and coming in (spec 70): a series of faint ticks,
    /// one per bubble but never closer together than `seriesInterval`, so
    /// the row-by-row wave reads as a light, even texture rather than a
    /// buzz. The same soft tick both ways: as each bubble lets go in a
    /// restart's collapse, and as each lands in a pour.
    private let series = UIImpactFeedbackGenerator(style: .soft)
    private static let seriesInterval: TimeInterval = 0.045
    private static let seriesIntensity: CGFloat = 0.7
    private var lastSeriesTick: TimeInterval = 0

    func prepareForShot() {
        pop.prepare()
    }

    func prepareForButton() {
        button.prepare()
    }

    func bubblePopped() {
        pop.impactOccurred(intensity: 0.5)
    }

    /// The flying bubble hits a side wall or lands — against bubbles or the
    /// ceiling (spec 61): half as strong as a pop.
    func bubbleHit() {
        pop.impactOccurred(intensity: 0.25)
    }

    /// Primes the series generator: a collapse or a pour is about to start.
    func prepareForBoardChange() {
        series.prepare()
    }

    /// A bubble starts falling in a restart's collapse.
    func boardBubbleLetGo() {
        seriesTick()
    }

    /// A poured bubble lands in its cell.
    func boardBubbleSettled() {
        seriesTick()
    }

    private func seriesTick() {
        let now = CACurrentMediaTime()
        guard now - lastSeriesTick >= Self.seriesInterval else { return }
        lastSeriesTick = now
        series.impactOccurred(intensity: Self.seriesIntensity)
    }

    func selectionChanged() {
        selection.selectionChanged()
    }

    // MARK: - Background slider (spec 73)

    /// A soft bump as the finger takes the slider and, fainter, as it lets
    /// go of a stretched one; a firmer knock when the value reaches either
    /// end. The steps in between tick with `selection`.
    private let sliderSoft = UIImpactFeedbackGenerator(style: .soft)
    private let sliderEnd = UIImpactFeedbackGenerator(style: .rigid)

    func sliderGrabbed() {
        sliderSoft.impactOccurred(intensity: 0.7)
        selection.prepare()
        sliderEnd.prepare()
    }

    func sliderTicked() {
        selection.selectionChanged()
    }

    func sliderReachedEnd() {
        sliderEnd.impactOccurred(intensity: 0.8)
    }

    func sliderSprangBack() {
        sliderSoft.impactOccurred(intensity: 0.45)
    }

    func buttonTapped() {
        button.impactOccurred(intensity: 1.0)
    }

    /// A match is voiced elsewhere — `GameScene.animateRemoval` in `.pops`
    /// (one haptic per pop), the bridges of the merge effect in `.bridges` —
    /// so `.match` removals stay silent here and only hanging bubbles pop;
    /// the match itself just primes the generator for the long wave.
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
