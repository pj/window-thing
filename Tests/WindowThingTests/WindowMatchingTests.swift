import Testing
@testable import WindowThingCore

/// Pinning a specific window records its title. Titles carry volatile detail —
/// zoom levels, document names, unread counts — so they rank candidates rather
/// than filter them: a pin that no longer recognises its window must fall back
/// to the same app, never empty out into the stack.
@Suite("Pinned window matching")
struct WindowMatchingTests {

    private func window(_ id: UInt32, app: String, bundle: String?, title: String) -> Window {
        Window(
            id: id,
            title: title,
            application: app,
            bundleId: bundle,
            frame: WindowFrame(x: 0, y: 0, width: 100, height: 100),
            pid: 100
        )
    }

    @Test("The pinned window wins over its siblings")
    func prefersThePinnedWindow() {
        let windows = [
            window(1, app: "Affinity", bundle: "com.canva.affinity", title: "frame001.png"),
            window(2, app: "Affinity", bundle: "com.canva.affinity", title: "frame004.png")
        ]
        let pinned = PinnedConfig(
            application: "Affinity", bundleId: "com.canva.affinity", windowTitles: ["frame004.png"]
        )

        #expect(LayoutCalculator.bestMatchingWindow(for: pinned, in: windows)?.id == 2)
    }

    @Test("A title that has drifted falls back to the same app, not to nothing")
    func fallsBackWhenTitleDrifts() {
        let windows = [
            window(1, app: "Affinity", bundle: "com.canva.affinity", title: "frame004.png @ 512%")
        ]
        // Recorded when the zoom level was different.
        let pinned = PinnedConfig(
            application: "Affinity",
            bundleId: "com.canva.affinity",
            windowTitles: ["frame004.png @ 338%"]
        )

        #expect(LayoutCalculator.bestMatchingWindow(for: pinned, in: windows)?.id == 1)
        #expect(LayoutCalculator.windowMatchScore(windows[0], pinned: pinned) == 1)
    }

    @Test("A different app never matches")
    func neverCrossesApps() {
        let windows = [window(1, app: "Mail", bundle: "com.apple.mail", title: "Inbox")]
        let pinned = PinnedConfig(
            application: "Affinity", bundleId: "com.canva.affinity", windowTitles: ["Inbox"]
        )

        #expect(LayoutCalculator.bestMatchingWindow(for: pinned, in: windows) == nil)
        #expect(LayoutCalculator.windowMatchScore(windows[0], pinned: pinned) == 0)
    }

    @Test("Already-placed windows are skipped")
    func skipsPlacedWindows() {
        let windows = [
            window(1, app: "Safari", bundle: "com.apple.Safari", title: "One"),
            window(2, app: "Safari", bundle: "com.apple.Safari", title: "Two")
        ]
        let pinned = PinnedConfig(application: "Safari", bundleId: "com.apple.Safari")

        let match = LayoutCalculator.bestMatchingWindow(
            for: pinned, in: windows, excluding: [1]
        )
        #expect(match?.id == 2)
    }

    @Test("An app-level pin takes the first candidate in z-order")
    func appPinKeepsZOrder() {
        let windows = [
            window(1, app: "Safari", bundle: "com.apple.Safari", title: "Front"),
            window(2, app: "Safari", bundle: "com.apple.Safari", title: "Behind")
        ]
        let pinned = PinnedConfig(application: "Safari", bundleId: "com.apple.Safari")

        #expect(LayoutCalculator.bestMatchingWindow(for: pinned, in: windows)?.id == 1)
    }
}
