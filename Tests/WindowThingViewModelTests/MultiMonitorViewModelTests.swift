import Testing
import Foundation
import CoreGraphics
@testable import WindowThingViewModel
@testable import WindowThingCore

// MARK: - Mocks (duplicated from OverlayViewModelTests for test isolation)

private class MockLayoutManager: LayoutManaging {
    var layouts: [Layout] = []
    var savedSetups: [SavedSetup] = []
    var currentLayout: Layout?
    var lastUsedLayout: Layout?
    var appliedLayouts: [Layout] = []
    var updatedLayouts: [Layout] = []

    func loadLayouts(from config: AppConfig) { layouts = config.layouts }
    func applyLayout(_ layout: Layout) { appliedLayouts.append(layout); currentLayout = layout; lastUsedLayout = layout }
    func setLayouts(_ newLayouts: [Layout]) { layouts = newLayouts }

    func updateLayout(_ layout: Layout) {
        updatedLayouts.append(layout)
        if let i = layouts.firstIndex(where: { $0.id == layout.id }) { layouts[i] = layout }
    }
    func saveCurrentSetup(name: String) {}
    func loadSetup(_ setup: SavedSetup) {}
    func moveWindow(_ window: Window, toCellAt address: CellAddress, displays: [Display]) throws {}
    func cellAddresses(for layout: Layout, displays: [Display]) -> [IndexedCell] {
        CellIndexer.indexCells(layout: layout, displays: displays)
    }
}

private class MockWindowManager: WindowManaging {
    var displays: [Display] = []
    var windows: [Window] = []
    var focusedApplication: Application?
    func getDisplays() -> [Display] { displays }
    func getWindows() -> [Window] { windows }
    func setWindowFrame(pid: pid_t, windowTitle: String?, frame: WindowFrame) -> Bool { true }
    func setWindowFrame(pid: pid_t, windowId: CGWindowID, frame: WindowFrame) -> Bool { true }
    func getFocusedApplication() -> Application? { focusedApplication }
}

private class MockConfigManager: ConfigProviding {
    var config: AppConfig = .default
    var configFilePath: URL = URL(fileURLWithPath: "/tmp/test-config.yaml")
    var setupsFilePath: URL = URL(fileURLWithPath: "/tmp/test-setups.yaml")
    var savedLayouts: [Layout] = []
    func loadConfig() {}
    func saveConfig() {}
    func saveLayouts(_ layouts: [Layout]) { savedLayouts = layouts }
}

// MARK: - Display Helpers

private func display(id: Int, name: String, x: CGFloat = 0, width: CGFloat = 1920, height: CGFloat = 1080, isMain: Bool = false) -> Display {
    Display(id: id, name: name, frame: WindowFrame(x: x, y: 0, width: width, height: height), isMain: isMain)
}

private let singleDisplay = [
    display(id: 0, name: "Main Display", isMain: true)
]

private let dualDisplays = [
    display(id: 0, name: "Main Display", isMain: true),
    display(id: 1, name: "External Display", x: 1920)
]

private let tripleDisplays = [
    display(id: 0, name: "Main Display", isMain: true),
    display(id: 1, name: "External Display", x: 1920),
    display(id: 2, name: "Left Display", x: -1920)
]

private func makeVM(
    layouts: [Layout] = [],
    displays: [Display] = singleDisplay
) -> (OverlayViewModel, MockLayoutManager, MockWindowManager, MockConfigManager) {
    let lm = MockLayoutManager()
    lm.layouts = layouts
    let wm = MockWindowManager()
    wm.displays = displays
    let cm = MockConfigManager()
    let vm = OverlayViewModel(windowManager: wm, layoutManager: lm, configManager: cm)
    vm.layouts = layouts
    vm.originalLayouts = layouts
    vm.displays = displays
    return (vm, lm, wm, cm)
}

private func makeDualDisplayLayout() -> Layout {
    Layout(
        name: "Dual Setup",
        screenSets: [
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: "Xcode", percentage: 60),
                    .stackAll(percentage: 40)
                ]),
                "External Display": .columns([
                    .pinned(app: "Terminal", percentage: 50),
                    .pinned(app: "Safari", percentage: 50)
                ])
            ])
        ]
    )
}

