import Foundation

/// Serializable state of a match, only obtainable while the engine is idle
/// (see `GameEngine.snapshot()`).
public struct GameSnapshot: Codable, Equatable {
    public struct BubbleRecord: Codable, Equatable, Hashable {
        public var boardX: Int
        public var boardY: Int
        public var color: BubbleColor

        public init(boardX: Int, boardY: Int, color: BubbleColor) {
            self.boardX = boardX
            self.boardY = boardY
            self.color = color
        }
    }

    public var bubbles: [BubbleRecord]
    public var readyColor: BubbleColor
    public var queueColor: BubbleColor
    public var score: Int
    public var livesLeft: Int
    public var maxLives: Int
    public var totalColors: Int
    /// Spec 13: `GameEngine.rowParity` at the time of the snapshot — needed
    /// to reconstruct which rows are wide vs. narrow (`Grid.isWideRow`) on
    /// restore. Required for `Codable` (no `decodeIfPresent` fallback): a
    /// snapshot encoded before spec 13 has no matching board shape anyway
    /// (it was a uniform 17-wide grid), so failing to decode an old save
    /// rather than silently guessing a parity is the correct behaviour —
    /// see `GameSaveStore.load()`.
    public var rowParity: Int
    /// Spec 22: `GameEngine.matchElapsedMs` at the time of the snapshot —
    /// active match time (foreground-only), restored so it keeps growing
    /// from this value rather than resetting on resume.
    public var elapsedMs: Int

    public init(
        bubbles: [BubbleRecord],
        readyColor: BubbleColor,
        queueColor: BubbleColor,
        score: Int,
        livesLeft: Int,
        maxLives: Int,
        totalColors: Int,
        rowParity: Int = 0,
        elapsedMs: Int = 0
    ) {
        self.bubbles = bubbles
        self.readyColor = readyColor
        self.queueColor = queueColor
        self.score = score
        self.livesLeft = livesLeft
        self.maxLives = maxLives
        self.totalColors = totalColors
        self.rowParity = rowParity
        self.elapsedMs = elapsedMs
    }
}
