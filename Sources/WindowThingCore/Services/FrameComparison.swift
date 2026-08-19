import Foundation
import CoreGraphics

public extension WindowFrame {

    /// How far a window may sit from its target before it is worth moving.
    ///
    /// Not zero: the Accessibility API round-trips through the owning app, which
    /// is free to land a point or two off — and many apps snap to their own
    /// grid. Demanding an exact match would mean re-issuing the same move on
    /// every reconcile pass, forever, for windows that are already where they
    /// should be.
    static let moveTolerance: CGFloat = 1.0

    /// Whether this frame is far enough from `target` to be worth an AX write.
    ///
    /// Reconciliation runs on a timer, so in the steady state almost every
    /// window is already in place; skipping those is what keeps a pass from
    /// costing several Accessibility round trips per window, twice a second, in
    /// perpetuity.
    func needsMove(to target: WindowFrame, tolerance: CGFloat = WindowFrame.moveTolerance) -> Bool {
        abs(x - target.x) > tolerance
            || abs(y - target.y) > tolerance
            || abs(width - target.width) > tolerance
            || abs(height - target.height) > tolerance
    }
}
