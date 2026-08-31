import Testing
import CoreGraphics
@testable import WindowThingCore

@Suite("Layout Calculator Tests")
struct LayoutCalculatorTests {

    // MARK: - Column Frame Calculation

    @Test("Calculate column frames equal split")
    func calculateColumnFramesEqualSplit() {
        let columns: [LayoutNode] = [
            .empty(percentage: 50),
            .empty(percentage: 50)
        ]
        let containerFrame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)

        let result = LayoutCalculator.calculateColumnFrames(columns: columns, containerFrame: containerFrame)

        #expect(result.count == 2)
        #expect(result[0].x == 0)
        #expect(result[0].width == 960)
        #expect(result[1].x == 960)
        #expect(result[1].width == 960)
    }

    @Test("Calculate column frames thirds")
    func calculateColumnFramesThirds() {
        let columns: [LayoutNode] = [
            .empty(percentage: 33.33),
            .empty(percentage: 33.33),
            .empty(percentage: 33.34)
        ]
        let containerFrame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)

        let result = LayoutCalculator.calculateColumnFrames(columns: columns, containerFrame: containerFrame)

        #expect(result.count == 3)
        #expect(abs(result[0].x - 0) < 1)
        #expect(abs(result[1].x - 640) < 1)
        #expect(abs(result[2].x - 1280) < 1)
    }

    @Test("Calculate column frames unequal split")
    func calculateColumnFramesUnequalSplit() {
        let columns: [LayoutNode] = [
            .empty(percentage: 70),
            .empty(percentage: 30)
        ]
        let containerFrame = WindowFrame(x: 0, y: 0, width: 1000, height: 500)

        let result = LayoutCalculator.calculateColumnFrames(columns: columns, containerFrame: containerFrame)

        #expect(result.count == 2)
        #expect(result[0].width == 700)
        #expect(result[1].width == 300)
    }

    @Test("Calculate column frames with offset")
    func calculateColumnFramesWithOffset() {
        let columns: [LayoutNode] = [
            .empty(percentage: 50),
            .empty(percentage: 50)
        ]
        let containerFrame = WindowFrame(x: 100, y: 50, width: 800, height: 600)

        let result = LayoutCalculator.calculateColumnFrames(columns: columns, containerFrame: containerFrame)

        #expect(result[0].x == 100)
        #expect(result[0].y == 50)
        #expect(result[1].x == 500)
        #expect(result[1].y == 50)
    }

    @Test("Calculate column frames no percentage")
    func calculateColumnFramesNoPercentage() {
        let columns: [LayoutNode] = [
            LayoutNode(type: .empty),
            LayoutNode(type: .empty),
            LayoutNode(type: .empty)
        ]
        let containerFrame = WindowFrame(x: 0, y: 0, width: 900, height: 600)

        let result = LayoutCalculator.calculateColumnFrames(columns: columns, containerFrame: containerFrame)

        #expect(result.count == 3)
        #expect(abs(result[0].width - 300) < 0.001)
        #expect(abs(result[1].width - 300) < 0.001)
        #expect(abs(result[2].width - 300) < 0.001)
    }

    // MARK: - Row Frame Calculation

    @Test("Calculate row frames equal split")
    func calculateRowFramesEqualSplit() {
        let rows: [LayoutNode] = [
            .empty(percentage: 50),
            .empty(percentage: 50)
        ]
        let containerFrame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)

        let result = LayoutCalculator.calculateRowFrames(rows: rows, containerFrame: containerFrame)

        #expect(result.count == 2)
        #expect(result[0].y == 0)
        #expect(result[0].height == 540)
        #expect(result[1].y == 540)
        #expect(result[1].height == 540)
    }

    @Test("Calculate row frames unequal split")
    func calculateRowFramesUnequalSplit() {
        let rows: [LayoutNode] = [
            .empty(percentage: 60),
            .empty(percentage: 40)
        ]
        let containerFrame = WindowFrame(x: 0, y: 0, width: 800, height: 1000)

        let result = LayoutCalculator.calculateRowFrames(rows: rows, containerFrame: containerFrame)

        #expect(result[0].height == 600)
        #expect(result[1].height == 400)
    }

    // MARK: - Window Matching

    @Test("Find matching window by bundle ID")
    func findMatchingWindowByBundleId() {
        let windows = TestFixtures.typicalWindows
        let pinned = PinnedConfig(application: nil, bundleId: "com.microsoft.VSCode", windowTitles: nil)

        let result = LayoutCalculator.findMatchingWindow(for: pinned, in: windows)

        #expect(result != nil)
        #expect(result?.bundleId == "com.microsoft.VSCode")
    }

    @Test("Find matching window by application name")
    func findMatchingWindowByApplicationName() {
        let windows = TestFixtures.typicalWindows
        let pinned = PinnedConfig(application: "Terminal", bundleId: nil, windowTitles: nil)

        let result = LayoutCalculator.findMatchingWindow(for: pinned, in: windows)

        #expect(result != nil)
        #expect(result?.application == "Terminal")
    }

    @Test("Find matching window case insensitive")
    func findMatchingWindowCaseInsensitive() {
        let windows = TestFixtures.typicalWindows
        let pinned = PinnedConfig(application: "terminal", bundleId: nil, windowTitles: nil)

        let result = LayoutCalculator.findMatchingWindow(for: pinned, in: windows)

        #expect(result != nil)
        #expect(result?.application == "Terminal")
    }

    @Test("Find matching window by partial name")
    func findMatchingWindowByPartialName() {
        let windows = TestFixtures.typicalWindows
        let pinned = PinnedConfig(application: "Saf", bundleId: nil, windowTitles: nil)

        let result = LayoutCalculator.findMatchingWindow(for: pinned, in: windows)

        #expect(result != nil)
        #expect(result?.application == "Safari")
    }

    @Test("Find matching window no match")
    func findMatchingWindowNoMatch() {
        let windows = TestFixtures.typicalWindows
        let pinned = PinnedConfig(application: "Xcode", bundleId: nil, windowTitles: nil)

        let result = LayoutCalculator.findMatchingWindow(for: pinned, in: windows)

        #expect(result == nil)
    }

    @Test("Window matches requires at least one criterion")
    func windowMatchesRequiresAtLeastOneCriterion() {
        let window = TestFixtures.codeWindow
        let emptyPinned = PinnedConfig(application: nil, bundleId: nil, windowTitles: nil)

        let result = LayoutCalculator.windowMatches(window, pinned: emptyPinned)

        #expect(result == false)
    }
}

