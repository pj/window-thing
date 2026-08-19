import Testing
import Foundation
@testable import WindowThingCore

/// How a pin finds its window again.
///
/// Titles alone are not an identity: two documents can share a name, and real
/// titles carry volatile detail. A window id is exact but does not survive the
/// window closing, so the two are ranked rather than chosen between.
@Suite("Window identity")
struct WindowIdentityTests {

    private func window(
        id: UInt32, app: String = "Editor", title: String = "", bundle: String? = "com.test.editor"
    ) -> Window {
        Window(id: id, title: title, application: app, bundleId: bundle,
               frame: WindowFrame(x: 0, y: 0, width: 800, height: 600), pid: 1)
    }

    // MARK: - Ranking

    @Test("The pinned window wins over another window of the same app")
    func idBeatsAppMatch() {
        let pin = PinnedConfig(application: "Editor", bundleId: "com.test.editor", windowId: 42)

        #expect(LayoutCalculator.windowMatchScore(window(id: 42), pinned: pin) == 3)
        #expect(LayoutCalculator.windowMatchScore(window(id: 7), pinned: pin) == 1)
    }

    @Test("The pinned window wins even when another has the recorded title")
    func idBeatsTitleMatch() {
        // Two documents called the same thing: the title cannot tell them apart,
        // the id can.
        let pin = PinnedConfig(
            application: "Editor", bundleId: "com.test.editor",
            windowTitles: ["notes.md"], windowId: 42)

        #expect(LayoutCalculator.windowMatchScore(window(id: 42, title: "notes.md"), pinned: pin) == 3)
        #expect(LayoutCalculator.windowMatchScore(window(id: 7, title: "notes.md"), pinned: pin) == 2)
    }

    @Test("A stale id falls back to the title, then to the app")
    func staleIdDegrades() {
        // The window closed, or the app relaunched — the pin should still find
        // something rather than the pane emptying out.
        let pin = PinnedConfig(
            application: "Editor", bundleId: "com.test.editor",
            windowTitles: ["notes.md"], windowId: 999)
        let live = [window(id: 1, title: "other.md"), window(id: 2, title: "notes.md")]

        #expect(LayoutCalculator.bestMatchingWindow(for: pin, in: live)?.id == 2)
    }

    @Test("An id belonging to another application is ignored")
    func idIsScopedToTheApp() {
        // Ids are reused after a window closes, so a stale one can land on some
        // unrelated window. It only counts inside an app match.
        let pin = PinnedConfig(application: "Editor", bundleId: "com.test.editor", windowId: 42)
        let impostor = window(id: 42, app: "Mail", bundle: "com.test.mail")

        #expect(LayoutCalculator.windowMatchScore(impostor, pinned: pin) == 0)
    }

    // MARK: - Stability

    @Test("Equally-good candidates resolve the same way whatever the order")
    func tieBreakIsDeterministic() {
        // This is the oscillation. Candidates arrive from
        // CGWindowListCopyWindowInfo in z-order, so the list reshuffles whenever
        // the user focuses a different window. Without a tie-break, two windows
        // that score the same swapped places between passes and whichever lost
        // dropped into the stack — the layout appeared to flicker by itself.
        let pin = PinnedConfig(application: "Editor", bundleId: "com.test.editor")
        let a = window(id: 10, title: "notes.md")
        let b = window(id: 20, title: "notes.md")

        #expect(LayoutCalculator.bestMatchingWindow(for: pin, in: [a, b])?.id == 10)
        #expect(LayoutCalculator.bestMatchingWindow(for: pin, in: [b, a])?.id == 10)
    }

    @Test("Identical titles resolve consistently across every ordering")
    func tieBreakHoldsForEveryPermutation() {
        let pin = PinnedConfig(
            application: "Editor", bundleId: "com.test.editor", windowTitles: ["notes.md"])
        let windows = [window(id: 30, title: "notes.md"),
                       window(id: 10, title: "notes.md"),
                       window(id: 20, title: "notes.md")]

        for ordering in windows.permutations() {
            #expect(LayoutCalculator.bestMatchingWindow(for: pin, in: ordering)?.id == 10)
        }
    }

    @Test("A pinned id is stable even as the front window changes")
    func idIsStableUnderReordering() {
        let pin = PinnedConfig(application: "Editor", bundleId: "com.test.editor", windowId: 20)
        let windows = [window(id: 10), window(id: 20), window(id: 30)]

        for ordering in windows.permutations() {
            #expect(LayoutCalculator.bestMatchingWindow(for: pin, in: ordering)?.id == 20)
        }
    }

    @Test("A window already placed elsewhere is not claimed twice")
    func respectsAlreadyPlaced() {
        let pin = PinnedConfig(application: "Editor", bundleId: "com.test.editor", windowId: 10)
        let windows = [window(id: 10), window(id: 20)]

        let next = LayoutCalculator.bestMatchingWindow(for: pin, in: windows, excluding: [10])
        #expect(next?.id == 20, "the pane should fall back rather than fight for a placed window")
    }

    // MARK: - Persistence

    @Test("The id survives a round trip through the config")
    func idIsCodable() throws {
        let pin = PinnedConfig(
            application: "Editor", bundleId: "com.test.editor",
            windowTitles: ["notes.md"], windowId: 42)

        let decoded = try JSONDecoder().decode(
            PinnedConfig.self, from: JSONEncoder().encode(pin))

        #expect(decoded.windowId == 42)
        #expect(decoded.windowTitles == ["notes.md"])
    }

    @Test("A config written before ids decodes with none")
    func olderConfigsDecode() throws {
        let json = #"{"application":"Editor","bundleId":"com.test.editor"}"#
        let decoded = try JSONDecoder().decode(
            PinnedConfig.self, from: Data(json.utf8))

        #expect(decoded.windowId == nil)
        #expect(decoded.application == "Editor")
    }
}

private extension Array {
    /// Every ordering, for asserting that a result does not depend on one.
    func permutations() -> [[Element]] {
        guard count > 1 else { return [self] }
        return indices.flatMap { i -> [[Element]] in
            var rest = self
            let element = rest.remove(at: i)
            return rest.permutations().map { [element] + $0 }
        }
    }
}
