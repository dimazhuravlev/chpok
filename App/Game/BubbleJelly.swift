import CoreGraphics
import Foundation

/// Soft-rubber deformation of bubbles (spec 47): a bubble stretches in flight,
/// flattens against a wall, and both the bubble that arrives and the ones it
/// hits squash and wobble back like jelly.
///
/// Every deformed bubble carries a traceless symmetric log-strain tensor,
/// stored as a 2-vector `e = (a, b)` in "double-angle space": stretching by
/// `s` along a direction at angle `φ` is `e = s·(cos 2φ, sin 2φ)`, squashing
/// along it is the same with a negative `s`. On screen that is a stretch by
/// `exp(|e|)` along `θ = atan2(b, a) / 2` and a squeeze by `exp(-|e|)` across,
/// so the area never changes. Why this representation: the dynamics are plain
/// linear, so when the direction of the strain changes — a wall bounce flips
/// the flight direction — `e` slides there smoothly instead of jumping.
///
/// The tensor sits on a damped spring, `ë = -ω²(e - target) - 2ζω·ė`. A hit is
/// an impulse on `ė`. The tuning is written as the *peak* strain a hit reaches
/// from rest, which is what one can judge by eye; `impulse` converts it.
///
/// Owned by the scene, which calls `step(dt)` once per frame. Bubbles are held
/// strongly until they settle, so a bubble that is moved into a merge layer
/// keeps wobbling there.
final class BubbleJelly {
    // MARK: - Tuning (spec 47)
    //
    // Strains are logarithmic: 0.15 is a 1.16 x 0.86 ellipse. Times in
    // seconds, frequency in hertz.

    /// How fast the rubber springs back, Hz. With the damping below, two or
    /// three fading wobbles in about 0.3 s.
    static let springFrequency: CGFloat = 6
    /// 0 would ring forever, 1 would not wobble at all.
    static let dampingRatio: CGFloat = 0.32
    /// Stretch along the line of flight.
    static let flightStretch: CGFloat = 0.15
    /// Peak squash at the moment of the shot — the bubble is pushed, then the
    /// spring stretches it into `flightStretch`, overshooting a little.
    static let launchSquash: CGFloat = 0.12
    /// Peak squash against a side wall, across the wall.
    static let wallSquash: CGFloat = 0.27
    /// Peak squash of the fired bubble when it lands, along its velocity —
    /// the same against bubbles and against the ceiling.
    static let landingSquash: CGFloat = 0.30
    /// Peak squash of a neighbour of the landed bubble, along the line from
    /// the landed bubble to it; scaled by `0.35 + 0.65·max(0, u·v̂)`, so the
    /// ones in front of the blow take more.
    static let neighbourSquash: CGFloat = 0.17
    /// How the blow of a landing travels through the board, ring by ring:
    /// a resting bubble closer than `radius` bubble sizes to the landed one
    /// (and not reached by an earlier ring) squashes `strength` times as much
    /// as the first ring, `delay` seconds later. On the hex grid the rings
    /// are the direct neighbours (1), the next ring (1.73 and 2) and the one
    /// after it (2.65 and 3).
    static let rings: [(radius: Double, strength: CGFloat, delay: TimeInterval)] = [
        (1.2, 1, 0),
        (2.2, 0.5, 0.04),
        (3.2, 0.22, 0.08)
    ]
    /// Strain never drawn beyond this.
    static let maxStrain: CGFloat = 0.4

    /// Fixed integration sub-step: stable at any frame rate.
    private static let subStep: TimeInterval = 1.0 / 240
    /// Longest frame the controller catches up on in one `step`.
    private static let maxFrame: TimeInterval = 0.1
    /// A bubble is at rest, and released, below these.
    private static let restStrain: CGFloat = 0.002
    private static let restRate: CGFloat = 0.02

    private struct Entry {
        let node: BubbleNode
        var e = CGVector.zero
        var rate = CGVector.zero
        var target = CGVector.zero
    }

    private struct Pending {
        let time: TimeInterval
        let node: BubbleNode
        let direction: CGVector
        let peak: CGFloat
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var pending: [Pending] = []
    /// The controller's own clock, for delayed impulses.
    private var clock: TimeInterval = 0
    private var carry: TimeInterval = 0

    private let omega = 2 * CGFloat.pi * springFrequency
    /// Velocity jump that makes a hit from rest peak at 1 strain unit.
    /// Analytically that is `ω / P(ζ)`, where `P` is the height of the first
    /// peak of the damped spring's impulse response; but the fixed sub-step
    /// integrator below is a bit more damped than the exact spring (the peak
    /// comes out ~8% low at 240 Hz), so the figure is corrected once, by
    /// running that very integrator on a single axis and measuring its peak.
    private let impulsePerPeak: CGFloat = {
        let zeta = Double(dampingRatio)
        let root = (1 - zeta * zeta).squareRoot()
        let exactPeak = exp(-zeta / root * atan(root / zeta))
        let omega = 2 * Double.pi * Double(springFrequency)
        let jump = omega / exactPeak

        let h = BubbleJelly.subStep
        var position = 0.0
        var rate = jump
        var peak = 0.0
        for _ in 0..<Int(1 / h) {
            rate += (-omega * omega * position - 2 * zeta * omega * rate) * h
            position += rate * h
            peak = max(peak, position)
        }
        return CGFloat(jump / peak)
    }()

