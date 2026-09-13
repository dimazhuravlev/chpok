import Foundation

/// Internal port of the original's individual functions. Method names track
/// the original where a direct counterpart exists, so this file plus
/// `GameEngine.swift`'s public surface can be read side-by-side with
/// game-logic.md. See the task report for the full
/// "original function -> Swift method" table.
extension GameEngine {

    // MARK: - §2 init / reset

    /// Mirrors the board-building portion of `BoardManager.initBoard`: a
    /// fully-random 17x9 board, then one queue-seed bubble immediately
    /// promoted via `addNewBubble()` (mirrors `initBoard`'s
    /// `Bubble(..., .inQueue)` + `BoardManager.addNewBubble()` pair).
    func buildFullRandomBoardAndQueue() {
        for i in stride(from: GameConsts.boardHeight - 1, through: 0, by: -1) {
            for j in stride(from: GameConsts.boardWidth - 1, through: 0, by: -1) {
                let color = getRandomColor(fullyRandom: true)
                bubbles.append(makeBubble(color: color, boardX: j, boardY: i, state: .onBoard))
            }
        }
        let seedColor = getRandomColor(fullyRandom: false)
        let seed = makeBubble(color: seedColor, boardX: 0, boardY: -10, state: .inQueue)
        bubbles.append(seed)
        queueBubble = seed
        addNewBubble()
        totalColors = GameConsts.totalColors
    }

    /// Mirrors constructing an explicit board plus ready/queue bubbles, used
    /// by `init(snapshot:)`/`init(board:...)`. Unlike
    /// `buildFullRandomBoardAndQueue`, ready/queue are created directly at
    /// the caller-specified colors (no extra RNG draw).
    func loadBoard(_ records: [GameSnapshot.BubbleRecord], readyColor: BubbleColor, queueColor: BubbleColor) {
        for r in records {
            bubbles.append(makeBubble(color: r.color, boardX: r.boardX, boardY: r.boardY, state: .onBoard))
        }
        let ready = makeBubble(color: readyColor, boardX: 0, boardY: -10, state: .readyToLaunch)
        bubbles.append(ready)
        readyBubble = ready
        events.append(.readyBubbleChanged(id: ready.id, color: ready.color))

        let queue = makeBubble(color: queueColor, boardX: 0, boardY: -10, state: .inQueue)
        bubbles.append(queue)
        queueBubble = queue
        events.append(.queueBubbleChanged(id: queue.id, color: queue.color))
    }

    func makeBubble(color: BubbleColor, boardX: Int, boardY: Int, state: BubbleState) -> Bubble {
        let id = nextBubbleId
        nextBubbleId += 1
        let position: Vec2
        switch state {
        case .onBoard, .launched:
            position = Grid.realCoord(boardX: boardX, boardY: boardY)
        case .readyToLaunch:
            position = layout.readyPosition
        case .inQueue:
            position = layout.queuePosition
        }
        return Bubble(id: id, color: color, state: state, boardX: boardX, boardY: boardY, position: position)
    }

    /// Mirrors `BoardManager.addNewBubble`: promotes the current queue
    /// bubble to ready-to-launch, then creates a fresh queue bubble at
    /// `(0, -10)` (sentinel, matching `initBoard`'s queue-seed call).
    func addNewBubble() {
        guard let promoted = queueBubble else { return }
        promoted.state = .readyToLaunch
        promoted.position = layout.readyPosition
        readyBubble = promoted
        queueBubble = nil
        events.append(.readyBubbleChanged(id: promoted.id, color: promoted.color))

        let color = getRandomColor(fullyRandom: false)
        let newQueue = makeBubble(color: color, boardX: 0, boardY: -10, state: .inQueue)
        bubbles.append(newQueue)
        queueBubble = newQueue
        events.append(.queueBubbleChanged(id: newQueue.id, color: newQueue.color))
    }

    /// Mirrors `BoardManager.addNewBubblePreStep`: reads the *current*
    /// `markHangedTime` (set by an intervening `markHangingClusters` call)
    /// at the moment this fires, not at the moment it was scheduled.
    func addNewBubblePreStep() {
        timerQueue.schedule(afterMs: markHangedTime, from: timeMs) { [weak self] in
            self?.addNewBubble()
        }
    }

    /// Mirrors `initBoard`'s `Cannon.cannonEnabled = false` +
    /// 500ms-later-true one-shot. Re-armed by `resetBoard()` too, matching
    /// the original (this runs unconditionally inside `initBoard`,
    /// regardless of `addNewUI`).
    func armCannonEnableLockout() {
        cannonEnabled = false
        timerQueue.schedule(afterMs: GameEngine.cannonEnableDelayMs, from: timeMs) { [weak self] in
            self?.cannonEnabled = true
        }
    }

