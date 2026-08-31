import Testing
import CoreGraphics
@testable import WindowThingCore

@Suite("Layout Modification Tests")
struct LayoutModificationTests {

    // MARK: - Tree Navigation

    @Test("Navigate to root")
    func navigateToRoot() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])

        let result = node.nodeAt(path: [])
        #expect(result == node)
    }

    @Test("Navigate to column child")
    func navigateToColumnChild() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .pinned(app: "Terminal", percentage: 50)
        ])

        let result = node.nodeAt(path: [1])
        #expect(result?.type == .pinned)
    }

    @Test("Navigate to nested node")
    func navigateToNestedNode() {
        let node = LayoutNode.columns([
            .rows([
                .empty(percentage: 50),
                .pinned(app: "Terminal", percentage: 50)
            ]),
            .empty(percentage: 50)
        ])

        let result = node.nodeAt(path: [0, 1])
        #expect(result?.type == .pinned)
    }

    @Test("Navigate to invalid path returns nil")
    func navigateToInvalidPath() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])

        let result = node.nodeAt(path: [5])
        #expect(result == nil)
    }

    // MARK: - Finding Stack Location

    @Test("Find stack at root")
    func findStackAtRoot() {
        let node = LayoutNode(type: .stack, percentage: 100)

        let result = node.findStackLocation()
        #expect(result == [])
    }

    @Test("Find stack in columns")
    func findStackInColumns() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            LayoutNode(type: .stack, percentage: 50)
        ])

        let result = node.findStackLocation()
        #expect(result == [1])
    }

    @Test("Find stack in nested layout")
    func findStackInNestedLayout() {
        let node = LayoutNode.columns([
            .rows([
                .empty(percentage: 50),
                LayoutNode(type: .stack, percentage: 50)
            ]),
            .empty(percentage: 50)
        ])

        let result = node.findStackLocation()
        #expect(result == [0, 1])
    }

    @Test("Find stack returns nil when no stack")
    func findStackReturnsNilWhenNoStack() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])

        let result = node.findStackLocation()
        #expect(result == nil)
    }

    // MARK: - Ensuring Stack

    @Test("Ensuring stack when stack exists")
    func ensuringStackWhenStackExists() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            LayoutNode(type: .stack, percentage: 50)
        ])

        let result = node.ensuringStack()
        #expect(result == node)
    }

    @Test("Ensuring stack when no stack adds one")
    func ensuringStackWhenNoStackAddsOne() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])

        let result = node.ensuringStack()
        #expect(result.type == .columns)
        #expect(result.columns?.count == 2)
        #expect(result.findStackLocation() != nil)
    }

    // MARK: - Node Replacement

    @Test("Replace node at root")
    func replaceNodeAtRoot() {
        let original = LayoutNode.empty()
        let replacement = LayoutNode.pinned(app: "Terminal")

        let result = original.replacingNode(at: [], with: replacement)
        #expect(result == replacement)
    }

    @Test("Replace node in columns")
    func replaceNodeInColumns() {
        let original = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        let replacement = LayoutNode.pinned(app: "Terminal", percentage: 50)

        let result = original.replacingNode(at: [1], with: replacement)
        #expect(result?.nodeAt(path: [1])?.type == .pinned)
    }

    @Test("Replace node in nested layout")
    func replaceNodeInNestedLayout() {
        let original = LayoutNode.columns([
            .rows([
                .empty(percentage: 50),
                .empty(percentage: 50)
            ]),
            .empty(percentage: 50)
        ])
        let replacement = LayoutNode.pinned(app: "Terminal", percentage: 50)

        let result = original.replacingNode(at: [0, 1], with: replacement)
        #expect(result?.nodeAt(path: [0, 1])?.type == .pinned)
    }

    // MARK: - Column/Row Insertion

    @Test("Insert column at beginning")
    func insertColumnAtBeginning() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        let newColumn = LayoutNode.pinned(app: "Terminal", percentage: 33)

        let result = node.insertingColumn(newColumn, at: 0)
        #expect(result?.columns?.count == 3)
        #expect(result?.nodeAt(path: [0])?.type == .pinned)
    }

    @Test("Insert column at end")
    func insertColumnAtEnd() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        let newColumn = LayoutNode.pinned(app: "Terminal", percentage: 33)

        let result = node.insertingColumn(newColumn, at: 2)
        #expect(result?.columns?.count == 3)
        #expect(result?.nodeAt(path: [2])?.type == .pinned)
    }

    @Test("Insert row at middle")
    func insertRowAtMiddle() {
        let node = LayoutNode.rows([
            .empty(percentage: 33),
            .empty(percentage: 33),
            .empty(percentage: 34)
        ])
        let newRow = LayoutNode.pinned(app: "Terminal", percentage: 25)

        let result = node.insertingRow(newRow, at: 1)
        #expect(result?.rows?.count == 4)
        #expect(result?.nodeAt(path: [1])?.type == .pinned)
    }

    @Test("Insert column on non-columns node returns nil")
    func insertColumnOnNonColumnsNodeReturnsNil() {
        let node = LayoutNode.rows([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        let newColumn = LayoutNode.pinned(app: "Terminal", percentage: 33)

        let result = node.insertingColumn(newColumn, at: 0)
        #expect(result == nil)
    }

    // MARK: - Column/Row Removal

    @Test("Remove column from middle")
    func removeColumnFromMiddle() {
        let node = LayoutNode.columns([
            .empty(percentage: 33),
            .pinned(app: "Terminal", percentage: 33),
            .empty(percentage: 34)
        ])

        let result = node.removingColumn(at: 1)
        #expect(result?.columns?.count == 2)
        #expect(result?.nodeAt(path: [1])?.type == .empty)
    }

    @Test("Remove row from end")
    func removeRowFromEnd() {
        let node = LayoutNode.rows([
            .empty(percentage: 50),
            .pinned(app: "Terminal", percentage: 50)
        ])

        let result = node.removingRow(at: 1)
        #expect(result?.rows?.count == 1)
    }

    @Test("Cannot remove last column")
    func cannotRemoveLastColumn() {
        let node = LayoutNode.columns([
            .empty(percentage: 100)
        ])

        let result = node.removingColumn(at: 0)
        #expect(result == nil)
    }

    @Test("Cannot remove last row")
    func cannotRemoveLastRow() {
        let node = LayoutNode.rows([
            .empty(percentage: 100)
        ])

        let result = node.removingRow(at: 0)
        #expect(result == nil)
    }

    @Test("Remove column containing stack preserves stack")
    func removeColumnContainingStackPreservesStack() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            LayoutNode(type: .stack, percentage: 50)
        ])

        let result = node.removingColumn(at: 1)
        #expect(result != nil)
        // After removing the stack column, should have stack somewhere
        #expect(result?.findStackLocation() != nil)
    }

    @Test("Remove row containing stack preserves stack")
    func removeRowContainingStackPreservesStack() {
        let node = LayoutNode.rows([
            LayoutNode(type: .stack, percentage: 50),
            .empty(percentage: 50)
        ])

        let result = node.removingRow(at: 0)
        #expect(result != nil)
        // After removing the stack row, should have stack somewhere
        #expect(result?.findStackLocation() != nil)
    }

    @Test("Remove column without stack maintains no stack")
    func removeColumnWithoutStackMaintainsNoStack() {
        let node = LayoutNode.columns([
            .empty(percentage: 33),
            .pinned(app: "Terminal", percentage: 33),
            .empty(percentage: 34)
        ])

        let result = node.removingColumn(at: 1)
        #expect(result != nil)
        // No stack before, no stack after
        #expect(result?.findStackLocation() == nil)
    }

    @Test("Remove column with stack converts empty to stack")
    func removeColumnWithStackConvertsEmptyToStack() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            LayoutNode(type: .stack, percentage: 50)
        ])

        let result = node.removingColumn(at: 1)
        #expect(result != nil)
        // The remaining empty should have been converted to stack
        #expect(result?.type == .columns)
        #expect(result?.columns?.count == 1)
        #expect(result?.columns?.first?.type == .stack)
    }

    @Test("Remove all but one column with all pinned ensures stack")
    func removeAllButOneColumnWithAllPinnedEnsuresStack() {
        let node = LayoutNode.columns([
            .pinned(app: "VSCode", percentage: 50),
            LayoutNode(type: .stack, percentage: 50)
        ])

        let result = node.removingColumn(at: 1)
        #expect(result != nil)
        // Should have wrapped or ensured stack exists
        #expect(result?.findStackLocation() != nil)
    }

    @Test("Layout without stack remains valid after modifications")
    func layoutWithoutStackRemainsValid() {
        // Create a layout with no stack - just pinned and empty cells
        let layout = Layout(
            name: "No Stack Layout",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode.columns([
                        .pinned(app: "VSCode", percentage: 50),
                        .empty(percentage: 50)
                    ])
                ])
        )

        // Remove a column
        let result = layout.removingColumn(
            monitor: ScreenConfig.primaryKey,
            at: [],
            index: 1
        )

        #expect(result.changed == true)
        let primaryLayout = result.layout.screens.layouts[ScreenConfig.primaryKey]

        // Should still have a valid layout, even without a stack
        #expect(primaryLayout != nil)
        // The layout should work - no crashes, valid structure
        #expect(primaryLayout?.type == .columns || primaryLayout?.type == .pinned)
    }

    @Test("Empty screen defaults to fullscreen placement")
    func emptyScreenDefaultsToFullscreenPlacement() {
        // A screen with just an empty node should work fine
        let layout = Layout(
            name: "Empty Screen",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(percentage: 100)
                ])
        )

        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let placements = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: mockWindowManager.displays,
            windows: mockWindowManager.windows
        )

        // Empty screen with no explicit stack - remaining windows placed fullscreen as fallback
        #expect(placements.count == 5)
        // All windows should be placed fullscreen on main display
        let mainDisplay = mockWindowManager.displays.first { $0.isMain }!
        for placement in placements {
            #expect(placement.targetFrame == mainDisplay.frame)
            #expect(placement.placementType == .stacked)
        }
    }

    // MARK: - Application Removal

    @Test("Remove pinned application converts to empty")
    func removePinnedApplicationConvertsToEmpty() {
        let node = LayoutNode.pinned(app: "Terminal", percentage: 100)

        let (result, removed) = node.removingApplication(
            applicationName: "Terminal",
            windowTitle: nil
        )

        #expect(removed == true)
        #expect(result.type == .empty)
    }

    @Test("Remove application from columns")
    func removeApplicationFromColumns() {
        let node = LayoutNode.columns([
            .pinned(app: "VSCode", bundleId: nil, percentage: 60),
            .pinned(app: "Terminal", percentage: 40)
        ])

        let (result, removed) = node.removingApplication(
            applicationName: "Terminal",
            windowTitle: nil
        )

        #expect(removed == true)
        #expect(result.nodeAt(path: [1])?.type == .empty)
    }

    @Test("Remove application not present returns unchanged")
    func removeApplicationNotPresentReturnsUnchanged() {
        let node = LayoutNode.columns([
            .pinned(app: "VSCode", bundleId: nil, percentage: 60),
            .empty(percentage: 40)
        ])

        let (result, removed) = node.removingApplication(
            applicationName: "Terminal",
            windowTitle: nil
        )

        #expect(removed == false)
        #expect(result == node)
    }

    // MARK: - Application Addition

    @Test("Add application to empty node converts to pinned")
    func addApplicationToEmptyNodeConvertsToPinned() {
        let node = LayoutNode.empty(percentage: 100)

        let result = node.addingApplication(
            at: [],
            applicationName: "Terminal",
            windowTitle: nil
        )

        #expect(result?.type == .pinned)
        #expect(result?.pinned?.application == "Terminal")
    }

    @Test("Add application to column child")
    func addApplicationToColumnChild() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])

        let result = node.addingApplication(
            at: [1],
            applicationName: "Terminal",
            windowTitle: nil
        )

        #expect(result?.nodeAt(path: [1])?.type == .pinned)
    }

    @Test("Add application to nested location")
    func addApplicationToNestedLocation() {
        let node = LayoutNode.columns([
            .rows([
                .empty(percentage: 50),
                .empty(percentage: 50)
            ]),
            .empty(percentage: 50)
        ])

        let result = node.addingApplication(
            at: [0, 1],
            applicationName: "Terminal",
            windowTitle: nil
        )

        #expect(result?.nodeAt(path: [0, 1])?.type == .pinned)
    }

    // MARK: - Layout-Level Modifications

    @Test("Move application from stack to pinned")
    func moveApplicationFromStackToPinned() {
        let layout = Layout(
            name: "Test Layout",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode.columns([
                        LayoutNode(type: .stack, percentage: 50),
                        .empty(percentage: 50)
                    ])
                ])
        )

        let result = layout.movingApplication(
            monitor: ScreenConfig.primaryKey,
            applicationName: "Terminal",
            windowTitle: nil,
            to: [1]
        )

        #expect(result.changed == true)
        let primaryLayout = result.layout.screens.layouts[ScreenConfig.primaryKey]
        #expect(primaryLayout?.nodeAt(path: [1])?.type == .pinned)
    }

    @Test("Move application from pinned to stack")
    func moveApplicationFromPinnedToStack() {
        let layout = Layout(
            name: "Test Layout",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode.columns([
                        LayoutNode(type: .stack, percentage: 50),
                        .pinned(app: "Terminal", percentage: 50)
                    ])
                ])
        )

        let result = layout.movingApplication(
            monitor: ScreenConfig.primaryKey,
            applicationName: "Terminal",
            windowTitle: nil,
            to: [0]  // Stack location
        )

        #expect(result.changed == true)
        let primaryLayout = result.layout.screens.layouts[ScreenConfig.primaryKey]
        #expect(primaryLayout?.nodeAt(path: [1])?.type == .empty)
    }

    @Test("Remove pinned window sets to empty")
    func removePinnedWindowSetsToEmpty() {
        let layout = Layout(
            name: "Test Layout",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode.columns([
                        .pinned(app: "VSCode", bundleId: nil, percentage: 50),
                        .pinned(app: "Terminal", percentage: 50)
                    ])
                ])
        )

        let result = layout.removingPinnedAt(
            monitor: ScreenConfig.primaryKey,
            location: [1]
        )

        #expect(result.changed == true)
        let primaryLayout = result.layout.screens.layouts[ScreenConfig.primaryKey]
        #expect(primaryLayout?.nodeAt(path: [1])?.type == .empty)
    }

    @Test("Insert column in layout")
    func insertColumnInLayout() {
        let layout = Layout(
            name: "Test Layout",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode.columns([
                        .empty(percentage: 50),
                        .empty(percentage: 50)
                    ])
                ])
        )

        let result = layout.insertingColumn(
            monitor: ScreenConfig.primaryKey,
            at: [],
            index: 1,
            node: .pinned(app: "Terminal", percentage: 33)
        )

        #expect(result.changed == true)
        let primaryLayout = result.layout.screens.layouts[ScreenConfig.primaryKey]
        #expect(primaryLayout?.columns?.count == 3)
        #expect(primaryLayout?.nodeAt(path: [1])?.type == .pinned)
    }

    @Test("Remove column from layout")
    func removeColumnFromLayout() {
        let layout = Layout(
            name: "Test Layout",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode.columns([
                        .empty(percentage: 33),
                        .pinned(app: "Terminal", percentage: 33),
                        .empty(percentage: 34)
                    ])
                ])
        )

        let result = layout.removingColumn(
            monitor: ScreenConfig.primaryKey,
            at: [],
            index: 1
        )

        #expect(result.changed == true)
        let primaryLayout = result.layout.screens.layouts[ScreenConfig.primaryKey]
        #expect(primaryLayout?.columns?.count == 2)
    }
}