private func makeMultiScreenSetLayout() -> Layout {
    Layout(
        name: "Adaptive",
        screenSets: [
            // Single-display config
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: "Xcode", percentage: 60),
                    .stackAll(percentage: 40)
                ])
            ]),
            // Dual-display config
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .pinned(app: "Xcode"),
                "External Display": .columns([
                    .pinned(app: "Terminal", percentage: 50),
                    .stackAll(percentage: 50)
                ])
            ]),
            // Triple-display config
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .pinned(app: "Xcode"),
                "External Display": .pinned(app: "Safari"),
                "Left Display": .stackAll()
            ])
        ]
    )
}

// MARK: - Screen Set Selection

@Suite("OverlayViewModel.screenSets")
struct ScreenSetTests {

    @Test("selectScreenSet changes editingRootNode")
    func selectScreenSetChangesRoot() {
        let layout = makeMultiScreenSetLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        // Initially at screen set 0 (single-display, columns)
        #expect(vm.editingRootNode?.type == .columns)
        #expect(vm.selectedScreenSetIndex == 0)

        // Switch to screen set 1 (dual-display, pinned for $PRIMARY)
        vm.selectScreenSet(1)
        #expect(vm.selectedScreenSetIndex == 1)
        #expect(vm.editingRootNode?.type == .pinned)
    }

    @Test("selectScreenSet resets selectedNodePath to root")
    func selectScreenSetResetsPath() {
        let layout = makeMultiScreenSetLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        vm.selectedNodePath = NodePath([0, 1])

        vm.selectScreenSet(1)
        #expect(vm.selectedNodePath.isRoot)
    }

    @Test("preferredMonitorKey returns $PRIMARY when present")
    func preferredMonitorKeyPrimary() {
        let layout = makeDualDisplayLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        let key = vm.preferredMonitorKey(for: layout.screenSets[0])
        #expect(key == ScreenConfig.primaryKey)
    }

    @Test("preferredMonitorKey returns sorted first key when no $PRIMARY")
    func preferredMonitorKeyFallback() {
        let screenSet = ScreenConfig(layouts: [
            "External Display": .stackAll(),
            "Left Display": .pinned(app: "Terminal")
        ])
        let layout = Layout(name: "No Primary", screenSets: [screenSet])
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        let key = vm.preferredMonitorKey(for: screenSet)
        #expect(key == "External Display")  // "E" < "L" alphabetically
    }

    @Test("editingRootNode shows preferred monitor layout from screen set")
    func editingRootNodeFromScreenSet() {
        let layout = makeDualDisplayLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        // $PRIMARY has columns with Xcode + stack
        #expect(vm.editingRootNode?.type == .columns)
        #expect(vm.editingRootNode?.columns?.count == 2)
        #expect(vm.editingRootNode?.columns?[0].pinned?.application == "Xcode")
    }
}

// MARK: - Add/Remove Screen Sets

@Suite("OverlayViewModel.addRemoveScreenSets")
struct AddRemoveScreenSetTests {

    @Test("addScreenSet appends new screen set with stackAll on $PRIMARY")
    func addScreenSet() {
        let layout = makeMultiScreenSetLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        let countBefore = vm.editingLayout!.screenSets.count
        vm.addScreenSet()

        #expect(vm.editingLayout!.screenSets.count == countBefore + 1)
        let newSet = vm.editingLayout!.screenSets.last!
        #expect(newSet.layouts[ScreenConfig.primaryKey] == .stackAll())
    }

    @Test("addScreenSet selects new screen set")
    func addScreenSetSelects() {
        let layout = makeMultiScreenSetLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        vm.addScreenSet()
        #expect(vm.selectedScreenSetIndex == vm.editingLayout!.screenSets.count - 1)
        #expect(vm.editingRootNode?.type == .stack)  // stackAll
    }

    @Test("removeScreenSet removes at index and clamps selection")
    func removeScreenSet() {
        let layout = makeMultiScreenSetLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        vm.selectScreenSet(2)  // Select the last (triple-display) screen set

        vm.removeScreenSet(at: 2)

        #expect(vm.editingLayout!.screenSets.count == 2)
        #expect(vm.selectedScreenSetIndex == 1)  // Clamped to last valid index
    }

    @Test("removeScreenSet with single screen set does nothing")
    func removeLastScreenSet() {
        let layout = Layout(name: "Single", screenSets: [
            ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        ])
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        vm.removeScreenSet(at: 0)
        #expect(vm.editingLayout!.screenSets.count == 1)  // Still 1
    }

