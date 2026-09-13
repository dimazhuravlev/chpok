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

    public init(
        bubbles: [BubbleRecord],
        readyColor: BubbleColor,
        queueColor: BubbleColor,
        score: Int,
        livesLeft: Int,
        maxLives: Int,
        totalColors: Int
    ) {
        self.bubbles = bubbles
        self.readyColor = readyColor
        self.queueColor = queueColor
        self.score = score
        self.livesLeft = livesLeft
        self.maxLives = maxLives
        self.totalColors = totalColors
    }
}
