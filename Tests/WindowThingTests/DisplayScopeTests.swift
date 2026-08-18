import Testing
import Foundation
@testable import WindowThingCore

/// How a layout spans several displays.
///
/// `.shared` is the built interface: one pool of windows and a single stack for
/// the whole layout, so pinning a window to a pane on another screen moves it
/// there. `.perMonitor` has no interface yet — it is modelled and tested so the
/// behaviour is settled before anything exposes it.
@Suite("Display scope")
struct DisplayScopeTests {

    // Two displays side by side in the global window space: a 2000×1000 main
    // and a 1600×1200 secondary to its right, tops aligned.
    private var main: Display {
        Display(id: 0, name: "Built-in", frame: WindowFrame(x: 0, y: 0, width: 2000, height: 1000), isMain: true)
    }
    private var secondary: Display {
        Display(id: 1, name: "External", frame: WindowFrame(x: 2000, y: 0, width: 1600, height: 1200), isMain: false)
    }
    private var displays: [Display] { [main, secondary] }

    /// A window sitting on the main display.
    private func onMain(_ id: UInt32, app: String, title: String = "") -> Window {
        Window(id: id, title: title, application: app, bundleId: "com.test.\(app)",
               frame: WindowFrame(x: 100, y: 100, width: 400, height: 300), pid: 1)
    }

    /// A window sitting on the secondary display.
    private func onSecondary(_ id: UInt32, app: String, title: String = "") -> Window {
        Window(id: id, title: title, application: app, bundleId: "com.test.\(app)",
               frame: WindowFrame(x: 2200, y: 100, width: 400, height: 300), pid: 2)
    }

    // MARK: - Window to display

    @Test("A window belongs to the display its centre sits on")
    func windowDisplayByCentre() {
        #expect(LayoutCalculator.display(containing: onMain(1, app: "A"), in: displays)?.id == 0)
        #expect(LayoutCalculator.display(containing: onSecondary(2, app: "B"), in: displays)?.id == 1)
    }

    @Test("A window off every screen falls back to the main display")
    func strayWindowFallsBackToMain() {
        let stray = Window(id: 9, title: "", application: "A", bundleId: nil,
                           frame: WindowFrame(x: -5000, y: -5000, width: 100, height: 100), pid: 1)
        #expect(LayoutCalculator.display(containing: stray, in: displays)?.isMain == true)
    }

    // MARK: - Shared scope

