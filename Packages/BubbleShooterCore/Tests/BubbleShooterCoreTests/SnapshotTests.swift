import XCTest
@testable import BubbleShooterCore

/// `GameSnapshot` tests: available only while idle, round-trips through
/// `GameEngine(snapshot:)` and through `JSONEncoder`/`JSONDecoder`.
final class SnapshotTests: XCTestCase {

    func testSnapshotAvailableWhileIdle() {
        let engine = GameEngine(random: SeededGameRandom(seed: 42))
        XCTAssertTrue(engine.isIdle)
        XCTAssertNotNil(engine.snapshot())
    }

    func testSnapshotRoundTripThroughEngine() {
        let engine = GameEngine(random: SeededGameRandom(seed: 42))
        guard let snapshot = engine.snapshot() else {
            XCTFail("expected a snapshot while idle")
            return
        }

        let restored = GameEngine(snapshot: snapshot, random: SeededGameRandom(seed: 1))

        XCTAssertEqual(restored.snapshot(), snapshot)
        XCTAssertEqual(restored.score, engine.score)
        XCTAssertEqual(restored.livesLeft, engine.livesLeft)
        XCTAssertEqual(restored.maxLives, engine.maxLives)
        XCTAssertEqual(restored.totalColors, engine.totalColors)

        let originalCoords = Set(engine.boardBubbles.map { GameSnapshot.BubbleRecord(boardX: $0.boardX, boardY: $0.boardY, color: $0.color) })
        let restoredCoords = Set(restored.boardBubbles.map { GameSnapshot.BubbleRecord(boardX: $0.boardX, boardY: $0.boardY, color: $0.color) })
        XCTAssertEqual(restoredCoords, originalCoords)
    }

    func testSnapshotNilDuringFlight() {
        let engine = GameEngine(random: SeededGameRandom(seed: 42))
        engine.advance(ms: 600)

        XCTAssertTrue(engine.fire(angleDegrees: 0))
        XCTAssertFalse(engine.isIdle)
        XCTAssertNil(engine.snapshot())
    }

    func testSnapshotJSONRoundTrip() throws {
        let engine = GameEngine(random: SeededGameRandom(seed: 42))
        guard let snapshot = engine.snapshot() else {
            XCTFail("expected a snapshot while idle")
            return
        }

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }
}
