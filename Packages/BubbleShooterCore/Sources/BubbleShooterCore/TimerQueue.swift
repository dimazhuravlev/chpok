import Foundation

/// Internal stand-in for Phaser's `time.events.add`/`loop` one-shot timers
/// (see "Решённые развилки"). Actions carry the absolute `fireAtMs` they
/// were scheduled for and a monotonically increasing `seq`; `fire(upToMs:)`
/// runs every eligible action in `(fireAtMs, seq)` order, re-scanning after
/// each one so that actions scheduled *during* draining also run if they are
/// themselves already eligible (mirrors same-frame-synchronous Phaser
/// callback chains such as `addNewRow` -> `addOneRow` -> ...).
///
/// Recurring timers (the original's 1000ms win-check loop) are deliberately
/// *not* modeled here — they are handled by `GameEngine` via a dedicated
/// counter, so a perpetual recurring action can never make `hasPending`
/// permanently true (which would make `GameEngine.isIdle` unreachable).
final class TimerQueue {
    private struct ScheduledAction {
        let fireAtMs: Int
        let seq: Int
        let action: () -> Void
    }

    private var actions: [ScheduledAction] = []
    private var nextSeq: Int = 0

    var hasPending: Bool { !actions.isEmpty }

    func schedule(afterMs delay: Int, from nowMs: Int, action: @escaping () -> Void) {
        let fireAt = nowMs + max(0, delay)
        actions.append(ScheduledAction(fireAtMs: fireAt, seq: nextSeq, action: action))
        nextSeq += 1
    }

    func fire(upToMs nowMs: Int) {
        while let idx = nextEligibleIndex(upToMs: nowMs) {
            let scheduled = actions.remove(at: idx)
            scheduled.action()
        }
    }

    /// Discards every not-yet-fired action without running it (used by
    /// `GameEngine.resetBoard()`; see report for rationale).
    func cancelAll() {
        actions.removeAll()
    }

    private func nextEligibleIndex(upToMs nowMs: Int) -> Int? {
        var bestIdx: Int?
        for (idx, a) in actions.enumerated() where a.fireAtMs <= nowMs {
            if let b = bestIdx {
                let best = actions[b]
                if (a.fireAtMs, a.seq) < (best.fireAtMs, best.seq) {
                    bestIdx = idx
                }
            } else {
                bestIdx = idx
            }
        }
        return bestIdx
    }
}
