import Foundation
@testable import BubbleShooterCore

/// A `GameRandom` that serves values from a fixed queue first (each taken
/// modulo the requested `upperBound`), then falls back to a
/// `SeededGameRandom` once the queue is exhausted — lets tests steer which
/// colors/outcomes come next (e.g. to avoid accidental same-color matches)
/// while staying fully deterministic even if the queue runs dry, per
/// 04-core-tests.md's "приём для управляемой случайности".
struct ScriptedRandom: GameRandom {
    private var queue: [Int]
    private var fallback: SeededGameRandom

    init(_ values: [Int], fallbackSeed: UInt64 = 999) {
        self.queue = values
        self.fallback = SeededGameRandom(seed: fallbackSeed)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        if !queue.isEmpty {
            let value = queue.removeFirst()
            return ((value % upperBound) + upperBound) % upperBound
        }
        return fallback.nextInt(upperBound: upperBound)
    }
}
