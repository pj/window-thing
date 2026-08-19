import Foundation
import CoreGraphics

/// Converting a divider drag into new pane percentages.
///
/// Split out of the layout canvas so it can be checked without a running app:
/// it is pure arithmetic, and getting it wrong makes dragging feel broken in
/// ways that are hard to pin down by eye.
public enum DividerResize {

    /// Smallest share a pane may be squeezed to, so a divider can't swallow its
    /// neighbour entirely and leave nothing to grab.
    ///
    /// A fraction of the container rather than a fixed number, because
    /// percentages are normalised by their sum and need not be on a 0–100
    /// scale: children of `[1, 1, 2]` are a third/third-ish split, and a flat
    /// minimum of 5 would exceed every one of them.
    public static let minimumFraction: Double = 0.05

    /// The floor for a container whose child percentages add up to `sum`.
    public static func minimumPct(forSum sum: Double) -> Double {
        sum * minimumFraction
    }

    /// New percentages for the two panes either side of a divider that has been
    /// dragged `travel` points along its axis.
    ///
    /// - Parameters:
    ///   - travel: drag distance in points, positive towards the second pane.
    ///   - containerLength: length of the whole container along that axis.
    ///   - startA: first pane's percentage when the drag began.
    ///   - startB: second pane's percentage when the drag began.
    ///   - siblingsPctSum: sum of *every* sibling percentage in the container.
    ///     Percentages are normalised by this rather than assumed to total 100,
    ///     so it is what maps points onto the percentage scale. Using just
    ///     `startA + startB` makes a divider between three or more panes lag the
    ///     cursor by the fraction of the container the other panes take up.
    ///
    /// Only the two adjacent panes change, and their combined share is
    /// preserved, so the rest of the layout stays put.
    public static func resolve(
        travel: CGFloat,
        containerLength: CGFloat,
        startA: Double,
        startB: Double,
        siblingsPctSum: Double
    ) -> (a: Double, b: Double) {
        let pair = startA + startB
        guard pair > 0 else { return (startA, startB) }

        let deltaPct = Double(travel / max(containerLength, 1)) * siblingsPctSum
        let minimum = minimumPct(forSum: siblingsPctSum)

        // With a pair smaller than two minimums there is no legal split; sit in
        // the middle rather than letting the clamps invert.
        guard pair >= minimum * 2 else { return (pair / 2, pair / 2) }

        let a = min(max(minimum, startA + deltaPct), pair - minimum)
        return (a, pair - a)
    }
}