// MARK: - Layout Manager Integration Tests

@Suite("Layout Manager Dynamic Modification Tests")
struct LayoutManagerDynamicModificationTests {

    @Test("Move application updates current layout")
    func moveApplicationUpdatesCurrentLayout() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        let initialLayout = Layout(
            name: "Test Layout",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode.columns([
                        LayoutNode(type: .stack, percentage: 50),
                        .empty(percentage: 50)
                    ])
                ])
        )

        layoutManager.loadLayouts(from: AppConfig(
            activationHotKey: .default,
            layouts: [initialLayout],
            defaultLayoutName: "Test Layout",
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        ))

        let success = layoutManager.moveTo(
            monitor: ScreenConfig.primaryKey,
            applicationName: "Terminal",
            windowTitle: nil,
            to: [1]
        )

        #expect(success == true)
        let primaryLayout = layoutManager.currentLayout?.screens.layouts[ScreenConfig.primaryKey]
        #expect(primaryLayout?.nodeAt(path: [1])?.type == .pinned)
    }

    @Test("Remove from calls applyLayout")
    func removeFromCallsApplyLayout() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        let initialLayout = Layout(
            name: "Test Layout",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode.columns([
                        .pinned(app: "VSCode", bundleId: nil, percentage: 50),
                        .pinned(app: "Terminal", percentage: 50)
                    ])
                ])
        )

        layoutManager.loadLayouts(from: AppConfig(
            activationHotKey: .default,
            layouts: [initialLayout],
            defaultLayoutName: "Test Layout",
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        ))

        mockWindowManager.setWindowFrameCalls.removeAll()

        let success = layoutManager.removeFrom(
            monitor: ScreenConfig.primaryKey,
            location: [1]
        )
        layoutManager.waitForPendingApply()

        #expect(success == true)
        // Should have called setWindowFrame for all windows after modification
        #expect(mockWindowManager.setWindowFrameCalls.count > 0)
    }

    @Test("Insert column adds new column and applies layout")
    func insertColumnAddsNewColumnAndAppliesLayout() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        let initialLayout = Layout(
            name: "Test Layout",
            screens: ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: LayoutNode.columns([
                        .empty(percentage: 50),
                        .empty(percentage: 50)
                    ])
                ])
        )

        layoutManager.loadLayouts(from: AppConfig(
            activationHotKey: .default,
            layouts: [initialLayout],
            defaultLayoutName: "Test Layout",
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        ))

        let success = layoutManager.insertColumn(
            monitor: ScreenConfig.primaryKey,
            at: [],
            index: 1,
            node: .pinned(app: "Terminal", percentage: 33)
        )

        #expect(success == true)
        let primaryLayout = layoutManager.currentLayout?.screens.layouts[ScreenConfig.primaryKey]
        #expect(primaryLayout?.columns?.count == 3)
    }
}
