import Testing
import CoreGraphics
@testable import WindowThingCore

@Suite("Display Reconciliation")
struct DisplayReconciliationTests {

    // MARK: - Screen Set Fallback on Display Disconnect

    @Test("Dual-display layout falls back when only one display available")
    func dualLayoutSingleDisplay() {
        let layout = TestFixtures.dualDisplayLayout
        let placements = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: TestFixtures.singleDisplay,
            windows: TestFixtures.typicalWindows
        )
        // All placements should be within the single display bounds (0-1920)
        for p in placements {
            #expect(p.targetFrame.x >= 0)
            #expect(p.targetFrame.x + p.targetFrame.width <= 1920)
        }
    }

    @Test("Screen set with missing named display skips that display's layout")
    func missingNamedDisplaySkipped() {
        // Layout references "External Display" but only main is available
        let screenSet = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode"),
            "External Display": .columns([
                .pinned(app: "Terminal", percentage: 50),
                .pinned(app: "Safari", percentage: 50)
            ])
        ])
        let layout = Layout(name: "Test", screens: screenSet)
        let placements = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: TestFixtures.singleDisplay,
            windows: TestFixtures.typicalWindows
        )
        // VSCode should be placed on main (pinned to $PRIMARY)
        let vscodePlacement = placements.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscodePlacement != nil)
        #expect(vscodePlacement!.targetFrame.x == 0)
        // Terminal and Safari should still be placed (stacked on main as remaining)
        let terminalPlacement = placements.first { $0.window.bundleId == "com.apple.Terminal" }
        #expect(terminalPlacement != nil)
        #expect(terminalPlacement!.targetFrame.x >= 0)
        #expect(terminalPlacement!.targetFrame.x + terminalPlacement!.targetFrame.width <= 1920)
    }

    @Test("Reconnecting a display brings its half of the layout back")
    func reconnectionUsesTheDisplaysTree() {
        // One map covering both screens. There is nothing to choose between:
        // the external's tree is used when it is attached and dropped when it
        // is not, and the stack on $PRIMARY catches the windows either way.
        let layout = Layout(
            name: "Desk",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 60),
                    .stackAll(percentage: 40)
                ]),
                "External Display": .pinned(app: nil, bundleId: "com.apple.Safari")
            ])
        )

        let alone = layout.screens.resolved(for: TestFixtures.singleDisplay)
        #expect(alone.layouts["External Display"] == nil)
        #expect(alone.layouts[ScreenConfig.primaryKey] != nil)

        let both = layout.screens.resolved(for: TestFixtures.dualDisplays)
        #expect(both.layouts["External Display"] != nil)
        #expect(both.layouts.count == 2)
    }

    @Test("Losing a display drops its tree and keeps the rest")
    func losingADisplayDegrades() {
        // One map across three screens. Unplugging one does not select a
        // different arrangement — it removes that display's tree and leaves
        // the others exactly as they were.
        let layout = Layout(
            name: "Multi",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode"),
                "External Display": .stackAll(),
                "Left Display": .pinned(app: "Terminal")
            ])
        )

        let all = layout.screens.resolved(for: TestFixtures.tripleDisplays)
        #expect(all.layouts.count == 3)

        let two = layout.screens.resolved(for: TestFixtures.dualDisplays)
        #expect(two.layouts.count == 2)
        #expect(two.layouts["Left Display"] == nil)
        #expect(two.layouts["External Display"] != nil)
    }

    @Test("reconcileCurrentLayout via mock repositions windows on remaining display")
    func reconcileAfterDisconnect() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.dualDisplays
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)
        layoutManager.applyLayout(TestFixtures.dualDisplayLayout)
        layoutManager.waitForPendingApply()

        // Verify initial placement: some windows on external display
        let initialExternal = mockWindowManager.setWindowFrameCalls.filter { $0.frame.x >= 1920 }
        #expect(!initialExternal.isEmpty)

        // Simulate display disconnect: now only main display
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.setWindowFrameCalls = []
        layoutManager.reconcileCurrentLayout()

        // All placements should now be on the main display
        for call in mockWindowManager.setWindowFrameCalls {
            #expect(call.frame.x >= 0, "Window at x=\(call.frame.x) should be >= 0")
            #expect(call.frame.x + call.frame.width <= 1920,
                    "Window extends past main display: x=\(call.frame.x), w=\(call.frame.width)")
        }
    }

    @Test("No screen set matches falls back to stack on primary")
    func noScreenSetMatchFallback() {
        // Layout only has a screen set for displays we don't have
        let layout = Layout(
            name: "Specific",
            screens: ScreenConfig(layouts: [
                    "Unknown Monitor": .pinned(app: "Safari"),
                    "Also Unknown": .pinned(app: "Terminal")
                ])
        )
        let placements = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: TestFixtures.singleDisplay,
            windows: TestFixtures.typicalWindows
        )
        // Should still place windows (fallback to stack on primary)
        #expect(!placements.isEmpty)
        for p in placements {
            #expect(p.targetFrame.x >= 0)
            #expect(p.targetFrame.x + p.targetFrame.width <= 1920)
        }
    }
}