    // MARK: - API

    /// The bubble was just fired along `direction` (scene coordinates):
    /// squashed by the push, then pulled into its flight stretch.
    func launch(_ node: BubbleNode, direction: CGVector) {
        impulse(node, direction: direction, peak: Self.launchSquash)
        setFlightTarget(node, direction: direction)
    }

    /// Keeps the bubble stretched along `direction`, its current velocity.
    func setFlightTarget(_ node: BubbleNode, direction: CGVector) {
        guard let d = Self.doubleAngle(direction) else { return }
        var entry = entries[ObjectIdentifier(node)] ?? Entry(node: node)
        entry.target = CGVector(dx: d.dx * Self.flightStretch, dy: d.dy * Self.flightStretch)
        entries[ObjectIdentifier(node)] = entry
    }

    /// Squashes the bubble along `direction` by `peak` at most, `delay`
    /// seconds from now.
    func impulse(_ node: BubbleNode, direction: CGVector, peak: CGFloat, delay: TimeInterval = 0) {
        guard Self.doubleAngle(direction) != nil else { return }
        if delay > 0 {
            pending.append(Pending(time: clock + delay, node: node, direction: direction, peak: peak))
        } else {
            apply(node, direction: direction, peak: peak)
        }
    }

    /// The bubble no longer flies: it springs back to its round shape.
    func clearTarget(_ node: BubbleNode) {
        entries[ObjectIdentifier(node)]?.target = .zero
    }

    func step(_ dt: TimeInterval) {
        carry += min(max(dt, 0), Self.maxFrame)
        while carry >= Self.subStep {
            carry -= Self.subStep
            clock += Self.subStep
            fireDueImpulses()
            integrate(CGFloat(Self.subStep))
        }
        render()
    }

    /// Drops everything, leaving the nodes (the scene is discarding them).
    func reset() {
        entries.removeAll()
        pending.removeAll()
        carry = 0
    }

    // MARK: - Internals

    /// `(cos 2φ, sin 2φ)` of a direction, or nil for a zero vector.
    private static func doubleAngle(_ v: CGVector) -> CGVector? {
        let squared = v.dx * v.dx + v.dy * v.dy
        guard squared > 1e-9 else { return nil }
        return CGVector(dx: (v.dx * v.dx - v.dy * v.dy) / squared, dy: 2 * v.dx * v.dy / squared)
    }

    private func apply(_ node: BubbleNode, direction: CGVector, peak: CGFloat) {
        guard let d = Self.doubleAngle(direction) else { return }
        var entry = entries[ObjectIdentifier(node)] ?? Entry(node: node)
        let jump = peak * impulsePerPeak
        entry.rate.dx -= jump * d.dx
        entry.rate.dy -= jump * d.dy
        entries[ObjectIdentifier(node)] = entry
    }

    private func fireDueImpulses() {
        guard !pending.isEmpty else { return }
        let due = pending.filter { $0.time <= clock }
        guard !due.isEmpty else { return }
        pending.removeAll { $0.time <= clock }
        for item in due where item.node.parent != nil {
            apply(item.node, direction: item.direction, peak: item.peak)
        }
    }

    /// Semi-implicit Euler: the rate first, then the strain with the new rate.
    private func integrate(_ h: CGFloat) {
        let damping = 2 * Self.dampingRatio * omega
        let stiffness = omega * omega
        for key in entries.keys {
            guard var entry = entries[key] else { continue }
            entry.rate.dx += (-stiffness * (entry.e.dx - entry.target.dx) - damping * entry.rate.dx) * h
            entry.rate.dy += (-stiffness * (entry.e.dy - entry.target.dy) - damping * entry.rate.dy) * h
            entry.e.dx += entry.rate.dx * h
            entry.e.dy += entry.rate.dy * h
            entries[key] = entry
        }
    }

    /// Writes the strains to the nodes and releases the ones that settled.
    private func render() {
        for (key, entry) in entries {
            if entry.node.parent == nil {
                entries.removeValue(forKey: key)
                continue
            }
            let settled = entry.target == .zero
                && hypot(entry.e.dx, entry.e.dy) < Self.restStrain
                && hypot(entry.rate.dx, entry.rate.dy) < Self.restRate
            if settled {
                entry.node.setDeformation(angle: 0, stretch: 0)
                entries.removeValue(forKey: key)
                continue
            }
            let magnitude = hypot(entry.e.dx, entry.e.dy)
            entry.node.setDeformation(
                angle: atan2(entry.e.dy, entry.e.dx) / 2,
                stretch: min(magnitude, Self.maxStrain)
            )
        }
    }
}
