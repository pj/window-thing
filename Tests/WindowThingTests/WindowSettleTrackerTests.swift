import Testing
import CoreGraphics
@testable import WindowThingCore

/// Some windows can't do what a layout asks — a fixed-size dialog, an app with a
/// minimum width, a terminal snapping to a character grid. Reconciliation runs
/// on a timer, so the app must notice and stop asking, without abandoning the
/// window entirely.
@Suite("Window settle tracker")
struct WindowSettleTrackerTests {

    private let target = WindowFrame(x: 0, y: 0, width: 1000, height: 1107)
    /// Where a window clamped by the menu bar actually lands.
    private let clamped = WindowFrame(x: 0, y: 33, width: 1000, height: 1074)
    private let id: CGWindowID = 42

    private func move(_ tracker: WindowSettleTracker, from current: WindowFrame) -> Bool {
        tracker.shouldMove(windowID: id, current: current, target: target)
    }

    // MARK: - The ordinary cases

    @Test("A window already at its target is left alone")
    func settledWindowIsSkipped() {
        let tracker = WindowSettleTracker()
        #expect(!move(tracker, from: target))
    }

    @Test("A misplaced window is moved")
    func misplacedWindowMoves() {
        let tracker = WindowSettleTracker()
        #expect(move(tracker, from: clamped))
    }

    // MARK: - Backing off

    @Test("A window that never complies is retried, then accepted where it is")
    func stopsAfterMaxAttempts() {
        let tracker = WindowSettleTracker(maxAttempts: 3)

        // It refuses the target every pass, staying exactly where it is.
        #expect(move(tracker, from: clamped))
        #expect(move(tracker, from: clamped))
        #expect(move(tracker, from: clamped))

        // Having had its chances, where it landed is taken as what it can do.
        #expect(!move(tracker, from: clamped))
        #expect(tracker.settledCount == 1)

        // And it stays quiet indefinitely rather than resuming.
        for _ in 0 ..< 50 {
            #expect(!move(tracker, from: clamped))
        }
    }

    @Test("A window that complies late clears its record")
    func lateComplianceResets() {
        let tracker = WindowSettleTracker(maxAttempts: 3)
        #expect(move(tracker, from: clamped))
        #expect(move(tracker, from: clamped))

        // It got there on the third pass.
        #expect(!move(tracker, from: target))
        #expect(tracker.settledCount == 0)

        // Nothing is held against it: a later failure starts the count over.
        #expect(move(tracker, from: clamped))
    }

    // MARK: - Not abandonment

    @Test("A settled window that drifts is placed again")
    func driftFromSettledIsCorrected() {
        // The point of recording where it settled rather than giving up: the
        // user drags the window somewhere else and it is still managed.
        let tracker = WindowSettleTracker(maxAttempts: 2)
        #expect(move(tracker, from: clamped))
        #expect(move(tracker, from: clamped))
        #expect(!move(tracker, from: clamped))   // accepted at `clamped`

        let dragged = WindowFrame(x: 600, y: 400, width: 500, height: 400)
        #expect(move(tracker, from: dragged), "a settled window was abandoned")
    }

    @Test("Drifting restarts the attempt count rather than resettling instantly")
    func driftRestartsTheCount() {
        let tracker = WindowSettleTracker(maxAttempts: 2)
        #expect(move(tracker, from: clamped))
        #expect(move(tracker, from: clamped))
        #expect(!move(tracker, from: clamped))

        // Were the count not reset, the first pass after a drag would conclude
        // the dragged position is the best it can do and stop there.
        let dragged = WindowFrame(x: 600, y: 400, width: 500, height: 400)
        #expect(move(tracker, from: dragged))
        #expect(move(tracker, from: clamped))
    }

    @Test("A new target is judged on its own merits")
    func newTargetStartsFresh() {
        let tracker = WindowSettleTracker(maxAttempts: 2)
        #expect(move(tracker, from: clamped))
        #expect(move(tracker, from: clamped))
        #expect(!move(tracker, from: clamped))

        // A different layout asks for something else; the old conclusion says
        // nothing about whether the window can manage this one.
        let elsewhere = WindowFrame(x: 0, y: 33, width: 500, height: 1074)
        #expect(tracker.shouldMove(windowID: id, current: clamped, target: elsewhere))
    }

    // MARK: - Bookkeeping

    @Test("Windows are tracked independently")
    func perWindowRecords() {
        let tracker = WindowSettleTracker(maxAttempts: 1)

        #expect(tracker.shouldMove(windowID: 1, current: clamped, target: target))
        #expect(!tracker.shouldMove(windowID: 1, current: clamped, target: target))

        // A second window is unaffected by the first giving up.
        #expect(tracker.shouldMove(windowID: 2, current: clamped, target: target))
    }

    @Test("An explicit apply gives every window another chance")
    func resetClearsEverything() {
        let tracker = WindowSettleTracker(maxAttempts: 1)
        #expect(move(tracker, from: clamped))
        #expect(!move(tracker, from: clamped))

        tracker.reset()

        #expect(move(tracker, from: clamped))
        #expect(tracker.settledCount == 0)
    }

    @Test("Records for closed windows are pruned")
    func pruneDropsDeadWindows() {
        let tracker = WindowSettleTracker(maxAttempts: 1)
        #expect(tracker.shouldMove(windowID: 1, current: clamped, target: target))
        #expect(!tracker.shouldMove(windowID: 1, current: clamped, target: target))
        #expect(tracker.settledCount == 1)

        tracker.prune(keeping: [99])
        #expect(tracker.settledCount == 0)

        // Pruned, so the window is treated as new if it comes back.
        #expect(tracker.shouldMove(windowID: 1, current: clamped, target: target))
    }
}
