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
        let layout = Layout(name: "Test", screenSets: [screenSet])
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

    @Test("Reconnection picks dual-display screen set over single")
    func reconnectionPicksDualScreenSet() {
        // Layout with both single-display and dual-display screen sets
        let layout = Layout(
            name: "Adaptive",
            screenSets: [
                // Single display screen set
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .columns([
                        .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 60),
                        .stackAll(percentage: 40)
                    ])
                ]),
                // Dual display screen set
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode"),
                    "External Display": .stackAll()
                ])
            ]
        )

        // With single display, should use first screen set (1 key with $PRIMARY)
        let singleMatch = layout.matchingScreenSet(for: TestFixtures.singleDisplay)
        #expect(singleMatch != nil)
        // The single-display match has 1 key ($PRIMARY only)
        // The dual has 2 keys ($PRIMARY + External) but External doesn't exist
        // So the dual won't match (External is not subset of available)

        // With dual displays, should prefer the dual screen set (matches 2)
        let dualMatch = layout.matchingScreenSet(for: TestFixtures.dualDisplays)
        #expect(dualMatch != nil)
        #expect(dualMatch!.layouts.count == 2)
        #expect(dualMatch!.layouts["External Display"] != nil)
    }

    @Test("Triple-display to dual-display falls back correctly")
    func tripleToDoualFallback() {
        let layout = Layout(
            name: "Multi",
            screenSets: [
                // Dual screen set
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode"),
                    "External Display": .stackAll()
                ]),
                // Triple screen set
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode"),
                    "External Display": .pinned(app: "Safari"),
                    "Left Display": .pinned(app: "Terminal")
                ])
            ]
        )

        // With triple displays, should match the triple screen set (3 > 2)
        let tripleMatch = layout.matchingScreenSet(for: TestFixtures.tripleDisplays)
        #expect(tripleMatch != nil)
        #expect(tripleMatch!.layouts.count == 3)

        // With dual displays (no "Left Display"), should fall back to dual screen set
        let dualMatch = layout.matchingScreenSet(for: TestFixtures.dualDisplays)
        #expect(dualMatch != nil)
        #expect(dualMatch!.layouts.count == 2)
        #expect(dualMatch!.layouts["Left Display"] == nil)
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
            screenSets: [
                ScreenConfig(layouts: [
                    "Unknown Monitor": .pinned(app: "Safari"),
                    "Also Unknown": .pinned(app: "Terminal")
                ])
            ]
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
