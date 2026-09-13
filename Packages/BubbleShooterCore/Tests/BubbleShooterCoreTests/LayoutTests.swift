import XCTest
@testable import BubbleShooterCore

/// `GameLayout` tests (game-logic.md §0/§4/§12; 03-core-port.md's derived
/// `fitting`/`gameOverRow`/`gameOverY` formulas). `.original` must reproduce
/// the original's fixed 800x600 canvas exactly.
final class LayoutTests: XCTestCase {

    func testOriginalLayout() {
        let layout = GameLayout.original
        XCTAssertEqual(layout.cannonY, 552)
        XCTAssertEqual(layout.inputAreaMaxY, 505)
        XCTAssertEqual(layout.cannonPivot, Vec2(x: 296, y: 552))
        XCTAssertEqual(layout.readyPosition, Vec2(x: 296, y: 552))
        XCTAssertEqual(layout.queuePosition, Vec2(x: 40, y: 552))
        XCTAssertEqual(layout.gameOverRow, 14)
        XCTAssertEqual(layout.gameOverY, 470)
    }

    func testOriginalContainsInputPoint() {
        let layout = GameLayout.original
        XCTAssertTrue(layout.containsInputPoint(Vec2(x: 300, y: 300)))
        XCTAssertFalse(layout.containsInputPoint(Vec2(x: 300, y: 540)))
        XCTAssertFalse(layout.containsInputPoint(Vec2(x: 10, y: 300)))
        XCTAssertFalse(layout.containsInputPoint(Vec2(x: 300, y: 10)))
    }

    func testFittingLayout() {
        let layout = GameLayout.fitting(canvasHeight: 1000)
        XCTAssertEqual(layout.canvasHeight, 1000)
        XCTAssertEqual(layout.cannonY, 952)
        XCTAssertEqual(layout.inputAreaMaxY, 888)
        XCTAssertEqual(layout.gameOverRow, 26)
        XCTAssertEqual(layout.gameOverY, 854)
    }
}
