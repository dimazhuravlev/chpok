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
        // Spec 11: gameOverRow/gameOverY now derive from GameConsts.rowHeight
        // (true hex packing), not bubbleSize — more, shorter rows fit in the
        // same pixel span, so gameOverRow grew from the original's 14 while
        // gameOverY (pixels) stayed close to the original's 470.
        XCTAssertEqual(layout.gameOverRow, 16)
        XCTAssertEqual(layout.gameOverY, 465.40500673763257, accuracy: 1e-9)
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
        XCTAssertEqual(layout.cannonY, 920)
        XCTAssertEqual(layout.inputAreaMaxY, 856)
        XCTAssertEqual(layout.gameOverRow, 29)
        XCTAssertEqual(layout.gameOverY, 825.6715747119590, accuracy: 1e-9)
    }
}
