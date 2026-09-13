import CoreGraphics
import BubbleShooterCore

/// Converts between the core's logical coordinate system (origin top-left,
/// Y axis down, board X in `25...585`) and the SpriteKit scene's coordinate
/// system (origin bottom-left, Y axis up, scene width 560 starting at X=0).
struct SceneGeometry {
    let canvasHeight: Double

    func scenePoint(_ v: Vec2) -> CGPoint {
        CGPoint(x: v.x - 25, y: canvasHeight - v.y)
    }

    func corePoint(_ p: CGPoint) -> Vec2 {
        Vec2(x: p.x + 25, y: canvasHeight - p.y)
    }
}