    // MARK: - §4 launch

    /// Mirrors `Bubble.prototype.launch(angle, distance)` (the `distance`
    /// parameter is computed by the caller in the original but never used
    /// inside `launch`, so it has no Swift counterpart here).
    func performLaunch(_ bubble: Bubble, angleDegrees: Double) {
        bubble.state = .launched
        let rad = (angleDegrees + 90) * Double.pi / 180
        bubble.velocity = Vec2(x: -GameConsts.launchPower * cos(rad), y: -GameConsts.launchPower * sin(rad))
        readyBubble = nil
        launchedBubble = bubble
        turnInProgress = true
        events.append(.launched(id: bubble.id, angleDegrees: angleDegrees))
    }

    // MARK: - §5 flight

    /// Mirrors the `STATE_LAUNCHED` branch of `Bubble.onUpdate`.
    func updateLaunchedBubble() {
        guard let bubble = launchedBubble else { return }

        bubble.position.x += bubble.velocity.x
        bubble.position.y += bubble.velocity.y

        if bubble.position.x > GameConsts.rightBoardBorder {
            bubble.velocity.x *= -1
            bubble.position.x = GameConsts.rightBoardBorder
        } else if bubble.position.x < GameConsts.leftBoardBorder {
            bubble.velocity.x *= -1
            bubble.position.x = GameConsts.leftBoardBorder
        }

        if checkIfArrivedToPosition(bubble) {
            resolveLanding(bubble)
        }
    }

    /// Mirrors `BoardManager.checkIfArrivedToPosition`: takes a trial extra
    /// step, then per bubble (in reverse insertion order) either resolves a
    /// collision (rolling back 75% of the trial step) or, on the same
    /// iteration regardless of that bubble, a ceiling breach — preserving
    /// the original's quirk where the ceiling check is syntactically tied to
    /// the loop but not actually dependent on the current element
    /// (game-logic.md §5, §17.16). Falls through to a full rollback ("not
    /// arrived yet") if neither ever triggers.
    func checkIfArrivedToPosition(_ bubble: Bubble) -> Bool {
        bubble.position.x += bubble.velocity.x
        bubble.position.y += bubble.velocity.y

        for stat in bubbles.reversed() {
            if !stat.isBeingRemoved && stat.state == .onBoard
                && bubble.position.distance(to: stat.position) < GameConsts.collisionDistance {
                bubble.position.x -= 0.75 * bubble.velocity.x
                bubble.position.y -= 0.75 * bubble.velocity.y
                return true
            } else if bubble.position.y < GameConsts.bubbleSize {
                bubble.position.y = GameConsts.ceilingSnapY
                return true
            }
        }

        bubble.position.x -= bubble.velocity.x
        bubble.position.y -= bubble.velocity.y
        return false
    }

    // MARK: - §6 snap / §7 landing

    /// Mirrors the landing portion of `Bubble.onUpdate`'s `STATE_LAUNCHED`
    /// branch: computes the snap anchor, snaps to a free cell, jumps the
    /// bubble straight to its exact grid position, transitions it to
    /// `.onBoard`, then resolves the match.
    ///
    /// Deviation: the original then either jumps immediately (on a match) or
    /// starts a cosmetic 90ms Phaser tween toward that same final position
    /// (on a miss) — a `render`-clock animation, not part of the 15ms
    /// bubble-logic timer this engine models, and not read by any later game
    /// logic (see report). This engine always sets the final grid position
    /// immediately and emits `.landed`; a UI layer can animate the visual
    /// glide itself off that event.
    func resolveLanding(_ bubble: Bubble) {
        let anchor = Vec2(
            x: bubble.position.x - 0.05 * bubble.velocity.x,
            y: bubble.position.y - 0.05 * bubble.velocity.y
        )
        assignStateDefaultCoords(bubble, anchor: anchor)
        bubble.position = Grid.realCoord(boardX: bubble.boardX, boardY: bubble.boardY)
        bubble.state = .onBoard
        launchedBubble = nil
        events.append(.landed(id: bubble.id, boardX: bubble.boardX, boardY: bubble.boardY))

        let matched = bubbleArrived(bubble)
        if matched {
            timerQueue.schedule(afterMs: timeToNewBubble, from: timeMs) { [weak self] in
                self?.addNewBubblePreStep()
            }
        } else {
            // Original: 0.2ms one-shot -> effectively immediate relative to
            // this engine's 15ms tick granularity.
            timerQueue.schedule(afterMs: 0, from: timeMs) { [weak self] in
                self?.addNewBubble()
            }
        }
    }

