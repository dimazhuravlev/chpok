import Foundation

/// A 2D point/vector in logical canvas pixels (origin top-left, Y axis down),
/// matching the original's coordinate system.
public struct Vec2: Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: Vec2) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
