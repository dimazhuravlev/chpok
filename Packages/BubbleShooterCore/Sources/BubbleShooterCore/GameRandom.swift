import Foundation

/// Source of randomness injected into `GameEngine`, so gameplay can be made
/// deterministic/reproducible in tests. Not present in the original (which
/// always calls `Math.random()` directly) — added per spec so tests can be
/// deterministic.
public protocol GameRandom {
    /// Returns a value in `0 ..< upperBound`.
    mutating func nextInt(upperBound: Int) -> Int
}

/// Non-deterministic randomness backed by Swift's standard RNG. Used for real
/// play; equivalent in spirit to the original's `Math.random()`.
public struct SystemGameRandom: GameRandom {
    public init() {}

    public mutating func nextInt(upperBound: Int) -> Int {
        Int.random(in: 0..<upperBound)
    }
}

/// Deterministic randomness for tests, backed by the SplitMix64 algorithm.
public struct SeededGameRandom: GameRandom {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        let value = nextUInt64()
        return Int(value % UInt64(upperBound))
    }

    private mutating func nextUInt64() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
