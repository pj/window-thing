import Testing
import Foundation
import CoreGraphics
@testable import WindowThingCore

/// The window poll skips its expensive half — an Accessibility round trip per
/// app, plus a position read per window — whenever this fingerprint is
/// unchanged. Anything it fails to notice is a change the caches never see, so
/// these are about what must register, not about what may be skipped.
@Suite("Window list fingerprint")
struct WindowListFingerprintTests {

    private func entry(
        id: CGWindowID,
        name: String = "Document",
        x: CGFloat = 0, y: CGFloat = 0,
        width: CGFloat = 800, height: CGFloat = 600
    ) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowName as String: name,
            kCGWindowBounds as String: [
                "X": x, "Y": y, "Width": width, "Height": height
            ] as [String: CGFloat]
        ]
    }

    @Test("The same screen twice fingerprints the same")
    func stableWhenNothingChanges() {
        let list = [entry(id: 1), entry(id: 2, name: "Mail")]

        #expect(WindowManager.fingerprint(of: list) == WindowManager.fingerprint(of: list))
    }

    @Test("A window that moved is noticed")
    func noticesAMove() {
        let before = [entry(id: 1, x: 0, y: 0)]
        let after = [entry(id: 1, x: 400, y: 0)]

        #expect(WindowManager.fingerprint(of: before) != WindowManager.fingerprint(of: after))
    }

    @Test("A window that resized is noticed")
    func noticesAResize() {
        let before = [entry(id: 1, width: 800, height: 600)]
        let after = [entry(id: 1, width: 1200, height: 600)]

        #expect(WindowManager.fingerprint(of: before) != WindowManager.fingerprint(of: after))
    }

    @Test("A window that opened is noticed")
    func noticesAnOpen() {
        let before = [entry(id: 1)]
        let after = [entry(id: 1), entry(id: 2)]

        #expect(WindowManager.fingerprint(of: before) != WindowManager.fingerprint(of: after))
    }

    @Test("A window that closed is noticed")
    func noticesAClose() {
        let before = [entry(id: 1), entry(id: 2)]
        let after = [entry(id: 1)]

        #expect(WindowManager.fingerprint(of: before) != WindowManager.fingerprint(of: after))
    }

    @Test("A renamed window is noticed")
    func noticesARename() {
        // Only when the window server knows the name. Where it does not, the
        // title comes from Accessibility and is refreshed on a timer instead —
        // this fingerprint cannot see those, which is why that timer exists.
        let before = [entry(id: 1, name: "Draft")]
        let after = [entry(id: 1, name: "Final")]

        #expect(WindowManager.fingerprint(of: before) != WindowManager.fingerprint(of: after))
    }

    @Test("Two windows swapping places is noticed")
    func noticesASwap() {
        // Same windows, same two frames, exchanged. A fingerprint that summed
        // or set-combined its inputs would call this unchanged and leave both
        // windows believed to be where the other one is.
        let before = [entry(id: 1, x: 0), entry(id: 2, x: 900)]
        let after = [entry(id: 1, x: 900), entry(id: 2, x: 0)]

        #expect(WindowManager.fingerprint(of: before) != WindowManager.fingerprint(of: after))
    }

    @Test("An empty screen is stable and differs from an occupied one")
    func handlesEmpty() {
        #expect(WindowManager.fingerprint(of: []) == WindowManager.fingerprint(of: []))
        #expect(WindowManager.fingerprint(of: []) != WindowManager.fingerprint(of: [entry(id: 1)]))
    }

    @Test("A malformed entry does not collide with a real one")
    func handlesMissingFields() {
        // Entries missing bounds or a number fall back to zeroes rather than
        // being dropped, so they still have to be told apart from a real window
        // that happens to sit at the origin.
        let malformed: [[String: Any]] = [[:]]

        #expect(WindowManager.fingerprint(of: malformed) == WindowManager.fingerprint(of: malformed))
        #expect(WindowManager.fingerprint(of: malformed) != WindowManager.fingerprint(of: [entry(id: 1)]))
    }
}
