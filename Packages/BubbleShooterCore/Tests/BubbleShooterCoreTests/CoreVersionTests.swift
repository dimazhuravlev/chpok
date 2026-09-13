import XCTest
@testable import BubbleShooterCore

final class CoreVersionTests: XCTestCase {
    func testVersionString() {
        XCTAssertEqual(CoreVersion.string, "0.1.0")
    }
}
