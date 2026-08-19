import Foundation
import CoreGraphics

/// Remembers what each window can actually achieve, so the app stops fighting
/// windows that cannot do what the layout asks.
///
/// Some windows simply refuse a target: a fixed-size dialog, an app with a
/// minimum width, a terminal that snaps to a character grid. Reconciliation runs
/// on a timer, so without this those windows are moved, checked, found wrong and
/// moved again for as long as the app runs — several Accessibility round trips
/// each, forever, changing nothing.
///
/// This is not "give up on the window". After a few failed attempts it records
/// where the window *did* land and treats that as satisfied for that target. If
/// the window later moves away from there — because the user dragged it, or the
/// layout changed — it is placed again. So a window that cannot be 1107pt tall
/// settles at 1074 and is left alone, but is still pulled back if it wanders.
public final class WindowSettleTracker {

    private struct Record {
        let target: WindowFrame
        var attempts: Int
        /// Where the window proved it can actually get to, once we stop asking.
        var settledAt: WindowFrame?
    }

    /// How many passes to attempt a target before accepting where it landed.
    /// More than one because a window may take a moment to respond, so a single
    /// failed check is not proof it cannot comply.
    public let maxAttempts: Int

    private var records: [CGWindowID: Record] = [:]

    public init(maxAttempts: Int = 3) {
        self.maxAttempts = maxAttempts
    }

    /// Whether to issue a move for this window, updating what we know about it.
    ///
    /// Call once per window per reconcile pass, whether or not it looks correct:
    /// success is what clears the record.
    public func shouldMove(
        windowID: CGWindowID,
        current: WindowFrame,
        target: WindowFrame
    ) -> Bool {
        // Where it should be. Nothing to do, and nothing left to remember.
        if !current.needsMove(to: target) {
            records[windowID] = nil
            return false
        }

        var record = records[windowID]

        // A different goal says nothing about the old one.
        if let existing = record, existing.target.needsMove(to: target) {
            record = nil
        }

        guard var existing = record else {
            records[windowID] = Record(target: target, attempts: 1, settledAt: nil)
            return true
        }

        if let settled = existing.settledAt {
            if !current.needsMove(to: settled) {
                // As close as this window gets. Leave it be.
                return false
            }
            // It has moved away from where it settled, so the old conclusion no
            // longer describes it. Start the target over from scratch.
            existing.settledAt = nil
            existing.attempts = 0
        }

        existing.attempts += 1

        if existing.attempts > maxAttempts {
            // It has had its chances; wherever it is now is what it can do.
            existing.settledAt = current
            records[windowID] = existing
            return false
        }

        records[windowID] = existing
        return true
    }

    /// Forget everything. Used when a layout is applied explicitly — the user
    /// asked for it, so every window deserves a fresh attempt.
    public func reset() {
        records.removeAll()
    }

    /// Drop records for windows that are no longer being placed, so closing
    /// windows doesn't leak entries for the life of the process.
    public func prune(keeping live: Set<CGWindowID>) {
        records = records.filter { live.contains($0.key) }
    }

    /// Windows currently accepted as being as close as they can get.
    public var settledCount: Int {
        records.values.count { $0.settledAt != nil }
    }
}