// MARK: - Empty Node Tests

@Suite("Empty Node Tests")
struct EmptyNodeTests {

    @Test("Empty node receives NO windows")
    func emptyNodeReceivesNoWindows() {
        let node = LayoutNode.empty()
        let frame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.reconcileLayout(
            node: node,
            frame: frame,
            screenFrame: frame,
            windows: windows,
            placedWindowIds: []
        )

        #expect(result.placements.isEmpty)
        #expect(result.placedWindowIds.isEmpty)
        #expect(result.stackFrame == nil)
    }

    @Test("Empty node in columns leaves gap")
    func emptyNodeInColumnsLeavesGap() {
        let node = LayoutNode.columns([
            .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 50),
            .empty(percentage: 50)  // This should remain empty
        ])
        let frame = WindowFrame(x: 0, y: 0, width: 1000, height: 800)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.reconcileLayout(
            node: node,
            frame: frame,
            screenFrame: frame,
            windows: windows,
            placedWindowIds: []
        )

        // Only VSCode should be placed
        #expect(result.placements.count == 1)
        #expect(result.placements[0].window.bundleId == "com.microsoft.VSCode")
    }
}

// MARK: - Stack Node Tests

@Suite("Stack Node Tests")
struct StackNodeTests {

    @Test("Stack node collects all remaining windows")
    func stackNodeCollectsAllRemainingWindows() {
        let node = LayoutNode(type: .stack, percentage: 100)
        let frame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)
        let windows = TestFixtures.typicalWindows  // 5 windows

        let result = LayoutCalculator.calculateNodePlacements(
            node: node,
            frame: frame,
            windows: windows
        )

