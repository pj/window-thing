import Testing
import CoreGraphics
@testable import WindowThingCore

/// `NSScreen.frame` is Cocoa (origin bottom-left of the primary screen, y up);
/// window frames are global CG (origin top-left of the primary screen, y down).
/// Displays must be expressed in the window space or layouts land at the wrong
/// height on every screen except the primary one.
@Suite("Display coordinate conversion")
struct DisplayCoordinateTests {

    /// 2880×1864 built-in, as the primary.
    private let primaryHeight: CGFloat = 1864

    @Test("The primary screen is unchanged — its two spaces coincide")
    func primaryIsIdentity() {
        let frame = WindowManager.globalFrame(
            forScreenFrame: CGRect(x: 0, y: 0, width: 2880, height: 1864),
            primaryHeight: primaryHeight
        )

        #expect(frame.x == 0)
        #expect(frame.y == 0)
        #expect(frame.width == 2880)
        #expect(frame.height == 1864)
    }

    @Test("A taller screen alongside gets a negative y, not a positive one")
    func tallerScreenAlongside() {
        // A 5120×2160 display to the right, bottoms aligned in Cocoa: its top
        // rises above the primary's, so in CG its origin is above zero.
        let frame = WindowManager.globalFrame(
            forScreenFrame: CGRect(x: 2880, y: 0, width: 5120, height: 2160),
            primaryHeight: primaryHeight
        )

        #expect(frame.x == 2880)
        #expect(frame.y == CGFloat(-296))   // 1864 - 2160
        #expect(frame.height == 2160)
    }

    @Test("A screen above the primary sits at negative y")
    func screenAbove() {
        let frame = WindowManager.globalFrame(
            forScreenFrame: CGRect(x: 0, y: 1864, width: 2880, height: 1800),
            primaryHeight: primaryHeight
        )

        // Cocoa put it at +1864 (upwards); CG puts its top edge 1800 above zero.
        #expect(frame.y == -1800)
    }

    @Test("A screen below the primary sits at positive y")
    func screenBelow() {
        let frame = WindowManager.globalFrame(
            forScreenFrame: CGRect(x: 0, y: -1080, width: 1920, height: 1080),
            primaryHeight: primaryHeight
        )

        #expect(frame.y == primaryHeight)
    }

    @Test("x is untouched — the two spaces share a horizontal axis")
    func horizontalIsUnchanged() {
        let left = WindowManager.globalFrame(
            forScreenFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            primaryHeight: primaryHeight
        )

        #expect(left.x == -1920)
        #expect(left.width == 1920)
    }
}

/// The usable area of a screen, and why the layout must use it.
@Suite("Visible frame")
struct VisibleFrameTests {

    @Test("A display's frame excludes the menu bar")
    func menuBarIsExcluded() {
        // A 3456x2234 primary screen with a 33pt menu bar: visibleFrame sits
        // 33pt lower in Cocoa terms, which is y=33 once flipped into the global
        // space windows actually live in.
        let visible = CGRect(x: 0, y: 0, width: 3456, height: 2201)
        let frame = WindowManager.globalFrame(forScreenFrame: visible, primaryHeight: 2234)

        #expect(frame.y == 33)
        #expect(frame.height == 2201)
    }

    @Test("Targets built from the visible frame are reachable")
    func targetsAreReachable() {
        // Regression: using the full frame put every target 33pt above where
        // macOS will let a window sit, so reconciliation rewrote every window on
        // every tick and never converged.
        let visible = CGRect(x: 0, y: 0, width: 3456, height: 2201)
        let target = WindowManager.globalFrame(forScreenFrame: visible, primaryHeight: 2234)

        // What the window server actually grants: clamped below the menu bar.
        let achievable = WindowFrame(x: 0, y: 33, width: 3456, height: 2201)

        #expect(!achievable.needsMove(to: target))
    }
}
