import XCTest
@testable import BubbleShooterCore

/// Flight tests (game-logic.md §5): straight shot to the ceiling, wall
/// bounce, re-fire guard while flying, and `fire(toward:)`'s input-area
/// gate.
final class FlightTests: XCTestCase {

    private func emptyBoardEngine(ready: BubbleColor = .red, queue: BubbleColor = .blue) -> GameEngine {
        let engine = GameEngine(board: [], readyColor: ready, queueColor: queue, random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600) // clear the post-init cannon lockout (§2/§15)
        return engine
    }

    // (a) empty board, straight-up shot: x stays 296, lands at the ceiling
    // in (8,0), a miss loses a life. Descent is no longer a flat 18px/tick
    // (spec 18): `flightAccumulator` alternates 1 sub-step (18px) then 2
    // sub-steps (36px) per tick, since `GameConsts.flightStepsPerTick ==
    // 1.5` — tick 1 descends 18, tick 2 descends 36 (54 total after two
    // ticks), then the pattern repeats for as long as the bubble keeps
    // flying. The step itself (18px, `GameConsts.launchPower`) never
    // changes; only how many of them happen per tick does.
    func testVerticalShotLandsAtCeilingColumn8() {
        let engine = emptyBoardEngine()
        XCTAssertTrue(engine.fire(angleDegrees: 0))
        guard let firedId = engine.launchedBubble?.id else {
            XCTFail("expected a launched bubble right after firing")
            return
        }

        var ticks = 0
        var totalDescended = 0.0
        while let flying = engine.launchedBubble, ticks < 2000 {
            XCTAssertEqual(flying.position.x, 296, accuracy: 0.0001)
            let yBefore = flying.position.y
            engine.tick()
            ticks += 1
            if let stillFlying = engine.launchedBubble, stillFlying === flying {
                // Odd ticks (1st, 3rd, ...) take 1 sub-step; even ticks take
                // 2 — see `GameConsts.flightStepsPerTick`'s doc comment.
                let expectedDescent = ticks % 2 == 1
                    ? GameConsts.launchPower
                    : GameConsts.launchPower * 2
                let descended = yBefore - stillFlying.position.y
                XCTAssertEqual(descended, expectedDescent, accuracy: 0.0001,
                                "tick \(ticks) must descend \(expectedDescent)px before landing")
                totalDescended += descended
                if ticks == 1 {
                    XCTAssertEqual(totalDescended, 18, accuracy: 0.0001)
                } else if ticks == 2 {
                    XCTAssertEqual(totalDescended, 54, accuracy: 0.0001,
                                    "18 (tick 1) + 36 (tick 2) == 54")
                }
            }
        }
        XCTAssertLessThan(ticks, 2000, "bubble should have landed by now")

        engine.runUntilIdle()
        let events = engine.drainEvents()
        XCTAssertTrue(events.contains(.landed(id: firedId, boardX: 8, boardY: 0)), "\(events)")
        XCTAssertTrue(events.contains(.lifeLost(livesLeft: 4)), "\(events)")

        let landed = engine.boardBubbles.first { $0.id == firedId }
        XCTAssertEqual(landed?.boardX, 8)
        XCTAssertEqual(landed?.boardY, 0)
    }

    // (e) Speed check (spec 18): flight must be noticeably faster (fewer
    // ticks to land) purely because more `launchPower`-sized sub-steps run
    // per tick — never because a sub-step itself grew, which would risk
    // tunnelling past a neighbour before `collisionDistance` triggers. This
    // independently re-derives, from the same public constants the engine
    // uses, both (1) the raw number of 18px sub-steps a straight-up shot on
    // an empty board needs to reach the ceiling snap, and (2) the tick count
    // `flightAccumulator`'s bookkeeping should take to perform that many
    // sub-steps — then checks the engine's actually-measured tick count
    // against that calculation.
    func testFlightIsFasterButStepStaysSafe() {
        // Safety net (spec 18): the sub-step itself must stay `launchPower`.
        // `flightStepsPerTick * launchPower` is merely the *average* px/tick
        // now, not a single step's size — it must stay well under
        // `collisionDistance * 2`, otherwise a single 18px sub-step could in
        // principle be widened instead of merely repeated, risking a shot
        // skipping clean past a neighbour.
        XCTAssertEqual(GameConsts.launchPower, 18)
        XCTAssertLessThan(GameConsts.flightStepsPerTick * GameConsts.launchPower, GameConsts.collisionDistance * 2)

        let engine = emptyBoardEngine()
        let startY = engine.readyBubble!.position.y

        // (1) Ground truth: raw launchPower-sized sub-steps to reach the
        // ceiling snap, replicating only the vertical / no-collision half of
        // `GameEngine.checkIfArrivedToPosition` (a real step, then a trial
        // extra step checked against `bubbleSize`).
        var y = startY
        var rawSteps = 0
        while true {
            rawSteps += 1
            y -= GameConsts.launchPower
            if y - GameConsts.launchPower < GameConsts.bubbleSize { break }
        }

        // (2) How many ticks `flightAccumulator`'s bookkeeping takes to run
        // that many sub-steps, replicating `tick()`'s own loop.
        var accumulator = 0.0
        var stepsDone = 0
        var expectedTicks = 0
        while stepsDone < rawSteps {
            expectedTicks += 1
            accumulator += GameConsts.flightStepsPerTick
            while accumulator >= 1 && stepsDone < rawSteps {
                stepsDone += 1
                accumulator -= 1
            }
        }
        XCTAssertLessThan(expectedTicks, rawSteps, "sanity: the multiplier must actually speed things up")

        XCTAssertTrue(engine.fire(angleDegrees: 0))
        var actualTicks = 0
        while engine.launchedBubble != nil, actualTicks < 2000 {
            engine.tick()
            actualTicks += 1
        }
        XCTAssertLessThan(actualTicks, 2000, "bubble should have landed by now")

        XCTAssertEqual(actualTicks, expectedTicks,
                        "measured flight tick count must match the flightStepsPerTick-derived calculation")
    }

