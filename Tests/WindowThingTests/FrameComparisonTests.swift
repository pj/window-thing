import Testing
import CoreGraphics
@testable import WindowThingCore

/// Reconciliation runs on a timer, so the question "is this window already where
/// it should be?" is asked constantly. Getting it wrong either re-issues
/// Accessibility writes forever or leaves windows out of place.
@Suite("Frame comparison")
struct FrameComparisonTests {

    private let target = WindowFrame(x: 100, y: 200, width: 800, height: 600)

    @Test("An identical frame needs no move")
    func identicalFrameIsSkipped() {
        #expect(!target.needsMove(to: target))
    }

    @Test("A frame off by less than the tolerance needs no move")
    func withinToleranceIsSkipped() {
        // Apps round, and the AX round trip can land a fraction out. Demanding
        // exactness would rewrite these frames on every tick, forever.
        let nudged = WindowFrame(x: 100.5, y: 199.5, width: 800.5, height: 599.5)
        #expect(!nudged.needsMove(to: target))
    }

    @Test("Each dimension is checked independently")
    func everyDimensionCounts() {
        #expect(WindowFrame(x: 150, y: 200, width: 800, height: 600).needsMove(to: target))
        #expect(WindowFrame(x: 100, y: 250, width: 800, height: 600).needsMove(to: target))
        #expect(WindowFrame(x: 100, y: 200, width: 900, height: 600).needsMove(to: target))
        #expect(WindowFrame(x: 100, y: 200, width: 800, height: 700).needsMove(to: target))
    }

    @Test("A move just past the tolerance is taken")
    func beyondToleranceMoves() {
        let out = WindowFrame(x: 101.5, y: 200, width: 800, height: 600)
        #expect(out.needsMove(to: target))
    }

    @Test("The tolerance is symmetric")
    func toleranceIsSymmetric() {
        let under = WindowFrame(x: 99.5, y: 200, width: 800, height: 600)
        let over = WindowFrame(x: 100.5, y: 200, width: 800, height: 600)

        #expect(!under.needsMove(to: target))
        #expect(!over.needsMove(to: target))
    }

    @Test("A caller can demand an exact match")
    func explicitZeroTolerance() {
        let nudged = WindowFrame(x: 100.5, y: 200, width: 800, height: 600)

        #expect(!nudged.needsMove(to: target))
        #expect(nudged.needsMove(to: target, tolerance: 0))
    }
}
