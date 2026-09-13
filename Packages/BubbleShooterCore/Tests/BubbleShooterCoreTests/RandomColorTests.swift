import XCTest
@testable import BubbleShooterCore

/// `getRandomColor(fullyRandom: false)` tests (game-logic.md §14): every
/// freshly-drawn queue color must already be present among *all* bubbles
/// (board + ready + queue + launched), never an arbitrary/unseen color.
final class RandomColorTests: XCTestCase {

    func testQueueColorsAlwaysAmongPresentColors() {
        let engine = GameEngine(random: SeededGameRandom(seed: 5))
        engine.advance(ms: 600)

        let angles: [Double] = [-60, -30, 0, 30, 60]
        var checkedEvents = 0

        for i in 0..<25 {
            guard engine.canFire else { break }
            XCTAssertTrue(engine.fire(angleDegrees: angles[i % angles.count]), "shot \(i)")
            engine.runUntilIdle()

            let events = engine.drainEvents()
            // Checked right after this shot's own resolution: at most one
            // .queueBubbleChanged fires per shot (addNewBubble is called
            // exactly once, from either the miss or the match path — a
            // row-add never calls it directly), so this snapshot of
            // `bubbles` accurately reflects "at the moment of the event".
            let presentColors = Set(engine.bubbles.map { $0.color })
            for event in events {
                if case let .queueBubbleChanged(_, color) = event {
                    checkedEvents += 1
                    XCTAssertTrue(presentColors.contains(color),
                                   "shot \(i): new queue color \(color) not among present colors \(presentColors)")
                }
            }
        }

        XCTAssertGreaterThan(checkedEvents, 0, "the scenario should have produced at least one queue-color draw")
    }

    // A board where red is the only color anywhere: rejection sampling
    // (§14) can only ever draw red, regardless of the RNG source.
    func testOnlyPresentColorIsDrawnWhenBoardIsMonochrome() {
        let board: [GameSnapshot.BubbleRecord] = (0...16).map { .init(boardX: $0, boardY: 0, color: .red) }
        let engine = GameEngine(board: board, readyColor: .red, queueColor: .red, random: SeededGameRandom(seed: 3))
        engine.advance(ms: 600)

        let angles: [Double] = [0, -30, 30, -60, 60, -15, 15, 0, -45, 45]
        var checkedEvents = 0

        for i in 0..<10 {
            guard engine.canFire else { break }
            XCTAssertTrue(engine.fire(angleDegrees: angles[i % angles.count]), "shot \(i)")
            engine.runUntilIdle()

            for event in engine.drainEvents() {
                if case let .queueBubbleChanged(_, color) = event {
                    checkedEvents += 1
                    XCTAssertEqual(color, .red, "shot \(i): only red was ever present")
                }
                if case let .readyBubbleChanged(_, color) = event {
                    XCTAssertEqual(color, .red, "shot \(i): only red was ever present")
                }
            }
        }

        XCTAssertGreaterThan(checkedEvents, 0, "the scenario should have produced at least one queue-color draw")
    }
}
