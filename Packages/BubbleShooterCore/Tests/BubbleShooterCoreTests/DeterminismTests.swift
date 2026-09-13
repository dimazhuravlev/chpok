import XCTest
@testable import BubbleShooterCore

/// Determinism tests: two engines seeded identically and driven by an
/// identical shot sequence must stay in lockstep — same score, same events,
/// tick for tick.
final class DeterminismTests: XCTestCase {

    func testIdenticalSeedsAndShotsProduceIdenticalRuns() {
        let a = GameEngine(random: SeededGameRandom(seed: 11))
        let b = GameEngine(random: SeededGameRandom(seed: 11))
        a.advance(ms: 600)
        b.advance(ms: 600)
        XCTAssertEqual(a.drainEvents(), b.drainEvents())

        let angles: [Double] = [-60, -45, -30, -15, 0, 15, 30, 45, 60, -50, -20, 10, 40, 65, -65]
        XCTAssertEqual(angles.count, 15)

        for (i, angle) in angles.enumerated() {
            XCTAssertEqual(a.canFire, b.canFire, "shot \(i): canFire should agree")
            guard a.canFire, b.canFire else { break }

            XCTAssertEqual(a.fire(angleDegrees: angle), b.fire(angleDegrees: angle), "shot \(i): fire() result")
            a.runUntilIdle()
            b.runUntilIdle()

            XCTAssertEqual(a.score, b.score, "shot \(i): score")
            XCTAssertEqual(a.drainEvents(), b.drainEvents(), "shot \(i): events")
            XCTAssertEqual(a.livesLeft, b.livesLeft, "shot \(i): livesLeft")
            XCTAssertEqual(a.isGameOver, b.isGameOver, "shot \(i): isGameOver")
        }
    }
}