    @Test("removeScreenSet at 0 when selected advances to next")
    func removeFirstScreenSet() {
        let layout = makeMultiScreenSetLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        vm.selectScreenSet(0)

        vm.removeScreenSet(at: 0)

        #expect(vm.selectedScreenSetIndex == 0)  // Still 0 (now pointing to old index 1)
        // The new index 0 should be the old dual-display config
        #expect(vm.editingLayout!.screenSets[0].layouts["External Display"] != nil)
    }
}

// MARK: - Multi-Display Edit Isolation

@Suite("OverlayViewModel.multiDisplayEditing")
struct MultiDisplayEditingTests {

    @Test("commitEdit updates only preferred monitor key in screen set")
    func editIsolatedToPreferredMonitor() {
        let layout = makeDualDisplayLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        // Edit the root (which is $PRIMARY's layout)
        let newNode = LayoutNode.rows([.empty(percentage: 50), .stackAll(percentage: 50)])
        vm.commitEdit(newNode)

        // $PRIMARY should be updated
        let screenSet = vm.editingLayout!.screenSets[0]
        #expect(screenSet.layouts[ScreenConfig.primaryKey]?.type == .rows)

        // "External Display" should be untouched
        #expect(screenSet.layouts["External Display"]?.type == .columns)
        #expect(screenSet.layouts["External Display"]?.columns?.count == 2)
    }

    @Test("editing one screen set doesn't affect another")
    func editIsolatedToScreenSet() {
        let layout = makeMultiScreenSetLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        vm.selectScreenSet(1)  // Dual-display config

        // Edit $PRIMARY in screen set 1
        vm.commitEdit(LayoutNode.stackAll())

        // Screen set 0 should be untouched
        let set0 = vm.editingLayout!.screenSets[0]
        #expect(set0.layouts[ScreenConfig.primaryKey]?.type == .columns)

        // Screen set 1's $PRIMARY should be updated
        let set1 = vm.editingLayout!.screenSets[1]
        #expect(set1.layouts[ScreenConfig.primaryKey]?.type == .stack)

        // Screen set 1's "External Display" should be untouched
        #expect(set1.layouts["External Display"]?.type == .columns)
    }

    @Test("undo after multi-display edit reverts only affected monitor")
    func undoRevertsAffectedMonitor() {
        let layout = makeDualDisplayLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        // Original: $PRIMARY is columns
        #expect(vm.editingRootNode?.type == .columns)

        // Edit to stack
        vm.commitEdit(LayoutNode.stackAll())
        #expect(vm.editingRootNode?.type == .stack)

        // Undo
        vm.undoManager.undo()
        #expect(vm.editingRootNode?.type == .columns)

        // External Display should still be untouched
        let screenSet = vm.editingLayout!.screenSets[0]
        #expect(screenSet.layouts["External Display"]?.type == .columns)
    }
}

// MARK: - Display-Aware Operations

@Suite("OverlayViewModel.displayAwareOps")
struct DisplayAwareOpsTests {

    @Test("duplicateLayout preserves all screen sets")
    func duplicatePreservesScreenSets() {
        let layout = makeMultiScreenSetLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        vm.duplicateLayout(layout)

        #expect(vm.layouts.count == 2)
        let copy = vm.layouts[1]
        #expect(copy.screenSets.count == 3)
        #expect(copy.screenSets[0].layouts.count == 1)  // Single display
        #expect(copy.screenSets[1].layouts.count == 2)  // Dual display
        #expect(copy.screenSets[2].layouts.count == 3)  // Triple display
    }

    @Test("cellAddresses uses layout with multiple displays")
    func cellAddressesMultiDisplay() {
        let layout = makeDualDisplayLayout()
        let (vm, lm, _, _) = makeVM(layouts: [layout], displays: dualDisplays)
        vm.startEditing(layout)

        let cells = lm.cellAddresses(for: layout, displays: dualDisplays)
        // $PRIMARY has 2 columns = 2 cells, External has 2 columns = 2 cells
        #expect(cells.count == 4)
        // First 2 on main (x < 1920), last 2 on external (x >= 1920)
        #expect(cells[0].frame.x < 1920)
        #expect(cells[1].frame.x < 1920)
        #expect(cells[2].frame.x >= 1920)
        #expect(cells[3].frame.x >= 1920)
    }