    @Test("Shared: a pane on one screen claims a window from the other")
    func sharedPinsAcrossScreens() {
        // The stack is on main; the secondary pins an app whose window is
        // currently sitting on main.
        let screenSet = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External": .pinned(app: "Mail")
        ])
        let windows = [onMain(1, app: "Mail"), onMain(2, app: "Safari")]

        let placements = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: screenSet, displays: displays, windows: windows, scope: .shared
        )

        let mail = placements.first { $0.window.id == 1 }
        #expect(mail?.placementType == .pinned)
        // Pulled across to the secondary display.
        #expect(mail?.targetFrame == secondary.frame)
    }

    @Test("Shared: the one stack collects leftovers from every screen")
    func sharedStackCollectsEverything() {
        let screenSet = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External": .empty()
        ])
        let windows = [onMain(1, app: "A"), onSecondary(2, app: "B")]

        let placements = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: screenSet, displays: displays, windows: windows, scope: .shared
        )

        // Both end up in the single stack, wherever they started.
        #expect(placements.count == 2)
        #expect(placements.allSatisfy { $0.placementType == .stacked })
        #expect(placements.allSatisfy { $0.targetFrame == main.frame })
    }

    @Test("Shared: the stack is honoured when it lives on a secondary screen")
    func sharedStackOnSecondaryDisplay() {
        // Regression: placements used to read the stack from the main display
        // only, so a stack anywhere else was silently discarded.
        let screenSet = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .pinned(app: "Mail"),
            "External": .stackAll()
        ])
        let windows = [onMain(1, app: "Mail"), onMain(2, app: "Safari")]

        let placements = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: screenSet, displays: displays, windows: windows, scope: .shared
        )

        let safari = placements.first { $0.window.id == 2 }
        #expect(safari?.placementType == .stacked)
        #expect(safari?.targetFrame == secondary.frame)
    }

    @Test("Shared: with no stack, leftovers only fall back to a main display the layout covers")
    func sharedFallbackNeedsTheMainDisplay() {
        // Regression: the fallback used to accept *any* display, so a layout that
        // described only the secondary screen would haul every unplaced window
        // onto it. A layout that says nothing about the main display has no
        // opinion about those windows, so they stay put.
        let secondaryOnly = ScreenConfig(layouts: ["External": .pinned(app: "Mail")])
        let windows = [onMain(1, app: "Mail"), onMain(2, app: "Safari")]

        let placements = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: secondaryOnly, displays: displays, windows: windows, scope: .shared
        )

        #expect(placements.count == 1)
        #expect(placements.first?.window.id == 1)

        // Whereas a layout that does cover main sweeps the leftovers onto it.
        let coversMain = ScreenConfig(layouts: [ScreenConfig.primaryKey: .pinned(app: "Mail")])

        let withMain = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: coversMain, displays: displays, windows: windows, scope: .shared
        )

        #expect(withMain.count == 2)
        #expect(withMain.allSatisfy { $0.targetFrame == main.frame })
    }

    // MARK: - Per-monitor scope

    @Test("Per-monitor: a pane only claims windows already on its screen")
    func perMonitorDoesNotPullAcrossScreens() {
        let screenSet = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External": .pinned(app: "Mail")
        ])
        // Mail is on main, so the secondary's Mail pane must stay empty.
        let windows = [onMain(1, app: "Mail")]

        let placements = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: screenSet, displays: displays, windows: windows, scope: .perMonitor
        )

        let mail = placements.first { $0.window.id == 1 }
        #expect(mail?.placementType == .stacked)
        #expect(mail?.targetFrame == main.frame)
    }

    @Test("Per-monitor: each screen stacks its own leftovers")
    func perMonitorStacksSeparately() {
        let screenSet = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External": .stackAll()
        ])
        let windows = [onMain(1, app: "A"), onSecondary(2, app: "B")]

        let placements = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: screenSet, displays: displays, windows: windows, scope: .perMonitor
        )

        #expect(placements.first { $0.window.id == 1 }?.targetFrame == main.frame)
        #expect(placements.first { $0.window.id == 2 }?.targetFrame == secondary.frame)
    }

    @Test("Per-monitor: a screen with no stack keeps its windows fullscreen on it")
    func perMonitorWithoutStackStaysPut() {
        let screenSet = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External": .empty()
        ])
        let windows = [onSecondary(2, app: "B")]

        let placements = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: screenSet, displays: displays, windows: windows, scope: .perMonitor
        )

        // Never migrates to the main display's stack.
        #expect(placements.first { $0.window.id == 2 }?.targetFrame == secondary.frame)
    }

    @Test("Per-monitor and shared disagree, which is the point of the setting")
    func scopesDiffer() {
        let screenSet = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External": .pinned(app: "Mail")
        ])
        let windows = [onMain(1, app: "Mail")]

        let shared = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: screenSet, displays: displays, windows: windows, scope: .shared
        )
        let perMonitor = LayoutCalculator.calculateScreenSetPlacements(
            screenSet: screenSet, displays: displays, windows: windows, scope: .perMonitor
        )

        #expect(shared.first?.targetFrame != perMonitor.first?.targetFrame)
    }

    // MARK: - Layout plumbing

    @Test("A layout with no scope recorded behaves as shared")
    func defaultsToShared() {
        let layout = Layout(name: "Test", screenSets: [
            ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        ])
        #expect(layout.effectiveDisplayScope == .shared)
    }

    @Test("The scope survives a round trip through the config")
    func scopeIsCodable() throws {
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])],
            displayScope: .perMonitor
        )

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)

        #expect(decoded.effectiveDisplayScope == .perMonitor)
    }
}