        // All 5 windows should be stacked
        #expect(result.count == 5)
        for placement in result {
            #expect(placement.targetFrame == frame)
            #expect(placement.placementType == .stacked)
        }
    }

    @Test("Stack with pinned windows in columns")
    func stackWithPinnedWindowsInColumns() {
        let node = LayoutNode.columns([
            .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 50),
            LayoutNode(type: .stack, percentage: 50)
        ])
        let frame = WindowFrame(x: 0, y: 0, width: 1000, height: 800)
        let windows = TestFixtures.typicalWindows  // 5 windows

        let result = LayoutCalculator.calculateNodePlacements(
            node: node,
            frame: frame,
            windows: windows
        )

        // All 5 windows should be placed
        #expect(result.count == 5)

        // VSCode pinned on left
        let vscodePlacement = result.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscodePlacement?.targetFrame.x == 0)
        #expect(vscodePlacement?.targetFrame.width == 500)
        #expect(vscodePlacement?.placementType == .pinned)

        // Others stacked on right
        let stackedPlacements = result.filter { $0.window.bundleId != "com.microsoft.VSCode" }
        #expect(stackedPlacements.count == 4)
        for placement in stackedPlacements {
            #expect(placement.targetFrame.x == 500)
            #expect(placement.targetFrame.width == 500)
            #expect(placement.placementType == .stacked)
        }
    }

    @Test("Stack with specific windows places them first")
    func stackWithSpecificWindowsPlacesThemFirst() {
        let node = LayoutNode.stack([
            PinnedConfig(application: "Safari", bundleId: nil, windowTitles: nil)
        ])
        let frame = WindowFrame(x: 0, y: 0, width: 800, height: 600)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculateNodePlacements(
            node: node,
            frame: frame,
            windows: windows
        )

        // All windows stacked, Safari should be present
        #expect(result.count == 5)
        let safariPlacement = result.first { $0.window.application == "Safari" }
        #expect(safariPlacement != nil)
    }

    @Test("Nested stack collects remaining windows")
    func nestedStackCollectsRemainingWindows() {
        let node = LayoutNode.columns([
            .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 60),
            .rows([
                .pinned(app: "Terminal", percentage: 50),
                LayoutNode(type: .stack, percentage: 50)
            ])
        ])
        let frame = WindowFrame(x: 0, y: 0, width: 1000, height: 800)
        let windows = TestFixtures.typicalWindows  // 5 windows

        let result = LayoutCalculator.calculateNodePlacements(
            node: node,
            frame: frame,
            windows: windows
        )

        // All 5 windows should be placed
        #expect(result.count == 5)

        // VSCode pinned
        let vscode = result.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscode?.placementType == .pinned)

        // Terminal pinned
        let terminal = result.first { $0.window.application == "Terminal" }
        #expect(terminal?.placementType == .pinned)

        // Remaining 3 stacked
        let stacked = result.filter { $0.placementType == .stacked }
        #expect(stacked.count == 3)
    }
}

// MARK: - Pinned Node Tests

@Suite("Pinned Node Tests")
struct PinnedNodeTests {

    @Test("Pinned node places matching window")
    func pinnedNodePlacesMatchingWindow() {
        let node = LayoutNode.pinned(app: nil, bundleId: "com.microsoft.VSCode")
        let frame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.reconcileLayout(
            node: node,
            frame: frame,
            screenFrame: frame,
            windows: windows,
            placedWindowIds: []
        )

        #expect(result.placements.count == 1)
        #expect(result.placements[0].window.bundleId == "com.microsoft.VSCode")
        #expect(result.placements[0].placementType == .pinned)
    }

    @Test("Pinned node no match returns empty")
    func pinnedNodeNoMatchReturnsEmpty() {
        let node = LayoutNode.pinned(app: "Xcode")
        let frame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.reconcileLayout(
            node: node,
            frame: frame,
            screenFrame: frame,
            windows: windows,
            placedWindowIds: []
        )

        #expect(result.placements.isEmpty)
    }

    @Test("Pinned node skips already placed windows")
    func pinnedNodeSkipsAlreadyPlacedWindows() {
        let node = LayoutNode.pinned(app: nil, bundleId: "com.microsoft.VSCode")
        let frame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)
        let windows = TestFixtures.typicalWindows

        // Mark VSCode as already placed
        let alreadyPlaced: Set<UInt32> = [TestFixtures.codeWindow.id]

        let result = LayoutCalculator.reconcileLayout(
            node: node,
            frame: frame,
            screenFrame: frame,
            windows: windows,
            placedWindowIds: alreadyPlaced
        )

        #expect(result.placements.isEmpty)
    }
}

// MARK: - Float/Zoomed Tests

@Suite("Float Zoomed Layout Tests")
struct FloatZoomedLayoutTests {