    /// Mirrors `BoardManager.assignStateDefaultCoords`: searches backward
    /// along the velocity vector (`counter` steps of `0.25*v`) for the first
    /// unoccupied cell. `boardX` gets a single decrement if `>= boardWidth`
    /// (not a full clamp) and a hard clamp to 0 if negative; `boardY` is
    /// never clamped — both exactly as the original (game-logic.md §6,
    /// §17.9).
    func assignStateDefaultCoords(_ bubble: Bubble, anchor: Vec2) {
        var counter = 0
        var occupied: Bool
        repeat {
            occupied = false
            var bx = anchor.x - 0.25 * Double(counter) * bubble.velocity.x
            var by = anchor.y - 0.25 * Double(counter) * bubble.velocity.y
            counter += 1

            bx -= GameConsts.initialX
            by -= GameConsts.initialY

            let boardY = jsRound(by / GameConsts.bubbleSize)
            bx -= Double(boardY % 2) * GameConsts.bubbleSize * 0.5
            var boardX = jsRound(bx * 0.9999 / GameConsts.bubbleSize)

            if boardX >= GameConsts.boardWidth { boardX -= 1 }
            if boardX < 0 { boardX = 0 }

            bubble.boardX = boardX
            bubble.boardY = boardY

            for other in bubbles where other !== bubble {
                if other.boardX == boardX && other.boardY == boardY {
                    occupied = true
                    break
                }
            }
        } while occupied
    }

    /// Mirrors `BoardManager.bubbleArrived`: flood-fills the same-color
    /// cluster from `bubble`, resolves removal/score, and on a miss loses a
    /// life. Returns whether a match happened (`totalRemoved >= 3`).
    @discardableResult
    func bubbleArrived(_ bubble: Bubble) -> Bool {
        markNeighboursOfSameColor(bubble)
        let totalRemoved = removeSameColorCluster()

        if totalRemoved < 3 {
            loseOneLife()
        }
        if totalRemoved >= 3 {
            timeToNewBubble = 30 + 72 * totalRemoved
            timerQueue.schedule(afterMs: 72 * totalRemoved, from: timeMs) { [weak self] in
                self?.markHangingClustersCall()
            }
            timerQueue.schedule(afterMs: 2 * 72 * totalRemoved, from: timeMs) { [weak self] in
                self?.markHangingClustersCall()
            }
        }
        return totalRemoved >= 3
    }

    // MARK: - §8 cluster removal

    /// Mirrors `BoardManager.markNeighboursOfSameColor` (recursive
    /// same-color flood fill).
    func markNeighboursOfSameColor(_ bubble: Bubble) {
        bubble.markedToBeRemoved = true
        for n in neighbours(of: bubble) {
            if bubble.color == n.color && !n.markedToBeRemoved {
                markNeighboursOfSameColor(n)
            }
        }
    }

    /// Mirrors `BoardManager.getNeighoburs`: onboard bubbles adjacent to
    /// `bubble` per `Grid.areNeighbours`, excluding `bubble` itself (the
    /// original's `b1 === b2` object-identity check — see `Grid`'s doc
    /// comment for why that is not part of `Grid.areNeighbours` itself).
    func neighbours(of bubble: Bubble) -> [Bubble] {
        bubbles.filter {
            $0 !== bubble && $0.state == .onBoard
                && Grid.areNeighbours(ax: bubble.boardX, ay: bubble.boardY, bx: $0.boardX, by: $0.boardY)
        }
    }

    /// Mirrors `BoardManager.removeSameColorCluster`: scores every
    /// `markedToBeRemoved` bubble in reverse-insertion order (`k` starting
    /// at 1, `10*ceil(k/3)`), then schedules removal in a *separately*
    /// sorted geometric order (bottom-to-top, then left-to-right) staggered
    /// `70*i` ms — two independent orderings over the same set, exactly as
    /// the original (game-logic.md §8, §17.12).
    func removeSameColorCluster() -> Int {
        let toBeRemovedCount = bubbles.filter { $0.markedToBeRemoved }.count
        var toBeRemovedArr: [Bubble] = []

        if toBeRemovedCount > 2 {
            var removedCount = 0
            for b in bubbles.reversed() where b.markedToBeRemoved {
                removedCount += 1
                b.pendingScore = 10 * Int(ceil(Double(removedCount) / 3.0))
                toBeRemovedArr.append(b)
            }
        }

        toBeRemovedArr.sort { a, b in
            if a.boardY != b.boardY { return a.boardY > b.boardY }
            return a.boardX < b.boardX
        }

        for i in stride(from: toBeRemovedArr.count - 1, through: 0, by: -1) {
            let bubble = toBeRemovedArr[i]
            if bubble.markedToBeRemoved {
                let delay = GameConsts.removalStaggerMs * i
                timerQueue.schedule(afterMs: delay, from: timeMs) { [weak self] in
                    self?.performRemoval(bubble, reason: .match)
                }
            }
        }

        if toBeRemovedCount < 3 {
            for b in bubbles {
                b.markedToBeRemoved = false
                b.pendingScore = 0
            }
        }

        return toBeRemovedCount
    }

