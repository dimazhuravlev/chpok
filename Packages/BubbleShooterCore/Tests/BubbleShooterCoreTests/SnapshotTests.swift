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

    /// Spec 13: `rowParity` must round-trip through both
    /// `GameEngine(snapshot:)` and JSON, and `init(snapshot:)` must use it
    /// (not the default 0) when placing the restored board bubbles.
    func testSnapshotRoundTripPreservesNonZeroRowParity() throws {
        let snapshot = GameSnapshot(
            bubbles: [
                .init(boardX: 0, boardY: 0, color: .red),
                .init(boardX: 15, boardY: 1, color: .blue),
            ],
            readyColor: .green,
            queueColor: .yellow,
            score: 10,
            livesLeft: 3,
            maxLives: 5,
            totalColors: 6,
            rowParity: 1
        )

        let restored = GameEngine(snapshot: snapshot, random: SeededGameRandom(seed: 1))
        XCTAssertEqual(restored.rowParity, 1)
        XCTAssertEqual(restored.snapshot(), snapshot)

        // rowParity 1 means boardY 0 is narrow: (0,0) offset by +16, not
        // the rowParity-0 wide-row 0 offset.
        let cell00 = restored.boardBubbles.first { $0.boardX == 0 && $0.boardY == 0 }
        XCTAssertEqual(cell00?.position, Grid.realCoord(boardX: 0, boardY: 0, rowParity: 1))
        XCTAssertEqual(cell00?.position.x, 56)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: data)
        XCTAssertEqual(decoded.rowParity, 1)
        XCTAssertEqual(decoded, snapshot)
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