    @Test("Floating window keeps current position")
    func floatingWindowKeepsCurrentPosition() {
        let node = LayoutNode(
            type: .floatZoomed,
            percentage: 100,
            layout: LayoutNode(type: .stack, percentage: 100),
            floats: [PinnedConfig(application: "Safari", bundleId: nil, windowTitles: nil)]
        )
        let screenFrame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.reconcileLayout(
            node: node,
            frame: screenFrame,
            screenFrame: screenFrame,
            windows: windows,
            placedWindowIds: []
        )

        let safariPlacement = result.placements.first { $0.window.application == "Safari" }
        #expect(safariPlacement != nil)
        #expect(safariPlacement?.placementType == .floating)
        // Safari keeps its original position (from TestFixtures)
        #expect(safariPlacement?.targetFrame == TestFixtures.safariWindow.frame)
    }

    @Test("Floating window constrained to screen bounds")
    func floatingWindowConstrainedToScreenBounds() {
        // Create a window that's outside the screen
        let outsideWindow = Window(
            id: 999,
            title: "Outside",
            application: "TestApp",
            bundleId: "com.test.app",
            frame: WindowFrame(x: 2000, y: 1500, width: 400, height: 300),  // Outside 1920x1080 screen
            pid: 9999
        )

        let node = LayoutNode(
            type: .floatZoomed,
            percentage: 100,
            layout: LayoutNode(type: .stack, percentage: 100),
            floats: [PinnedConfig(application: "TestApp", bundleId: nil, windowTitles: nil)]
        )
        let screenFrame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)

        let result = LayoutCalculator.reconcileLayout(
            node: node,
            frame: screenFrame,
            screenFrame: screenFrame,
            windows: [outsideWindow],
            placedWindowIds: []
        )

        let placement = result.placements.first
        #expect(placement != nil)
        #expect(placement?.placementType == .floating)
        // Window should be constrained to screen bounds
        #expect(placement!.targetFrame.x <= screenFrame.x + screenFrame.width - 400)
        #expect(placement!.targetFrame.y <= screenFrame.y + screenFrame.height - 300)
    }

    @Test("Zoomed window goes fullscreen")
    func zoomedWindowGoesFullscreen() {
        let node = LayoutNode(
            type: .floatZoomed,
            percentage: 100,
            layout: LayoutNode(type: .stack, percentage: 100),
            zoomed: [PinnedConfig(application: "Safari", bundleId: nil, windowTitles: nil)]
        )
        let screenFrame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.reconcileLayout(
            node: node,
            frame: screenFrame,
            screenFrame: screenFrame,
            windows: windows,
            placedWindowIds: []
        )

        let safariPlacement = result.placements.first { $0.window.application == "Safari" }
        #expect(safariPlacement != nil)
        #expect(safariPlacement?.placementType == .zoomed)
        #expect(safariPlacement?.targetFrame == screenFrame)
    }

    @Test("Float and zoomed with base layout")
    func floatAndZoomedWithBaseLayout() {
        let node = LayoutNode(
            type: .floatZoomed,
            percentage: 100,
            layout: LayoutNode.columns([
                .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 50),
                LayoutNode(type: .stack, percentage: 50)
            ]),
            floats: [PinnedConfig(application: "Finder", bundleId: nil, windowTitles: nil)],
            zoomed: [PinnedConfig(application: "Safari", bundleId: nil, windowTitles: nil)]
        )
        let screenFrame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)
        let windows = TestFixtures.typicalWindows  // 5 windows

        let result = LayoutCalculator.calculateNodePlacements(
            node: node,
            frame: screenFrame,
            windows: windows
        )

        // All 5 windows placed
        #expect(result.count == 5)

        // Finder floating
        let finder = result.first { $0.window.application == "Finder" }
        #expect(finder?.placementType == .floating)

        // Safari zoomed (fullscreen)
        let safari = result.first { $0.window.application == "Safari" }
        #expect(safari?.placementType == .zoomed)
        #expect(safari?.targetFrame == screenFrame)

        // VSCode pinned left
        let vscode = result.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscode?.placementType == .pinned)
        #expect(vscode?.targetFrame.width == 960)

        // Remaining stacked right
        let stacked = result.filter { $0.placementType == WindowPlacement.PlacementType.stacked }
        #expect(stacked.count == 2)  // Terminal and Slack
    }
}

