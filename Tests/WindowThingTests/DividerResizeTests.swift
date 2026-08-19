import Testing
import CoreGraphics
@testable import WindowThingCore

/// Dragging a divider should move the boundary to exactly where the cursor is.
/// The property worth pinning down is that: points in, the same points out.
@Suite("Divider resize")
struct DividerResizeTests {

    /// Where the boundary between pane A and pane B ends up, in points.
    private func boundary(a: Double, siblingsPctSum: Double, containerLength: CGFloat) -> CGFloat {
        CGFloat(a / siblingsPctSum) * containerLength
    }

    @Test("Two panes: the divider lands under the cursor")
    func twoPanesTrackCursor() {
        let result = DividerResize.resolve(
            travel: 100, containerLength: 1000,
            startA: 50, startB: 50, siblingsPctSum: 100)

        // Started at 500pt, dragged 100pt right, so it should be at 600pt.
        #expect(boundary(a: result.a, siblingsPctSum: 100, containerLength: 1000) == 600)
        #expect(result.a == 60)
        #expect(result.b == 40)
    }

    @Test("Three panes: the divider still lands under the cursor")
    func threePanesTrackCursor() {
        // Regression: this used to scale by the dragged pair's own total rather
        // than the container's, so the divider lagged the cursor by the share
        // the third pane occupied — here it stopped at 580pt instead of 600pt.
        let result = DividerResize.resolve(
            travel: 100, containerLength: 1000,
            startA: 50, startB: 30, siblingsPctSum: 100)

        #expect(boundary(a: result.a, siblingsPctSum: 100, containerLength: 1000) == 600)
        #expect(result.a == 60)
        #expect(result.b == 20)
    }

    @Test("Percentages that don't total 100 still track the cursor")
    func unnormalisedPercentagesTrackCursor() {
        // flattenTree normalises by the sum, so [1, 1, 2] is a valid layout.
        // 1000pt container → panes of 250, 250, 500; first divider at 250.
        let result = DividerResize.resolve(
            travel: 100, containerLength: 1000,
            startA: 1, startB: 1, siblingsPctSum: 4)

        #expect(boundary(a: result.a, siblingsPctSum: 4, containerLength: 1000) == 350)
    }

    @Test("The pair's combined share is preserved, so other panes don't move")
    func pairTotalIsPreserved() {
        for travel in [CGFloat(-300), -50, 0, 50, 300] {
            let result = DividerResize.resolve(
                travel: travel, containerLength: 1000,
                startA: 50, startB: 30, siblingsPctSum: 100)

            #expect(abs((result.a + result.b) - 80) < 0.000_001,
                    "travel \(travel) changed the pair's total")
        }
    }

    @Test("Dragging backwards works the same way")
    func negativeTravel() {
        let result = DividerResize.resolve(
            travel: -100, containerLength: 1000,
            startA: 50, startB: 30, siblingsPctSum: 100)

        #expect(boundary(a: result.a, siblingsPctSum: 100, containerLength: 1000) == 400)
        #expect(result.a == 40)
    }

    // MARK: - Clamping

    @Test("A pane can't be squeezed below the minimum")
    func clampsAtMinimum() {
        let far = DividerResize.resolve(
            travel: -10_000, containerLength: 1000,
            startA: 50, startB: 30, siblingsPctSum: 100)
        #expect(far.a == DividerResize.minimumPct(forSum: 100))
        #expect(far.b == 80 - DividerResize.minimumPct(forSum: 100))

        let other = DividerResize.resolve(
            travel: 10_000, containerLength: 1000,
            startA: 50, startB: 30, siblingsPctSum: 100)
        #expect(other.b == DividerResize.minimumPct(forSum: 100))
        #expect(other.a == 80 - DividerResize.minimumPct(forSum: 100))
    }

    @Test("The minimum scales with the container, not a fixed 5")
    func minimumScalesWithSum() {
        // On a [1, 1, 2] container the floor is 0.2, not 5 — a flat 5 would be
        // larger than any pane in it and pin every drag.
        #expect(DividerResize.minimumPct(forSum: 100) == 5)
        #expect(DividerResize.minimumPct(forSum: 4) == 0.2)

        let squeezed = DividerResize.resolve(
            travel: -10_000, containerLength: 1000,
            startA: 1, startB: 1, siblingsPctSum: 4)
        #expect(squeezed.a == 0.2)
    }

    @Test("A pair too small to split legally is halved rather than inverted")
    func degeneratePairDoesNotInvert() {
        // pair = 4, below two minimums. The clamps would otherwise cross and
        // produce a negative pane.
        let result = DividerResize.resolve(
            travel: 500, containerLength: 1000,
            startA: 2, startB: 2, siblingsPctSum: 100)

        #expect(result.a == 2)
        #expect(result.b == 2)
        #expect(result.a >= 0 && result.b >= 0)
    }

    @Test("A zero-width container doesn't divide by zero")
    func zeroContainerLength() {
        let result = DividerResize.resolve(
            travel: 50, containerLength: 0,
            startA: 50, startB: 50, siblingsPctSum: 100)

        #expect(result.a.isFinite && result.b.isFinite)
        #expect(abs((result.a + result.b) - 100) < 0.000_001)
    }

    @Test("An empty pair is returned untouched")
    func emptyPair() {
        let result = DividerResize.resolve(
            travel: 50, containerLength: 1000,
            startA: 0, startB: 0, siblingsPctSum: 100)

        #expect(result.a == 0)
        #expect(result.b == 0)
    }
}
