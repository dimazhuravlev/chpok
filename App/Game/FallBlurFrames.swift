import CoreImage.CIFilterBuiltins
import SpriteKit
import UIKit

/// Pre-blurred bubble textures for the bubbles that fall off the board
/// (spec 45): on the way down they blur into a cloud, with the same
/// `CIGaussianBlur` and the same radius curve as the dissolve of a matched
/// cluster (`BridgeMergeNode`).
///
/// A falling bubble is just a circle, so its blur is radially symmetric and
/// the same for every bubble — the color comes from the sprite's tint. That is
/// why the blur is not live: an `SKEffectNode` per falling bubble would mean
/// dozens of offscreen buffers, each with a huge kernel, redrawn every frame
/// — the very hitch this is meant to avoid. Instead a ladder of textures,
/// a white circle blurred by a growing radius, is drawn once per launch, and
/// the fall swaps the sprite's texture for the nearest rung.
///
/// The ladder has `frameCount` frames. Frame 0 is no blur at all: the bubble's
/// own texture, so it is not generated. The radii grow quadratically — finer
/// steps where the blur is slight and a step shows most.
///
/// Every frame is a square of `side` pixels that holds the circle plus 3
/// radii of blur around it (the reach of the kernel, so the cloud is never cut
/// off by the edge of the texture); the denser the blur, the fewer pixels per
/// logical unit, and `Frame.size` maps the texture 1:1 back onto the scene.
///
/// The ladder is drawn in the background, once, when the scene appears. A
/// bubble that starts falling before it is ready simply falls sharp; the
/// state is only ever touched on the main thread.
enum FallBlurFrames {
    // MARK: - Tuning (spec 45)

    /// Number of frames, frame 0 (no blur) included.
    static let frameCount = 24
    /// Side of every generated texture, pixels.
    private static let side = 256
    /// Share of the fall during which the bubble just falls, sharp; the blur
    /// runs over the rest. Blurring from the first frame read as too fast
    /// (owner request).
    static let blurDelay: CGFloat = 0.4

    // MARK: - Ladder

    /// One rung of the ladder: the texture and the size of the sprite that
    /// shows it 1:1, logical units.
    struct Frame {
        let texture: SKTexture
        let size: CGSize
    }

    /// Frames 1...`frameCount - 1`, empty until the background pass is done.
    private static var frames: [Frame] = []
    private static var isPreparing = false

    /// True once the ladder can be used.
    static var isReady: Bool { !frames.isEmpty }

    /// Blur radius of frame `index`, logical units: from 0 (frame 0) to
    /// `BridgeMergeNode.maxBlurRadius` (the last frame), in quadratic steps.
    static func blurRadius(ofFrame index: Int) -> CGFloat {
        let t = CGFloat(index) / CGFloat(frameCount - 1)
        return BridgeMergeNode.maxBlurRadius * t * t
    }

    /// The frame whose radius is the nearest to `radius` — the inverse of
    /// `blurRadius(ofFrame:)`.
    static func frameIndex(forRadius radius: CGFloat) -> Int {
        let t = min(1, max(0, radius / BridgeMergeNode.maxBlurRadius))
        return Int((t.squareRoot() * CGFloat(frameCount - 1)).rounded())
    }

    /// Frame `index`, or nil for frame 0 (use the bubble's own texture) and
    /// while the ladder is not ready.
    static func frame(at index: Int) -> Frame? {
        guard index >= 1, index <= frames.count else { return nil }
        return frames[index - 1]
    }

    /// Starts drawing the ladder in the background, once per launch; the
    /// main thread only creates the textures when the images arrive. Call it
    /// when the scene appears. A frame that fails to render leaves the whole
    /// ladder unpublished, and bubbles keep falling sharp.
    static func prepare() {
        guard !isPreparing else { return }
        isPreparing = true

        DispatchQueue.global(qos: .utility).async {
            let context = CIContext()
            var images: [CGImage] = []
            for index in 1..<frameCount {
                guard let image = render(frame: index, context: context) else { return }
                images.append(image)
            }
            DispatchQueue.main.async {
                frames = images.enumerated().map { offset, image in
                    let texture = SKTexture(cgImage: image)
                    texture.filteringMode = .linear
                    // Minified on screen like the bubble itself, and the first
                    // frames have an almost sharp edge: without mipmaps it
                    // would alias.
                    texture.usesMipmaps = true
                    let extent = 2 * (BridgeMergeNode.circleRadius + 3 * blurRadius(ofFrame: offset + 1))
                    return Frame(texture: texture, size: CGSize(width: extent, height: extent))
                }
            }
        }
    }

    /// A white circle, as big as the bubble's, blurred by the radius of frame
    /// `index` and centered in a `side`-pixel square.
    private static func render(frame index: Int, context: CIContext) -> CGImage? {
        let radius = blurRadius(ofFrame: index)
        let pixelsPerUnit = CGFloat(side) / (2 * (BridgeMergeNode.circleRadius + 3 * radius))
        let circleRadius = BridgeMergeNode.circleRadius * pixelsPerUnit

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let circle = renderer.image { _ in
            UIColor.white.setFill()
            let rect = CGRect(
                x: CGFloat(side) / 2 - circleRadius, y: CGFloat(side) / 2 - circleRadius,
                width: circleRadius * 2, height: circleRadius * 2
            )
            UIBezierPath(ovalIn: rect).fill()
        }
        guard let cgCircle = circle.cgImage else { return nil }

        // The same single `CIGaussianBlur` as the cluster's. The circle stays
        // 3 radii clear of the edge, so rendering just the input's extent
        // loses nothing.
        let source = CIImage(cgImage: cgCircle)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = source
        blur.radius = Float(radius * pixelsPerUnit)
        guard let output = blur.outputImage else { return nil }
        return context.createCGImage(output, from: source.extent)
    }

    // MARK: - Fall

    /// The action that blurs a falling bubble over `duration` seconds: after
    /// `blurDelay` of it the radius follows `BridgeMergeNode`'s ease-out up to
    /// its maximum over the remaining time, and
    /// every time the nearest frame changes, the bubble's texture and size
    /// are swapped for it. The ring goes with the first blurred frame — a
    /// cloud has no outline. Run it alongside the fall and the fade. Nil when
    /// the ladder is not ready: the bubble falls sharp.
    static func blurAction(duration: TimeInterval) -> SKAction? {
        guard isReady else { return nil }

        var shown = 0
        return SKAction.customAction(withDuration: duration) { node, elapsed in
            guard let bubble = node as? BubbleNode else { return }
            let progress = duration > 0 ? CGFloat(elapsed) / CGFloat(duration) : 1
            let blurProgress = (progress - blurDelay) / (1 - blurDelay)
            let radius = BridgeMergeNode.maxBlurRadius * BridgeMergeNode.easeOut(blurProgress)
            let index = frameIndex(forRadius: radius)
            guard index != shown, let frame = frame(at: index) else { return }
            shown = index
            bubble.texture = frame.texture
            bubble.size = frame.size
            bubble.setBorderHidden(true)
        }
    }
}
