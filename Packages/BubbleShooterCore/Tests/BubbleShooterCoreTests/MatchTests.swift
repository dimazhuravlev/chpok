import XCTest
@testable import BubbleShooterCore

/// Cluster match + scoring tests (game-logic.md §7/§8):
/// `GameConsts.clusterPointsPerStep * ceil(k/3)` per removed bubble, summed
/// over the whole cluster.
final class MatchTests: XCTestCase {

    // (a) row 0: red at columns 7,8,9, blue everywhere else; a vertical red
    // shot joins the red trio into a 4-cluster.
    func testFourClusterScoreAndSurvivors() {
        var board: [GameSnapshot.BubbleRecord] = []
        for col in 0...16 {
            let color: BubbleColor = (7...9).contains(col) ? .red : .blue
            board.append(GameSnapshot.BubbleRecord(boardX: col, boardY: 0, color: color))
        }
        let engine = GameEngine(board: board, readyColor: .red, queueColor: .blue, random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600)

        XCTAssertTrue(engine.fire(angleDegrees: 0))
        engine.runUntilIdle()

        let events = engine.drainEvents()
        let removedMatch: [(color: BubbleColor, points: Int)] = events.compactMap {
            if case let .removed(_, color, _, points, reason) = $0, reason == .match {
                return (color, points)
            }
            return nil
        }

        XCTAssertEqual(removedMatch.count, 4)
        XCTAssertTrue(removedMatch.allSatisfy { $0.color == .red })
        // §8: k=1..4 -> ceil(k/3) = 1,1,1,2. Emission order follows the
        // *geometric* sort (bottom-to-top, then left-to-right, §8), a
        // different ordering than the k used to compute each bubble's own
        // score — so only the multiset of points (not necessarily the
        // chronological sequence) is guaranteed to be {1,1,1,2}.
        XCTAssertEqual(removedMatch.map(\.points).sorted(), [1, 1, 1, 2])
        XCTAssertEqual(removedMatch.map(\.points).reduce(0, +), 5)

        XCTAssertEqual(engine.score, 5)
        XCTAssertEqual(engine.livesLeft, 5, "a match must not cost a life")
        XCTAssertEqual(engine.boardBubbles.filter { $0.color == .blue }.count, 14)
        XCTAssertTrue(engine.boardBubbles.allSatisfy { $0.color == .blue })
    }

    // (b) score scales with cluster size: a red chain of length L in row 0
    // (columns 8..8+L-1) plus a red shot from below (which collides with
    // (8,0) and lands adjacent to it, joining the chain) makes a cluster of
    // N = L+1; total score is sum(ceil(k/3), k=1...N).
    func testClusterScoreScalesWithSize() {
        let expectedTotalByClusterSize: [Int: Int] = [3: 3, 4: 5, 5: 7, 6: 9, 7: 12]

        for chainLength in 2...6 {
            let clusterSize = chainLength + 1
            var board: [GameSnapshot.BubbleRecord] = []
            for offset in 0..<chainLength {
                board.append(GameSnapshot.BubbleRecord(boardX: 8 + offset, boardY: 0, color: .red))
            }
            let engine = GameEngine(board: board, readyColor: .red, queueColor: .blue, random: SeededGameRandom(seed: 1))
            engine.advance(ms: 600)

            XCTAssertTrue(engine.fire(angleDegrees: 0), "chain length \(chainLength)")
            engine.runUntilIdle()

            let events = engine.drainEvents()
            let removedMatch: [Int] = events.compactMap {
                if case let .removed(_, _, _, points, reason) = $0, reason == .match {
                    return points
                }
                return nil
            }

            XCTAssertEqual(removedMatch.count, clusterSize, "chain length \(chainLength): cluster size")
            XCTAssertEqual(
                removedMatch.reduce(0, +),
                expectedTotalByClusterSize[clusterSize],
                "chain length \(chainLength): total score for cluster size \(clusterSize)"
            )
            XCTAssertEqual(engine.score, expectedTotalByClusterSize[clusterSize])
        }
    }
}
