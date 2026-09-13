import XCTest
@testable import BubbleShooterCore

/// Timing tests (game-logic.md §15/§16). `GameEvent` carries no timestamp,
/// so these tests tick manually (rather than `runUntilIdle()`) and record
/// `engine.timeMs` at the tick each event is observed on.
final class TimingTests: XCTestCase {

    /// Ticks until idle (or `maxTicks`), recording `engine.timeMs` for every
    /// tick that produced at least one event, tagged with those events.
    private func recordEventTimes(_ engine: GameEngine, maxTicks: Int = 5000) -> [(timeMs: Int, events: [GameEvent])] {
        var log: [(Int, [GameEvent])] = []
        var ticks = 0
        while !engine.isIdle, ticks < maxTicks {
            engine.tick()
            ticks += 1
            let events = engine.drainEvents()
            if !events.isEmpty {
                log.append((engine.timeMs, events))
            }
        }
        return log
    }

    // A 3-cluster match: consecutive .removed events land ~70ms apart in
    // scheduling (§8's `70*i`), observed here rounded up to the nearest
    // 15ms tick boundary (so up to 75ms apart, never less than 70).
    func testRemovalsAreStaggered70msApart() {
        let board: [GameSnapshot.BubbleRecord] = [
            .init(boardX: 8, boardY: 0, color: .red),
            .init(boardX: 9, boardY: 0, color: .red),
        ]
        let engine = GameEngine(board: board, readyColor: .red, queueColor: .blue, random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600)
        XCTAssertTrue(engine.fire(angleDegrees: 0))

        let log = recordEventTimes(engine)

        var removedTimes: [Int] = []
        var turnResolvedTimes: [Int] = []
        var lastRemovedTime: Int?
        for (timeMs, events) in log {
            for e in events {
                if case .removed = e {
                    removedTimes.append(timeMs)
                    lastRemovedTime = timeMs
                }
                if case .turnResolved = e {
                    turnResolvedTimes.append(timeMs)
                }
            }
        }

        XCTAssertEqual(removedTimes.count, 3, "expected a 3-bubble cluster")
        for i in 1..<removedTimes.count {
            let delta = removedTimes[i] - removedTimes[i - 1]
            XCTAssertTrue((60...75).contains(delta), "removed[\(i - 1)]->removed[\(i)] delta \(delta)ms out of [60,75]")
        }

        // .turnResolved fires exactly once per shot, after every .removed.
        XCTAssertEqual(turnResolvedTimes.count, 1)
        if let last = lastRemovedTime, let resolved = turnResolvedTimes.first {
            XCTAssertGreaterThanOrEqual(resolved, last, ".turnResolved must not precede the last .removed")
        }
    }

    // A miss that exhausts the last life adds a row ~100ms after landing
    // (§10's `addRowDelayMs`), observed rounded up to the next 15ms tick.
    func testRowAddFiresAbout100msAfterLanding() {
        let board: [GameSnapshot.BubbleRecord] = (0...16).map { .init(boardX: $0, boardY: 0, color: .red) }
        let engine = GameEngine(
            board: board, readyColor: .blue, queueColor: .blue,
            livesLeft: 0, maxLives: 5, totalColors: 6,
            random: SeededGameRandom(seed: 1)
        )
        engine.advance(ms: 600)
        // blue doesn't match anything on an all-red board: guaranteed miss.
        XCTAssertTrue(engine.fire(angleDegrees: 0))

        let log = recordEventTimes(engine)

        var landedTime: Int?
        var rowsAddedTime: Int?
        for (timeMs, events) in log {
            for e in events {
                if case .landed = e { landedTime = timeMs }
                if case .rowsAdded = e { rowsAddedTime = timeMs }
            }
        }

        guard let landed = landedTime, let rowsAdded = rowsAddedTime else {
            XCTFail("expected both .landed and .rowsAdded events")
            return
        }
        let delta = rowsAdded - landed
        XCTAssertTrue((100...114).contains(delta), ".rowsAdded fired \(delta)ms after landing, expected ~100ms (rounded up to the next 15ms tick)")
    }

    // Exactly one .turnResolved per shot, regardless of whether it was a
    // clean miss (no removals at all).
    func testTurnResolvedFiresExactlyOncePerShotOnAMiss() {
        let engine = GameEngine(board: [], readyColor: .red, queueColor: .blue, random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600)
        XCTAssertTrue(engine.fire(angleDegrees: 0))

        let log = recordEventTimes(engine)
        let turnResolvedCount = log.flatMap(\.events).filter {
            if case .turnResolved = $0 { return true }
            return false
        }.count
        XCTAssertEqual(turnResolvedCount, 1)
    }
}