    /// Mirrors `Bubble.prototype.remove`: guarded by both `isBeingRemoved`
    /// and `isGameOver` (mirroring `SimpleGame.gameOverStartedFlag` —
    /// scheduled removals silently no-op once the game is over, exactly as
    /// the original, game-logic.md §12).
    func performRemoval(_ bubble: Bubble, reason: RemovalReason) {
        guard !bubble.isBeingRemoved, !isGameOver else { return }
        bubble.isBeingRemoved = true
        let points = bubble.pendingScore
        score += points
        bubble.pendingScore = 0
        events.append(.removed(id: bubble.id, color: bubble.color, position: bubble.position, points: points, reason: reason))
        events.append(.scoreChanged(score: score))
        bubbles.removeAll { $0 === bubble }
    }

    // MARK: - §9 hanging clusters

    /// Mirrors `BoardManager.markHangingClustersCall`.
    func markHangingClustersCall() {
        markHangingClusters(skipScore: false)
    }

    /// Mirrors `BoardManager.markHangingClusters`: marks every onboard
    /// bubble as hanging, rescues everything reachable from row 0 via
    /// `traverseCluster`, then schedules removal (staggered `70*i` ms) for
    /// whatever is still marked. `skipScore` suppresses the flat 100pt
    /// bonus per bubble (used by `addNewRow`'s safety passes) but not the
    /// removal itself. Note: like the original, the row-0 scan has no
    /// `state == .onBoard` filter (confirmed against source) — harmless in
    /// practice since ready/queue bubbles only ever reach `boardY == 0`
    /// after 10+ row additions.
    func markHangingClusters(skipScore: Bool) {
        for b in bubbles {
            b.traversed = false
            if b.state == .onBoard { b.markedToBeHanged = true }
        }

        for b in bubbles where b.boardY == 0 {
            b.traversed = false
            traverseCluster(b)
            for b2 in bubbles { b2.traversed = false }
        }

        let removeArray = bubbles.filter { $0.markedToBeHanged }
        if !skipScore {
            for b in removeArray { b.pendingScore = 100 }
        }

        markHangedTime = removeArray.count * GameConsts.removalStaggerMs
        for i in stride(from: removeArray.count - 1, through: 0, by: -1) {
            let bubble = removeArray[i]
            if !bubble.isBeingRemoved {
                let delay = GameConsts.removalStaggerMs * i
                timerQueue.schedule(afterMs: delay, from: timeMs) { [weak self] in
                    self?.performRemoval(bubble, reason: .hanging)
                }
            }
        }
    }

    /// Mirrors `BoardManager.traverseCluster`: DFS over *any*-color
    /// neighbours (connectivity to the ceiling, not color), rescuing
    /// (`markedToBeHanged = false`) everything it reaches. Bubbles already
    /// `markedToBeRemoved` (mid-match) are treated as walls, matching the
    /// original.
    func traverseCluster(_ bubble: Bubble) {
        bubble.traversed = true
        bubble.markedToBeHanged = false
        for n in neighbours(of: bubble) {
            if !n.traversed && !n.markedToBeRemoved {
                traverseCluster(n)
            }
        }
    }

    // MARK: - §10 lives

    /// Mirrors `LivesUI.prototype.loseOneLife` verbatim.
    func loseOneLife() {
        if livesLeft > 0 {
            livesLeft -= 1
            events.append(.lifeLost(livesLeft: livesLeft))
        } else {
            isAddingRow = true
            timerQueue.schedule(afterMs: GameConsts.addRowDelayMs, from: timeMs) { [weak self] in
                self?.addNewRow()
            }
        }
    }

    /// Mirrors `LivesUI.resetMaxLives`.
    func resetMaxLivesValue() -> Int {
        totalColors - 1
    }

    /// Mirrors `LivesUI.resetLives` verbatim, including the two sequential
    /// (not if/else) clamps.
    func resetLivesInternal() {
        maxLives -= 1
        if maxLives <= 0 {
            maxLives = resetMaxLivesValue()
        }
        if maxLives > resetMaxLivesValue() {
            maxLives = resetMaxLivesValue()
        }
        livesLeft = maxLives
        events.append(.livesReset(livesLeft: livesLeft, maxLives: maxLives))
    }