// MARK: - Monitor Handling Tests

@Suite("Monitor Handling Tests")
struct MonitorHandlingTests {

    @Test("Primary key matches main display")
    func primaryKeyMatchesMainDisplay() {
        let layout = Layout(
            name: "Primary Layout",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode(type: .stack, percentage: 100)
                ])
        )
        let displays = TestFixtures.singleDisplay
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )

        // All windows should be placed on main display
        #expect(result.count == 5)
        for placement in result {
            #expect(placement.targetFrame.x >= 0)
            #expect(placement.targetFrame.x < 1920)
        }
    }

    @Test("Non-main displays processed before main")
    func nonMainDisplaysProcessedBeforeMain() {
        // Layout: VSCode pinned on secondary, stack on main
        let layout = Layout(
            name: "Dual Display",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode(type: .stack, percentage: 100),
                    "External Display": .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 100)
                ])
        )
        let displays = TestFixtures.dualDisplays
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )

        // All 5 windows placed
        #expect(result.count == 5)

        // VSCode on secondary display (x >= 1920)
        let vscode = result.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscode?.targetFrame.x == 1920)

        // All others on main display stack
        let mainDisplayPlacements = result.filter { $0.targetFrame.x < 1920 }
        #expect(mainDisplayPlacements.count == 4)
    }

    @Test("Windows on secondary not duplicated on main stack")
    func windowsOnSecondaryNotDuplicatedOnMainStack() {
        // Pinned on secondary, stack on main should NOT include secondary's window
        let layout = Layout(
            name: "Dual Display",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode(type: .stack, percentage: 100),
                    "External Display": .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 100)
                ])
        )
        let displays = TestFixtures.dualDisplays
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )

        // VSCode should appear only once
        let vscodePlacements = result.filter { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscodePlacements.count == 1)
    }

    @Test("No matching screen set falls back to stack on primary")
    func noMatchingScreenSetFallsBackToStackOnPrimary() {
        let layout = Layout(
            name: "Specific Display",
            screens: ScreenConfig(layouts: [
                    "NonExistent Display": .empty()
                ])
        )
        let displays = TestFixtures.singleDisplay
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )

        // Should fall back to single stack on primary screen
        #expect(result.count == 5)  // All windows
        let mainDisplay = displays.first { $0.isMain }!
        for placement in result {
            #expect(placement.targetFrame == mainDisplay.frame)
            #expect(placement.placementType == .stacked)
        }
    }

    @Test("Pinned on secondary stack on secondary")
    func pinnedOnSecondaryStackOnSecondary() {
        // Both layouts on secondary display - no main display in layout
        let layout = Layout(
            name: "Secondary Only",
            screens: ScreenConfig(layouts: [
                    "External Display": LayoutNode.columns([
                        .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 50),
                        LayoutNode(type: .stack, percentage: 50)
                    ])
                ])
        )
        let displays = TestFixtures.dualDisplays
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )

        // VSCode pinned
        let vscode = result.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscode?.targetFrame.x == 1920)  // Secondary display
        #expect(vscode?.placementType == .pinned)

        // Note: Without main display in layout, remaining windows won't be stacked
        // (stack only collects windows on main display in phase 2)
    }

    @Test("Multiple displays with explicit names")
    func multipleDisplaysWithExplicitNames() {
        let layout = Layout(
            name: "Named Displays",
            screens: ScreenConfig(layouts: [
                    "Main Display": .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 100),
                    "External Display": .pinned(app: "Terminal", percentage: 100)
                ])
        )
        let displays = TestFixtures.dualDisplays
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )

        // Note: This layout has no stack, so remaining windows go fullscreen on main
        #expect(result.count >= 2)

        let vscode = result.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscode?.targetFrame.x == 0)  // Main display

        let terminal = result.first { $0.window.application == "Terminal" }
        #expect(terminal?.targetFrame.x == 1920)  // External display
    }
}

// MARK: - Nested Layout Tests

@Suite("Nested Layout Tests")
struct NestedLayoutTests {

    @Test("Deeply nested columns and rows")
    func deeplyNestedColumnsAndRows() {
        let node = LayoutNode.columns([
            .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 60),
            .rows([
                .pinned(app: "Terminal", percentage: 50),
                .pinned(app: "Safari", percentage: 50)
            ])
        ])
        let frame = WindowFrame(x: 0, y: 0, width: 1000, height: 800)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculateNodePlacements(
            node: node,
            frame: frame,
            windows: windows
        )