    // (f) No tunnelling at speed (spec 18): a single bubble sits at row 0,
    // column 8; a straight-up shot travels the same column and must still
    // register the collision and stop adjacent to it, even though some
    // ticks now run 2 full sub-steps back to back. If sub-stepping ever
    // skipped a collision check, the shot would tunnel through the existing
    // bubble and land at or above its row instead of just below it.
    func testNoTunnellingAtSpeed() {
        let board: [GameSnapshot.BubbleRecord] = [
            .init(boardX: 8, boardY: 0, color: .red),
        ]
        let engine = GameEngine(board: board, readyColor: .blue, queueColor: .green, random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600)

        XCTAssertTrue(engine.fire(angleDegrees: 0))
        guard let firedId = engine.launchedBubble?.id else {
            XCTFail("expected a launched bubble right after firing")
            return
        }

        engine.runUntilIdle()
        let events = engine.drainEvents()
        guard case let .landed(_, landedX, landedY)? = events.first(where: {
            if case .landed(let id, _, _) = $0 { return id == firedId }
            return false
        }) else {
            XCTFail("expected the fired bubble to land")
            return
        }

        // Must have stopped below (8,0), not tunnelled through it to land in
        // its row or above.
        XCTAssertGreaterThanOrEqual(landedY, 1,
                                     "fired bubble must not tunnel past the existing bubble at row 0")
        XCTAssertTrue(
            Grid.areNeighbours(ax: 8, ay: 0, bx: landedX, by: landedY, rowParity: engine.rowParity),
            "landed cell (\(landedX),\(landedY)) must be a neighbour of the existing bubble at (8,0)"
        )

        let landed = engine.boardBubbles.first { $0.id == firedId }
        XCTAssertEqual(landed?.boardX, landedX)
        XCTAssertEqual(landed?.boardY, landedY)
    }

    // (b) empty board, angle 75: bounces off the right wall (x clamps to
    // 561, vx flips sign), eventually lands in row 0 within the board's
    // horizontal bounds.
    //
    // Bounce detection can no longer assume a tick is exactly one sub-step
    // (spec 18: a tick may run 1 or 2 full `launchPower` sub-steps). A
    // single-step lookahead prediction computed once before `tick()` would
    // miss a bounce that happens on the *second* sub-step of a 2-step tick.
    // Instead this watches `velocity.x`'s sign across the whole tick: the
    // bounce clamp is the only place that flips it, so a positive-to-negative
    // flip unambiguously means a bounce happened inside that tick, however
    // many sub-steps it ran — and the clamp guarantees position never ends
    // the tick past the border, even if a second sub-step then moved it back
    // away from the wall.
    func testAngledShotBouncesOffRightWall() {
        let engine = emptyBoardEngine()
        XCTAssertTrue(engine.fire(angleDegrees: 75))
        guard let firedId = engine.launchedBubble?.id else {
            XCTFail("expected a launched bubble right after firing")
            return
        }

        var foundBounce = false
        var ticks = 0
        while let flying = engine.launchedBubble, ticks < 2000 {
            let prevVx = flying.velocity.x
            engine.tick()
            ticks += 1
            if !foundBounce, prevVx > 0,
               let stillFlying = engine.launchedBubble, stillFlying === flying,
               stillFlying.velocity.x < 0 {
                XCTAssertLessThanOrEqual(stillFlying.position.x, GameConsts.rightBoardBorder + 0.0001,
                                          "must not remain past the right wall after bouncing off it")
                foundBounce = true
            }
        }
        XCTAssertLessThan(ticks, 2000, "bubble should have landed by now")
        XCTAssertTrue(foundBounce, "expected the flight to bounce off the right wall at least once")

        engine.runUntilIdle()
        let landed = engine.boardBubbles.first { $0.id == firedId }
        XCTAssertNotNil(landed)
        XCTAssertEqual(landed?.boardY, 0)
        // Row 0 is wide at the default rowParity 0, so a landed bubble's X
        // must fall exactly within the wide row's span (spec 13 tightens
        // this from the old, looser 37...585 bounds — see GameConsts).
        if let x = landed?.position.x {
            XCTAssertGreaterThanOrEqual(x, GameConsts.leftBoardBorder)
            XCTAssertLessThanOrEqual(x, GameConsts.rightBoardBorder)
        }
    }

    // (c) firing while a bubble is already in flight is a no-op.
    func testFireWhileFlyingReturnsFalse() {
        let engine = emptyBoardEngine()
        XCTAssertTrue(engine.fire(angleDegrees: 0))
        let firstId = engine.launchedBubble?.id

        XCTAssertFalse(engine.fire(angleDegrees: 30))
        XCTAssertEqual(engine.launchedBubble?.id, firstId, "a second fire() must not replace the flying bubble")

        let launchedEvents = engine.drainEvents().filter {
            if case .launched = $0 { return true }
            return false
        }
        XCTAssertEqual(launchedEvents.count, 1)
    }

    // (d) fire(toward:) is gated by the input-area rectangle (original
    // layout: y must be <= inputAreaMaxY = 505).
    func testFireTowardRespectsInputArea() {
        let engine = emptyBoardEngine()
        XCTAssertFalse(engine.fire(toward: Vec2(x: 300, y: 540)))
        XCTAssertNil(engine.launchedBubble)

        XCTAssertTrue(engine.fire(toward: Vec2(x: 296, y: 300)))
        XCTAssertNotNil(engine.launchedBubble)
    }
}