    // MARK: - §11 rows

    /// Mirrors `BoardManager.addNewRow`.
    func addNewRow() {
        isAddingRow = false

        var colorArr = [Int](repeating: 0, count: GameConsts.totalColors)
        for b in bubbles {
            colorArr[b.color.rawValue] += 1
        }

        totalColors = 0
        var rowsToAdd = 1
        for count in colorArr where count == 0 { rowsToAdd += 1 }
        totalColors = GameConsts.totalColors - rowsToAdd + 1

        resetLivesInternal()

        let rowsAddedThisCall = rowsToAdd
        while rowsToAdd > 0 {
            addOneRow()
            rowsToAdd -= 1
        }

        markHangingClusters(skipScore: true)
        events.append(.rowsAdded(count: rowsAddedThisCall))
    }

    /// Mirrors `BoardManager.addOneRow`: shifts every live bubble down one
    /// row (including ready/queue, whose `boardY` is otherwise unused —
    /// matches the original shifting all of `bubbleArr` unconditionally),
    /// forcing an immediate (not next-tick) game-over check per shifted
    /// onboard bubble, then fills row 0 with `boardWidth` new bubbles.
    func addOneRow() {
        for b in bubbles {
            b.boardY += 1
            if b.state == .onBoard {
                b.position = Grid.realCoord(boardX: b.boardX, boardY: b.boardY)
                checkGameOver(for: b)
            }
        }

        for i in stride(from: GameConsts.boardWidth - 1, through: 0, by: -1) {
            let color = getRandomColor(fullyRandom: false)
            bubbles.append(makeBubble(color: color, boardX: i, boardY: 0, state: .onBoard))
        }

        if !isGameOver {
            timerQueue.schedule(afterMs: 50, from: timeMs) { [weak self] in
                self?.markHangingClusters(skipScore: true)
            }
        }
    }

    // MARK: - §12 game over / §13 win

    /// Mirrors the game-over check inside `Bubble.onUpdate`'s `STATE_DEFAULT`
    /// branch, with thresholds taken from `layout` instead of the
    /// original's hardcoded 14/470 (see `GameLayout`).
    func checkGameOver(for bubble: Bubble) {
        guard bubble.state == .onBoard else { return }
        if bubble.boardY > layout.gameOverRow && bubble.position.y > layout.gameOverY && !bubble.isBeingRemoved {
            triggerLoss()
        }
    }

    /// Mirrors `SimpleGame.gameOverStarted()` (always called with the
    /// default `gameWon = false` in the original).
    func triggerLoss() {
        guard !isGameOver else { return }
        isGameOver = true
        events.append(.gameOver(won: false, score: score, bonus: 0))
    }

    /// Mirrors `MainUI.gameWonCheck`/`checkIfGameWon` (board empty of
    /// `.onBoard` bubbles).
    func checkWin() {
        guard !isGameOver else { return }
        if !bubbles.contains(where: { $0.state == .onBoard }) {
            isGameOver = true
            events.append(.gameOver(won: true, score: score, bonus: score))
        }
    }

    // MARK: - §14 random color

    /// Mirrors `Bubble.getRandomColor`. Both branches use the fixed
    /// `GameConsts.totalColors` (6) universe — *not* the engine's dynamic,
    /// shrinking `totalColors` property, exactly as the original (which
    /// hardcodes a 6-element `availableColorIdx` regardless of
    /// `BoardManager.totalColors`).
    func getRandomColor(fullyRandom: Bool) -> BubbleColor {
        if fullyRandom {
            let idx = random.nextInt(upperBound: GameConsts.totalColors)
            return BubbleColor(rawValue: idx) ?? .blue
        }

        var available = [Bool](repeating: false, count: GameConsts.totalColors)
        for b in bubbles {
            available[b.color.rawValue] = true
        }
        var colorIdx: Int
        repeat {
            colorIdx = random.nextInt(upperBound: GameConsts.totalColors)
        } while !available[colorIdx]
        return BubbleColor(rawValue: colorIdx) ?? .blue
    }
}

/// Mirrors `Math.round`, defined as `floor(x + 0.5)` — rounds .5 toward
/// +infinity for *all* signs, unlike Swift's `.rounded()` (away from zero).
/// `boardCoordX`/`boardCoordY` are always whole numbers at runtime, so this
/// only matters for negative inputs landing exactly on a .5 boundary.
private func jsRound(_ x: Double) -> Int {
    Int(floor(x + 0.5))
}