        #expect(result.count == 3)

        let vscode = result.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscode?.targetFrame.x == 0)
        #expect(vscode?.targetFrame.width == 600)

        let terminal = result.first { $0.window.application == "Terminal" }
        #expect(terminal?.targetFrame.x == 600)
        #expect(terminal?.targetFrame.y == 0)
        #expect(terminal?.targetFrame.height == 400)

        let safari = result.first { $0.window.application == "Safari" }
        #expect(safari?.targetFrame.x == 600)
        #expect(safari?.targetFrame.y == 400)
        #expect(safari?.targetFrame.height == 400)
    }

    @Test("Stack at leaf of nested layout")
    func stackAtLeafOfNestedLayout() {
        let node = LayoutNode.columns([
            .rows([
                .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 70),
                LayoutNode(type: .stack, percentage: 30)  // Stack nested in rows in columns
            ]),
            .pinned(app: "Terminal", percentage: 50)
        ])
        let frame = WindowFrame(x: 0, y: 0, width: 1000, height: 1000)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculateNodePlacements(
            node: node,
            frame: frame,
            windows: windows
        )

        // All 5 windows placed
        #expect(result.count == 5)

        // VSCode and Terminal pinned
        let pinnedCount = result.filter { $0.placementType == .pinned }.count
        #expect(pinnedCount == 2)

        // Remaining 3 stacked
        let stackedCount = result.filter { $0.placementType == .stacked }.count
        #expect(stackedCount == 3)
    }
}

// MARK: - Edge Cases

@Suite("Edge Case Tests")
struct EdgeCaseTests {

    @Test("Empty windows array")
    func emptyWindowsArray() {
        let node = LayoutNode(type: .stack, percentage: 100)
        let frame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)

        let result = LayoutCalculator.calculateNodePlacements(
            node: node,
            frame: frame,
            windows: []
        )

        #expect(result.isEmpty)
    }

    @Test("Empty displays array")
    func emptyDisplaysArray() {
        let layout = TestFixtures.halfSplitLayout
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: [],
            windows: windows
        )

        #expect(result.isEmpty)
    }

    @Test("Layout with no screen sets falls back to stack")
    func layoutWithNoScreenSetsFallsBackToStack() {
        let layout = Layout(name: "Empty")
        let displays = TestFixtures.singleDisplay
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )

        // Should fall back to single stack on primary screen
        #expect(result.count == 5)  // All windows
        let mainDisplay = displays.first { $0.isMain }!
        for placement in result {
            #expect(placement.targetFrame == mainDisplay.frame)
            #expect(placement.placementType == .stacked)
        }
    }

    @Test("All windows pinned leaves stack empty")
    func allWindowsPinnedLeavesStackEmpty() {
        // Pin all 5 windows explicitly
        let node = LayoutNode.columns([
            .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 20),
            .pinned(app: "Terminal", percentage: 20),
            .pinned(app: "Safari", percentage: 20),
            .pinned(app: "Finder", percentage: 20),
            .rows([
                .pinned(app: "Slack", percentage: 50),
                LayoutNode(type: .stack, percentage: 50)  // Stack should be empty
            ])
        ])
        let frame = WindowFrame(x: 0, y: 0, width: 1000, height: 1000)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculateNodePlacements(
            node: node,
            frame: frame,
            windows: windows
        )

        // All 5 windows pinned
        #expect(result.count == 5)
        let pinnedCount = result.filter { $0.placementType == .pinned }.count
        #expect(pinnedCount == 5)
    }

    @Test("Same window cannot be placed twice")
    func sameWindowCannotBePlacedTwice() {
        // Try to pin VSCode twice
        let node = LayoutNode.columns([
            .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 50),
            .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 50)  // Should not match
        ])
        let frame = WindowFrame(x: 0, y: 0, width: 1000, height: 800)
        let windows = TestFixtures.typicalWindows

        let result = LayoutCalculator.calculateNodePlacements(
            node: node,
            frame: frame,
            windows: windows
        )

        // VSCode placed only once
        let vscodePlacements = result.filter { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscodePlacements.count == 1)
    }
}
