import XCTest
@testable import BubbleShooterCore

/// Spec 60: `predictedPath(toward:)` traces the same flight a real shot
/// takes — every in-flight position lies on it, bounces sit on the walls,
/// and it ends where the bubble stops.
final class PredictedPathTests: XCTestCase {

    private func readyEngine(seed: UInt64 = 42) -> GameEngine {
        let engine = GameEngine(random: SeededGameRandom(seed: seed))
        engine.advance(ms: 510) // clear the post-init cannon lockout
        return engine
    }

    /// Distance from `p` to the polyline `path`.
    private func distance(_ p: Vec2, to path: [Vec2]) -> Double {
        var best = Double.infinity
        for (a, b) in zip(path, path.dropFirst()) {
            let abx = b.x - a.x, aby = b.y - a.y
            let length2 = abx * abx + aby * aby
            let t = length2 > 0 ? max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / length2)) : 0
            best = min(best, p.distance(to: Vec2(x: a.x + t * abx, y: a.y + t * aby)))
        }
        return best
    }

    /// Fires toward `point` and checks the real flight against the path
    /// predicted just before; returns the path.
    @discardableResult
    private func assertFlightFollowsPath(_ engine: GameEngine, toward point: Vec2,
                                         file: StaticString = #filePath, line: UInt = #line) -> [Vec2] {
        guard let path = engine.predictedPath(toward: point) else {
            XCTFail("expected a path", file: file, line: line)
            return []
        }
        XCTAssertTrue(engine.fire(toward: point), file: file, line: line)
        var last: Vec2?
        var ticks = 0
        while let flying = engine.launchedBubble, ticks < 2000 {
            XCTAssertLessThan(distance(flying.position, to: path), 1e-6, file: file, line: line)
            last = flying.position
            engine.tick()
            ticks += 1
        }
        // The bubble stops within one tick's flight (two sub-steps) of the
        // last position seen in flight, further along the path.
        if let last, let end = path.last {
            XCTAssertLessThanOrEqual(last.distance(to: end), 2 * GameConsts.launchPower + 1e-6, file: file, line: line)
        }
        return path
    }

    func testStraightShotHasNoBounce() {
        let engine = readyEngine()
        let pivot = engine.layout.cannonPivot
        let path = assertFlightFollowsPath(engine, toward: Vec2(x: pivot.x, y: pivot.y - 100))
        XCTAssertEqual(path.count, 2)
        XCTAssertEqual(path[1].x, pivot.x, accuracy: 1e-9)
    }

    func testBankShotBouncesOffTheWall() {
        for seed: UInt64 in [1, 7, 42, 99] {
            let engine = readyEngine(seed: seed)
            let pivot = engine.layout.cannonPivot
            // Shallow to the left (the input area ends 47 above the cannon):
            // hits the left wall before the board.
            let path = assertFlightFollowsPath(engine, toward: Vec2(x: pivot.x - 200, y: pivot.y - 70))
            guard path.count >= 3 else { return XCTFail("expected a bounce, got \(path)") }
            // Where the flight meets the wall; it leaves from that very point.
            XCTAssertEqual(path[1].x, GameConsts.leftBoardBorder, accuracy: 1e-9)
            XCTAssertGreaterThan(path[2].x, GameConsts.leftBoardBorder)
            assertMirrored(path)
        }
    }

    /// Spec 92: at every bounce the flight leaves the wall from the point it
    /// met it, at the mirrored angle — no jog along the wall in between.
    private func assertMirrored(_ path: [Vec2], file: StaticString = #filePath, line: UInt = #line) {
        for i in 1..<max(1, path.count - 1) {
            let bounce = path[i]
            guard bounce.x == GameConsts.leftBoardBorder || bounce.x == GameConsts.rightBoardBorder else { continue }
            let inX = bounce.x - path[i - 1].x, inY = bounce.y - path[i - 1].y
            let outX = path[i + 1].x - bounce.x, outY = path[i + 1].y - bounce.y
            XCTAssertLessThan(inX * outX, 0, "x must turn back at the wall", file: file, line: line)
            // Same slope magnitude both ways: dy/|dx| in equals dy/|dx| out.
            XCTAssertEqual(inY / abs(inX), outY / abs(outX), accuracy: 1e-9, file: file, line: line)
        }
    }

    func testRightWallAndEmptyBoardCeiling() {
        let engine = GameEngine(board: [], readyColor: .red, queueColor: .blue, random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600)
        let pivot = engine.layout.cannonPivot
        let path = assertFlightFollowsPath(engine, toward: Vec2(x: pivot.x + 200, y: pivot.y - 70))
        // Bounce points, then the last point on the line of flight before
        // the ceiling sets y, then the arrival.
        XCTAssertTrue(path.dropFirst().dropLast(2).allSatisfy {
            $0.x == GameConsts.rightBoardBorder || $0.x == GameConsts.leftBoardBorder
        })
        assertMirrored(Array(path.dropLast()))
        XCTAssertEqual(path.last?.y ?? 0, GameConsts.ceilingSnapY, accuracy: 1e-9)
    }

    func testNoPathWithoutReadyBubbleOrOutsideInputArea() {
        let engine = readyEngine()
        let pivot = engine.layout.cannonPivot
        XCTAssertNil(engine.predictedPath(toward: Vec2(x: pivot.x, y: pivot.y + 500)))
        XCTAssertTrue(engine.fire(toward: Vec2(x: pivot.x, y: pivot.y - 100)))
        XCTAssertNil(engine.predictedPath(toward: Vec2(x: pivot.x, y: pivot.y - 100)))
    }
}