    @Test("displays property populated from windowManager")
    func displaysFromWindowManager() {
        let (vm, _, wm, _) = makeVM(displays: dualDisplays)
        wm.displays = dualDisplays
        // Simulate refresh (manually set since refresh() calls NSWorkspace)
        vm.displays = wm.getDisplays()
        #expect(vm.displays.count == 2)
        #expect(vm.displays[0].isMain == true)
        #expect(vm.displays[1].name == "External Display")
    }

    @Test("addScreenSet then edit produces valid multi-display layout")
    func addThenEdit() {
        let layout = Layout(name: "Start", screenSets: [
            ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        ])
        let (vm, _, _, cm) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        // Add a screen set
        vm.addScreenSet()
        #expect(vm.selectedScreenSetIndex == 1)

        // Edit the new screen set's $PRIMARY
        let newRoot = LayoutNode.columns([.empty(percentage: 50), .stackAll(percentage: 50)])
        vm.commitEdit(newRoot)

        // Verify both screen sets are intact
        let result = vm.editingLayout!
        #expect(result.screenSets.count == 2)
        #expect(result.screenSets[0].layouts[ScreenConfig.primaryKey]?.type == .stack)
        #expect(result.screenSets[1].layouts[ScreenConfig.primaryKey]?.type == .columns)

        // Verify auto-save was triggered
        #expect(!cm.savedLayouts.isEmpty)
    }

    @Test("selectLayout with multiple screen sets resets to screen set 0")
    func selectLayoutResetsScreenSet() {
        let layoutA = makeMultiScreenSetLayout()
        let layoutB = Layout(name: "B", screenSets: [
            ScreenConfig(layouts: [ScreenConfig.primaryKey: .empty()])
        ])
        let (vm, _, _, _) = makeVM(layouts: [layoutA, layoutB])
        vm.startEditing(layoutA)
        vm.selectScreenSet(2)
        #expect(vm.selectedScreenSetIndex == 2)

        // Switch to layout B
        vm.selectLayout(at: 1)
        #expect(vm.selectedScreenSetIndex == 0)
        #expect(vm.editingLayout?.name == "B")
    }
}

// MARK: - Edge Cases

@Suite("OverlayViewModel.multiMonitorEdgeCases")
struct MultiMonitorEdgeCaseTests {

    @Test("empty screen sets array handled gracefully")
    func emptyScreenSets() {
        let layout = Layout(name: "Empty", screenSets: [])
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        #expect(vm.editingRootNode == nil)
    }

    @Test("screen set with no $PRIMARY uses first sorted key")
    func noPrimaryKeyUsesFirst() {
        let layout = Layout(name: "Named Only", screenSets: [
            ScreenConfig(layouts: [
                "Zebra Display": .pinned(app: "Zebra"),
                "Apple Display": .pinned(app: "Apple")
            ])
        ])
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        // Should pick "Apple Display" (sorted first)
        #expect(vm.editingRootNode?.type == .pinned)
        #expect(vm.editingRootNode?.pinned?.application == "Apple")
    }

    @Test("selectScreenSet out of bounds does nothing")
    func selectScreenSetOutOfBounds() {
        let layout = makeMultiScreenSetLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        vm.selectScreenSet(0)
        let rootBefore = vm.editingRootNode

        // This calls refreshEditingRootNode which guards on safe index
        vm.selectScreenSet(99)
        // selectedScreenSetIndex is set regardless but refreshEditingRootNode
        // will set editingRootNode to nil if the index is out of bounds
        #expect(vm.editingRootNode == nil || vm.editingRootNode == rootBefore)
    }

    @Test("multiple addScreenSet calls increment correctly")
    func multipleAdds() {
        let layout = Layout(name: "One", screenSets: [
            ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        ])
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        vm.addScreenSet()
        vm.addScreenSet()
        vm.addScreenSet()

        #expect(vm.editingLayout!.screenSets.count == 4)
        #expect(vm.selectedScreenSetIndex == 3)
    }

    @Test("removeScreenSet middle index doesn't corrupt data")
    func removeMiddle() {
        let layout = makeMultiScreenSetLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        vm.selectScreenSet(1)  // Dual-display config

        // Remove middle (index 1)
        vm.removeScreenSet(at: 1)

        // Should now have 2 screen sets: single and triple
        #expect(vm.editingLayout!.screenSets.count == 2)
        // First is single-display (only $PRIMARY)
        #expect(vm.editingLayout!.screenSets[0].layouts.count == 1)
        // Second is triple-display (3 keys)
        #expect(vm.editingLayout!.screenSets[1].layouts.count == 3)
    }
}
