import Testing
@testable import WindowThingCore

/// Fitting a layout to whatever is plugged in.
///
/// A layout names displays; some of them may not be there. There are no
/// prepared alternatives to choose between any more, so one map degrades.
@Suite("Screen resolution")
struct ScreenResolutionTests {

    private func display(_ name: String, main: Bool = false, x: Double = 0) -> Display {
        Display.testDisplay(id: Int(x), name: name, x: x, width: 1920, height: 1080, isMain: main)
    }

    private var laptop: [Display] { [display("Built-in", main: true)] }
    private var desk: [Display] { [display("Built-in", main: true), display("Studio", x: 1920)] }

    @Test("An attached display keeps its tree")
    func attachedDisplaysSurvive() {
        let screens = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "Studio": .pinned(app: "Safari")
        ])
        let resolved = screens.resolved(for: desk)
        #expect(resolved.layouts.count == 2)
        #expect(resolved.layouts["Studio"] == .pinned(app: "Safari"))
    }

    @Test("An unplugged display's tree is dropped, and the rest still applies")
    func unpluggedDisplaysAreDropped() {
        let screens = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "Studio": .pinned(app: "Safari")
        ])
        let resolved = screens.resolved(for: laptop)
        #expect(resolved.layouts["Studio"] == nil)
        #expect(resolved.layouts[ScreenConfig.primaryKey] == .stackAll())
    }

    @Test("A window pinned only on an unplugged display falls back to the stack")
    func orphanedPinsFallBackToTheStack() {
        // Safari is pinned on the Studio, which is gone. Nothing places it any
        // more, so it is left to the stack — which is what the stack is for.
        let screens = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "Studio": .pinned(app: "Safari")
        ])
        let resolved = screens.resolved(for: laptop)

        let placements = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: resolved,
            displays: laptop,
            windows: [
                Window.testWindow(id: 1, application: "Safari", bundleId: "com.apple.Safari"),
                Window.testWindow(id: 2, application: "Notes", bundleId: "com.apple.Notes")
            ]
        )
        let safari = placements.first { $0.window.bundleId == "com.apple.Safari" }
        #expect(safari != nil)
        // On the laptop, in the stack, rather than off-screen or unplaced.
        #expect(safari!.targetFrame.x == 0)
    }

    @Test("Losing the stack collapses the whole layout to a fullscreen stack")
    func losingTheStackCollapses() {
        // The stack lived on the Studio. With it gone there is nowhere for
        // unpinned windows to land, so the arrangement is no longer valid —
        // this is not a local repair.
        let screens = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .pinned(app: "Xcode"),
            "Studio": .stackAll()
        ])
        let resolved = screens.resolved(for: laptop)

        #expect(resolved.layouts.count == 1)
        #expect(resolved.layouts[ScreenConfig.primaryKey]?.type == .stack)
    }

    @Test("A layout that never had a stack is left alone")
    func noStackIsNotTheSameAsLosingOne() {
        // Every pane is pinned and nothing collects the remainder. That is a
        // choice, not damage: collapsing it would rearrange screens the user
        // deliberately left alone.
        let screens = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .columns([
                .pinned(app: "Xcode", percentage: 50),
                .pinned(app: "Safari", percentage: 50)
            ])
        ])
        let resolved = screens.resolved(for: laptop)
        #expect(resolved.layouts[ScreenConfig.primaryKey]?.type == .columns)
    }

    @Test("A layout naming nothing attached falls back rather than doing nothing")
    func nothingAttachedFallsBack() {
        let screens = ScreenConfig(layouts: ["Studio": .stackAll()])
        let resolved = screens.resolved(for: laptop)
        #expect(resolved.layouts[ScreenConfig.primaryKey]?.type == .stack)
    }

    @Test("$PRIMARY follows whichever display is main")
    func primaryFollowsTheMainDisplay() {
        let screens = ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        let swapped = [display("Built-in", x: 0), display("Studio", main: true, x: 1920)]
        #expect(screens.resolved(for: swapped).layouts[ScreenConfig.primaryKey] != nil)
    }

    // MARK: - The primary-display invariant

    @Test("A layout with no primary gains one on load")
    func loadEnsuresAPrimary() {
        let layout = Layout(name: "Odd", screens: ScreenConfig(layouts: ["Studio": .stackAll()]))
        let fixed = layout.ensuringPrimaryDisplay()
        // The stack is already spoken for, so the primary starts empty rather
        // than becoming a second stack.
        #expect(fixed.screens.layouts[ScreenConfig.primaryKey]?.type == .empty)
    }

    @Test("A layout that already names the primary is untouched")
    func loadLeavesAPrimaryAlone() {
        let layout = Layout(
            name: "Fine",
            screens: ScreenConfig(layouts: [ScreenConfig.primaryKey: .columns([
                .stackAll(percentage: 50), .empty(percentage: 50)
            ])])
        )
        #expect(layout.ensuringPrimaryDisplay() == layout)
    }

    @Test("A layout with no stack anywhere gets one on the primary")
    func loadGivesTheStackAHome() {
        let layout = Layout(name: "Pins", screens: ScreenConfig(layouts: ["Studio": .pinned(app: "Safari")]))
        #expect(layout.ensuringPrimaryDisplay().screens.layouts[ScreenConfig.primaryKey]?.type == .stack)
    }
}
